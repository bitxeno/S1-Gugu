import Foundation
import SwiftyJSON

// MARK: - 结果模型

struct ThreadsResult: Sendable {
    let forumName: String?
    let threads: [Thread]
    let subForums: [Forum]
    let threadTypes: [String: String]
}

struct PostsResult: Sendable {
    let forumId: Int?
    /// 该页 postlist 原始 JSON(离线备份用)
    let rawPageJSON: String?
    /// 主楼投票(可能为 nil)
    let vote: VoteInfo?
    struct ThreadSummary: Sendable {
        let tid: String
        let subject: String?
        let replies: String
        let author: String
        let authorId: Int
        let maxposition: Int?

        init(json: JSON) {
            tid = json["tid"].flexibleString
            subject = json["subject"].flexibleStringOrNil
            replies = json["replies"].flexibleString
            author = json["author"].flexibleString
            authorId = json["authorid"].intValue
            maxposition = json["maxposition"].flexibleIntOrNil
        }

        /// 离线备份回退时的摘要占位
        init(tid: String, subject: String?, replies: String, author: String, authorId: Int, maxposition: Int?) {
            self.tid = tid
            self.subject = subject
            self.replies = replies
            self.author = author
            self.authorId = authorId
            self.maxposition = maxposition
        }
    }

    let thread: ThreadSummary?
    let posts: [Post]
    let page: Int
    let pageCount: Int
}

struct FavoritesPage: Sendable {
    let items: [Favourite]
    let page: Int
    let hasMore: Bool
}

struct PmPage: Sendable {
    let items: [PmGroup]
    let hasMore: Bool
}

struct PmMessagesPage: Sendable {
    let items: [PrivateMessage]
    let hasMore: Bool
}

struct NotesPage: Sendable {
    let items: [Note]
    let hasMore: Bool
}

// MARK: - API

/// Discuz 移动 API 端点层。SwiftyJSON 宽松解析(字段增减安全),
/// 前置 ResponseCleaner 清洗服务端脏 JSON。所有响应都会喂给 SessionStore。
struct DiscuzAPI: Sendable {

    static let shared = DiscuzAPI()

    var client: S1APIClient = .shared

    static let threadsPerPage = 50
    static let postsPerPage = 40

    // MARK: 读

    func forumIndex() async throws -> [ForumSection] {
        let json = try await fetch(query: ["module": "forumindex"])
        await ResponseCacheService.store(json, forKey: ResponseCacheService.forumIndexKey())
        return Self.parseForumIndex(json)
    }

    static func parseForumIndex(_ json: JSON) -> [ForumSection] {
        let variables = json["Variables"]
        var forums = variables["forumlist"].arrayValue.map { Forum(json: $0) }
        forums.sort { $0.todayposts > $1.todayposts }
        let byId = Dictionary(uniqueKeysWithValues: forums.map { ($0.id, $0) })
        var sections: [ForumSection] = []
        for category in variables["catlist"].arrayValue {
            let ids = category["forums"].arrayValue.compactMap { $0.flexibleInt }
            let list = ids.compactMap { byId[$0] }
            guard !list.isEmpty else { continue }
            sections.append(
                ForumSection(
                    id: category["name"].stringValue.isEmpty ? "cat\(sections.count)" : category["name"].stringValue,
                    categoryName: category["name"].stringValue,
                    forums: list
                )
            )
        }
        return sections
    }

    func threads(fid: Int, page: Int, typeId: String? = nil) async throws -> ThreadsResult {
        var query: [String: String] = [
            "module": "forumdisplay",
            "version": "4",
            "filter": "typeid",
            "tpp": String(Self.threadsPerPage),
            "fid": String(fid),
            "page": String(page),
        ]
        if let typeId, !typeId.isEmpty {
            query["typeid"] = typeId
        }
        let json = try await fetch(query: query)
        await ResponseCacheService.store(json, forKey: ResponseCacheService.threadsKey(fid: fid, typeId: typeId, page: page))
        return Self.parseThreads(json)
    }

    static func parseThreads(_ json: JSON) -> ThreadsResult {
        let variables = json["Variables"]
        var types: [String: String] = [:]
        for (id, name) in variables["threadtypes"]["types"] {
            types[id] = name.stringValue
        }
        return ThreadsResult(
            forumName: variables["forum"]["name"].flexibleStringOrNil,
            threads: variables["forum_threadlist"].arrayValue.map { Thread(json: $0) },
            subForums: variables["sublist"].arrayValue.map { Forum(json: $0) },
            threadTypes: types
        )
    }

