import Foundation
import SwiftSoup
import UIKit

/// 每楼 HTML → [PostBlock]。纯函数(除 InlineImageStore 引用),应在后台线程调用。
enum BlockSplitter {

    static func split(
        html: String,
        baseURL: URL?,
        quoteReplacer: ((String) -> String?)? = nil,
        extraAttachments: [PostFileAttachment] = []
    ) -> [PostBlock] {
        guard !html.isEmpty else { return [] }
        guard let document = try? SwiftSoup.parseBodyFragment(html),
              let body = document.body()
        else { return [fallbackBlock(fromHTML: html)] }

        var blocks: [PostBlock] = []
        walk(nodes: body.getChildNodes(), baseURL: baseURL, quoteReplacer: quoteReplacer, into: &blocks)

        // 未在正文中引用的文件附件补到末尾
        if !extraAttachments.isEmpty {
            let referenced = Set(blocks.compactMap { block -> URL? in
                if case let .fileAttachment(file) = block { return file.url }
                return nil
            })
            for attachment in extraAttachments where !referenced.contains(attachment.url) {
                blocks.append(.fileAttachment(attachment))
            }
        }
        return blocks
    }

    // MARK: - Walk

    private static func walk(
        nodes: [Node],
        baseURL: URL?,
        quoteReplacer: ((String) -> String?)?,
        into blocks: inout [PostBlock]
    ) {
        for node in nodes {
            guard let element = node as? Element else {
                appendTextRun(node: node, baseURL: baseURL, into: &blocks)
                continue
            }
            let tag = element.tagName().lowercased()
            let className = (try? element.className()) ?? ""

            if tag == "blockquote" || (tag == "div" && className.contains("quote")) {
                appendQuote(element: element, baseURL: baseURL, replacer: quoteReplacer, into: &blocks)
            } else if tag == "div" && className.contains("blockcode") {
                appendCode(element: element, into: &blocks)
            } else if tag == "pre" {
                blocks.append(.code(elementText(element)))
            } else if tag == "attach" {
                if let file = fileAttachment(from: element, baseURL: baseURL) {
                    blocks.append(.fileAttachment(file))
                }
            } else if tag == "table" {
                blocks.append(.fallback(AttributedText(HtmlAttributedBuilder.attributed(
                    from: element, style: HtmlAttributedBuilder.bodyStyle(), baseURL: baseURL
                ))))
            } else if let image = standaloneImage(in: element, baseURL: baseURL) {
                blocks.append(.image(image))
            } else {
                appendTextRun(node: node, baseURL: baseURL, into: &blocks)
            }
        }
    }

    private static func appendTextRun(node: Node, baseURL: URL?, into blocks: inout [PostBlock]) {
        let attributed = HtmlAttributedBuilder.attributed(
            from: [node], style: HtmlAttributedBuilder.bodyStyle(), baseURL: baseURL
        )
        guard attributed.length > 0, attributed.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false || containsAttachment(attributed)
        else { return }
        blocks.append(.text(AttributedText(attributed)))
    }

    private static func containsAttachment(_ attributed: NSAttributedString) -> Bool {
        attributed.length > 0 && attributed.string.contains("\u{FFFC}")
    }

    // MARK: - 引用

    private static func appendQuote(
        element: Element,
        baseURL: URL?,
        replacer: ((String) -> String?)?,
        into blocks: inout [PostBlock]
    ) {
        let innerHTML = (try? element.html()) ?? ""

        var author: String?
        if let match = innerHTML.firstMatch(of: /<font[^>]*color="#999999"[^>]*>([^<]+?)\s*发表于/) {
            author = String(match.1).trimmingCharacters(in: .whitespaces)
        }

        // 黑名单用户的引用整体替换
        if let author, let replacement = replacer?(author) {
            blocks.append(.quote(author: author, attributed: AttributedText(attributedText(replacement))))
            return
        }

        // 去掉引用头部(author 发表于 …)
        var contentHTML = innerHTML
        if author != nil {
            contentHTML = contentHTML.replacing(
                /<font[^>]*color="#999999"[^>]*>[^<]*?<\/font>\s*(?:<br\s*\/?>)?/,
                with: ""
            )
        }
        if let parsed = try? SwiftSoup.parseBodyFragment(contentHTML), let body = parsed.body() {
            let attributed = HtmlAttributedBuilder.attributed(
                from: body.getChildNodes(), style: quoteStyle(), baseURL: baseURL
            )
            if attributed.length > 0 {
                blocks.append(.quote(author: author, attributed: AttributedText(attributed)))
                return
            }
        }
        blocks.append(.quote(author: author, attributed: AttributedText(attributedText("[引用]"))))
    }

