import Foundation
import SwiftyJSON

// MARK: - SwiftyJSON 宽容读取扩展

extension JSON {
    /// 数字/字符串混用字段(Discuz 手拼 JSON 两者随机出现)的宽容读取
    var flexibleString: String {
        if let string { return string }
        if let number {
            let double = number.doubleValue
            if double.truncatingRemainder(dividingBy: 1) == 0, abs(double) < 9e15 {
                return String(Int64(double))
            }
            return String(describing: number)
        }
        return rawString() ?? ""
    }

    /// 缺失/null → nil,有值 → flexibleString
    var flexibleStringOrNil: String? {
        if !exists() || type == .null { return nil }
        let value = flexibleString
        return value.isEmpty ? nil : value
    }

    /// 字符串数字也能转(string "36" → 36);缺失/null → 0
    var flexibleInt: Int {
        if let i = int { return i }
        return Int(flexibleString) ?? 0
    }

    /// 同 flexibleInt,但缺失/null → nil(用于可选字段)
    var flexibleIntOrNil: Int? {
        if !exists() || type == .null { return nil }
        if let i = int { return i }
        return Int(flexibleString)
    }
}

// MARK: - 版块

struct Forum: Sendable, Identifiable, Hashable {
    let fid: String
    let name: String?
    let threads: Int
    let todayposts: Int

    var id: Int { Int(fid) ?? 0 }
    var displayName: String { name ?? "(未命名版块)" }

    init(fid: String = "", name: String? = nil, threads: Int = 0, todayposts: Int = 0) {
        self.fid = fid
        self.name = name
        self.threads = threads
        self.todayposts = todayposts
    }

    init(json: JSON) {
        fid = json["fid"].flexibleString
        name = json["name"].flexibleStringOrNil
        threads = json["threads"].intValue
        todayposts = json["todayposts"].intValue
    }
}

/// 版块组列表的最终模型(按 catlist 顺序分组,组内按今日帖数降序,对齐 S1-Next)
struct ForumSection: Sendable, Identifiable, Equatable {
    let id: String
    let categoryName: String
    let forums: [Forum]
}

// MARK: - 主题

struct Thread: Sendable, Identifiable, Hashable {
    let tid: String
    let subject: String?
    let replies: String
    let author: String
    let authorId: Int
    let displayorder: Int
    let typeid: String?
    let dbdateline: String?
    let dblastpost: String?
    let views: Int
    let special: Int
    let attachment: Int
    let readperm: Int

    /// 黑名单过滤标记(模型组装层填充,非 API 字段)
    var isHiddenByBlacklist: Bool = false
    var blacklistRemark: String?

    var id: Int { Int(tid) ?? 0 }
    var title: String { subject ?? "(无标题)" }
    var replyCount: Int { Int(replies) ?? 0 }
    var isSticky: Bool { displayorder > 0 }
    var hasAttachment: Bool { attachment > 0 }
    var isVote: Bool { special == 1 }

    /// dbdateline 可能是 Unix 时间戳串,也可能是服务端格式化串
    var publishedText: String { Self.formatDate(dbdateline) }
    var lastPostText: String { Self.formatDate(dblastpost) }

    static func formatDate(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        if let seconds = Double(value), seconds > 1_000_000_000 {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter.string(from: Date(timeIntervalSince1970: seconds))
        }
        return value
    }

    init(threadId: Int, title: String) {
        tid = String(threadId)
        subject = title
        replies = "0"
        author = ""
        authorId = 0
        displayorder = 0
        typeid = nil
        dbdateline = nil
        dblastpost = nil
        views = 0
        special = 0
        attachment = 0
        readperm = 0
    }

    init(json: JSON) {
        tid = json["tid"].flexibleString
        subject = json["subject"].flexibleStringOrNil
        replies = json["replies"].flexibleString
        author = json["author"].flexibleString
        authorId = json["authorid"].intValue
        displayorder = json["displayorder"].intValue
        typeid = json["typeid"].flexibleStringOrNil
        dbdateline = json["dbdateline"].flexibleStringOrNil
        dblastpost = json["dblastpost"].flexibleStringOrNil
        views = json["views"].intValue
        special = json["special"].intValue
        attachment = json["attachment"].intValue
        readperm = json["readperm"].intValue
    }
}

