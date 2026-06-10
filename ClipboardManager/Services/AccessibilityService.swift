import AppKit
import CoreGraphics

final class AccessibilityService: Sendable {
    static let shared = AccessibilityService()
    private init() {}

    // "AXTrustedCheckOptionPrompt" é o valor conhecido de kAXTrustedCheckOptionPrompt (API pública estável).
    // Evitamos referenciar a global C var para compatibilidade com Swift 6 strict concurrency.
    private static let promptKey = "AXTrustedCheckOptionPrompt"

    var isAccessibilityGranted: Bool {
        AXIsProcessTrustedWithOptions([Self.promptKey: false] as CFDictionary)
    }

    func requestAccessibilityIfNeeded() {
        AXIsProcessTrustedWithOptions([Self.promptKey: true] as CFDictionary)
    }

    /// Simulates ⌘V. Call after the target app is already active.
    func simulatePaste() {
        let src = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cgAnnotatedSessionEventTap)

        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