    private static func quoteStyle() -> HtmlAttributedBuilder.Style {
        HtmlAttributedBuilder.Style(
            font: HtmlAttributedBuilder.scaledFont(.subheadline),
            color: .secondaryLabel,
            link: nil
        )
    }

    private static func attributedText(_ string: String) -> NSAttributedString {
        NSAttributedString(
            string: string,
            attributes: [
                .font: HtmlAttributedBuilder.scaledFont(.subheadline),
                .foregroundColor: UIColor.secondaryLabel,
            ]
        )
    }

    // MARK: - 代码

    private static func appendCode(element: Element, into blocks: inout [PostBlock]) {
        if let listItems = try? element.select("li"), listItems.size() > 0 {
            let lines = listItems.array().compactMap { try? $0.text() }
            blocks.append(.code(lines.joined(separator: "\n")))
        } else {
            blocks.append(.code(elementText(element)))
        }
    }

    // MARK: - 附件

    private static func fileAttachment(from element: Element, baseURL: URL?) -> PostFileAttachment? {
        let href = (try? element.attr("href")) ?? ""
        guard !href.isEmpty, let url = HtmlAttributedBuilder.resolveURL(href, baseURL: baseURL) else { return nil }
        let name = (try? element.attr("name")) ?? ""
        let text = (try? element.text()) ?? ""
        let size = text.split(separator: ",").last.map { $0.trimmingCharacters(in: .whitespaces) }
        return PostFileAttachment(name: name.isEmpty ? url.lastPathComponent : name, url: url, sizeText: size)
    }

    static func fileAttachments(from attachments: [Int: PostAttachment]) -> [PostFileAttachment] {
        attachments.values
            .filter { !$0.isImage }
            .compactMap { attachment in
                guard let url = attachment.realURL else { return nil }
                return PostFileAttachment(
                    name: attachment.filename ?? url.lastPathComponent,
                    url: url,
                    sizeText: formattedSize(attachment.filesize)
                )
            }
    }

    private static func formattedSize(_ bytes: Int) -> String? {
        guard bytes > 0 else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    // MARK: - 独立图片

    private static func standaloneImage(in element: Element, baseURL: URL?) -> PostImage? {
        if element.tagName().lowercased() == "img" {
            return makeImage(from: element, baseURL: baseURL)
        }
        guard let images = try? element.select("img"), images.size() == 1 else { return nil }
        // 容器内只有一张图且无有效文本时,视为独立图片段
        guard !hasVisibleText(element), !containsSpecialStructure(element) else { return nil }
        guard let img = images.first() else { return nil }
        return makeImage(from: img, baseURL: baseURL)
    }

    private static func hasVisibleText(_ element: Element) -> Bool {
        for node in element.getChildNodes() {
            if let text = node as? TextNode,
               !text.getWholeText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
            if let child = node as? Element, hasVisibleText(child) {
                return true
            }
        }
        return false
    }

    private static func containsSpecialStructure(_ element: Element) -> Bool {
        guard let special = try? element.select("blockquote, .blockcode, table, attach") else { return false }
        return !special.isEmpty()
    }

    private static func makeImage(from img: Element, baseURL: URL?) -> PostImage? {
        guard let url = HtmlAttributedBuilder.imageURL(in: img, baseURL: baseURL) else { return nil }
        // 极小图(图标/表情)不作为独立图片块
        let width = dimension(of: img, attribute: "width")
        let height = dimension(of: img, attribute: "height")
        if let width, let height, width < 64, height < 64 { return nil }
        return PostImage(url: url, displayWidth: width, displayHeight: height)
    }

    private static func dimension(of element: Element, attribute: String) -> Int? {
        if let raw = try? element.attr(attribute), let value = Int(raw), value > 0 {
            return value
        }
        if let style = try? element.attr("style") {
            let pattern = attribute == "width" ? /width:\s*(\d+)px/ : /height:\s*(\d+)px/
            if let match = style.firstMatch(of: pattern) {
                return Int(String(match.1))
            }
        }
        return nil
    }

    // MARK: - Fallback

    private static func fallbackBlock(fromHTML html: String) -> PostBlock {
        .fallback(AttributedText(attributedText(String(html.prefix(500)))))
    }

    private static func elementText(_ element: Element) -> String {
        (try? element.text()) ?? ""
    }
}
