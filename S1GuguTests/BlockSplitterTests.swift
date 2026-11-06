import XCTest
import SwiftyJSON
@testable import S1Gugu

final class BlockSplitterTests: XCTestCase {

    func testPlainTextToTextBlock() {
        let blocks = BlockSplitter.split(html: "<p>第一段</p><p>第二段</p>", baseURL: nil)
        let texts = blocks.compactMap { block -> String? in
            if case let .text(attributed) = block { return attributed.value.string }
            return nil
        }
        XCTAssertEqual(texts.count, 2)
        XCTAssertTrue(texts[0].contains("第一段"))
        XCTAssertTrue(texts[1].contains("第二段"))
    }

    func testStandaloneImageBecomesImageBlock() {
        let blocks = BlockSplitter.split(
            html: #"<p>说明文字</p><img src="https://img.stage1st.com/forum/202605/28/a.jpg" width="800" height="600" />"#,
            baseURL: nil
        )
        guard case let .image(image)? = blocks.last else {
            return XCTFail("最后一个块应为图片块,实际:\(blocks)")
        }
        XCTAssertEqual(image.url.absoluteString, "https://img.stage1st.com/forum/202605/28/a.jpg")
        XCTAssertEqual(image.aspectRatio ?? 0, 800.0 / 600.0, accuracy: 0.001)
    }

    func testQuoteBlockExtractsAuthor() {
        let html = ##"<blockquote><font color="#999999">张三 发表于 2024-1-1 12:00</font><br />引用的内容</blockquote>"##
        let blocks = BlockSplitter.split(html: html, baseURL: nil)
        guard case let .quote(author, dateText, attributed)? = blocks.first else {
            return XCTFail("第一个块应为引用块,实际:\(blocks)")
        }
        XCTAssertEqual(author, "张三")
        XCTAssertEqual(dateText, "2024-1-1 12:00")
        XCTAssertTrue(attributed.value.string.contains("引用的内容"))
        XCTAssertFalse(attributed.value.string.contains("发表于"))
    }

    func testQuoteBlacklistReplacement() {
        let html = ##"<blockquote><font color="#999999">张三 发表于 2024-1-1 12:00</font><br />不该看的内容</blockquote>"##
        let blocks = BlockSplitter.split(html: html, baseURL: nil, quoteReplacer: { author in
            author == "张三" ? "[已被抹布]" : nil
        })
        guard case let .quote(_, _, attributed)? = blocks.first else {
            return XCTFail("第一个块应为引用块")
        }
        XCTAssertEqual(attributed.value.string, "[已被抹布]")
    }

    func testCodeBlock() {
        let blocks = BlockSplitter.split(
            html: #"<div class="blockcode"><div><ol><li>let x = 1</li><li>let y = 2</li></ol></div></div>"#,
            baseURL: nil
        )
        guard case let .code(code)? = blocks.first else {
            return XCTFail("第一个块应为代码块,实际:\(blocks)")
        }
        XCTAssertEqual(code, "let x = 1\nlet y = 2")
    }

    func testSmileyStaysInlineAsAttachment() {
        let blocks = BlockSplitter.split(
            html: #"<p>哈哈<img src="https://static.stage1st.com/image/smiley/fox/01.gif" />太搞了</p>"#,
            baseURL: nil
        )
        // 单张小图不算独立图片块;文本块应包含对象替换符(附件占位)
        let hasImageBlock = blocks.contains { block in
            if case .image = block { return true }
            return false
        }
        XCTAssertFalse(hasImageBlock)
        let firstText = blocks.compactMap { block -> String? in
            if case let .text(attributed) = block { return attributed.value.string }
            return nil
        }.first
        XCTAssertTrue(firstText?.contains("\u{FFFC}") ?? false)
    }

    func testTopLevelSmileyMergesIntoTextRun() {
        // 顶层裸节点:文字 + 表情 + 文字应合并为同一个文本块(表情与文字同行)
        let blocks = BlockSplitter.split(
            html: #"发出来给大家一起蹬<img src="https://static.stage1st.com/image/smiley/fox/02.gif" />哈哈"#,
            baseURL: nil
        )
        XCTAssertFalse(blocks.contains { block in
            if case .image = block { return true }
            return false
        }, "表情不应成为独立图片块,实际:\(blocks)")
        XCTAssertEqual(blocks.count, 1, "相邻行内内容应合并为单块,实际:\(blocks)")
        guard case let .text(attributed)? = blocks.first else {
            return XCTFail("应为文本块,实际:\(blocks)")
        }
        XCTAssertTrue(attributed.value.string.contains("发出来给大家一起蹬"))
        XCTAssertTrue(attributed.value.string.contains("\u{FFFC}"))
        XCTAssertTrue(attributed.value.string.contains("哈哈"))
    }

