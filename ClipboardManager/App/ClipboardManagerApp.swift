import SwiftUI

@main
struct ClipboardManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Settings window (opened via ⌘, or menu)
        Settings {
            SettingsView(settings: appDelegate.settings ?? Settings())
        }

        // Menu bar icon + menu
        MenuBarExtra {
            MenuBarMenuView(
                openHistory: { appDelegate.openPopup() },
                clearHistory: { appDelegate.clearHistory() },
                openSettings: {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
            )
        } label: {
            Image(systemName: "doc.on.clipboard")
        }
    }
}
