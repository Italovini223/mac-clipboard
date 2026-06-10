import Foundation
import GRDB

@MainActor
final class StorageService {
    private let db: DatabaseQueue
    private let settings: Settings

    init(sqliteManager: SQLiteManager, settings: Settings) {
        self.db = sqliteManager.db
        self.settings = settings
    }

    func insert(_ item: ClipboardItem) {
        try? db.write { db in
            try item.insert(db)
            self.pruneIfNeeded(db: db)
            self.pruneByAge(db: db)
        }
    }

    func fetchAll(limit: Int = 100) -> [ClipboardItem] {
        (try? db.read { db in
            try ClipboardItem
                .order(Column("is_favorite").desc, Column("created_at").desc)
                .limit(limit)
                .fetchAll(db)
        }) ?? []
    }

    func search(_ query: String) -> [ClipboardItem] {
        guard !query.isEmpty else { return fetchAll() }
        let safeQuery = query
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\"", with: "\"\"")
        guard !safeQuery.isEmpty else { return fetchAll() }

        return (try? db.read { db in
            // Try FTS5 first
            let ftsPattern = "\(safeQuery)*"
            let results = try ClipboardItem.fetchAll(db, sql: """
                SELECT ch.* FROM clipboard_history ch
                WHERE ch.id IN (
                    SELECT rowid FROM clipboard_fts WHERE clipboard_fts MATCH ?
                )
                ORDER BY ch.is_favorite DESC, ch.created_at DESC
                LIMIT 100
                """, arguments: [ftsPattern])
            if !results.isEmpty { return results }
            // Fallback to LIKE
            return try ClipboardItem
                .filter(Column("content").like("%\(safeQuery)%"))
                .order(Column("is_favorite").desc, Column("created_at").desc)
                .limit(100)
                .fetchAll(db)
        }) ?? []
    }

    func setFavorite(id: Int64?, value: Bool) {
        guard let id else { return }
        try? db.write { db in
            try db.execute(sql: """
                UPDATE clipboard_history SET is_favorite = ? WHERE id = ?
                """, arguments: [value, id])
        }
    }

    func delete(id: Int64?) {
        guard let id else { return }
        try? db.write { db in
            try db.execute(sql: "DELETE FROM clipboard_history WHERE id = ?", arguments: [id])
        }
    }

    func clearHistory() {
        try? db.write { db in
            try db.execute(sql: "DELETE FROM clipboard_history WHERE is_favorite = 0")
        }
    }

    func totalCount() -> Int {
        (try? db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM clipboard_history")
        }) ?? 0
    }

    // MARK: - Private

    private func pruneIfNeeded(db: Database) {
        let limit = settings.historyLimit
        try? db.execute(sql: """
            DELETE FROM clipboard_history
            WHERE is_favorite = 0
              AND id NOT IN (
                SELECT id FROM clipboard_history
                WHERE is_favorite = 0
                ORDER BY created_at DESC
                LIMIT ?
              )
            """, arguments: [limit])
    }

    private func pruneByAge(db: Database) {
        let days = settings.retentionDays
        guard days > 0 else { return }
        try? db.execute(sql: """
            DELETE FROM clipboard_history
            WHERE is_favorite = 0
              AND created_at < datetime('now', ?)
            """, arguments: ["-\(days) days"])
    }
}
