import UIKit
import SwiftSoup

/// Discuz 服务端渲染 HTML 片段 → NSAttributedString。
/// 支持:b/strong、i/em、u、s、font(color/size)、a、img(内联表情)、br、hr、li、块级元素换行。
/// 复杂结构由 BlockSplitter 降级处理。全部纯函数,可在后台线程调用。
enum HtmlAttributedBuilder {

    struct Style {
        var font: UIFont
        var color: UIColor
        var link: URL?
    }

    static func bodyStyle() -> Style {
        Style(font: scaledFont(.body), color: .label, link: nil)
    }

    /// 用户字号缩放(M3 设置)作用于正文渲染
    static func scaledFont(_ textStyle: UIFont.TextStyle) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: textStyle)
        let scale = CGFloat(AppSettings.fontScale)
        guard scale != 1.0 else { return base }
        return UIFont(descriptor: base.fontDescriptor, size: base.pointSize * scale)
    }

    /// 相对 Discuz font size(1–7)映射到相对 .body 的倍率
    private static let fontSizeRatios: [CGFloat] = [0.8, 0.9, 1.0, 1.15, 1.3, 1.5, 1.7]

    static func attributed(from nodes: [Node], style: Style, baseURL: URL?) -> NSAttributedString {
        let output = NSMutableAttributedString()
        append(nodes: nodes, style: style, into: output, baseURL: baseURL)
        return output
    }

    static func attributed(from element: Element, style: Style, baseURL: URL?) -> NSAttributedString {
        attributed(from: element.getChildNodes(), style: style, baseURL: baseURL)
    }

    // MARK: - Walk

    private static func append(nodes: [Node], style: Style, into output: NSMutableAttributedString, baseURL: URL?) {
        for node in nodes {
            append(node: node, style: style, into: output, baseURL: baseURL)
        }
    }

    private static func append(node: Node, style: Style, into output: NSMutableAttributedString, baseURL: URL?) {
        if let text = node as? TextNode {
            let raw = text.getWholeText()
            guard !raw.isEmpty else { return }
            let attributed = NSAttributedString(string: raw, attributes: attributes(for: style))
            output.append(attributed)
            return
        }
        guard let element = node as? Element else { return }
        let tag = element.tagName().lowercased()

        switch tag {
        case "br":
            output.append(newline(style: style))
        case "hr":
            output.append(newline(style: style))
            output.append(NSAttributedString(
                string: "—————",
                attributes: attributes(for: Style(font: style.font, color: .separator, link: nil))
            ))
            output.append(newline(style: style))
        case "b", "strong":
            appendBold(element: element, style: style, into: output, baseURL: baseURL)
        case "i", "em":
            var child = style
            if let italic = descriptor(style.font).withSymbolicTraits(.traitItalic) {
                child.font = UIFont(descriptor: italic, size: style.font.pointSize)
            }
            append(element: element, style: child, into: output, baseURL: baseURL)
        case "s", "strike", "del":
            var child = style
            append(element: element, style: child, into: output, baseURL: baseURL)
            let range = NSRange(location: output.length - length(of: element, style: style, baseURL: baseURL), length: length(of: element, style: style, baseURL: baseURL))
            output.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case "u":
            var child = style
            append(element: element, style: child, into: output, baseURL: baseURL)
            let range = NSRange(location: output.length - length(of: element, style: style, baseURL: baseURL), length: length(of: element, style: style, baseURL: baseURL))
            output.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case "font":
            appendFont(element: element, style: style, into: output, baseURL: baseURL)
        case "a":
            appendLink(element: element, style: style, into: output, baseURL: baseURL)
        case "img":
            appendImage(element: element, style: style, into: output, baseURL: baseURL)
        case "div", "p", "blockquote", "table", "ul", "ol", "pre", "h1", "h2", "h3", "h4", "h5", "h6":
            appendBlockBoundary(into: output)
            append(element: element, style: style, into: output, baseURL: baseURL)
            appendBlockBoundary(into: output)
        case "li":
            appendBlockBoundary(into: output)
            output.append(NSAttributedString(string: "•  ", attributes: attributes(for: style)))
            append(element: element, style: style, into: output, baseURL: baseURL)
            appendBlockBoundary(into: output)
        case "span", "em2", "small", "big":
            append(element: element, style: style, into: output, baseURL: baseURL)
        default:
            append(element: element, style: style, into: output, baseURL: baseURL)
        }
    }

    private static func append(element: Element, style: Style, into output: NSMutableAttributedString, baseURL: URL?) {
        append(nodes: element.getChildNodes(), style: style, into: output, baseURL: baseURL)
    }

    private static func appendBold(element: Element, style: Style, into output: NSMutableAttributedString, baseURL: URL?) {
        var child = style
        if let bold = descriptor(style.font).withSymbolicTraits(.traitBold) {
            child.font = UIFont(descriptor: bold, size: style.font.pointSize)
        }
        append(element: element, style: child, into: output, baseURL: baseURL)
    }

    private static func appendFont(element: Element, style: Style, into output: NSMutableAttributedString, baseURL: URL?) {
        var child = style
        if let colorString = try? element.attr("color"), let color = UIColor(discuzHex: colorString) {
            child.color = color
        }
        if let sizeString = try? element.attr("size"), let size = Int(sizeString), (1...7).contains(size) {
            let ratio = fontSizeRatios[size - 1]
            child.font = UIFont(descriptor: style.font.fontDescriptor, size: style.font.pointSize * ratio)
        }
        append(element: element, style: child, into: output, baseURL: baseURL)
    }

    private static func appendLink(element: Element, style: Style, into output: NSMutableAttributedString, baseURL: URL?) {
        var child = style
        if let href = try? element.attr("href"), !href.isEmpty, href != "#" {
            child.link = resolveURL(href, baseURL: baseURL)
            child.color = Theme.accent
        }
        append(element: element, style: child, into: output, baseURL: baseURL)
    }

    private static func appendImage(element: Element, style: Style, into output: NSMutableAttributedString, baseURL: URL?) {
        guard let url = imageURL(in: element, baseURL: baseURL) else { return }
        let isSmiley = url.absoluteString.contains("image/smiley") || url.absoluteString.contains("smiley")
        let pointSize = isSmiley ? style.font.pointSize * 1.2 : min(style.font.pointSize * 1.4, 40)
        let attachment = InlineImageAttachment(url: url, pointSize: pointSize)
        let attributed = NSAttributedString(attachment: attachment)
        output.append(NSAttributedString(attributedString: attributed))
    }

    private static func appendBlockBoundary(into output: NSMutableAttributedString) {
        guard let last = output.string.last, last != "\n", !output.string.isEmpty else { return }
        output.append(NSAttributedString(string: "\n"))
    }

    private static func newline(style: Style) -> NSAttributedString {
        NSAttributedString(string: "\n", attributes: attributes(for: style))
    }

    // MARK: - Helpers

    private static func attributes(for style: Style) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: style.font,
            .foregroundColor: style.color,
        ]
        if let link = style.link {
            attributes[.link] = link
        }
        return attributes
    }

    private static func descriptor(_ font: UIFont) -> UIFontDescriptor {
        font.fontDescriptor
    }

    private static func length(of element: Element, style: Style, baseURL: URL?) -> Int {
        attributed(from: element, style: style, baseURL: baseURL).length
    }

    static func imageURL(in element: Element, baseURL: URL?) -> URL? {
        // 真实地址优先级:zoomfile > file > src(none.gif 占位过滤)
        for attribute in ["zoomfile", "file", "src"] {
            guard let value = try? element.attr(attribute), !value.isEmpty else { continue }
            if value.hasSuffix("none.gif") { continue }
            return resolveURL(value, baseURL: baseURL)
        }
        return nil
    }

    static func resolveURL(_ href: String, baseURL: URL?) -> URL? {
        if let url = URL(string: href), url.scheme != nil { return url }
        guard let baseURL else { return URL(string: href) }
        return URL(string: href, relativeTo: baseURL)?.absoluteURL
    }

    static func isSmileyURL(_ url: URL) -> Bool {
        url.absoluteString.contains("image/smiley")
    }
}
