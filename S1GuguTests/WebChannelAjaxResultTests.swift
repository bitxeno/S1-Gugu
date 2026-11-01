import XCTest
@testable import S1Gugu

final class WebChannelAjaxResultTests: XCTestCase {

    /// 投票成功响应(Discuz showmessage location => true):只有跳转脚本,无 succeedhandle 回调
    func testLocationScriptResponseCountsAsSuccess() {
        let html = #"<?xml version="1.0" encoding="utf-8"?><root><![CDATA[<script type="text/javascript" reload="1">window.location.href='forum.php?mod=viewthread&tid=2292712&mobile=2';</script>]]></root>"#
        let result = WebChannel.parseAjaxResult(html)
        XCTAssertTrue(result.success)
    }

    func testSucceedHandleResponse() {
        let html = #"<root><![CDATA[<script type="text/javascript" reload="1">if(typeof succeedhandle_=='function') {succeedhandle_('forum.php?mod=viewthread&tid=1', '操作成功', {});}</script>]]></root>"#
        let result = WebChannel.parseAjaxResult(html)
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.message, "操作成功")
    }

    func testErrorHandleResponse() {
        let html = #"<root><![CDATA[<script type="text/javascript" reload="1">if(typeof errorhandle_=='function') {errorhandle_('您已参与过投票', {});}</script>]]></root>"#
        let result = WebChannel.parseAjaxResult(html)
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.message, "您已参与过投票")
    }

    func testAlertErrorResponse() {
        let html = #"<div id="messagetext"><p>您当前的访问请求当中含有非法字符，已经被系统拒绝</p></div>"#
        let result = WebChannel.parseAjaxResult(html)
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.message.contains("非法字符"))
    }
}
