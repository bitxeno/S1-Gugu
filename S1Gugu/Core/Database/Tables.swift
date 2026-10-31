import Foundation
import SQLiteData

// MARK: - 用户黑名单

/// 过滤维度与强度对齐 S1-Next:
/// postLevel:0 正常 / 1 隐藏(占位) / 2 删除;forumLevel:0 正常 / 3 隐藏 / 4 删除
@Table("blacklist")
struct BlackListEntry: Identifiable, Sendable, Equatable, Hashable {
    let id: Int
    var uid: Int = 0
    var name: String?
    var postLevel: Int = 0
    var forumLevel: Int = 0
    var remark: String?
    var timestamp: Int = 0
}

// MARK: - 屏蔽词

/// level:1 隐藏 / 2 删除
@Table("blackword")
struct BlackWordEntry: Identifiable, Sendable, Equatable, Hashable {
    let id: Int
    var word: String = ""
    var level: Int = 0
    var timestamp: Int = 0
}

// MARK: - 浏览历史(上限 300 条)

@Table("history")
struct HistoryEntry: Identifiable, Sendable, Equatable, Hashable {
    @Column(primaryKey: true)
    var threadId: Int
    var title: String = ""
    var timestamp: Int = 0

    var id: Int { threadId }
}

// MARK: - 阅读进度(锚点 = 楼层 pid)

@Table("readprogress")
struct ReadProgressEntry: Identifiable, Sendable, Equatable, Hashable {
    @Column(primaryKey: true)
    var threadId: Int
    var page: Int = 1
    var anchorPid: Int = 0
    var timestamp: Int = 0

    var id: Int { threadId }
}

// MARK: - 帖子离线备份(整帖原始 JSON,离线时重跑渲染管线)

@Table("postbackup")
struct PostBackupEntry: Identifiable, Sendable, Equatable, Hashable {
    @Column(primaryKey: true)
    var threadId: Int
    var title: String = ""
    var pageCount: Int = 0
    /// JSON:{"pages":[{"page":1,"posts":[原始 RawPost JSON…]}]}
    var payload: String = ""
    var timestamp: Int = 0

    var id: Int { threadId }
}

// MARK: - 多账号(凭据在 Keychain 按 name 索引,此处只存元数据)

@Table("accounts")
struct AccountEntry: Identifiable, Sendable, Equatable, Hashable {
    let id: Int
    var uid: Int = 0
    var name: String = ""
    var lastUsedAt: Int = 0
}

// MARK: - 列表响应缓存(cache-first 秒开,对齐 S1-Next CacheDatabase 思路)

@Table("responsecache")
struct ResponseCacheEntry: Identifiable, Sendable, Equatable, Hashable {
    @Column(primaryKey: true)
    var key: String
    /// 响应原文 JSON(离线/秒开时重走解析管线)
    var payload: String = ""
    var timestamp: Int = 0

    var id: String { key }
}
