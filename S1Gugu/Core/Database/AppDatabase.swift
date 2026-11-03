import Foundation
import OSLog
import SQLiteData

/// 单库 s1gugu.sqlite,SQLiteData(GRDB)。迁移只增不改。
final class AppDatabase: Sendable {

    static let shared: AppDatabase = {
        do {
            return try AppDatabase.makeDefault()
        } catch {
            fatalError("数据库初始化失败:\(error)")
        }
    }()

    let writer: any DatabaseWriter

    init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    static func makeDefault() throws -> AppDatabase {
        var configuration = Configuration()
        #if DEBUG
        let logger = Logger(subsystem: "app.bitxeno.s1gugu", category: "db")
        configuration.prepareDatabase { database in
            database.trace(options: .profile) { statement in
                logger.debug("\(statement.expandedDescription, privacy: .public)")
            }
        }
        #endif

        let writer = try defaultDatabase(configuration: configuration)

        var migrator = DatabaseMigrator()
        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif
        migrator.registerMigration("v1-create-tables") { database in
            try #sql("""
                CREATE TABLE "blacklist" (
                  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
                  "uid" INTEGER NOT NULL DEFAULT 0,
                  "name" TEXT,
                  "postLevel" INTEGER NOT NULL DEFAULT 0,
                  "forumLevel" INTEGER NOT NULL DEFAULT 0,
                  "remark" TEXT,
                  "timestamp" INTEGER NOT NULL DEFAULT 0
                ) STRICT
                """).execute(database)
            try #sql("""
                CREATE INDEX "idx_blacklist_uid" ON "blacklist"("uid")
                """).execute(database)
            try #sql("""
                CREATE TABLE "blackword" (
                  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
                  "word" TEXT NOT NULL,
                  "level" INTEGER NOT NULL DEFAULT 0,
                  "timestamp" INTEGER NOT NULL DEFAULT 0
                ) STRICT
                """).execute(database)
            try #sql("""
                CREATE UNIQUE INDEX "idx_blackword_word" ON "blackword"("word")
                """).execute(database)
            try #sql("""
                CREATE TABLE "history" (
                  "threadId" INTEGER PRIMARY KEY,
                  "title" TEXT NOT NULL DEFAULT '',
                  "timestamp" INTEGER NOT NULL DEFAULT 0
                ) STRICT
                """).execute(database)
            try #sql("""
                CREATE TABLE "readprogress" (
                  "threadId" INTEGER PRIMARY KEY,
                  "page" INTEGER NOT NULL DEFAULT 1,
                  "anchorPid" INTEGER NOT NULL DEFAULT 0,
                  "timestamp" INTEGER NOT NULL DEFAULT 0
                ) STRICT
                """).execute(database)
        }
        migrator.registerMigration("v2-post-backup") { database in
            try #sql("""
                CREATE TABLE "postbackup" (
                  "threadId" INTEGER PRIMARY KEY,
                  "title" TEXT NOT NULL DEFAULT '',
                  "pageCount" INTEGER NOT NULL DEFAULT 0,
                  "payload" TEXT NOT NULL DEFAULT '',
                  "timestamp" INTEGER NOT NULL DEFAULT 0
                ) STRICT
                """).execute(database)
        }
        migrator.registerMigration("v3-accounts") { database in
            try #sql("""
                CREATE TABLE "accounts" (
                  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
                  "uid" INTEGER NOT NULL DEFAULT 0,
                  "name" TEXT NOT NULL DEFAULT '',
                  "lastUsedAt" INTEGER NOT NULL DEFAULT 0
                ) STRICT
                """).execute(database)
            try #sql("""
                CREATE UNIQUE INDEX "idx_accounts_name" ON "accounts"("name")
                """).execute(database)
        }
        migrator.registerMigration("v4-response-cache") { database in
            try #sql("""
                CREATE TABLE "responsecache" (
                  "key" TEXT PRIMARY KEY,
                  "payload" TEXT NOT NULL DEFAULT '',
                  "timestamp" INTEGER NOT NULL DEFAULT 0
                ) STRICT
                """).execute(database)
        }
        migrator.registerMigration("v5-dbthread") { database in
            try #sql("""
                CREATE TABLE "dbthread" (
                  "threadId" INTEGER PRIMARY KEY,
                  "lastCountWhenView" INTEGER NOT NULL DEFAULT 0,
                  "timestamp" INTEGER NOT NULL DEFAULT 0
                ) STRICT
                """).execute(database)
        }
        migrator.registerMigration("v6-forum-favorite") { database in
            try #sql("""
                CREATE TABLE "forumfavorite" (
                  "forumId" INTEGER PRIMARY KEY,
                  "name" TEXT NOT NULL DEFAULT '',
                  "sortOrder" INTEGER NOT NULL DEFAULT 0
                ) STRICT
                """).execute(database)
        }
        migrator.registerMigration("v7-editor-drafts") { database in
            try #sql("""
                CREATE TABLE "editordraft" (
                  "key" TEXT PRIMARY KEY,
                  "subject" TEXT NOT NULL DEFAULT '',
                  "body" TEXT NOT NULL DEFAULT '',
                  "extraValue" TEXT,
                  "timestamp" INTEGER NOT NULL DEFAULT 0
                ) STRICT
                """).execute(database)
        }
        try migrator.migrate(writer)
        return AppDatabase(writer: writer)
    }

    func read<T: Sendable>(_ body: @Sendable (Database) throws -> T) async throws -> T {
        try await writer.read(body)
    }

    func write<T: Sendable>(_ body: @Sendable (Database) throws -> T) async throws -> T {
        try await writer.write(body)
    }
}
