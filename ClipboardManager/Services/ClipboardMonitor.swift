import AppKit
import Foundation

@MainActor
final class ClipboardMonitor {
    var onNewItem: (@MainActor (ClipboardItem) -> Void)?
    // Stores the exact NSPasteboard.changeCount written by the app so we can skip it.
    // More robust than a boolean: works even if the user copies something in the same 500ms window.
    var lastWrittenChangeCount: Int = -1

    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private let settings: Settings

    private static let sensitivePatterns: [NSRegularExpression] = {
        let patterns = [
            // JWT
            "^eyJ[A-Za-z0-9\\-_=]+\\.[A-Za-z0-9\\-_=]+\\.[A-Za-z0-9\\-_=+/]*$",
            // Common API key prefixes
            "(^|\\s)(sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{36,}|gho_[A-Za-z0-9]{36,}|ghs_[A-Za-z0-9]{36,}|AKIA[A-Z0-9]{16}|AIza[0-9A-Za-z\\-_]{35})",
            // PEM private keys
            "-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----",
            // Bearer tokens
            "^Bearer [A-Za-z0-9\\-._~+/]+=*$",
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }
    }()

    init(settings: Settings) {
        self.settings = settings
    }

    func start() {
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkForChanges()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Private

    private func checkForChanges() {
        let pb = NSPasteboard.general
        let currentCount = pb.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        if currentCount == lastWrittenChangeCount {
            lastWrittenChangeCount = -1
            return
        }

        let sourceApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        // Skip ignored apps
        if let app = sourceApp, settings.ignoredApps.contains(app) {
            return
        }

        guard let item = buildItem(from: pb, sourceApp: sourceApp) else { return }

        // Skip sensitive content
        if isSensitive(item.content) { return }

        onNewItem?(item)
    }

    private func buildItem(from pb: NSPasteboard, sourceApp: String?) -> ClipboardItem? {
        // Image
        if let image = NSImage(pasteboard: pb) {
            let tiff = image.tiffRepresentation
            let name = "[Image \(Int(image.size.width))×\(Int(image.size.height))]"
            return ClipboardItem(
                content: name,
                contentType: .image,
                sourceApp: sourceApp,
                createdAt: Date(),
                isFavorite: false,
                rawData: tiff
            )
        }

        // File URLs
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], !urls.isEmpty {
            let paths = urls.map(\.path).joined(separator: "\n")
            return ClipboardItem(
                content: paths,
                contentType: .file,
                sourceApp: sourceApp,
                createdAt: Date(),
                isFavorite: false
            )
        }

        // String content
        guard let string = pb.string(forType: .string), !string.isEmpty else { return nil }

        // Avoid storing exact duplicates (check most recent item)
        let type = detectType(string)
        return ClipboardItem(
            content: string,
            contentType: type,
            sourceApp: sourceApp,
            createdAt: Date(),
            isFavorite: false
        )
    }

    private func detectType(_ text: String) -> ClipboardItem.ContentType {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true {
            return .url
        }
        if looksLikeCode(trimmed) { return .code }
        return .text
    }

    private func looksLikeCode(_ text: String) -> Bool {
        let codeIndicators = ["{", "}", "func ", "class ", "import ", "def ", "var ", "let ", "const ", "=>", "->", "()"]
        let lines = text.components(separatedBy: .newlines)
        guard lines.count > 2 else { return false }
        let score = codeIndicators.filter { text.contains($0) }.count
        return score >= 2
    }

    private func isSensitive(_ text: String) -> Bool {
        guard settings.ignorePasswords || settings.ignoreApiKeys else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return Self.sensitivePatterns.contains { pattern in
            pattern.firstMatch(in: text, range: range) != nil
        }
    }
}