    func posts(tid: Int, page: Int, authorId: Int? = nil) async throws -> PostsResult {
        // 回复列表走 checkpost 接口(version=1 + submodule=checkpost + mobile=no)。
        // 相比旧 version=4:引用为 <blockquote>(已由 PostPreprocessor 原生处理)、
        // 附带「本帖最后由…编辑」信息;Variables 结构与 postlist/thread/special_poll 一致。
        var query: [String: String] = [
            "mobile": "no",
            "module": "viewthread",
            "version": "1",
            "submodule": "checkpost",
            "ppp": String(Self.postsPerPage),
            "tid": String(tid),
            "page": String(page),
        ]
        if let authorId, authorId > 0 {
            query["authorid"] = String(authorId)
        }
        let json = try await fetch(query: query)
        await ResponseCacheService.store(json, forKey: ResponseCacheService.postsKey(tid: tid, page: page, authorId: authorId))
        return Self.parsePosts(json)
    }

    static func parsePosts(_ json: JSON) -> PostsResult {
        let payload = json["Variables"]
        let summary = payload["thread"].exists() ? PostsResult.ThreadSummary(json: payload["thread"]) : nil
        let rawPosts = payload["postlist"].arrayValue.map { RawPost(json: $0) }
        let posts = rawPosts.map { PostAssembler.assemble($0, threadAuthor: summary?.author) }
        let pageCount = payload["pagecount"].flexibleIntOrNil
            ?? summary?.maxposition.map { ($0 + Self.postsPerPage - 1) / Self.postsPerPage }
            ?? estimatedPageCount(replies: Int(summary?.replies ?? "0") ?? 0)
        let page = payload["page"].flexibleIntOrNil ?? 1
        return PostsResult(
            forumId: payload["fid"].int,
            rawPageJSON: payload["postlist"].rawString(),
            vote: payload["special_poll"].exists() ? VoteInfo(json: payload["special_poll"]) : nil,
            thread: summary,
            posts: posts,
            page: page,
            pageCount: max(pageCount, 1)
        )
    }

    func favorites(page: Int) async throws -> FavoritesPage {
        let json = try await fetch(query: ["module": "myfavthread", "page": String(page)])
        let payload = json["Variables"]
        let items = payload["list"].arrayValue.map { Favourite(json: $0) }
        return FavoritesPage(items: items, page: page, hasMore: items.count >= Self.threadsPerPage)
    }

    // MARK: 会话

    func performLogin(username: String, password: String, questionId: Int, answer: String) async throws {
        let json = try await fetch(
            query: [
                "module": "login",
                "loginsubmit": "yes",
                "loginfield": "auto",
                "cookietime": "2592000",
            ],
            form: [
                "username": username,
                "password": password,
                "questionid": String(questionId),
                "answer": answer,
            ]
        )
        try requireSuccess(json, fallbackMessage: "登录失败")
        if json["Variables"].exists() == false && json["Message"].exists() == false {
            throw APIError.invalidResponse
        }
    }

    /// 登录后首个 formhash 视为过期,必须请求 toplist 刷新。
    func refreshFormhash() async throws {
        _ = try await fetch(query: ["module": "toplist"])
    }

    // MARK: 写(需 formhash)

    func addFavorite(tid: Int, description: String) async throws {
        let formhash = try await SessionStore.shared.requireFormhash()
        let json = try await fetch(
            query: ["module": "favthread", "favoritesubmit": "yes"],
            form: ["formhash": formhash, "id": String(tid), "description": description]
        )
        try requireSuccess(json, fallbackMessage: "收藏失败")
    }

    func removeFavorite(favId: String) async throws {
        let formhash = try await SessionStore.shared.requireFormhash()
        let json = try await fetch(
            query: ["module": "favthread", "deletesubmit": "true", "op": "delete"],
            form: ["formhash": formhash, "favid": favId]
        )
        try requireSuccess(json, fallbackMessage: "移除收藏失败")
    }

    // MARK: 回复 / 发帖 / 编辑

    /// 引用回复上下文(来自编辑器表单)
    struct QuoteContext: Sendable {
        let repQuotePid: Int
        let noticeAuthor: String
        let noticeTrimStr: String
        let formhash: String
    }

