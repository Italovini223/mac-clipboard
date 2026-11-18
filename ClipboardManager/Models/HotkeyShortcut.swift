import AppKit
import Carbon

extension Notification.Name {
    /// Postada por `Settings.hotkey` quando o atalho salvo muda. O `AppDelegate` relê do UserDefaults.
    static let hotkeyDidChange = Notification.Name("com.weethub.ClipboardManager.hotkeyDidChange")
    /// Postada pelo `AppDelegate` quando o macOS recusou o novo atalho (conflito) e o anterior foi restaurado.
    static let hotkeyRegistrationFailed = Notification.Name("com.weethub.ClipboardManager.hotkeyRegistrationFailed")
    /// O recorder da aba Hotkeys avisa o início/fim da gravação para o atalho atual ficar suspenso.
    static let hotkeyRecordingDidBegin = Notification.Name("com.weethub.ClipboardManager.hotkeyRecordingDidBegin")
    static let hotkeyRecordingDidEnd = Notification.Name("com.weethub.ClipboardManager.hotkeyRecordingDidEnd")
}

/// Atalho global (tecla virtual + modificadores no formato Carbon), persistido em UserDefaults como JSON.
struct HotkeyShortcut: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    static let `default` = HotkeyShortcut(keyCode: UInt32(kVK_ANSI_V), carbonModifiers: UInt32(optionKey))

    private static let defaultsKey = "hotkey"

    /// Lê o atalho salvo; cai no padrão se não existir ou estiver corrompido/inválido.
    static func load() -> HotkeyShortcut {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let shortcut = try? JSONDecoder().decode(HotkeyShortcut.self, from: data),
              shortcut.isValid
        else { return .default }
        return shortcut
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    // MARK: Modifiers

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option)  { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift)   { result |= UInt32(shiftKey) }
        return result
    }

    var hasCommand: Bool { carbonModifiers & UInt32(cmdKey) != 0 }
    var hasOption: Bool  { carbonModifiers & UInt32(optionKey) != 0 }
    var hasControl: Bool { carbonModifiers & UInt32(controlKey) != 0 }
    var hasShift: Bool   { carbonModifiers & UInt32(shiftKey) != 0 }

    // MARK: Validation

    /// Exige ao menos ⌘, ⌃ ou ⌥ (tecla sozinha ou só ⇧ capturaria a digitação normal).
    /// Exceção: F1–F20 podem ser usadas sem modificador.
    var isValid: Bool {
        if hasCommand || hasControl || hasOption { return true }
        return Self.functionKeyNames[keyCode] != nil
    }

    // MARK: Display

    /// "⌥V", "⌘⇧V", "⌃Space", "F5": símbolos na ordem ⌃⌥⇧⌘ seguidos do nome da tecla.
    var displayString: String {
        var result = ""
        if hasControl { result += "⌃" }
        if hasOption  { result += "⌥" }
        if hasShift   { result += "⇧" }
        if hasCommand { result += "⌘" }
        return result + keyName
    }

    /// Caractere imprimível da tecla no layout atual, em minúsculas (nil para Space, setas, F-keys etc.).
    var keyCharacter: Character? {
        guard Self.specialKeyNames[keyCode] == nil, Self.functionKeyNames[keyCode] == nil,
              let name = Self.printableName(for: keyCode), name.count == 1
        else { return nil }
        return name.lowercased().first
    }

    private var keyName: String {
        if let name = Self.functionKeyNames[keyCode] ?? Self.specialKeyNames[keyCode] { return name }
        return Self.printableName(for: keyCode)?.uppercased() ?? "Key \(keyCode)"
    }

    private static let functionKeyNames: [UInt32: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"
    ]

    private static let specialKeyNames: [UInt32: String] = [
        49: "Space", 36: "Return", 76: "Enter", 48: "Tab", 51: "⌫", 117: "⌦", 53: "Esc",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "Home", 119: "End", 116: "Page Up", 121: "Page Down"
    ]

    /// Tradução via `UCKeyTranslate` com o layout atual do teclado, para funcionar em ABNT2, AZERTY etc.
    private static func printableName(for keyCode: UInt32) -> String? {
        guard let layoutData = currentLayoutData() else { return nil }
        let layout = unsafeBitCast(CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self)

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = UCKeyTranslate(
            layout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            chars.count,
            &length,
            &chars
        )
        guard status == noErr, length > 0 else { return nil }
        let name = String(utf16CodeUnits: chars, count: length).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// Layouts não latinos (ex.: russo) não têm dados de layout próprios para letras ASCII;
    /// nesse caso usa o layout ASCII-capable mais recente.
    private static func currentLayoutData() -> CFData? {
        let sources = [
            TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue()
        ]
        for case let source? in sources {
            if let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
                return Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue()
            }
        }
        return nil
    }
}