// MARK: - 帖子与附件

struct PostAttachment: Sendable, Equatable, Hashable {
    let url: String
    let attachment: String
    let isimage: String?
    let filename: String?
    let filesize: Int
    let ext: String?

    var isImage: Bool { isimage != "0" }
    var realURL: URL? {
        let combined = url + attachment
        guard !combined.isEmpty else { return nil }
        return URL(string: combined)
    }

    init(json: JSON) {
        url = json["url"].flexibleString
        attachment = json["attachment"].flexibleString
        isimage = json["isimage"].flexibleStringOrNil
        filename = json["filename"].flexibleStringOrNil
        filesize = json["filesize"].intValue
        ext = json["ext"].flexibleStringOrNil
    }
}

/// viewthread 单楼原始数据(message 为服务端预渲染 HTML,后续进渲染管线)
struct RawPost: Sendable {
    let pid: Int
    let author: String
    let authorId: Int
    let isFirst: Bool
    let message: String?
    let number: String?
    let dbdateline: String
    let attachments: [Int: PostAttachment]

    init(json: JSON) {
        pid = json["pid"].intValue
        author = json["author"].flexibleString
        authorId = json["authorid"].intValue
        isFirst = json["first"].flexibleString == "1"
        message = json["message"].flexibleStringOrNil
        number = json["number"].flexibleStringOrNil
        dbdateline = json["dbdateline"].flexibleString
        // attachments 可能是对象、空数组或缺省,遍历时统一安全
        var map: [Int: PostAttachment] = [:]
        for (key, sub) in json["attachments"] {
            if let aid = Int(key) {
                map[aid] = PostAttachment(json: sub)
            }
        }
        attachments = map
    }
}

/// 渲染管线输入的帖子模型
struct Post: Sendable, Identifiable, Equatable {
    let pid: Int
    let author: String
    let authorId: Int
    let isFirst: Bool
    let floor: Int?
    let dateTimeText: String
    let avatarURL: URL?
    let banned: Bool
    let isOp: Bool
    /// 预处理后的 HTML(通用清洗,不含黑名单处理)
    let preprocessedHTML: String
    let attachments: [Int: PostAttachment]

    var id: Int { pid }

    /// 黑名单过滤标记(0 正常 / 1 隐藏 / 2 删除)
    var hideFlag: Int = 0
    var hideRemark: String?
}

// MARK: - 收藏

struct Favourite: Sendable, Identifiable, Hashable {
    let id: String
    let favid: String?
    let title: String?
    let description: String?
    let dateline: String?

    var threadId: Int { Int(id) ?? 0 }
    var displayName: String { title ?? "(无标题)" }

    init(json: JSON) {
        id = json["id"].flexibleString
        favid = json["favid"].flexibleStringOrNil
        title = json["title"].flexibleStringOrNil
        description = json["description"].flexibleStringOrNil
        dateline = json["dateline"].flexibleStringOrNil
    }
}

// MARK: - 私信与通知

struct PmGroup: Sendable, Identifiable, Hashable {
    let plId: String
    let isNew: Bool
    let lastAuthor: String?
    let lastSummary: String?
    let lastDateline: String
    let pmNum: String
    let toUid: String
    let toUsername: String?

    var id: String { plId.isEmpty ? toUid : plId }
    var displayName: String { toUsername ?? lastAuthor ?? "私信" }
    var lastTimeText: String { Thread.formatDate(lastDateline) }

    init(json: JSON) {
        plId = json["plid"].flexibleString
        isNew = json["isnew"].flexibleString == "1"
        lastAuthor = json["lastauthor"].flexibleStringOrNil
        lastSummary = json["lastsummary"].flexibleStringOrNil
        lastDateline = json["lastdateline"].flexibleString
        pmNum = json["pmnum"].flexibleString
        toUid = json["touid"].flexibleString
        toUsername = json["tousername"].flexibleStringOrNil
    }
}

struct PrivateMessage: Sendable, Identifiable, Hashable {
    let pmId: String
    let authorId: String
    let author: String?
    let message: String?
    let dateline: String