    /// 拉取回复编辑器表单,提取引用所需字段
    func replyQuoteContext(tid: Int, repQuotePid: Int) async throws -> QuoteContext {
        let editor = try await WebChannel.getEditorInfo(
            path: "forum.php",
            query: ["mod": "post", "action": "reply", "inajax": "yes", "tid": String(tid), "repquote": String(repQuotePid)]
        )
        guard let noticeAuthor = editor.noticeAuthor, let noticeTrimStr = editor.noticeTrimStr else {
            throw APIError.server("获取引用信息失败")
        }
        let fallbackHash = await SessionStore.shared.state.formhash ?? ""
        let formhash = editor.formhash ?? fallbackHash
        return QuoteContext(repQuotePid: repQuotePid, noticeAuthor: noticeAuthor, noticeTrimStr: noticeTrimStr, formhash: formhash)
    }

    /// 纯文本回复(无论坛附件)
    func reply(tid: Int, message: String, quote: QuoteContext?) async throws {
        let fallbackHash = try await SessionStore.shared.requireFormhash()
        let formhash = quote?.formhash ?? fallbackHash
        var form: [String: String] = ["formhash": formhash, "tid": String(tid), "message": message]
        if let quote {
            form["noticeauthor"] = quote.noticeAuthor
            form["noticetrimstr"] = quote.noticeTrimStr
        }
        let json = try await fetch(
            query: ["module": "sendreply", "replysubmit": "yes"],
            form: form
        )
        try requireSuccess(json, fallbackMessage: "回复失败")
    }

    /// 纯文本发新主题(无论坛附件)
    func newThread(fid: Int, typeId: String?, subject: String, message: String, formhash: String?, posttime: String?) async throws {
        let fallbackHash = try await SessionStore.shared.requireFormhash()
        let hash = formhash ?? fallbackHash
        var form: [String: String] = [
            "formhash": hash,
            "posttime": posttime ?? String(Int(Date().timeIntervalSince1970)),
            "subject": subject,
            "message": message,
            "allownoticeauthor": "1",
            "usesig": "1",
        ]
        if let typeId, !typeId.isEmpty { form["typeid"] = typeId }
        let json = try await fetch(
            query: ["module": "newthread", "extra": "", "topicsubmit": "yes", "fid": String(fid)],
            form: form
        )
        try requireSuccess(json, fallbackMessage: "发布失败")
    }

    // MARK: 私信 / 通知

    func pmGroups(page: Int) async throws -> PmPage {
        let json = try await fetch(
            query: ["module": "mypm", "filter": "privatepm", "page": String(page)]
        )
        let items = json["Variables"]["list"].arrayValue.map { PmGroup(json: $0) }
        return PmPage(items: items, hasMore: items.count >= Self.threadsPerPage)
    }

    func pmMessages(touid: String, page: Int) async throws -> PmMessagesPage {
        let json = try await fetch(
            query: ["module": "mypm", "subop": "view", "touid": touid, "page": String(page)]
        )
        let items = json["Variables"]["list"].arrayValue.map { PrivateMessage(json: $0) }
        return PmMessagesPage(items: items, hasMore: items.count >= 10)
    }

    func sendPm(touid: String, message: String) async throws {
        let formhash = try await SessionStore.shared.requireFormhash()
        let json = try await fetch(
            query: ["module": "sendpm", "pmsubmit": "true"],
            form: ["formhash": formhash, "touid": touid, "message": message]
        )
        try requireSuccess(json, fallbackMessage: "发送失败")
    }

    func notices(page: Int) async throws -> NotesPage {
        let json = try await fetch(
            query: [
                "module": "mynotelist",
                "view": "mypost",
                "type": "post",
                "version": "3",
                "page": String(page),
            ]
        )
        let payload = json["Variables"]
        let items = payload["list"].arrayValue.map { Note(json: $0) }
        return NotesPage(items: items, hasMore: items.count >= Self.threadsPerPage)
    }

    // MARK: 个人空间

    func profile(uid: String) async throws -> Profile {
        let json = try await fetch(query: ["module": "profile", "uid": uid])
        return Profile(json: json["Variables"])
    }

    func friends(uid: String) async throws -> [Friend] {
        let json = try await fetch(query: ["module": "friend", "uid": uid])
        return json["Variables"]["list"].arrayValue.map { Friend(json: $0) }
    }


