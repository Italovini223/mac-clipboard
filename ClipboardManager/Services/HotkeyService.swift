import Carbon
import Foundation
import os

extension Logger {
    /// Registro/troca do atalho global:
    /// `log stream --predicate 'subsystem == "com.weethub.ClipboardManager"'`
    static let hotkey = Logger(subsystem: "com.weethub.ClipboardManager", category: "hotkey")
}

// Global hotkey registration via Carbon API.
// RegisterEventHotKey does not require Accessibility permission.
@MainActor
final class HotkeyService {
    // nonisolated(unsafe) allows the C callback to access this without actor isolation checks.
    nonisolated(unsafe) private static var onTriggered: (() -> Void)?

    // nonisolated(unsafe) so deinit (which is always nonisolated in Swift 6) can access these raw C pointers.
    nonisolated(unsafe) private var hotKeyRef: EventHotKeyRef?
    nonisolated(unsafe) private var eventHandlerRef: EventHandlerRef?

    /// Atalho configurado. Durante `suspend()` continua valendo, só não está registrado no sistema.
    private(set) var shortcut: HotkeyShortcut = .default
    private var isSuspended = false

    /// Registra `shortcut` (desregistrando o anterior) e devolve o `OSStatus` do Carbon.
    /// Conflito com outro app = `eventHotKeyExistsErr` (-9878); nesse caso nenhum atalho fica registrado.
    /// O event handler é instalado uma única vez, então trocar de atalho não duplica o disparo.
    @discardableResult
    func register(_ shortcut: HotkeyShortcut,
                  onTriggered: (@MainActor @Sendable () -> Void)? = nil) -> OSStatus {
        if let onTriggered {
            HotkeyService.onTriggered = {
                Task { @MainActor in onTriggered() }
            }
        }
        installEventHandlerIfNeeded()
        unregisterHotKey()

        let hotKeyID = EventHotKeyID(signature: 0x434D4752, id: 1) // 'CMGR'
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        if status == noErr {
            self.shortcut = shortcut
            Logger.hotkey.info("registered \(shortcut.displayString, privacy: .public)")
        } else {
            hotKeyRef = nil
            Logger.hotkey.error("failed to register \(shortcut.displayString, privacy: .public): OSStatus \(status)")
        }
        return status
    }

    /// Troca para `newShortcut`; se o sistema recusar, re-registra o atalho anterior e devolve false.
    func update(to newShortcut: HotkeyShortcut) -> Bool {
        let previous = shortcut
        if register(newShortcut) == noErr { return true }
        if register(previous) != noErr {
            Logger.hotkey.error("could not restore previous shortcut \(previous.displayString, privacy: .public)")
        }
        return false
    }

    /// Desliga o atalho enquanto o usuário grava outro (senão teclar a combinação atual abriria o popup).
    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        unregisterHotKey()
        Logger.hotkey.info("suspended")
    }

    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        register(shortcut)
    }

    func unregister() {
        unregisterHotKey()
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
        HotkeyService.onTriggered = nil
    }

    private func unregisterHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, _) -> OSStatus in
                HotkeyService.onTriggered?()
                return noErr
            },
            1,
            &eventSpec,
            nil,
            &eventHandlerRef
        )
    }

    deinit {
        // Safe to call unregister from deinit since it accesses only C APIs
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let handler = eventHandlerRef { RemoveEventHandler(handler) }
    }
}
