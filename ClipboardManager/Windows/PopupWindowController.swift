import AppKit
import SwiftUI
import os

@MainActor
final class PopupWindowController {
    private var panel: NSPanel?
    private let viewModel: ClipboardViewModel
    private var previousApp: NSRunningApplication?
    private var outsideClickMonitor: Any?
    // Guards against didResignKeyNotification firing immediately after show()
    // (happens on macOS 14 when activation hasn't settled yet)
    private var isOpening = false
    private var hasWarnedAboutAccessibility = false

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
            // Global monitors only see events delivered to other windows, so this fires
            // for any click outside the popup — including inside the previous app.
            // The click already gave focus to whatever the user clicked: don't take it back.
            Task { @MainActor [weak self] in self?.hide(restoreFocus: false) }
        }
    }

    func hide(restoreFocus: Bool = true) {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        panel?.orderOut(nil)

        let shouldPaste = viewModel.pendingPaste
        viewModel.pendingPaste = false
        viewModel.onPopupClosed()

        let target = previousApp

        if shouldPaste {
            Logger.paste.info("hide: paste requested, target=\(target?.bundleIdentifier ?? "nil", privacy: .public)")
            Task { await pasteIntoTarget(target) }
        } else if restoreFocus {
            target?.activate(options: .activateIgnoringOtherApps)
        }
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    // MARK: - Private

    /// Posts ⌘V into the app that was frontmost when the popup opened.
    /// The panel is non-activating, so that app normally never lost focus and no
    /// activation is needed — we only wait for the panel to give up key status.
    private func pasteIntoTarget(_ target: NSRunningApplication?) async {
        await waitForPanelToResignKey()

        if let target, NSWorkspace.shared.frontmostApplication?.processIdentifier != target.processIdentifier {
            // The user switched apps while the popup was open: bring the target back
            // and wait for the system to confirm before pasting.
            let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
            Logger.paste.info("pasteIntoTarget: frontmost=\(frontmost, privacy: .public) is not target, activating")
            await ActivationWaiter().activateAndWait(target, timeout: .milliseconds(1000))
        }

        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
        Logger.paste.info("pasteIntoTarget: frontmost=\(frontmost, privacy: .public)")

        if !(await AccessibilityService.shared.simulatePaste()) {
            warnAboutAccessibilityOnce()
        }
    }

    /// After orderOut the system hands key status back to the target app's window;
    /// pasting before that lands the ⌘V on nothing.
    private func waitForPanelToResignKey() async {
        var waited = 0
        while panel?.isKeyWindow == true, waited < 200 {
            try? await Task.sleep(for: .milliseconds(10))
            waited += 10
        }
        // Small settle time so the target's text field is first responder again.
        try? await Task.sleep(for: .milliseconds(50))
    }

    /// The item is already on the clipboard, so the user can still ⌘V manually.
    private func warnAboutAccessibilityOnce() {
        guard !hasWarnedAboutAccessibility else { return }
        hasWarnedAboutAccessibility = true

        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Auto-paste needs Accessibility permission"
        alert.informativeText = "The item was copied to the clipboard — press ⌘V to paste it. "
            + "To paste automatically, allow Clipboard Manager in System Settings → Privacy & Security → Accessibility. "
            + "After updating the app you may need to remove and re-add it there."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            AccessibilityService.shared.openAccessibilitySettings()
        }
    }

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
                // Same app still frontmost: key status moved within our own app (e.g. a
                // context menu), not an outside click — those close via the click monitor.
                let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
                if let prev = self.previousApp?.processIdentifier, frontmostPID == prev { return }
                // The user switched apps (⌘Tab, Mission Control…): close without pulling
                // focus back to the previous app.
                self.hide(restoreFocus: false)
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

/// Activates an app and suspends until NSWorkspace reports it active (or the timeout hits).
@MainActor
private final class ActivationWaiter {
    private var continuation: CheckedContinuation<Void, Never>?
    private var observer: NSObjectProtocol?

    func activateAndWait(_ app: NSRunningApplication, timeout: Duration) async {
        let pid = app.processIdentifier
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            continuation = cont
            observer = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                let activated = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                    .processIdentifier
                MainActor.assumeIsolated {
                    if activated == pid { self?.finish(timedOut: false) }
                }
            }
            // .activateIgnoringOtherApps has no effect on macOS 14+, so don't pass it.
            app.activate(options: [])
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                self?.finish(timedOut: true)
            }
        }
    }

    private func finish(timedOut: Bool) {
        guard let cont = continuation else { return }
        continuation = nil
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
        if timedOut { Logger.paste.error("ActivationWaiter: timed out waiting for target activation") }
        cont.resume()
    }
}
