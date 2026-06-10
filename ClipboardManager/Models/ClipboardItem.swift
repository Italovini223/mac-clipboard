import Foundation
import GRDB

struct ClipboardItem: Identifiable, Codable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "clipboard_history"

    var id: Int64?
    var content: String
    var contentType: ContentType
    var sourceApp: String?
    var createdAt: Date
    var isFavorite: Bool
    var rawData: Data?

    enum ContentType: String, Codable, Hashable, CaseIterable {
        case text, url, image, code, file

        var systemImage: String {
            switch self {
            case .text:  "doc.text"
            case .url:   "link"
            case .image: "photo"
            case .code:  "chevron.left.forwardslash.chevron.right"
            case .file:  "doc"
            }
        }

        var label: String {
            switch self {
            case .text:  "Text"
            case .url:   "URL"
            case .image: "Image"
            case .code:  "Code"
            case .file:  "File"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case content
        case contentType = "content_type"
        case sourceApp   = "source_app"
        case createdAt   = "created_at"
        case isFavorite  = "is_favorite"
        case rawData     = "raw_data"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var displayContent: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if contentType == .image { return trimmed.isEmpty ? "[Image]" : trimmed }
        return trimmed.isEmpty ? "[Empty]" : trimmed
    }

    var previewContent: String {
        String(displayContent.prefix(300))
    }

    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
}
