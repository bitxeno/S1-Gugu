import Foundation
import SwiftSoup

// MARK: - 模型

struct ForumSearchResult: Sendable, Identifiable, Hashable {
    let id: Int
    /// li.pbw 的 HTML 片段(渲染管线归因化)
    let html: String
}

struct ForumSearchPage: Sendable {
    let count: Int
    let page: Int
    let maxPage: Int
    /// 翻页 URL 模板(…&page= 尾部,拼接目标页码)
    let nextPageHref: String?
    let results: [ForumSearchResult]
    /// 响应不是搜索结果页(错误页/未登录)
    let invalid: Bool
}

struct UserSearchResult: Sendable, Identifiable, Hashable {
    let uid: String
    let name: String?

    var id: String { uid }
}

struct WebBlacklistUser: Sendable, Hashable {
    let uid: Int
    let name: String?
}

struct WebBlacklistPage: Sendable {
    let users: [WebBlacklistUser]
    let page: Int
    let maxPage: Int
}

struct HomeThreadItem: Sendable, Identifiable, Hashable {
    let title: String
    /// thread-xxx-page-x.html 相对链接
    let url: String
    let forum: String?
    let replyCount: String?
    let viewCount: String?
    let lastReplier: String?
    let lastReplyDate: String?

    var threadId: Int {
        url.firstMatch(of: /thread-(\d+)/).map { Int(String($0.1)) ?? 0 } ?? 0
    }
    var id: String { url }
}

struct HomeReplyItem: Sendable, Identifiable, Hashable {
    let reply: String
    let url: String

    var threadId: Int {
        url.firstMatch(of: /thread-(\d+)/).map { Int(String($0.1)) ?? 0 } ?? 0
    }
    var id: String { url }
}

struct RateInfo: Sendable, Identifiable, Hashable {
    let uid: String?
    let uname: String?
    let score: Int
    let time: String
    let content: String?

    var id: String { "\(uid ?? "-")-\(time)-\(score)" }
    var symbolScore: String { score < 0 ? "\(score)" : "+\(score)" }
}

// MARK: - 解析器(纯函数,对齐 S1-Next 各 WebWrapper)

enum HTMLParsers {

    // MARK: 论坛搜索(search.php?mod=forum)

    static func forumSearch(_ html: String) -> ForumSearchPage {
        guard let document = try? SwiftSoup.parse(html) else {
            return ForumSearchPage(count: 0, page: 1, maxPage: 1, nextPageHref: nil, results: [], invalid: true)
        }
        if let error = extractErrorMessage(document) {
            NetworkLog.decode.info("搜索错误页 \(error, privacy: .public)")
            return ForumSearchPage(count: 0, page: 1, maxPage: 1, nextPageHref: nil, results: [], invalid: true)
        }

        var count = 0
        if let em = try? document.select("em").first(),
           let countText = try? em.text(),
           let match = countText.firstMatch(of: /相关内容\s*(\d+)\s*个/) {
            count = Int(String(match.1)) ?? 0
        }

        var results: [ForumSearchResult] = []
        if let elements = try? document.select("li.pbw").array() {
            for (index, element) in elements.enumerated() {
                let html = (try? element.html()) ?? ""
                guard !html.isEmpty else { continue }
                results.append(ForumSearchResult(id: index, html: html))
            }
        }

        var page = 1
        var maxPage = 1
        var nextHref: String?
        if let pg = try? document.select("div.pg").first() {
            if let strong = try? pg.select("strong").first(), let text = try? strong.text() {
                page = Int(text.trimmingCharacters(in: .whitespaces)) ?? 1
            }
            if let span = try? pg.select("span[title]").first(), let text = try? span.text(),
               let match = text.firstMatch(of: /\d+/) {
                maxPage = Int(String(match.0)) ?? 1
            }
            if let a = try? pg.select("a").first(), let href = try? a.attr("href") {
                nextHref = href.replacing(/page=\d+/, with: "page=")
            }
        }
        return ForumSearchPage(
            count: count, page: page, maxPage: maxPage,
            nextPageHref: nextHref, results: results,
            invalid: false
        )
    }

    // MARK: 用户搜索(search.php?mod=user)

    static func userSearch(_ html: String) -> (results: [UserSearchResult], error: String?) {
        guard let document = try? SwiftSoup.parse(html) else {
            return ([], "解析失败")
        }
        if let error = extractErrorMessage(document) {
            return ([], error)
        }
        var results: [UserSearchResult] = []
        if let elements = try? document.select("li.bbda.cl").array() {
            for element in elements {
                guard let children = try? element.children(), children.size() > 1,
                      let userLink = try? children.get(1).getElementsByTag("a").first(),
                      let href = try? userLink.attr("href")
                else { continue }
                guard let match = href.firstMatch(of: /uid[-=](\d+)/) else { continue }
                let uid = String(match.1)
                let name = (try? userLink.text()) ?? ""
                results.append(UserSearchResult(uid: uid, name: name))
            }
        }
        return (results, nil)
    }

    // MARK: TA 的主题(home.php do=thread type=thread)