    func testImageAttachmentsAppendAsImageBlocks() {
        // 移动 API 游客态不内嵌附件图:图片/文件附件应补为块尾的图片块与附件块
        let imageJSON = JSON([
            "url": "https://stage1st.com/2b/forum.php?mod=image",
            "attachment": "&aid=88&size=300",
            "isimage": "1",
            "filename": "a.jpg",
            "filesize": 1024,
            "ext": "jpg",
        ])
        let fileJSON = JSON([
            "url": "https://stage1st.com/2b/forum.php?mod=attachment",
            "attachment": "&aid=99",
            "isimage": "0",
            "filename": "doc.pdf",
            "filesize": 2048,
            "ext": "pdf",
        ])
        let blocks = BlockSplitter.split(
            html: "<p>正文</p>",
            baseURL: nil,
            extraAttachments: [PostAttachment(json: imageJSON), PostAttachment(json: fileJSON)]
        )
        XCTAssertEqual(blocks.count, 3, "文本 + 图片附件 + 文件附件,实际:\(blocks)")
        guard blocks.count == 3 else { return }
        guard case let .image(image) = blocks[1] else {
            return XCTFail("第 2 块应为图片块,实际:\(blocks)")
        }
        XCTAssertEqual(image.url.absoluteString, "https://stage1st.com/2b/forum.php?mod=image&aid=88&size=300")
        guard case let .fileAttachment(file) = blocks[2] else {
            return XCTFail("第 3 块应为附件块,实际:\(blocks)")
        }
        XCTAssertEqual(file.name, "doc.pdf")
    }

    /// checkpost(version=1)接口的引用结构为 <div class="quote"><blockquote>,需能解析为引用块
    func testV1QuoteDivBlockquoteParsesAsQuote() {
        let html = ##"<div class="quote"><blockquote><a href="https://stage1st.com/2b/forum.php?mod=redirect&amp;goto=findpost&amp;pid=70456467&amp;ptid=2293069" target="_blank"><font color="#999999">seducer0719 发表于 2026-11-2 12:18</font></a><br />\r\n这不是堕落天使？</blockquote></div><br />\r\n正文内容"##
        let blocks = BlockSplitter.split(html: html, baseURL: nil)
        guard case let .quote(author, dateText, attributed)? = blocks.first else {
            return XCTFail("第一个块应为引用块,实际:\(blocks)")
        }
        XCTAssertEqual(author, "seducer0719")
        XCTAssertEqual(dateText, "2026-11-2 12:18")
        XCTAssertTrue(attributed.value.string.contains("这不是堕落天使"))
        // 引用之后的正文仍应作为文本块出现
        let hasBody = blocks.contains { block in
            if case let .text(t) = block { return t.value.string.contains("正文内容") }
            return false
        }
        XCTAssertTrue(hasBody, "引用后的正文应作为文本块,实际:\(blocks)")
    }

    /// 登录态:正文里的 [attach]aid[/attach] 应按附件元数据替换为图片块(而非字面量)
    func testInlineAttachBBCodeBecomesImageBlock() {
        let attachmentJSON = JSON([
            "aid": "2166637",
            "url": "https://img.stage1st.com/forum/",
            "attachment": "202611/02/abc.png",
            "isimage": "-1",
            "attachimg": "1",
            "filename": "op.png",
            "filesize": "290470",
            "width": "768",
            "height": "432",
        ])
        let attachment = PostAttachment(json: attachmentJSON)
        let html = "<br />[attach]2166637[/attach]<br />看这张图"
        let blocks = BlockSplitter.split(
            html: html,
            baseURL: nil,
            extraAttachments: [attachment],
            attachmentsByAid: [2166637: attachment]
        )
        // 不应残留 BBCode 字面量
        let joined = blocks.compactMap { block -> String? in
            if case let .text(t) = block { return t.value.string }
            return nil
        }.joined()
        XCTAssertFalse(joined.contains("[attach]"), "不应残留 [attach] 字面量,实际:\(joined)")
        // 应有一个图片块,且带服务端宽高比例
        guard let imageBlock = blocks.first(where: { if case .image = $0 { return true } else { return false } }),
              case let .image(image) = imageBlock else {
            return XCTFail("应包含图片块,实际:\(blocks)")
        }
        XCTAssertEqual(image.url.absoluteString, "https://img.stage1st.com/forum/202611/02/abc.png")
        XCTAssertEqual(image.displayWidth, 768)
        XCTAssertEqual(image.displayHeight, 432)
        // 已内联引用的附件不应在末尾重复追加
        XCTAssertEqual(blocks.filter { if case .image = $0 { return true } else { return false } }.count, 1,
                       "图片附件不应重复,实际:\(blocks)")
    }

    /// [attachimg] 形式同样按附件元数据替换为图片
    func testInlineAttachImgBBCodeBecomesImageBlock() {
        let attachment = PostAttachment(json: JSON([
            "aid": "99",
            "url": "https://img.stage1st.com/forum/",
            "attachment": "202611/02/x.jpg",
            "isimage": "1",
            "attachimg": "1",
            "filename": "x.jpg",
            "filesize": "1000",
        ]))
        let blocks = BlockSplitter.split(
            html: "[attachimg]99[/attachimg]",
            baseURL: nil,
            extraAttachments: [attachment],
            attachmentsByAid: [99: attachment]
        )
        guard case let .image(image)? = blocks.first else {
            return XCTFail("应包含图片块,实际:\(blocks)")
        }
        XCTAssertEqual(image.url.absoluteString, "https://img.stage1st.com/forum/202611/02/x.jpg")
    }

