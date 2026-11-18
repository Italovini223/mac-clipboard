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

    private static let promptedVersionKey = "accessibilityPromptedVersion"

    /// Chamado no launch. Mostra o prompt do sistema só se a permissão realmente faltar e
    /// no máximo uma vez por versão do app (instalação nova ou atualização, já que a
    /// assinatura ad-hoc invalida a permissão a cada versão). Nas demais aberturas, como o
    /// login do Mac, o aviso fica só no menu da barra e em Settings.
    @MainActor
    func promptOnceIfNeeded() async {
        // No login o tccd pode demorar a responder: confirma por alguns segundos antes de
        // concluir que falta permissão.
        for _ in 0..<5 {
            if isAccessibilityGranted { return }
            try? await Task.sleep(for: .seconds(1))
        }
        guard !isAccessibilityGranted else { return }

        let version = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: Self.promptedVersionKey) != version else {
            Logger.paste.info("promptOnceIfNeeded: já pedido nesta versão (\(version, privacy: .public)), sem novo prompt")
            return
        }
        defaults.set(version, forKey: Self.promptedVersionKey)
        requestAccessibilityIfNeeded()
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

        // If a modifier of the hotkey is still held the target app would receive e.g. ⌥⌘V, or
        // ⇧⌘V ("paste and match style") when the hotkey includes ⇧.
        let waited = await waitForHotkeyModifiersRelease(timeout: .milliseconds(300))
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
        Logger.paste.info("simulatePaste: posting ⌘V (frontmost=\(frontmost, privacy: .public), hotkeyModifiersStillHeld=\(!waited))")

        let src = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: keyDown)
            event?.flags = .maskCommand   // only ⌘, never a leftover modifier
            event?.post(tap: .cghidEventTap)
        }
        return true
    }

    /// Polls until the ⌃⌥⇧ of the configured hotkey are released (⌘ is posted by us anyway).
    /// Returns false if any is still down after `timeout`.
    private func waitForHotkeyModifiersRelease(timeout: Duration) async -> Bool {
        let shortcut = HotkeyShortcut.load()
        var mask: CGEventFlags = []
        if shortcut.hasControl { mask.insert(.maskControl) }
        if shortcut.hasOption  { mask.insert(.maskAlternate) }
        if shortcut.hasShift   { mask.insert(.maskShift) }

        let step = Duration.milliseconds(10)
        var elapsed = Duration.zero
        while !CGEventSource.flagsState(.combinedSessionState).intersection(mask).isEmpty {
            if elapsed >= timeout { return false }
            try? await Task.sleep(for: step)
            elapsed += step
        }
        return true
    }
}
