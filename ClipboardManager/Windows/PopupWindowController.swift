import AppKit
import SwiftUI

@MainActor
final class PopupWindowController {
    private var panel: NSPanel?
    private let viewModel: ClipboardViewModel
    private var previousApp: NSRunningApplication?
    private var outsideClickMonitor: Any?

    init(viewModel: ClipboardViewModel) {
        self.viewModel = viewModel
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication

        if panel == nil { createPanel() }
        guard let panel else { return }

        positionPanel(panel)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        viewModel.onPopupOpened()

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    func hide() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        panel?.orderOut(nil)
        previousApp?.activate(options: .activateIgnoringOtherApps)
        viewModel.onPopupClosed()
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
        p.level          = .popUpMenu
        p.isFloatingPanel = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovableByWindowBackground = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.contentView = hosting

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: p,
            queue: .main
        ) { [weak self] _ in
            self?.hide()
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
