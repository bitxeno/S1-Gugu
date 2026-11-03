import XCTest
@testable import S1Gugu

/// 回归:HTML / inajax 响应不能走 JSON 清洗。
/// 曾因 `getEditorInfo` 用 `ResponseCleaner.clean` 解码 HTML,把「第一个 `{` 之前的含 `<` 前缀」
/// 整段截掉,导致 form(id=postform、formhash)落在被截断区,解析失败并提示「获取编辑器信息失败」。
final class ResponseCleanerHTMLTests: XCTestCase {

    /// 模拟 Discuz inajax 编辑器页:form 在前,后面的 <script> 里才出现第一个 '{'
    private let editorHTML = """
    <?xml version="1.0" encoding="utf-8"?>
    <root><![CDATA[<script type="text/javascript">
    var allowpostattach = parseInt('1');
    var tid = parseInt('2186903');
    </script>
    <form method="post" autocomplete="off" id="postform" action="forum.php?mod=post&action=reply&tid=2186903">
    <input type="hidden" name="formhash" id="formhash" value="8e7a1067" />
    <textarea id="e_textarea" name="message"></textarea>
    </form>
    <script type="text/javascript">var postminchars = parseInt('10'); if (x) { y(); }</script>
    ]]></root>
    """

    func testHTMLStringDoesNotTruncateBeforeFirstBrace() {
        let data = Data(editorHTML.utf8)
        let html = ResponseCleaner.htmlString(data)
        XCTAssertEqual(html, editorHTML)
        XCTAssertTrue(html.contains("id=\"postform\""))
        XCTAssertTrue(html.contains("name=\"formhash\""))
    }

    /// 旧路径(JSON 清洗)会截断 form —— 文档化该行为,防止有人误用回 HTML 通道
    func testJSONCleanWouldHaveDroppedForm() {
        let data = Data(editorHTML.utf8)
        let cleaned = String(data: ResponseCleaner.clean(data), encoding: .utf8) ?? ""
        XCTAssertFalse(cleaned.contains("id=\"postform\""))
    }

    func testParseEditorInfoFromHTMLResponse() throws {
        let html = ResponseCleaner.htmlString(Data(editorHTML.utf8))
        let unwrapped = WebChannel.unwrapAjaxHTML(html)
        let info = try XCTUnwrap(
            WebChannel.parseEditorInfo(unwrapped, baseURL: URL(string: "https://stage1st.com/2b/")!)
        )
        XCTAssertEqual(info.formhash, "8e7a1067")
        XCTAssertNotNil(info.formAction)
    }
}