    static func homeThreads(_ html: String) -> (items: [HomeThreadItem], hasMore: Bool) {
        guard let document = try? SwiftSoup.parse(html) else { return ([], false) }
        var items: [HomeThreadItem] = []
        let rows = (try? document.select("#delform tr").array()) ?? []
        for (index, row) in rows.enumerated() {
            if index == 0 { continue } // 表头
            guard let cells = try? row.children(), cells.size() >= 5,
                  let titleLink = try? cells.get(1).getElementsByTag("a").first()
            else { continue }
            let title = (try? titleLink.text()) ?? ""
            let url = (try? titleLink.attr("href")) ?? ""
            guard !url.isEmpty, !title.isEmpty else { continue }
            let forum = (try? cells.get(2).getElementsByTag("a").first()?.text()) ?? nil
            let reply = (try? cells.get(3).child(0).text()) ?? nil
            let view = (try? cells.get(3).child(1).text()) ?? nil
            var lastReplier: String?
            var lastDate: String?
            if let by = try? cells.get(4).children(), by.size() >= 2 {
                lastReplier = (try? by.get(0).getElementsByTag("a").first()?.text()) ?? nil
                lastDate = (try? by.get(1).getElementsByTag("a").first()?.text()) ?? nil
                if lastDate == nil {
                    lastDate = (try? by.get(1).text()) ?? nil
                }
            }
            items.append(HomeThreadItem(
                title: title, url: url, forum: forum,
                replyCount: reply, viewCount: view,
                lastReplier: lastReplier, lastReplyDate: lastDate
            ))
        }
        let hasMore = ((try? document.select("div.pg>a.nxt").array()) ?? []).isEmpty == false
        return (items, hasMore)
    }

    // MARK: TA 的回复(home.php do=thread type=reply)

    static func homeReplies(_ html: String) -> (items: [HomeReplyItem], hasMore: Bool) {
        guard let document = try? SwiftSoup.parse(html) else { return ([], false) }
        var items: [HomeReplyItem] = []
        let rows = (try? document.select("#delform tr").array()) ?? []
        for (index, row) in rows.enumerated() {
            if index == 0 { continue }
            guard let firstCell = try? row.children().first(),
                  let children = try? firstCell.children(), children.size() >= 3,
                  let link = try? children.get(1)
            else { continue }
            let reply = (try? link.text()) ?? ""
            let url = (try? link.attr("href")) ?? ""
            guard !url.isEmpty, !reply.isEmpty else { continue }
            items.append(HomeReplyItem(reply: reply, url: url))
        }
        let hasMore = ((try? document.select("div.pg>a.nxt").array()) ?? []).isEmpty == false
        return (items, hasMore)
    }

    // MARK: 评分明细(viewratings inajax)

    static func rates(_ html: String) -> [RateInfo] {
        let inner = WebChannel.unwrapAjaxHTML(html)
        guard let document = try? SwiftSoup.parse(inner) else { return [] }
        var result: [RateInfo] = []
        let rows = (try? document.select("table>tbody>tr").array()) ?? []
        for row in rows {
            guard let cells = try? row.children(), cells.size() >= 4 else { continue }
            let scoreText = (try? cells.get(0).text()) ?? ""
            guard let match = scoreText.firstMatch(of: /[-+]?\d+/),
                  let score = Int(String(match.0))
            else { continue } // 表头行("积分")
            let userLink = try? cells.get(1).getElementsByTag("a").first()
            let uname = (try? userLink?.text()) ?? nil
            let href = (try? userLink?.attr("href")) ?? ""
            let uid = href.firstMatch(of: /uid[-=](\d+)/).map { String($0.1) }
            let time = (try? cells.get(2).text()) ?? ""
            let content = (try? cells.get(3).text()) ?? ""
            result.append(RateInfo(uid: uid, uname: uname, score: score, time: time, content: content))
        }
        return result
    }

    // MARK: 网页黑名单(home.php mod=space&do=friend&view=blacklist)

    static func webBlacklist(_ html: String) -> WebBlacklistPage {
        guard let document = try? SwiftSoup.parse(html) else {
            return WebBlacklistPage(users: [], page: 1, maxPage: 1)
        }
        var seen = Set<Int>()
        var users: [WebBlacklistUser] = []
        let items = (try? document.select("#friend_ul li").array()) ?? []
        for item in items {
            guard let link = try? item.select("h4 > a").first() else { continue }
            let href = (try? link.attr("href")) ?? ""
            guard let match = href.firstMatch(of: /(?:space-uid-|uid=)(\d+)/),
                  let uid = Int(match.1),
                  uid > 0,
                  seen.insert(uid).inserted
            else { continue }
            let name = ((try? link.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            users.append(WebBlacklistUser(uid: uid, name: name.isEmpty ? nil : name))
        }
        let info = webBlacklistPageInfo(document)
        return WebBlacklistPage(users: users, page: info.page, maxPage: info.maxPage)
    }

    private static func webBlacklistPageInfo(_ document: Document) -> (page: Int, maxPage: Int) {
        var page = 1
        var maxPage = 1
        if let label = try? document.select(".pg label").first() {
            if let input = try? label.select("input").first(),
               let value = Int((try? input.attr("value")) ?? "") {
                page = max(value, 1)
            }
            if let span = try? label.select("span").first(),
               let text = try? span.text() {
                // Discuz 的页码文本形如 "1 / 3"
                let numbers = text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
                if let last = numbers.last { maxPage = max(last, page) }
            }
        }
        if maxPage <= 1 {
            // 部分主题页只有「下一页」链接,没有页码 label
            let links = (try? document.select(".pg a[href]").array()) ?? []
            for link in links {
                let href = (try? link.attr("href")) ?? ""
                if let match = href.firstMatch(of: /page=(\d+)/),
                   let value = Int(match.1) {
                    maxPage = max(maxPage, value)
                }
            }
        }
        return (page, maxPage)
    }

    // MARK: Helpers

    private static func extractErrorMessage(_ document: Document) -> String? {
        if let error = try? document.select("div#messagetext").first(),
           let text = try? error.text(), !text.isEmpty {
            return text
        }
        if let error = try? document.select("div.alert_error").first(),
           let text = try? error.text(), !text.isEmpty {
            return text
        }
        return nil
    }
}