    // MARK: 搜索(HTML 结果页,需登录态)

    /// 论坛主题搜索。首页 POST;翻页传 nextPageHref 模板 + 页码。
    func searchForum(keyword: String, pageHrefTemplate: String?, page: Int) async throws -> ForumSearchPage {
        let html: String
        if let template = pageHrefTemplate, page > 1 {
            let url = WebChannel.resolve(template + String(page), baseURL: client.baseURL)!
            html = try await htmlString(from: try await client.getToURL(url: url))
        } else {
            let formhash = try await SessionStore.shared.requireFormhash()
            let raw = try await client.postForm(
                path: "search.php",
                query: ["searchsubmit": "yes", "mod": "forum"],
                form: ["formhash": formhash, "srchtxt": keyword]
            )
            html = try await htmlString(from: raw)
        }
        return HTMLParsers.forumSearch(html)
    }

    /// 用户搜索
    func searchUser(keyword: String) async throws -> (results: [UserSearchResult], error: String?) {
        let formhash = try await SessionStore.shared.requireFormhash()
        let raw = try await client.postForm(
            path: "search.php",
            query: ["searchsubmit": "yes", "mod": "user"],
            form: ["formhash": formhash, "srchtxt": keyword]
        )
        let html = try await htmlString(from: raw)
        return HTMLParsers.userSearch(html)
    }

    /// TA 的主题
    func homeThreads(uid: String, page: Int) async throws -> (items: [HomeThreadItem], hasMore: Bool) {
        let raw = try await client.get(
            path: "home.php",
            query: [
                "mod": "space", "do": "thread", "from": "space",
                "type": "thread", "view": "me",
                "uid": uid, "page": String(page),
            ]
        )
        return HTMLParsers.homeThreads(try await htmlString(from: raw))
    }

    /// TA 的回复
    func homeReplies(uid: String, page: Int) async throws -> (items: [HomeReplyItem], hasMore: Bool) {
        let raw = try await client.get(
            path: "home.php",
            query: [
                "mod": "space", "do": "thread", "from": "space",
                "type": "reply", "view": "me",
                "uid": uid, "page": String(page),
            ]
        )
        return HTMLParsers.homeReplies(try await htmlString(from: raw))
    }

    /// 楼层评分明细
    func rates(tid: Int, pid: Int) async throws -> [RateInfo] {
        let raw = try await client.get(
            path: "forum.php",
            query: ["mod": "misc", "action": "viewratings", "inajax": "1", "tid": String(tid), "pid": String(pid)]
        )
        return HTMLParsers.rates(try await htmlString(from: raw))
    }

