import XCTest
import GRDB
@testable import S1Gugu

final class EditorDraftTests: XCTestCase {

    private var database: AppDatabase!

    override func setUpWithError() throws {
        super.setUp()
        let writer = try DatabaseQueue()
        try writer.write { db in
            try db.execute(sql: """
                CREATE TABLE "editordraft" (
                  "key" TEXT PRIMARY KEY,
                  "subject" TEXT NOT NULL DEFAULT '',
                  "body" TEXT NOT NULL DEFAULT '',
                  "extraValue" TEXT,
                  "timestamp" INTEGER NOT NULL DEFAULT 0
                ) STRICT
                """)
        }
        database = AppDatabase(writer: writer)
    }

    override func tearDown() {
        database = nil
        super.tearDown()
    }

    func testRoundTripsSubjectBodyAndExtraValue() async {
        let draft = EditorDraft(subject: "标题", body: "正文", extraValue: "type-1")
        let key = "newthread.\(UUID().uuidString)"

        let saved = await DraftStore.save(key, draft, database: database)
        let loaded = await DraftStore.load(key, database: database)

        XCTAssertTrue(saved)
        XCTAssertEqual(loaded, draft)
    }

    func testMissingDraftReturnsNil() async {
        let loaded = await DraftStore.load("missing.\(UUID().uuidString)", database: database)

        XCTAssertNil(loaded)
    }

    func testClearIfMatchesKeepsNewerDraft() async {
        let key = "newthread.\(UUID().uuidString)"
        let sentDraft = EditorDraft(subject: "标题", body: "发送正文")
        let newerDraft = EditorDraft(subject: "更新标题", body: "更新正文")
        _ = await DraftStore.save(key, newerDraft, database: database)

        await DraftStore.clearIfMatches(key, sentDraft, database: database)
        let loaded = await DraftStore.load(key, database: database)

        XCTAssertEqual(loaded, newerDraft)
    }

    func testClearIfMatchesRemovesSentDraft() async {
        let key = "reply.\(UUID().uuidString)"
        let draft = EditorDraft(body: "回复正文")
        _ = await DraftStore.save(key, draft, database: database)

        await DraftStore.clearIfMatches(key, draft, database: database)
        let loaded = await DraftStore.load(key, database: database)

        XCTAssertNil(loaded)
    }

    func testNewThreadDraftPickerOnlyReturnsNewThreadDrafts() async {
        _ = await DraftStore.save("newthread.22", EditorDraft(subject: "一个版块主题", body: "正文"), database: database)
        _ = await DraftStore.save("newthread.23", EditorDraft(subject: "另一个版块主题", body: "正文"), database: database)
        _ = await DraftStore.save("reply.22.0", EditorDraft(body: "回复内容"), database: database)

        let drafts = await DraftStore.newThreadDrafts(database: database)

        XCTAssertEqual(Set(drafts.map(\.key)), ["newthread.22", "newthread.23"])
    }

    func testReplyDraftPickerOnlyReturnsCurrentThreadDrafts() async {
        _ = await DraftStore.save("reply.22.0", EditorDraft(body: "普通回复"), database: database)
        _ = await DraftStore.save("reply.22.501", EditorDraft(body: "引用回复"), database: database)
        _ = await DraftStore.save("reply.23.0", EditorDraft(body: "其他帖子回复"), database: database)
        _ = await DraftStore.save("newthread.22", EditorDraft(subject: "主题", body: "主题正文"), database: database)

        let drafts = await DraftStore.replyDrafts(threadId: 22, database: database)

        XCTAssertEqual(Set(drafts.map(\.key)), ["reply.22.0", "reply.22.501"])
    }

    func testDraftWithWhitespaceOnlyIsEmpty() {
        XCTAssertFalse(EditorDraft(subject: " \n", body: "\t").hasContent)
        XCTAssertTrue(EditorDraft(subject: "标题", body: "").hasContent)
    }
}
