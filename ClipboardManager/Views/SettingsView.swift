import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: Settings

    var body: some View {
        TabView {
            GeneralTab(settings: settings)
                .tabItem { Label("General", systemImage: "gear") }
            PrivacyTab(settings: settings)
                .tabItem { Label("Privacy", systemImage: "lock.shield") }
            HotkeysTab()
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }
        }
        .frame(width: 480, height: 360)
        .padding()
    }
}

// MARK: - General

private struct GeneralTab: View {
    @Bindable var settings: Settings

    var body: some View {
        Form {
            Section("Behavior") {
                Toggle("Launch at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { newValue in
                        settings.launchAtLogin = newValue
                        applyLaunchAtLogin(newValue)
                    }
                ))
                Toggle("Show in menu bar", isOn: $settings.showInMenuBar)
            }

            Section("History") {
                Stepper("Limit: \(settings.historyLimit) items",
                        value: $settings.historyLimit,
                        in: 50...2000,
                        step: 50)

                Stepper("Retain for \(settings.retentionDays) days",
                        value: $settings.retentionDays,
                        in: 1...365,
                        step: 1)
            }
        }
        .formStyle(.grouped)
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("LaunchAtLogin error: \(error)")
        }
    }
}

// MARK: - Privacy

private struct PrivacyTab: View {
    @Bindable var settings: Settings
    @State private var newApp = ""

    var body: some View {
        Form {
            Section("Sensitive Content") {
                Toggle("Skip passwords & secrets", isOn: $settings.ignorePasswords)
                Toggle("Skip API keys & tokens", isOn: $settings.ignoreApiKeys)
            }

            Section {
                ForEach(settings.ignoredApps, id: \.self) { app in
                    HStack {
                        Text(app).font(.system(.body, design: .monospaced))
                        Spacer()
                        Button(role: .destructive) {
                            settings.ignoredApps.removeAll { $0 == app }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    TextField("Bundle ID (e.g. com.1password.1password)", text: $newApp)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let trimmed = newApp.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty, !settings.ignoredApps.contains(trimmed) else { return }
                        settings.ignoredApps.append(trimmed)
                        newApp = ""
                    }
                    .disabled(newApp.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Ignored Applications")
            } footer: {
                Text("Clipboard content from these apps will not be recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Hotkeys

private struct HotkeysTab: View {
    var body: some View {
        Form {
            Section("Global Shortcuts") {
                LabeledContent("Open History") {
                    Text("⌥ V")
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                }
            }
            Section {
                Text("Custom hotkey binding will be available in a future update.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
    }
}
