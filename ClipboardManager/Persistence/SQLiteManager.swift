import Foundation
import GRDB

final class SQLiteManager {
    let db: DatabaseQueue

    init() throws {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent("ClipboardManager", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let dbPath = dir.appendingPathComponent("clipboard.db").path
        var config = Configuration()
        config.journalMode = .wal
        db = try DatabaseQueue(path: dbPath, configuration: config)
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "clipboard_history", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("content", .text).notNull().defaults(to: "")
                t.column("content_type", .text).notNull().defaults(to: "text")
                t.column("source_app", .text)
                t.column("created_at", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
                t.column("is_favorite", .boolean).notNull().defaults(to: false)
                t.column("raw_data", .blob)
            }
            try db.create(index: "idx_clipboard_created_at",
                          on: "clipboard_history",
                          columns: ["created_at"],
                          options: .ifNotExists)
            try db.create(index: "idx_clipboard_favorite",
                          on: "clipboard_history",
                          columns: ["is_favorite"],
                          options: .ifNotExists)

            // FTS5 for instant search
            try db.create(virtualTable: "clipboard_fts", using: FTS5()) { t in
                t.synchronize(withTable: "clipboard_history")
                t.column("content")
            }
        }

        try migrator.migrate(db)
    }
}
