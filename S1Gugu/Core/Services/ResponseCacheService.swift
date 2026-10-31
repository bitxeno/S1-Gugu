import Foundation
import OSLog
import SQLiteData
import SwiftyJSON

/// 列表响应缓存(cache-first,对齐 S1-Next S1ApiCacheProvider):
/// 打开列表先渲染缓存,同时后台刷新;网络失败回退缓存。
/// key 按账号隔离(uid);LRU 裁剪上限 300 条。
enum ResponseCacheService {

    static let maxEntries = 300

    // MARK: - Key 构造(对齐 S1-Next u{uid}#类型#参数)

    private static func uidKey() async -> String {
        let uid = await SessionStore.shared.state.uid ?? 0
        return "u\(uid)"
    }

    static func forumIndexKey() async -> String {
        "\(await uidKey())#forumindex"
    }

    static func threadsKey(fid: Int, typeId: String?, page: Int) async -> String {
        "\(await uidKey())#threads#\(fid),\(typeId ?? ""),\(page)"
    }

    static func postsKey(tid: Int, page: Int, authorId: Int?) async -> String {
        "\(await uidKey())#posts#\(tid),\(page),\(authorId ?? 0)"
    }

    // MARK: - 读写

    /// 读缓存 JSON;超过 staleLimit 秒视为过期但仍返回(调用方决定是否后台刷新)
    static func json(forKey key: String) async -> JSON? {
        guard let entry = try? await AppDatabase.shared.read({ database in
            try ResponseCacheEntry.find(key).fetchOne(database)
        }), let data = entry.payload.data(using: .utf8)
        else { return nil }
        return try? JSON(data: data)
    }

    static func timestamp(forKey key: String) async -> Int? {
        try? await AppDatabase.shared.read { database in
            try ResponseCacheEntry.find(key).fetchOne(database)?.timestamp
        }
    }

    static func store(_ json: JSON, forKey key: String) async {
        let payload = json.rawString() ?? ""
        let now = Int(Date().timeIntervalSince1970)
        _ = try? await AppDatabase.shared.write { database in
            try ResponseCacheEntry.upsert {
                ResponseCacheEntry(key: key, payload: payload, timestamp: now)
            }.execute(database)
            // LRU 裁剪:只保留最近 maxEntries 条
            let overflow = try ResponseCacheEntry
                .order { $0.timestamp.desc() }
                .limit(-1, offset: maxEntries)
                .fetchAll(database)
            if !overflow.isEmpty {
                try ResponseCacheEntry
                    .where { $0.key.in(overflow.map(\.key)) }
                    .delete()
                    .execute(database)
            }
        }
    }

    /// 清空列表缓存(设置里可用;不含帖子备份)
    static func clearAll() async {
        _ = try? await AppDatabase.shared.write { database in
            try database.execute(sql: "DELETE FROM responsecache")
        }
    }

    // MARK: - 缓存年龄文案

    static func ageText(_ timestamp: Int) -> String {
        let age = Int(Date().timeIntervalSince1970) - timestamp
        switch age {
        case ..<60: return "刚刚"
        case ..<3600: return "\(age / 60) 分钟前"
        case ..<86400: return "\(age / 3600) 小时前"
        default: return "\(age / 86400) 天前"
        }
    }
}
