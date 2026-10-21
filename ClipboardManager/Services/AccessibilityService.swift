import AppKit
import CoreGraphics
import os

extension Logger {
    /// Diagnóstico do fluxo de auto-paste:
    /// `log stream --predicate 'subsystem == "com.weethub.ClipboardManager"'`
    static let paste = Logger(subsystem: "com.weethub.ClipboardManager", category: "paste")
}

final class AccessibilityService: Sendable {
    static let shared = AccessibilityService()
    private init() {}

    // "AXTrustedCheckOptionPrompt" é o valor conhecido de kAXTrustedCheckOptionPrompt (API pública estável).
    // Evitamos referenciar a global C var para compatibilidade com Swift 6 strict concurrency.
    private static let promptKey = "AXTrustedCheckOptionPrompt"

    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )

    var isAccessibilityGranted: Bool {
        AXIsProcessTrustedWithOptions([Self.promptKey: false] as CFDictionary)
    }

    func requestAccessibilityIfNeeded() {
        AXIsProcessTrustedWithOptions([Self.promptKey: true] as CFDictionary)
    }

    /// Pede a permissão (se ainda não concedida) e abre Ajustes do Sistema → Acessibilidade.
    func openAccessibilitySettings() {
        if !isAccessibilityGranted { requestAccessibilityIfNeeded() }
        if let url = Self.settingsURL { NSWorkspace.shared.open(url) }
    }

    /// Simulates ⌘V. Call after the target app is already active.
    /// Returns false (and posts nothing) when Accessibility isn't granted — without it
    /// macOS silently drops synthetic events.
    @discardableResult
    func simulatePaste() async -> Bool {
        let trusted = isAccessibilityGranted
        guard trusted else {
            Logger.paste.error("simulatePaste: Accessibility not trusted, ⌘V not posted")
            return false
        }

        // The hotkey is ⌥V: if ⌥ is still held the target app would receive ⌥⌘V.
        let waited = await waitForOptionRelease(timeout: .milliseconds(300))
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
        Logger.paste.info("simulatePaste: posting ⌘V (frontmost=\(frontmost, privacy: .public), optionStillHeld=\(!waited))")

        let src = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: keyDown)
            event?.flags = .maskCommand   // only ⌘, never a leftover modifier
            event?.post(tap: .cghidEventTap)
        }
        return true
    }

    /// Polls until ⌥ is released. Returns false if it's still down after `timeout`.
    private func waitForOptionRelease(timeout: Duration) async -> Bool {
        let step = Duration.milliseconds(10)
        var elapsed = Duration.zero
        while CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate) {
            if elapsed >= timeout { return false }
            try? await Task.sleep(for: step)
            elapsed += step
        }
        return true
    }
}