    /// 图片块前后的 <br> 空行属于作者排版,应两侧对称保留(不能一侧删一侧留)
    func testImageSurroundingBlankLinesPreservedSymmetrically() {
        let attachment = PostAttachment(json: JSON([
            "aid": "2166637",
            "url": "https://img.stage1st.com/forum/",
            "attachment": "202611/02/abc.png",
            "isimage": "-1",
            "attachimg": "1",
            "filename": "op.png",
            "filesize": "290470",
            "width": "768",
            "height": "432",
        ]))
        // 还原真实结构:<br/><br/><br/>[attach]…[/attach]<br/><br/>正文
        let html = "<br /><br /><br />[attach]2166637[/attach]<br /><br />看这张图"
        let blocks = BlockSplitter.split(
            html: html,
            baseURL: nil,
            extraAttachments: [attachment],
            attachmentsByAid: [2166637: attachment]
        )
        // 图片块存在
        XCTAssertTrue(blocks.contains { if case .image = $0 { return true } else { return false } },
                      "应包含图片块,实际:\(blocks)")
        // 图片前的空行块被保留(纯换行块)
        guard let imageIndex = blocks.firstIndex(where: { if case .image = $0 { return true } else { return false } }),
              imageIndex >= 1,
              case let .text(before) = blocks[imageIndex - 1] else {
            return XCTFail("图片前应保留空行块,实际:\(blocks)")
        }
        // 3 个 <br> 作为独立块渲染成 3 行空白:去掉块尾多余换行后为 2 个换行
        // (CRLF 已归一,不能翻倍成 6 个换行)
        XCTAssertEqual(before.value.string, "\n\n",
                       "图片前 3 个 <br> 应渲染为 3 行空白(2 个换行),实际:\(before.value.string.debugDescription)")
        // 图片后的文本块保留作者的前导换行(<br/><br/>)
        guard let afterIndex = blocks.indices.first(where: { $0 > imageIndex }),
              case let .text(after) = blocks[afterIndex] else {
            return XCTFail("图片后应有文本块,实际:\(blocks)")
        }
        XCTAssertTrue(after.value.string.hasPrefix("\n"), "图片后文本应保留前导换行,实际:\(after.value.string.debugDescription)")
        XCTAssertTrue(after.value.string.contains("看这张图"))
    }

    // MARK: - 「本帖最后由…编辑」正文内弱化显示

    private let editedMessage = """
    <i class="pstatus"> 本帖最后由 28201 于 2026-10-20 23:07 编辑 </i><br />\n<br />\n试一试就知道了
    """

    /// 编辑标记保留在正文中,但字号更小、使用次要文字色
    func testEditMarkerRenderedSmallAndSecondaryColor() {
        let blocks = BlockSplitter.split(html: editedMessage, baseURL: nil)
        let combined = NSMutableAttributedString()
        for block in blocks {
            if case let .text(t) = block { combined.append(t.value) }
        }
        let string = combined.string
        XCTAssertTrue(string.contains("本帖最后由"), "正文应保留编辑标记,实际:\(string)")
        XCTAssertTrue(string.contains("试一试就知道了"))

        guard let editRange = string.range(of: "本帖最后由") else {
            return XCTFail("应能定位编辑标记,实际:\(string)")
        }
        let editLocation = string.distance(from: string.startIndex, to: editRange.lowerBound)
        let editColor = combined.attribute(.foregroundColor, at: editLocation, effectiveRange: nil) as? UIColor
        let editFont = combined.attribute(.font, at: editLocation, effectiveRange: nil) as? UIFont
        // Theme 颜色为动态色,按解析后的 RGBA 断言
        XCTAssertEqual(
            editColor?.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).cgColor,
            Theme.secondaryLabel.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).cgColor,
            "编辑标记应为次要文字色"
        )

        // 编辑标记应保持斜体(原 <i> 语义)
        XCTAssertNotNil(editFont)
        if let editFont {
            XCTAssertTrue(editFont.fontDescriptor.symbolicTraits.contains(.traitItalic), "编辑标记应保持斜体")
        }

        guard let bodyRange = string.range(of: "试一试就知道了") else {
            return XCTFail("应能定位正文")
        }
        let bodyLocation = string.distance(from: string.startIndex, to: bodyRange.lowerBound)
        let bodyFont = combined.attribute(.font, at: bodyLocation, effectiveRange: nil) as? UIFont
        XCTAssertNotNil(editFont)
        XCTAssertNotNil(bodyFont)
        if let editFont, let bodyFont {
            XCTAssertLessThan(editFont.pointSize, bodyFont.pointSize, "编辑标记字号应小于正文")
        }
    }
}
