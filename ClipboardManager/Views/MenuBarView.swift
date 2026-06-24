import SwiftUI

struct MenuBarMenuView: View {
    let openHistory: () -> Void
    let clearHistory: () -> Void
    let openSettings: () -> Void

    var body: some View {
        Button("Open Clipboard History") { openHistory() }
            .keyboardShortcut("v", modifiers: .option)

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
