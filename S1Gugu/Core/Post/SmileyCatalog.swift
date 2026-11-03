import Foundation

/// S1 论坛表情目录(对齐 S1-Next EmoticonFactory 的分组与 BBCode 规律)。
/// 服务器图片:`static.stage1st.com/image/smiley/<dir>/<code>.png`
/// 发帖 BBCode:`[<prefix>:<code>]`
struct SmileyGroup: Sendable, Hashable {
    let title: String
    let dir: String
    let prefix: String
    let count: Int
}

enum SmileyCatalog {

    static let groups: [SmileyGroup] = [
        SmileyGroup(title: "常用", dir: "face2017", prefix: "f", count: 277),
        SmileyGroup(title: "卡通", dir: "carton2017", prefix: "c", count: 490),
        SmileyGroup(title: "动物", dir: "animal2017", prefix: "a", count: 31),
        SmileyGroup(title: "装备", dir: "device2017", prefix: "d", count: 45),
        SmileyGroup(title: "鹅鹅鹅", dir: "goose2017", prefix: "g", count: 74),
        SmileyGroup(title: "高达", dir: "bundam2017", prefix: "b", count: 37),
    ]

    static func url(for group: SmileyGroup, index: Int) -> URL? {
        guard (1...group.count).contains(index) else { return nil }
        return URL(string: "https://static.stage1st.com/image/smiley/\(group.dir)/\(code(for: group, index: index)).png")
    }

    static func bbcode(for group: SmileyGroup, index: Int) -> String {
        "[\(group.prefix):\(code(for: group, index: index))]"
    }

    private static func code(for group: SmileyGroup, index: Int) -> String {
        String(format: "%03d", index)
    }
}

extension Notification.Name {
    /// 帖子内容发生变化(回复/编辑成功后),PostListVC 监听刷新
    static let postDidChange = Notification.Name("app.bitxeno.s1gugu.postDidChange")
}

/// 编辑器本地草稿。保留正文之外，也保存发帖标题和分类。
struct EditorDraft: Sendable, Equatable {
    var subject: String
    var body: String
    var extraValue: String?

    init(subject: String = "", body: String, extraValue: String? = nil) {
        self.subject = subject
        self.body = body
        self.extraValue = extraValue
    }

    var hasContent: Bool {
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// 编辑器草稿数据库读写。
enum DraftStore {
    static func load(_ key: String, database appDatabase: AppDatabase = .shared) async -> EditorDraft? {
        guard let entry = try? await appDatabase.read({ database in
            try EditorDraftEntry.find(key).fetchOne(database)
        }) else { return nil }
        return EditorDraft(subject: entry.subject, body: entry.body, extraValue: entry.extraValue)
    }

    @discardableResult
    static func save(_ key: String, _ draft: EditorDraft, database appDatabase: AppDatabase = .shared) async -> Bool {
        let entry = EditorDraftEntry(
            key: key,
            subject: draft.subject,
            body: draft.body,
            extraValue: draft.extraValue,
            timestamp: Int(Date().timeIntervalSince1970)
        )
        do {
            _ = try await appDatabase.write { database in
                try EditorDraftEntry.upsert { entry }.execute(database)
            }
            return true
        } catch {
            return false
        }
    }

    static func clear(_ key: String, database appDatabase: AppDatabase = .shared) async {
        _ = try? await appDatabase.write { database in
            try EditorDraftEntry.find(key).delete().execute(database)
        }
    }

    static func clearIfMatches(
        _ key: String?,
        _ draft: EditorDraft,
        database appDatabase: AppDatabase = .shared
    ) async {
        guard let key, let saved = await load(key, database: appDatabase) else { return }
        if saved == draft {
            await clear(key, database: appDatabase)
        }
    }

    static func newThreadDrafts(database appDatabase: AppDatabase = .shared) async -> [EditorDraftEntry] {
        (try? await appDatabase.read { database in
            try EditorDraftEntry
                .where { $0.key.like("newthread.%") }
                .order { $0.timestamp.desc() }
                .fetchAll(database)
        }) ?? []
    }

    static func replyDrafts(threadId: Int, database appDatabase: AppDatabase = .shared) async -> [EditorDraftEntry] {
        let prefix = "reply.\(threadId)."
        return (try? await appDatabase.read { database in
            try EditorDraftEntry
                .where { $0.key.like("\(prefix)%") }
                .order { $0.timestamp.desc() }
                .fetchAll(database)
        }) ?? []
    }
}
