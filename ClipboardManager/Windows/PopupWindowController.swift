import AppKit
import SwiftUI

@MainActor
final class PopupWindowController {
    private var panel: NSPanel?
    private let viewModel: ClipboardViewModel
    private var previousApp: NSRunningApplication?
    private var outsideClickMonitor: Any?
    // Guards against didResignKeyNotification firing immediately after show()
    // (happens on macOS 14 when activation hasn't settled yet)
    private var isOpening = false

    init(viewModel: ClipboardViewModel) {
        self.viewModel = viewModel
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication

        if panel == nil { createPanel() }
        guard let panel else { return }

        positionPanel(panel)

        isOpening = true
        // Do NOT call NSApp.activate(). .nonactivatingPanel lets the panel become
        // key without making our app frontmost, so the previous app keeps its text
        // cursor and any active selection intact.
        panel.makeKeyAndOrderFront(nil)

        // macOS 14 sometimes ignores makeKeyAndOrderFront on the first call when the
        // app is not frontmost. A second attempt after the system settles fixes this.
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            if panel.isVisible { panel.makeKeyAndOrderFront(nil) }
            try? await Task.sleep(for: .milliseconds(250))
            isOpening = false
        }

        viewModel.onPopupOpened()

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self else { return }
            // Keep the popup open when the user clicks inside the same app that was
            // active when the popup opened — they may be clicking a text field to
            // set (or change) the paste destination before selecting a history item.
            let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            if let prev = self.previousApp?.processIdentifier, frontmostPID == prev { return }
            Task { @MainActor [weak self] in self?.hide() }
        }
    }

    func hide() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        panel?.orderOut(nil)

        let shouldPaste = viewModel.pendingPaste
        viewModel.pendingPaste = false
        viewModel.onPopupClosed()

        previousApp?.activate(options: .activateIgnoringOtherApps)

        if shouldPaste {
            // Delay starts AFTER previousApp?.activate() so the target app has
            // time to become frontmost before the simulated Cmd+V is sent.
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                AccessibilityService.shared.simulatePaste()
            }
        }
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    // MARK: - Private

    private func createPanel() {
        let hosting = NSHostingView(rootView:
            MainPopupView(viewModel: viewModel, onClose: { [weak self] in self?.hide() })
        )
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.level               = .popUpMenu
        p.isFloatingPanel     = true
        p.collectionBehavior  = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovableByWindowBackground = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.contentView = hosting

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: p,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isOpening else { return }
                // Don't close if the user clicked inside the same app that was
                // active when the popup opened (e.g. clicking a text field to
                // set or change the paste target).
                let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
                if let prev = self.previousApp?.processIdentifier, frontmostPID == prev { return }
                self.hide()
            }
        }

        panel = p
    }

    private func positionPanel(_ panel: NSPanel) {
        let screen = NSScreen.screens.first(where: {
            $0.frame.contains(NSEvent.mouseLocation)
        }) ?? NSScreen.main ?? NSScreen.screens[0]

        let sf = screen.visibleFrame
        let pw: CGFloat = 640
        let ph: CGFloat = 480
        let x = sf.midX - pw / 2
        let y = sf.midY - ph / 2 + sf.height * 0.1
        panel.setFrame(NSRect(x: x, y: y, width: pw, height: ph), display: false)
    }
}
