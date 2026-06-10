import AppKit
import CoreGraphics

final class AccessibilityService: Sendable {
    static let shared = AccessibilityService()
    private init() {}

    // C global var is not Sendable in Swift 6 — capture the string value once at load time
    nonisolated(unsafe) private static let promptKey: String =
        kAXTrustedCheckOptionPrompt.takeRetainedValue() as String

    var isAccessibilityGranted: Bool {
        AXIsProcessTrustedWithOptions([
            Self.promptKey: false
        ] as CFDictionary)
    }

    func requestAccessibilityIfNeeded() {
        AXIsProcessTrustedWithOptions([
            Self.promptKey: true
        ] as CFDictionary)
    }

    /// Simulates ⌘V. Call after the target app is already active.
    func simulatePaste() {
        let src = CGEventSource(stateID: .hidSystemState)
        // V key virtual code = 0x09
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cgAnnotatedSessionEventTap)

        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
