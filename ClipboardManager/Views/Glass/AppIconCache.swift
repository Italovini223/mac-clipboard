import AppKit

/// Ícone e nome de app a partir do bundle id, em cache (as linhas são redesenhadas a cada seleção).
@MainActor
final class AppIconCache {
    static let shared = AppIconCache()

    private struct Entry {
        let icon: NSImage?
        let name: String
    }

    private var entries: [String: Entry] = [:]

    private init() {}

    func icon(for bundleId: String) -> NSImage? { entry(for: bundleId).icon }

    func name(for bundleId: String) -> String { entry(for: bundleId).name }

    private func entry(for bundleId: String) -> Entry {
        if let cached = entries[bundleId] { return cached }

        let entry: Entry
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            var name = FileManager.default.displayName(atPath: url.path)
            if name.hasSuffix(".app") { name.removeLast(4) }
            entry = Entry(icon: icon, name: name)
        } else {
            // App não instalado (ex.: bundle id digitado à mão nas configurações).
            let fallback = bundleId.components(separatedBy: ".").last?.capitalized ?? bundleId
            entry = Entry(icon: nil, name: fallback)
        }
        entries[bundleId] = entry
        return entry
    }
}
