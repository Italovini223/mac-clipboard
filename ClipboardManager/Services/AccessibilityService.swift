import AppKit
import CoreGraphics

final class AccessibilityService: Sendable {
    static let shared = AccessibilityService()
    private init() {}

    var isAccessibilityGranted: Bool {
        AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false
        ] as CFDictionary)
    }

    func requestAccessibilityIfNeeded() {
        AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true
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