    var id: String { pmId.isEmpty ? "\(dateline)-\(message ?? "")" : pmId }
    var timeText: String { Thread.formatDate(dateline) }

    init(json: JSON) {
        pmId = json["pmid"].flexibleString
        authorId = json["authorid"].flexibleString
        author = json["author"].flexibleStringOrNil
        message = json["message"].flexibleStringOrNil
        dateline = json["dateline"].flexibleString
    }
}

struct Note: Sendable, Identifiable, Hashable {
    let noteId: String
    let author: String?
    let authorId: String
    let note: String?
    let dateline: String

    var id: String { "\(noteId)-\(dateline)-\(note ?? "")" }
    var timeText: String { Thread.formatDate(dateline) }

    init(json: JSON) {
        noteId = json["id"].flexibleString
        author = json["author"].flexibleStringOrNil
        authorId = json["authorid"].flexibleString
        note = json["note"].flexibleStringOrNil
        dateline = json["dateline"].flexibleString
    }
}

// MARK: - 用户资料

struct Profile: Sendable {
    let uid: String
    let username: String?
    let avatarURL: URL?
    let groupTitle: String?
    let signatureHTML: String?
    let friendsCount: Int
    let threadsCount: Int
    let repliesCount: Int
    let regDate: String?
    let lastVisitDate: String?

    init(json: JSON) {
        let space = json["space"]
        uid = space["uid"].flexibleString
        username = space["username"].flexibleStringOrNil
        avatarURL = space["avatar"].string.flatMap(URL.init(string:))
        groupTitle = space["group"]["grouptitle"].flexibleStringOrNil
        signatureHTML = space["signature"].flexibleStringOrNil
        friendsCount = space["friends"].intValue
        threadsCount = space["threads"].intValue
        repliesCount = space["posts"].intValue
        regDate = space["regdate"].flexibleStringOrNil
        lastVisitDate = space["lastvisit"].flexibleStringOrNil
    }
}

struct Friend: Sendable, Identifiable, Hashable {
    let uid: String
    let username: String?

    var id: String { uid }
    var displayName: String { username ?? "UID \(uid)" }

    init(json: JSON) {
        let fuid = json["fuid"].flexibleString
        uid = fuid.isEmpty ? json["uid"].flexibleString : fuid
        let name = json["fusername"].flexibleStringOrNil
        username = name ?? json["username"].flexibleStringOrNil
    }
}

// MARK: - 投票

struct VoteOptionInfo: Sendable, Identifiable, Hashable {
    let id: Int
    let option: String
    let votes: Int
    let percent: String?

    init(json: JSON) {
        id = json["polloptionid"].flexibleInt
        option = json["_option"].flexibleString
        votes = json["votes"].flexibleInt
        percent = json["percent"].flexibleStringOrNil
    }
}

struct VoteInfo: Sendable, Hashable {
    let allowVote: Bool
    let maxChoices: Int
    let multiple: Bool
    let visiblePoll: Bool
    let votersCount: Int
    let options: [VoteOptionInfo]

    init(json: JSON) {
        let allow = json["allowvote"]
        allowVote = allow.type == .bool ? allow.boolValue : allow.flexibleString == "1"
        maxChoices = json["maxchoices"].flexibleInt
        let multipleJson = json["multiple"]
        self.multiple = multipleJson.type == .bool ? multipleJson.boolValue : multipleJson.flexibleString == "1"
        let visible = json["visiblepoll"]
        visiblePoll = visible.type == .bool ? visible.boolValue : visible.flexibleString == "1"
        votersCount = json["voterscount"].flexibleInt
        options = json["polloptions"]
            .dictionaryValue
            .values
            .map { VoteOptionInfo(json: $0) }
            .sorted { $0.id < $1.id }
    }
}

// MARK: - 小黑屋

struct DarkRoomItem: Sendable, Identifiable, Hashable {
    let cid: String
    let uid: String
    let username: String?
    let action: String?
    let reason: String?
    let operatorName: String?
    let dateline: String?
    let groupExpiry: String?

    var id: String { cid }
}

struct DarkRoomPage: Sendable {
    let items: [DarkRoomItem]
    /// 翻页锚点(message "1|79047" 的后半段)
    let nextCid: String?
}