    /// HTML 响应 → 字符串(不走 JSON 清洗)
    private func htmlString(from data: Data) async throws -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            throw APIError.invalidResponse
        }
        return text
    }


    // MARK: M3:投票 / 小黑屋 / 签到

    /// 参与投票(web 表单通道,支持多选)
    func votePoll(tid: Int, optionIds: [Int]) async throws {
        let formhash = try await SessionStore.shared.requireFormhash()
        var form: [(String, String)] = [("formhash", formhash)]
        for id in optionIds {
            form.append(("pollanswers[]", String(id)))
        }
        let raw = try await client.postFormPairs(
            path: "forum.php",
            query: ["mod": "misc", "action": "votepoll", "pollsubmit": "yes", "quickforward": "yes", "inajax": "1", "tid": String(tid)],
            form: form
        )
        let html = ResponseCleaner.htmlString(raw)
        let result = WebChannel.parseAjaxResult(html)
        if !result.success {
            throw APIError.actionFailed(result.message)
        }
    }

    /// 小黑屋(分页,anchor 为上一页 message 的 cid)
    func darkRoom(anchorCid: String?) async throws -> DarkRoomPage {
        var query = ["mod": "misc", "action": "showdarkroom", "ajaxdata": "json"]
        if let anchorCid, !anchorCid.isEmpty {
            query["cid"] = anchorCid
        }
        let raw = try await client.get(path: "forum.php", query: query)
        let text = String(data: raw, encoding: .utf8) ?? ""
        // 先直接解析;失败再修未引号 key(darkroom 的 data 对象 key 是裸 uid)
        let json = (try? JSON(data: raw))
            ?? (try? JSON(data: Data(ResponseCleaner.repairUnquotedKeys(text).utf8)))
        guard let json else {
            let dump = FileManager.default.temporaryDirectory.appendingPathComponent("darkroom_debug.txt")
            try? text.data(using: .utf8)?.write(to: dump)
            NetworkLog.decode.error("小黑屋原文已存 \(dump.path, privacy: .public)")
            throw APIError.decoding("小黑屋数据解析失败")
        }
        var items: [DarkRoomItem] = []
        for (_, entry) in json["data"] {
            items.append(DarkRoomItem(
                cid: entry["cid"].flexibleString,
                uid: entry["uid"].flexibleString,
                username: entry["username"].flexibleStringOrNil,
                action: entry["action"].flexibleStringOrNil,
                reason: entry["reason"].flexibleStringOrNil,
                operatorName: entry["operator"].flexibleStringOrNil,
                dateline: entry["dateline"].flexibleStringOrNil,
                groupExpiry: entry["groupexpiry"].flexibleStringOrNil
            ))
        }
        let message = json["message"].flexibleString
        let nextCid = message.split(separator: "|").count > 1 ? String(message.split(separator: "|")[1]) : nil
        return DarkRoomPage(items: items, nextCid: nextCid)
    }

    /// 每日签到(web 插件 inajax 通道)
    func autoSign() async throws -> String {
        let formhash = try await SessionStore.shared.requireFormhash()
        let raw = try await client.get(
            path: "study_daily_attendance-daily_attendance.html",
            query: ["inajax": "1", "formhash": formhash]
        )
        let html = ResponseCleaner.htmlString(raw)
        let result = WebChannel.parseAjaxResult(html)
        if result.success {
            return result.message.isEmpty ? "签到成功" : result.message
        }
        // 已签到等提示不算失败
        if result.message.contains("已"), !result.message.contains("失败") {
            return result.message
        }
        throw APIError.actionFailed(result.message)
    }


    // MARK: App 后端(签到等,authorization: sid)

    struct AppLoginResult: Sendable {
        let uid: Int
        let sid: String
        let username: String?
    }

    struct AppSignResult: Sendable {
        let alreadySigned: Bool
        let message: String
    }

    /// App 后端登录,换取 sid
    func appLogin(username: String, password: String, questionId: Int, answer: String) async throws -> AppLoginResult {
        let raw = try await client.postForm(
            path: "api/app/user/login",
            query: [:],
            form: [
                "username": username,
                "password": password,
                "questionid": String(questionId),
                "answer": answer,
            ]
        )
        let json = try JSON(data: ResponseCleaner.clean(raw))
        guard json["success"].boolValue, json["code"].intValue == 200 else {
            throw APIError.actionFailed(json["message"].flexibleStringOrNil ?? "App 后端登录失败")
        }
        let sid = json["data"]["sid"].flexibleString
        guard !sid.isEmpty else {
            throw APIError.actionFailed("App 后端未返回会话令牌")
        }
        return AppLoginResult(
            uid: json["data"]["uid"].flexibleInt,
            sid: sid,
            username: json["data"]["username"].flexibleStringOrNil
        )
    }

    /// 每日签到(App 后端通道;web 打卡插件已在服务端下线)
    func appSign(uid: Int, sid: String) async throws -> AppSignResult {
        let raw = try await client.postForm(
            path: "api/app/user/sign",
            query: [:],
            form: ["uid": String(uid), "sid": sid]
        )
        let json = try JSON(data: ResponseCleaner.clean(raw))
        let message = json["message"].flexibleString
        if json["success"].boolValue {
            return AppSignResult(alreadySigned: false, message: message.isEmpty ? "签到成功" : message)
        }
        // 今日已签等情况:服务端以 success=false + message 返回
        if message.contains("已") || message.contains("重复") {
            return AppSignResult(alreadySigned: true, message: message)
        }
        throw APIError.actionFailed(message.isEmpty ? "签到失败" : message)
    }

    /// App 后端用户状态(含今日是否已签)
    struct AppUserStatus: Sendable {
        let signed: Bool
        let groupTitle: String?
        let credits: Int
    }

    func appUserStatus(uid: Int, sid: String) async throws -> AppUserStatus {
        let raw = try await client.get(
            path: "api/app/user",
            query: ["uid": String(uid), "sid": sid]
        )
        let json = try JSON(data: ResponseCleaner.clean(raw))
        guard json["success"].boolValue else {
            throw APIError.actionFailed(json["message"].flexibleStringOrNil ?? "查询失败")
        }
        return AppUserStatus(
            signed: json["data"]["signed"].boolValue,
            groupTitle: json["data"]["grouptitle"].flexibleStringOrNil,
            credits: json["data"]["credits"].flexibleInt
        )
    }

    // MARK: - Private

    private func requireSuccess(_ json: JSON, fallbackMessage: String) throws {
        let message = json["Message"]
        if message.exists() {
            let val = message["messageval"].flexibleString
            let success = val.hasSuffix("_succeed") || val.hasSuffix("_success") || val.hasSuffix("_succeed_mobile")
            if !success {
                throw APIError.actionFailed(message["messagestr"].flexibleStringOrNil ?? fallbackMessage)
            }
        }
    }

    private func fetch(query: [String: String], form: [String: String]? = nil) async throws -> JSON {
        let raw: Data
        if let form {
            raw = try await client.postForm(path: "api/mobile/index.php", query: query, form: form)
        } else {
            raw = try await client.get(path: "api/mobile/index.php", query: query)
        }
        let cleaned = ResponseCleaner.clean(raw)

        let json: JSON
        do {
            json = try JSON(data: cleaned)
        } catch {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("s1gugu_failed_\(Int(Date().timeIntervalSince1970)).json")
            try? cleaned.write(to: url)
            NetworkLog.decode.error("解码失败:\(String(describing: error), privacy: .public) 原文已存 \(url.path, privacy: .public)")
            throw APIError.decoding(String(describing: error))
        }

        let variables = json["Variables"]
        if variables.exists() {
            let uid = variables["member_uid"].flexibleString
            let name = variables["member_username"].flexibleString
            let hash = variables["formhash"].flexibleString
            await SessionStore.shared.ingest(
                memberUid: uid.isEmpty ? nil : uid,
                memberUsername: name.isEmpty ? nil : name,
                formhash: hash.isEmpty ? nil : hash
            )
        }
        if let error = json["error"].string, !error.isEmpty {
            throw APIError.server(error)
        }
        return json
    }

    static func estimatedPageCount(replies: Int) -> Int {
        max(1, (replies + 1 + Self.postsPerPage - 1) / Self.postsPerPage)
    }
}

