import XCTest
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
        guard case let .quote(author, attributed)? = blocks.first else {
            return XCTFail("第一个块应为引用块,实际:\(blocks)")
        }
        XCTAssertEqual(author, "张三")
        XCTAssertTrue(attributed.value.string.contains("引用的内容"))
        XCTAssertFalse(attributed.value.string.contains("发表于"))
    }

    func testQuoteBlacklistReplacement() {
        let html = ##"<blockquote><font color="#999999">张三 发表于 2024-1-1 12:00</font><br />不该看的内容</blockquote>"##
        let blocks = BlockSplitter.split(html: html, baseURL: nil, quoteReplacer: { author in
            author == "张三" ? "[已被抹布]" : nil
        })
        guard case let .quote(_, attributed)? = blocks.first else {
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
}
