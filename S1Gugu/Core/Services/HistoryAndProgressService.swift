import Foundation

/// 浏览历史(上限 300 条,同 tid 更新时间戳)
enum HistoryService {

    static let maxCount = 300

    static func add(threadId: Int, title: String) async {
        guard threadId > 0 else { return }
        do {
            try await AppDatabase.shared.write { (database) -> Void in
                try HistoryEntry.upsert {
                    HistoryEntry(threadId: threadId, title: title, timestamp: Int(Date().timeIntervalSince1970))
                }.execute(database)
                let overflow = try HistoryEntry.order { $0.timestamp.desc() }
                    .limit(-1, offset: maxCount)
                    .fetchAll(database)
                if !overflow.isEmpty {
                    try HistoryEntry
                        .where { $0.threadId.in(overflow.map(\.threadId)) }
                        .delete()
                        .execute(database)
                }
            }
        } catch {
            NetworkLog.db.error("历史写入失败 \(String(describing: error), privacy: .public)")
        }
    }

    static func entries(query: String? = nil) async -> [HistoryEntry] {
        (try? await AppDatabase.shared.read { database in
            if let query, !query.isEmpty {
                try HistoryEntry
                    .where { $0.title.like("%\(query)%") }
                    .order { $0.timestamp.desc() }
                    .fetchAll(database)
            } else {
                try HistoryEntry.order { $0.timestamp.desc() }.fetchAll(database)
            }
        }) ?? []
    }

    static func remove(threadId: Int) async {
        _ = try? await AppDatabase.shared.write { database in
            try HistoryEntry.find(threadId).delete().execute(database)
        }
    }

    static func clear() async {
        _ = try? await AppDatabase.shared.write { database in
            try database.execute(sql: "DELETE FROM history")
        }
    }
}

extension HistoryService {
    static func title(of threadId: Int) async -> String? {
        try? await AppDatabase.shared.read { database in
            try HistoryEntry.find(threadId).fetchOne(database)?.title
        }
    }
}

/// 阅读进度(页码 + 首个可见楼层 pid)
enum ReadProgressService {

    static func progress(for threadId: Int) async -> ReadProgressEntry? {
        try? await AppDatabase.shared.read { database in
            try ReadProgressEntry.find(threadId).fetchOne(database)
        }
    }

    static func save(threadId: Int, page: Int, anchorPid: Int) async {
        guard threadId > 0 else { return }
        _ = try? await AppDatabase.shared.write { database in
            try ReadProgressEntry.upsert {
                ReadProgressEntry(
                    threadId: threadId,
                    page: page,
                    anchorPid: anchorPid,
                    timestamp: Int(Date().timeIntervalSince1970)
                )
            }.execute(database)
        }
    }
}

/// 上次浏览帖子时的回复总数(对齐 S1-Next DbThread.lastCountWhenView):
/// 版块列表用「当前回复数 − 上次浏览回复数」渲染「+N」新回复标记。
enum DbThreadService {

    static func lastCountWhenView(for threadId: Int) async -> Int {
        (try? await AppDatabase.shared.read { database in
            try DbThreadEntry.find(threadId).fetchOne(database)?.lastCountWhenView ?? 0
        }) ?? 0
    }

    /// 一次读取整批 tid 的记录,供列表页拼装模型
    static func entries(threadIds: [Int]) async -> [Int: DbThreadEntry] {
        guard !threadIds.isEmpty else { return [:] }
        return (try? await AppDatabase.shared.read { database in
            let entries = try DbThreadEntry
                .where { $0.threadId.in(threadIds) }
                .fetchAll(database)
            return Dictionary(uniqueKeysWithValues: entries.map { ($0.threadId, $0) })
        }) ?? [:]
    }

    static func save(threadId: Int, replyCount: Int) async {
        guard threadId > 0, replyCount > 0 else { return }
        _ = try? await AppDatabase.shared.write { database in
            try DbThreadEntry.upsert {
                DbThreadEntry(
                    threadId: threadId,
                    lastCountWhenView: replyCount,
                    timestamp: Int(Date().timeIntervalSince1970)
                )
            }.execute(database)
        }
    }
}

/// 版块收藏(纯本地):论坛首页顶部「收藏」区块,支持拖动排序。
enum ForumFavoriteService {

    static func entries() async -> [ForumFavoriteEntry] {
        (try? await AppDatabase.shared.read { database in
            try ForumFavoriteEntry.order { $0.sortOrder }.fetchAll(database)
        }) ?? []
    }

    static func isFavorite(forumId: Int) async -> Bool {
        guard forumId > 0 else { return false }
        return (try? await AppDatabase.shared.read { database in
            try ForumFavoriteEntry.find(forumId).fetchOne(database) != nil
        }) ?? false
    }

    /// 切换收藏状态,返回切换后是否已收藏
    @discardableResult
    static func toggle(forum: Forum) async -> Bool {
        let forumId = forum.id
        guard forumId > 0 else { return false }
        return (try? await AppDatabase.shared.write { database -> Bool in
            if try ForumFavoriteEntry.find(forumId).fetchOne(database) != nil {
                try ForumFavoriteEntry.find(forumId).delete().execute(database)
                return false
            }
            let maxOrder = try ForumFavoriteEntry
                .order { $0.sortOrder.desc() }
                .limit(1)
                .fetchOne(database)?.sortOrder ?? -1
            try ForumFavoriteEntry.upsert {
                ForumFavoriteEntry(forumId: forumId, name: forum.displayName, sortOrder: maxOrder + 1)
            }.execute(database)
            return true
        }) ?? false
    }

    /// 拖动排序落地:把最终顺序写回 sortOrder
    static func saveOrder(ids: [Int]) async {
        guard !ids.isEmpty else { return }
        _ = try? await AppDatabase.shared.write { database in
            for (index, forumId) in ids.enumerated() {
                try database.execute(
                    sql: "UPDATE \"forumfavorite\" SET \"sortOrder\" = ? WHERE \"forumId\" = ?",
                    arguments: [index, forumId]
                )
            }
        }
    }
}
