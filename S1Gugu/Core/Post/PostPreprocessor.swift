import Foundation
import SwiftSoup

// MARK: - HTML 预处理(对齐 S1-Next PostFilter / Post.filterReply)

enum PostPreprocessor {

    static func preprocess(_ rawHTML: String) -> String {
        guard !rawHTML.isEmpty else { return rawHTML }
        var html = rawHTML

        // 手动 unicode 实体二次解码(&#x4E0D; 等)
        if html.contains("&amp;#x") || html.contains("&#x") {
            html = decodeNumericEntities(html)
        }
        html = replaceCodeDivID(html)
        html = replaceNewQuoteToOld(html)
        html = replaceBilibiliTag(html)
        html = replaceMediaTag(html)
        html = mapColorNames(html)
        html = html.replacingOccurrences(of: "<imgwidth=\"", with: "<img width=\"")
        html = prettify(html)
        return html
    }

    /// v4 接口的 `<div class="reply_wrap">` 归一为 `<blockquote>`
    static func replaceNewQuoteToOld(_ html: String) -> String {
        guard html.contains("reply_wrap") else { return html }
        do {
            let document = try SwiftSoup.parse(html)
            let nodes = try document.select("div.reply_wrap")
            guard nodes.array().count > 0 else { return html }
            for node in nodes.array() {
                try? node.attr("class", "")
                try? node.tagName("blockquote")
            }
            if let parent = try nodes.parents().first() {
                return try parent.html()
            }
            return try document.body()?.html() ?? html
        } catch {
            return html
        }
    }

    /// 去掉代码块的随机 id 与「复制代码」按钮
    static func replaceCodeDivID(_ html: String) -> String {
        html.replacingOccurrences(
            of: "<div class=\"blockcode\"><div id=\"code_\\w{3}\">",
            with: "<div class=\"blockcode\"><div>",
            options: .regularExpression
        )
        .replacingOccurrences(
            of: "<em onclick=\"copycode\\(getID\\('code_\\w{3}'\\)\\);\">复制代码</em></div>",
            with: "</div>",
            options: .regularExpression
        )
    }

    /// `[thgame_biliplay]…[/thgame_biliplay]` → b 站链接
    static func replaceBilibiliTag(_ html: String) -> String {
        guard html.contains("[thgame_biliplay") else { return html }
        var result = html
        for match in html.matches(of: /\[thgame_biliplay[^\]]*\][\s\S]*?\[\/thgame_biliplay\]/) {
            let content = String(match.output)
            guard let avMatch = content.firstMatch(of: /\{,=av\}(\d+)/) else { continue }
            let avNumber = String(avMatch.1)
            var page = 1
            if let pageMatch = content.firstMatch(of: /\{,=page\}(\d+)/) {
                page = Int(String(pageMatch.1)) ?? 1
            }
            let url = page > 1
                ? "https://www.bilibili.com/video/av\(avNumber)/index_\(page).html"
                : "https://www.bilibili.com/video/av\(avNumber)"
            result = result.replacingOccurrences(of: content, with: "<a href=\"\(url)\">B站视频 av\(avNumber)</a>")
        }
        return result
    }

    /// `[media]url[/media]` → 链接
    static func replaceMediaTag(_ html: String) -> String {
        guard html.contains("[media]") else { return html }
        var result = html
        for match in html.matches(of: /\[media\](.*?)\[\/media\]/) {
            let url = String(match.1)
            result = result.replacingOccurrences(
                of: String(match.0),
                with: "<a href=\"\(url)\">\(url)</a>"
            )
        }
        return result
    }

    /// Android/系统不支持的 HTML 颜色名 → hex
    static func mapColorNames(_ html: String) -> String {
        guard html.contains("color=\"") else { return html }
        var result = html
        for match in html.matches(of: /color="([a-zA-Z]+)"/) {
            let name = String(match.1).lowercased()
            guard let hex = colorNameMap[name] else { continue }
            result = result.replacingOccurrences(of: String(match.0), with: "color=\"\(hex)\"")
        }
        return result
    }

    private static let colorNameMap: [String: String] = [
        "sienna": "#A0522D", "darkolivegreen": "#556B2F", "darkgreen": "#006400",
        "darkslateblue": "#483D8B", "indigo": "#4B0082", "darkslategray": "#2F4F4F",
        "darkred": "#8B0000", "darkorange": "#FF8C00", "slategray": "#708090",
        "dimgray": "#696969", "sandybrown": "#F4A460", "yellowgreen": "#9ACD32",
        "seagreen": "#2E8B57", "mediumturquoise": "#48D1CC", "royalblue": "#4169E1",
        "orange": "#FFA500", "deepskyblue": "#00BFFF", "darkorchid": "#9932CC",
        "pink": "#FFC0CB", "wheat": "#F5DEB3", "lemonchiffon": "#FFFACD",
        "palegreen": "#98FB98", "paleturquoise": "#AFEEEE", "lightblue": "#ADD8E6",
        "white": "#FFFFFF",
    ]

    /// 去掉结尾多余换行
    static func prettify(_ html: String) -> String {
        var text = html
        while true {
            if text.hasSuffix("\r\n") { text.removeLast(2); continue }
            if text.hasSuffix("\n") { text.removeLast(); continue }
            if text.hasSuffix("<br />") || text.hasSuffix("<br/>") {
                text.removeLast(text.hasSuffix("<br />") ? 6 : 5)
                continue
            }
            break
        }
        return text
    }

    /// 数字实体解码(&#x4E0D; / &#123;)
    static func decodeNumericEntities(_ html: String) -> String {
        guard let encoded = html.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return html }
        guard let decoded = encoded.removingPercentEncoding else { return html }
        _ = decoded
        var result = html
        for match in html.matches(of: /&#x([0-9A-Fa-f]{1,6});/) {
            guard let scalar = UInt32(String(match.1), radix: 16), let unicode = Unicode.Scalar(scalar) else { continue }
            result = result.replacingOccurrences(of: String(match.0), with: String(Character(unicode)))
        }
        for match in html.matches(of: /&#(\d{1,7});/) {
            guard let scalar = UInt32(String(match.1)), let unicode = Unicode.Scalar(scalar) else { continue }
            result = result.replacingOccurrences(of: String(match.0), with: String(Character(unicode)))
        }
        return result
    }
}
