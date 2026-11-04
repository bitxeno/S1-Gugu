import Foundation
import OSLog
import SQLiteData

/// 黑名单/屏蔽词的内存快照与过滤判定。过滤在模型组装层进行,不落在 UI。
@MainActor
final class BlacklistService {

    static let shared = BlacklistService()

    /// 黑名单或屏蔽词变更后广播,已打开的列表据此重新过滤
    static let didChangeNotification = Notification.Name("app.bitxeno.s1gugu.blacklistDidChange")

    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    struct Snapshot: Sendable, Equatable {
        var entries: [BlackListEntry] = []
        var words: [BlackWordEntry] = []

        /// 主题强度:0 正常 / 3 隐藏 / 4 删除
        func forumLevel(uid: Int, name: String?) -> Int {
            matchedEntry(uid: uid, name: name)?.forumLevel ?? 0
        }

        /// 回复强度:0 正常 / 1 隐藏 / 2 删除
        func postLevel(uid: Int, name: String?) -> Int {
            matchedEntry(uid: uid, name: name)?.postLevel ?? 0
        }

        /// 引用内容若来自黑名单用户,返回占位文案(remark 或「已被抹布」)
        func quoteReplacement(author: String) -> String? {
            guard let entry = matchedEntry(uid: 0, name: author), entry.postLevel != 0 else { return nil }
            if let remark = entry.remark, !remark.isEmpty { return "[\(remark)]" }
            return "[已被抹布]"
        }

        /// 楼层隐藏占位卡的备注文案
        func matchedRemark(uid: Int, name: String?) -> String? {
            matchedEntry(uid: uid, name: name)?.remark
        }

        /// 正文命中屏蔽词:0 无 / 1 隐藏 / 2 删除
        func wordLevel(in text: String) -> Int {
            guard !text.isEmpty, !words.isEmpty else { return 0 }
            var maxLevel = 0
            for word in words where text.localizedCaseInsensitiveContains(word.word) {
                maxLevel = max(maxLevel, word.level)
                if maxLevel == 2 { break }
            }
            return maxLevel
        }

        /// uid 优先、用户名兜底
        private func matchedEntry(uid: Int, name: String?) -> BlackListEntry? {
            var matched: BlackListEntry?
            if uid > 0 {
                matched = entries.first { $0.uid == uid }
            }
            if matched == nil, let name, !name.isEmpty {
                matched = entries.first { $0.name?.caseInsensitiveCompare(name) == .orderedSame }
            }
            return matched
        }
    }

    private(set) var snapshot = Snapshot()
    private var didLoad = false

    func reloadIfNeeded() async {
        guard !didLoad else { return }
        await reload()
    }

