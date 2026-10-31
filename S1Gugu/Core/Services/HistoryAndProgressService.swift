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
