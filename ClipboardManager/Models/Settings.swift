import Foundation
import Observation

@Observable
final class Settings {
    var historyLimit: Int {
        didSet { UserDefaults.standard.set(historyLimit, forKey: "historyLimit") }
    }
    var retentionDays: Int {
        didSet { UserDefaults.standard.set(retentionDays, forKey: "retentionDays") }
    }
    var ignorePasswords: Bool {
        didSet { UserDefaults.standard.set(ignorePasswords, forKey: "ignorePasswords") }
    }
    var ignoreApiKeys: Bool {
        didSet { UserDefaults.standard.set(ignoreApiKeys, forKey: "ignoreApiKeys") }
    }
    var ignoredApps: [String] {
        didSet { UserDefaults.standard.set(ignoredApps, forKey: "ignoredApps") }
    }
    var launchAtLogin: Bool {
        didSet { UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin") }
    }
    var showInMenuBar: Bool {
        didSet { UserDefaults.standard.set(showInMenuBar, forKey: "showInMenuBar") }
    }

    init() {
        let defaults = UserDefaults.standard
        historyLimit   = defaults.integer(forKey: "historyLimit").nonZero ?? 500
        retentionDays  = defaults.integer(forKey: "retentionDays").nonZero ?? 30
        ignorePasswords = defaults.object(forKey: "ignorePasswords") as? Bool ?? true
        ignoreApiKeys   = defaults.object(forKey: "ignoreApiKeys")   as? Bool ?? true
        ignoredApps     = defaults.stringArray(forKey: "ignoredApps") ?? [
            "com.1password.1password",
            "com.agilebits.onepassword-osx",
            "com.bitwarden.desktop",
            "org.keepassxc.keepassxc",
            "com.lastpass.LastPass"
        ]
        launchAtLogin  = defaults.bool(forKey: "launchAtLogin")
        showInMenuBar  = defaults.object(forKey: "showInMenuBar") as? Bool ?? true
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