    func reload() async {
        do {
            async let entries = database.read { try BlackListEntry.order { $0.id }.fetchAll($0) }
            async let words = database.read { try BlackWordEntry.order { $0.id }.fetchAll($0) }
            snapshot = Snapshot(entries: try await entries, words: try await words)
            didLoad = true
        } catch {
            NetworkLog.session.error("黑名单加载失败 \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - 黑名单 CRUD

    private struct IncomingBlacklist: Sendable {
        let uid: Int
        let name: String?
        let postLevel: Int
        let forumLevel: Int
        let remark: String?
        let timestamp: Int
    }

    func addBlackList(uid: Int, name: String?, postLevel: Int, forumLevel: Int, remark: String?) async {
        let incoming = IncomingBlacklist(
            uid: max(uid, 0),
            name: normalized(name),
            postLevel: postLevel,
            forumLevel: forumLevel,
            remark: normalized(remark),
            timestamp: Int(Date().timeIntervalSince1970)
        )
        _ = await save([incoming])
    }

    /// 从论坛网页黑名单导入。对齐 S1-Next:默认回复/主题隐藏,已有记录合并并保留原备注。
    /// 返回导入人数;0 表示网页黑名单为空,nil 表示写入失败。
    @discardableResult
    func importWebBlacklist(_ users: [WebBlacklistUser]) async -> Int? {
        var seen = Set<Int>()
        let now = Int(Date().timeIntervalSince1970)
        let incoming = users.compactMap { user -> IncomingBlacklist? in
            guard user.uid > 0, seen.insert(user.uid).inserted else { return nil }
            return IncomingBlacklist(
                uid: user.uid,
                name: normalized(user.name),
                postLevel: 1,
                forumLevel: 3,
                remark: nil,
                timestamp: now
            )
        }
        guard !incoming.isEmpty else { return 0 }
        guard await save(incoming) else { return nil }
        return incoming.count
    }

    private func save(_ incoming: [IncomingBlacklist]) async -> Bool {
        do {
            try await database.write { database in
                for item in incoming {
                    try Self.merge(item, in: database)
                }
            }
            await reload()
            notifyDidChange()
            return true
        } catch {
            NetworkLog.db.error("黑名单保存失败 \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// 与 S1-Next `BlackListBiz.mergeFrom` 对齐:按 uid 或用户名合并已有记录,
    /// 保留原备注,并删除同一用户的重复行。
    private nonisolated static func merge(_ incoming: IncomingBlacklist, in database: Database) throws {
        let entries = try BlackListEntry.order { $0.id }.fetchAll(database)
        let matched = entries.filter { entry in
            let uidMatch = incoming.uid > 0 && entry.uid == incoming.uid
            let nameMatch: Bool
            if let name = incoming.name, !name.isEmpty, let entryName = entry.name {
                nameMatch = entryName.caseInsensitiveCompare(name) == .orderedSame
            } else {
                nameMatch = false
            }
            return uidMatch || nameMatch
        }

        // 同时有 uid 和用户名的记录优先保留
        let keep = matched.max { lhs, rhs in matchScore(lhs) < matchScore(rhs) }
        if let keep {
            var updated = keep
            if incoming.uid > 0 { updated.uid = incoming.uid }
            if let name = incoming.name, !name.isEmpty { updated.name = name }
            updated.postLevel = incoming.postLevel
            updated.forumLevel = incoming.forumLevel
            if let remark = incoming.remark, !remark.isEmpty { updated.remark = remark }
            updated.timestamp = incoming.timestamp
            try BlackListEntry.update(updated).execute(database)
            for duplicate in matched where duplicate.id != keep.id {
                try BlackListEntry.find(duplicate.id).delete().execute(database)
            }
        } else {
            try BlackListEntry.insert {
                BlackListEntry.Draft(
                    uid: incoming.uid,
                    name: incoming.name,
                    postLevel: incoming.postLevel,
                    forumLevel: incoming.forumLevel,
                    remark: incoming.remark,
                    timestamp: incoming.timestamp
                )
            }.execute(database)
        }
    }

    private nonisolated static func matchScore(_ entry: BlackListEntry) -> Int {
        (entry.uid > 0 ? 1 : 0) + ((entry.name?.isEmpty == false) ? 1 : 0)
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    private func notifyDidChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    func updateBlackList(_ entry: BlackListEntry) async {
        var updated = entry
        updated.timestamp = Int(Date().timeIntervalSince1970)
        let row = updated
        _ = try? await database.write { database in
            try BlackListEntry.update(row).execute(database)
        }
        await reload()
        notifyDidChange()
    }

    func removeBlackList(id: Int) async {
        _ = try? await database.write { database in
            try BlackListEntry.find(id).delete().execute(database)
        }
        await reload()
        notifyDidChange()
    }

    /// 按 uid(优先)或用户名查找已存在的黑名单条目
    func existingBlacklist(uid: Int, name: String?) -> BlackListEntry? {
        if uid > 0, let byUid = snapshot.entries.first(where: { $0.uid == uid }) {
            return byUid
        }
        if let name, !name.isEmpty {
            return snapshot.entries.first { $0.name?.caseInsensitiveCompare(name) == .orderedSame }
        }
        return nil
    }

    /// 按 uid/用户名移除黑名单
    func removeBlackList(uid: Int, name: String?) async {
        guard let entry = existingBlacklist(uid: uid, name: name) else { return }
        await removeBlackList(id: entry.id)
    }

    // MARK: - 屏蔽词 CRUD

    func addBlackWord(word: String, level: Int) async {
        _ = try? await database.write { database in
            try BlackWordEntry.insert {
                BlackWordEntry.Draft(word: word, level: level, timestamp: Int(Date().timeIntervalSince1970))
            }.execute(database)
        }
        await reload()
        notifyDidChange()
    }

    func updateBlackWord(_ entry: BlackWordEntry) async {
        var updated = entry
        updated.timestamp = Int(Date().timeIntervalSince1970)
        let row = updated
        _ = try? await database.write { database in
            try BlackWordEntry.update(row).execute(database)
        }
        await reload()
        notifyDidChange()
    }

    func removeBlackWord(id: Int) async {
        _ = try? await database.write { database in
            try BlackWordEntry.find(id).delete().execute(database)
        }
        await reload()
        notifyDidChange()
    }
}
