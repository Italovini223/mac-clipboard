import Carbon
import Foundation

// Global hotkey registration via Carbon API.
// RegisterEventHotKey does not require Accessibility permission.
@MainActor
final class HotkeyService {
    // nonisolated(unsafe) allows the C callback to access this without actor isolation checks.
    nonisolated(unsafe) private static var onTriggered: (() -> Void)?

    // nonisolated(unsafe) so deinit (which is always nonisolated in Swift 6) can access these raw C pointers.
    nonisolated(unsafe) private var hotKeyRef: EventHotKeyRef?
    nonisolated(unsafe) private var eventHandlerRef: EventHandlerRef?

    func register(keyCode: UInt32 = 9, // kVK_ANSI_V
                  modifiers: UInt32 = UInt32(optionKey),
                  onTriggered: @escaping @MainActor @Sendable () -> Void) {
        HotkeyService.onTriggered = {
            Task { @MainActor in onTriggered() }
        }

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

        let hotKeyID = EventHotKeyID(signature: 0x434D4752, id: 1) // 'CMGR'
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
        HotkeyService.onTriggered = nil
    }

    deinit {
        // Safe to call unregister from deinit since it accesses only C APIs
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let handler = eventHandlerRef { RemoveEventHandler(handler) }
    }
}
