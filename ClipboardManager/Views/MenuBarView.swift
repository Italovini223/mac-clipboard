import SwiftUI

struct MenuBarMenuView: View {
    let openHistory: () -> Void
    let clearHistory: () -> Void
    let openSettings: () -> Void

    // Lido do UserDefaults (não de um Settings) porque a troca acontece na janela de Settings.
    @State private var hotkey = HotkeyShortcut.load()

    var body: some View {
        if !AccessibilityService.shared.isAccessibilityGranted {
            Button("⚠︎ Auto-paste needs Accessibility…") {
                AccessibilityService.shared.openAccessibilitySettings()
            }

            Divider()
        }

        Button("Open Clipboard History") { openHistory() }
            .keyboardShortcut(hotkey.menuShortcut)
            // Se o menu não reavaliar com ele aberto, o hint atualiza na próxima abertura.
            .onReceive(NotificationCenter.default.publisher(for: .hotkeyDidChange)) { _ in
                hotkey = HotkeyShortcut.load()
            }
            .onReceive(NotificationCenter.default.publisher(for: .hotkeyRegistrationFailed)) { _ in
                hotkey = HotkeyShortcut.load()
            }

        Divider()

        Button("Clear History…") { clearHistory() }

        Divider()

        Button("Settings…", action: openSettings)
            .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit Clipboard Manager") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)

        Divider()

        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            Text("Version \(version)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private extension HotkeyShortcut {
    /// Dica de atalho no item do menu. Só letras/dígitos viram `KeyEquivalent`; qualquer outra
    /// tecla (Space, setas, F-keys, pontuação) fica sem dica.
    var menuShortcut: KeyboardShortcut? {
        guard let character = keyCharacter, character.isLetter || character.isNumber else { return nil }
        var modifiers: EventModifiers = []
        if hasCommand { modifiers.insert(.command) }
        if hasOption  { modifiers.insert(.option) }
        if hasControl { modifiers.insert(.control) }
        if hasShift   { modifiers.insert(.shift) }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: modifiers)
    }
}
