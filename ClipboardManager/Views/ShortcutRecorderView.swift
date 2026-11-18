import AppKit
import SwiftUI

/// Captura teclas enquanto o usuário grava um atalho. Enquanto grava, avisa via notificação
/// para o atalho atual ficar suspenso (senão teclá-lo abriria o popup em vez de gravar).
@MainActor
@Observable
final class ShortcutRecorderModel {
    private(set) var isRecording = false
    var message: String?

    private var monitor: Any?

    func start(onCapture: @escaping (HotkeyShortcut) -> Void) {
        guard !isRecording else { return }
        isRecording = true
        message = nil
        NotificationCenter.default.post(name: .hotkeyRecordingDidBegin, object: nil)

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Devolver nil engole o evento; ele não pode cruzar o isolamento, por isso só o Bool volta.
            let swallow = MainActor.assumeIsolated { self?.handle(event, onCapture: onCapture) ?? false }
            return swallow ? nil : event
        }
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        NotificationCenter.default.post(name: .hotkeyRecordingDidEnd, object: nil)
    }

    private func handle(_ event: NSEvent, onCapture: (HotkeyShortcut) -> Void) -> Bool {
        let keyCode = UInt32(event.keyCode)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let modifiers = HotkeyShortcut.carbonModifiers(from: flags)

        // Esc cancela; Delete restaura o padrão (só sem modificadores).
        if modifiers == 0 {
            if keyCode == 53 {
                stop()
                return true
            }
            if keyCode == 51 {
                stop()
                onCapture(.default)
                return true
            }
        }

        let shortcut = HotkeyShortcut(keyCode: keyCode, carbonModifiers: modifiers)
        guard shortcut.isValid else {
            message = "Include ⌘, ⌃ or ⌥ (F1–F20 work on their own)."
            return true
        }

        message = nil
        // Encerra a gravação (retoma o atalho antigo) antes de gravar o novo, para o registro
        // do novo poder detectar conflito.
        stop()
        onCapture(shortcut)
        return true
    }
}

struct ShortcutRecorderView: View {
    @Bindable var settings: Settings
    @State private var recorder = ShortcutRecorderModel()

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 8) {
                Button {
                    if recorder.isRecording {
                        recorder.stop()
                    } else {
                        recorder.start { settings.hotkey = $0 }
                    }
                } label: {
                    Text(recorder.isRecording ? "Press shortcut…" : settings.hotkey.displayString)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(recorder.isRecording ? Color.accentColor : Color.primary)
                        .frame(minWidth: 90)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Color.accentColor, lineWidth: recorder.isRecording ? 1.5 : 0)
                        }
                }
                .buttonStyle(.plain)

                Button("Reset") {
                    recorder.stop()
                    recorder.message = nil
                    settings.hotkey = .default
                }
                .disabled(settings.hotkey == .default && !recorder.isRecording)
            }

            if let message = recorder.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.trailing)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hotkeyRegistrationFailed)) { _ in
            // O AppDelegate restaurou o atalho anterior no UserDefaults; realinha esta instância.
            settings.hotkey = HotkeyShortcut.load()
            recorder.message = "This shortcut is already used by another app or the system."
        }
        // Gravação nunca deve sobreviver à aba/janela, senão o atalho global ficaria suspenso.
        .onDisappear { recorder.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            recorder.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
            recorder.stop()
        }
    }
}
