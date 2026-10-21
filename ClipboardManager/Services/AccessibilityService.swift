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

    // O prompt do sistema aparece no máximo uma vez por execução.
    private let hasPrompted = OSAllocatedUnfairLock(initialState: false)

    /// Mostra o prompt do sistema, uma única vez por execução. Retorna false se já foi mostrado.
    @discardableResult
    func requestAccessibilityIfNeeded() -> Bool {
        let shouldPrompt = hasPrompted.withLock { prompted in
            defer { prompted = true }
            return !prompted
        }
        guard shouldPrompt else { return false }
        AXIsProcessTrustedWithOptions([Self.promptKey: true] as CFDictionary)
        return true
    }

    /// Leva o usuário à permissão sem empilhar dois modais: se o prompt do sistema ainda não
    /// foi mostrado, mostra só ele (tem botão para os Ajustes); senão abre só os Ajustes.
    func openAccessibilitySettings() {
        if !isAccessibilityGranted, requestAccessibilityIfNeeded() { return }
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