// MARK: - Post 组装(解码后 → 渲染管线输入)

import SwiftSoup

enum PostAssembler {

    static func assemble(_ raw: RawPost, threadAuthor: String?) -> Post {
        let banned = (raw.message ?? "").contains("作者被禁止或删除")
        let html = PostPreprocessor.preprocess(raw.message ?? "")
        return Post(
            pid: raw.pid,
            author: raw.author,
            authorId: raw.authorId,
            isFirst: raw.isFirst,
            floor: raw.number.flatMap { Int($0) },
            dateTimeText: DiscuzFormatters.timestamp(raw.dbdateline),
            avatarURL: AvatarURL.url(uid: raw.authorId),
            banned: banned,
            isOp: threadAuthor != nil && threadAuthor == raw.author,
            preprocessedHTML: html,
            attachments: raw.attachments
        )
    }
}

enum AvatarURL {
    /// `avatar.stage1st.com/{uid 补零 9 位,拆 3/2/2/2}_avatar_big.jpg`
    static func url(uid: Int) -> URL? {
        guard uid > 0 else { return nil }
        let padded = String(format: "%09d", uid)
        let start = padded.startIndex
        let a = padded[start..<padded.index(start, offsetBy: 3)]
        let b = padded[padded.index(start, offsetBy: 3)..<padded.index(start, offsetBy: 5)]
        let c = padded[padded.index(start, offsetBy: 5)..<padded.index(start, offsetBy: 7)]
        let d = padded[padded.index(start, offsetBy: 7)..<padded.index(start, offsetBy: 9)]
        return URL(string: "https://avatar.stage1st.com/\(a)/\(b)/\(c)/\(d)_avatar_big.jpg")
    }
}

enum DiscuzFormatters {
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static func timestamp(_ secondsString: String) -> String {
        guard let seconds = Double(secondsString), seconds > 0 else { return "" }
        return timestampFormatter.string(from: Date(timeIntervalSince1970: seconds))
    }
}
