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
            HotkeysTab(settings: settings)
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }
        }
        .frame(width: 480, height: 360)
        .padding()
    }
}

// MARK: - General

private struct GeneralTab: View {
    @Bindable var settings: Settings
    @State private var accessibilityGranted = AccessibilityService.shared.isAccessibilityGranted

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "v\(version) (build \(build))"
    }

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

            Section {
                LabeledContent("Accessibility") {
                    HStack(spacing: 6) {
                        Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(accessibilityGranted ? .green : .orange)
                        Text(accessibilityGranted ? "Granted" : "Not granted")
                            .foregroundStyle(.secondary)
                    }
                }
                if !accessibilityGranted {
                    Button("Open Accessibility Settings…") {
                        AccessibilityService.shared.openAccessibilitySettings()
                    }
                }
            } header: {
                Text("Auto-paste")
            } footer: {
                Text("Required to paste the selected item automatically. After updating the app, remove and re-add it in Accessibility if this shows \"Not granted\".")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Version") {
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { accessibilityGranted = AccessibilityService.shared.isAccessibilityGranted }
        // Re-check when the user comes back from System Settings.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityGranted = AccessibilityService.shared.isAccessibilityGranted
        }
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
    @Bindable var settings: Settings

    var body: some View {
        Form {
            Section {
                LabeledContent("Open History") {
                    ShortcutRecorderView(settings: settings)
                }
            } header: {
                Text("Global Shortcuts")
            } footer: {
                Text("Click the shortcut and press the new combination. Esc cancels; Delete or Reset restores \(HotkeyShortcut.default.displayString).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
