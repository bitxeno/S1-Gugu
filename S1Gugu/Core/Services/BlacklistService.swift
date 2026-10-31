import Foundation
import OSLog

/// 黑名单/屏蔽词的内存快照与过滤判定。过滤在模型组装层进行,不落在 UI。
@MainActor
final class BlacklistService {

    static let shared = BlacklistService()

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

        /// uid 优先、用户名兜底;同一人两条记录时取更强一级
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
            async let entries = AppDatabase.shared.read { try BlackListEntry.order { $0.id }.fetchAll($0) }
            async let words = AppDatabase.shared.read { try BlackWordEntry.order { $0.id }.fetchAll($0) }
            snapshot = Snapshot(entries: try await entries, words: try await words)
            didLoad = true
        } catch {
            NetworkLog.session.error("黑名单加载失败 \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - 黑名单 CRUD

    func addBlackList(uid: Int, name: String?, postLevel: Int, forumLevel: Int, remark: String?) async {
        _ = try? await AppDatabase.shared.write { database in
            try BlackListEntry.insert {
                BlackListEntry.Draft(
                    uid: uid,
                    name: name,
                    postLevel: postLevel,
                    forumLevel: forumLevel,
                    remark: remark,
                    timestamp: Int(Date().timeIntervalSince1970)
                )
            }.execute(database)
        }
        await reload()
    }

    func updateBlackList(_ entry: BlackListEntry) async {
        var updated = entry
        updated.timestamp = Int(Date().timeIntervalSince1970)
        let row = updated
        _ = try? await AppDatabase.shared.write { database in
            try BlackListEntry.update(row).execute(database)
        }
        await reload()
    }

    func removeBlackList(id: Int) async {
        _ = try? await AppDatabase.shared.write { database in
            try BlackListEntry.find(id).delete().execute(database)
        }
        await reload()
    }

    // MARK: - 屏蔽词 CRUD

    func addBlackWord(word: String, level: Int) async {
        _ = try? await AppDatabase.shared.write { database in
            try BlackWordEntry.insert {
                BlackWordEntry.Draft(word: word, level: level, timestamp: Int(Date().timeIntervalSince1970))
            }.execute(database)
        }
        await reload()
    }

    func updateBlackWord(_ entry: BlackWordEntry) async {
        var updated = entry
        updated.timestamp = Int(Date().timeIntervalSince1970)
        let row = updated
        _ = try? await AppDatabase.shared.write { database in
            try BlackWordEntry.update(row).execute(database)
        }
        await reload()
    }

    func removeBlackWord(id: Int) async {
        _ = try? await AppDatabase.shared.write { database in
            try BlackWordEntry.find(id).delete().execute(database)
        }
        await reload()
    }
}
