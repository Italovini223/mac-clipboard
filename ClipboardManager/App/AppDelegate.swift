import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var viewModel: ClipboardViewModel!
    private var popupController: PopupWindowController!
    private var hotkeyService: HotkeyService!
    private(set) var settings: Settings!

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = Settings()

        guard let sqliteManager = try? SQLiteManager() else {
            fatalError("Failed to initialize SQLite database")
        }

        let storage = StorageService(sqliteManager: sqliteManager, settings: settings)
        let monitor = ClipboardMonitor(settings: settings)

        viewModel = ClipboardViewModel(storage: storage, monitor: monitor)
        popupController = PopupWindowController(viewModel: viewModel)

        hotkeyService = HotkeyService()
        hotkeyService.register { [weak self] in
            self?.popupController.toggle()
        }

        viewModel.startMonitoring()

        // Request accessibility for auto-paste (non-blocking prompt)
        if !AccessibilityService.shared.isAccessibilityGranted {
            AccessibilityService.shared.requestAccessibilityIfNeeded()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // Stay alive as a menu bar app
    }

    func openPopup() {
        popupController.show()
    }

    func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear Clipboard History?"
        alert.informativeText = "Favorited items will not be removed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            viewModel.clearHistory()
        }
    }
}
