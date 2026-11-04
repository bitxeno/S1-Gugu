import XCTest
import GRDB
@testable import S1Gugu

@MainActor
final class BlacklistServiceTests: XCTestCase {

    private var database: AppDatabase!
    private var service: BlacklistService!

    override func setUp() async throws {
        let writer = try DatabaseQueue()
        try await writer.write { db in
            try db.execute(sql: """
                CREATE TABLE "blacklist" (
                  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
                  "uid" INTEGER NOT NULL DEFAULT 0,
                  "name" TEXT,
                  "postLevel" INTEGER NOT NULL DEFAULT 0,
                  "forumLevel" INTEGER NOT NULL DEFAULT 0,
                  "remark" TEXT,
                  "timestamp" INTEGER NOT NULL DEFAULT 0
                ) STRICT
                """)
            try db.execute(sql: """
                CREATE TABLE "blackword" (
                  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
                  "word" TEXT NOT NULL,
                  "level" INTEGER NOT NULL DEFAULT 0,
                  "timestamp" INTEGER NOT NULL DEFAULT 0
                ) STRICT
                """)
        }
        database = AppDatabase(writer: writer)
        service = BlacklistService(database: database)
    }

    func testAddMergesSameUserAndPreservesRemark() async {
        await service.addBlackList(uid: 1, name: "Alice", postLevel: 1, forumLevel: 3, remark: "备注")
        await service.addBlackList(uid: 1, name: "Alice2", postLevel: 2, forumLevel: 4, remark: nil)

        XCTAssertEqual(service.snapshot.entries.count, 1)
        let entry = service.snapshot.entries[0]
        XCTAssertEqual(entry.uid, 1)
        XCTAssertEqual(entry.name, "Alice2")
        XCTAssertEqual(entry.postLevel, 2)
        XCTAssertEqual(entry.forumLevel, 4)
        XCTAssertEqual(entry.remark, "备注")
    }

    func testAddMergesByNameIgnoringCase() async {
        await service.addBlackList(uid: 0, name: "Alice", postLevel: 1, forumLevel: 3, remark: nil)
        await service.addBlackList(uid: 0, name: "alice", postLevel: 2, forumLevel: 4, remark: nil)

        XCTAssertEqual(service.snapshot.entries.count, 1)
        XCTAssertEqual(service.snapshot.entries[0].postLevel, 2)
    }

    func testDuplicateRowsAreCollapsedWhenSaving() async throws {
        try await database.write { db in
            try db.execute(sql: """
                INSERT INTO blacklist (uid, name, postLevel, forumLevel, remark, timestamp)
                VALUES (1, 'Alice', 1, 3, NULL, 0)
                """)
            try db.execute(sql: """
                INSERT INTO blacklist (uid, name, postLevel, forumLevel, remark, timestamp)
                VALUES (1, NULL, 2, 4, NULL, 0)
                """)
        }
        await service.reload()
        XCTAssertEqual(service.snapshot.entries.count, 2)

        await service.addBlackList(uid: 1, name: "Bob", postLevel: 1, forumLevel: 3, remark: nil)

        XCTAssertEqual(service.snapshot.entries.count, 1)
        let entry = service.snapshot.entries[0]
        XCTAssertEqual(entry.uid, 1)
        XCTAssertEqual(entry.name, "Bob")
        XCTAssertEqual(entry.postLevel, 1)
        XCTAssertEqual(entry.forumLevel, 3)
    }

    func testImportWebBlacklistDedupesAndUsesHiddenDefaults() async {
        let count = await service.importWebBlacklist([
            WebBlacklistUser(uid: 1, name: "A"),
            WebBlacklistUser(uid: 1, name: "A duplicate"),
            WebBlacklistUser(uid: 2, name: "B"),
        ])

        XCTAssertEqual(count, 2)
        XCTAssertEqual(service.snapshot.entries.count, 2)
        XCTAssertTrue(service.snapshot.entries.allSatisfy {
            $0.postLevel == 1 && $0.forumLevel == 3
        })
    }
}
