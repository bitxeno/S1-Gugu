import XCTest
@testable import S1Gugu

final class HTMLParsersTests: XCTestCase {

    func testForumSearchParsing() {
        let html = """
        <html><body>
        <em>找到 “黄金” 相关内容 25 个</em>
        <ul>
        <li class="pbw"><a href="thread-111-1-1.html">标题A</a><p>摘要A</p></li>
        <li class="pbw"><a href="thread-222-1-1.html">标题B</a><p>摘要B</p></li>
        </ul>
        <div class="pg"><strong>2</strong><a href="search.php?mod=forum&searchid=9&page=3">3</a><span title=" / 5 "> / 5 </span></div>
        </body></html>
        """
        let page = HTMLParsers.forumSearch(html)
        XCTAssertFalse(page.invalid)
        XCTAssertEqual(page.count, 25)
        XCTAssertEqual(page.results.count, 2)
        XCTAssertEqual(page.page, 2)
        XCTAssertEqual(page.maxPage, 5)
        XCTAssertTrue(page.nextPageHref?.hasSuffix("page=") ?? false)
    }

    func testForumSearchErrorPage() {
        let html = #"<div id="messagetext">抱歉,您没有权限搜索</div>"#
        let page = HTMLParsers.forumSearch(html)
        XCTAssertTrue(page.invalid)
        XCTAssertEqual(page.results.count, 0)
    }

    func testUserSearchParsing() {
        let html = """
        <ul>
        <li class="bbda cl"><span>1</span><span><a href="space-uid-561399.html">kozalak</a></span></li>
        <li class="bbda cl"><span>2</span><span><a href="space-uid-42.html">某人</a></span></li>
        </ul>
        """
        let (results, error) = HTMLParsers.userSearch(html)
        XCTAssertNil(error)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].uid, "561399")
        XCTAssertEqual(results[0].name, "kozalak")
    }

    func testHomeThreadsParsing() {
        let html = """
        <html><body>
        <table id="delform"><tbody>
        <tr><th>标题</th><th>版块</th><th>回复/浏览</th><th>最后发表</th></tr>
        <tr>
          <td>1</td>
          <td><a href="thread-333-1-1.html">我的主题</a></td>
          <td><a href="forum-87-1.html">归墟</a></td>
          <td><em>5</em><em>100</em></td>
          <td><p><a href="space-uid-1.html">某人</a></p><p><a href="#">2026-1-1</a></p></td>
        </tr>
        </tbody></table>
        <div class="pg"><a href="home.php?page=2" class="nxt">下一页</a></div>
        </body></html>
        """
        let (items, hasMore) = HTMLParsers.homeThreads(html)
        XCTAssertTrue(hasMore)
        XCTAssertEqual(items.count, 1)
        let item = try! XCTUnwrap(items.first)
        XCTAssertEqual(item.title, "我的主题")
        XCTAssertEqual(item.threadId, 333)
        XCTAssertEqual(item.forum, "归墟")
        XCTAssertEqual(item.replyCount, "5")
        XCTAssertEqual(item.viewCount, "100")
        XCTAssertEqual(item.lastReplier, "某人")
    }

    func testHomeRepliesParsing() {
        let html = """
        <html><body>
        <table id="delform"><tbody>
        <tr><th>回复</th></tr>
        <tr><td><span>某人</span><a href="thread-444-2-1.html">主题标题</a><span>2026-1-1</span></td></tr>
        </tbody></table>
        </body></html>
        """
        let (items, hasMore) = HTMLParsers.homeReplies(html)
        XCTAssertFalse(hasMore)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.reply, "主题标题")
        XCTAssertEqual(items.first?.threadId, 444)
    }

    func testRatesParsing() {
        // 结构对齐真实 viewratings 响应(表头行 + 数据行)
        let html = """
        <?xml version="1.0" encoding="utf-8"?>
        <root><![CDATA[<div class="c">
        <table cellspacing="0" cellpadding="0"><tbody>
        <tr><td>积分</td><td>用户名</td><td>时间</td><td>理由</td></tr>
        <tr><td>积分+2</td><td><a href="space-uid-123.html">张三</a></td><td>2026-1-1 12:00</td><td>优秀文章</td></tr>
        <tr><td>积分-1</td><td><a href="space-uid-456.html">李四</a></td><td>2026-1-2 10:00</td><td>水贴</td></tr>
        </tbody></table></div>]]></root>
        """
        let rates = HTMLParsers.rates(html)
        XCTAssertEqual(rates.count, 2)
        XCTAssertEqual(rates[0].uname, "张三")
        XCTAssertEqual(rates[0].score, 2)
        XCTAssertEqual(rates[0].symbolScore, "+2")
        XCTAssertEqual(rates[0].uid, "123")
        XCTAssertEqual(rates[0].content, "优秀文章")
        XCTAssertEqual(rates[1].score, -1)
        XCTAssertEqual(rates[1].symbolScore, "-1")
    }

    func testRatesEmptyErrorPage() {
        // 服务端无评分时返回 alert_error(真实响应样例)
        let html = """
        <?xml version="1.0" encoding="utf-8"?>
        <root><![CDATA[<div class="alert_error">抱歉,指定帖子在近一年内没有评分记录</div>]]></root>
        """
        XCTAssertEqual(HTMLParsers.rates(html).count, 0)
    }

    func testWebBlacklistParsing() {
        let html = """
        <html><body>
        <div id="friend_ul"><ul class="buddy cl">
          <li id="friend_539063_li">
            <div class="avt"><a href="space-uid-539063.html"><img src="a.jpg"></a></div>
            <h4>
              <span class="xg1 xw0 y"><a href="home.php?mod=spacecp&ac=friend&op=blacklist&subop=delete&uid=539063">黑名单除名</a></span>
              <a href="space-uid-539063.html">咖啡渣</a>
            </h4>
          </li>
          <li id="friend_42_li">
            <div class="avt"><a href="space-uid-42.html"><img src="b.jpg"></a></div>
            <h4><a href="space-uid-42.html">某人</a></h4>
          </li>
        </ul></div>
        <div class="pg"><label><span>1 / 3</span><input type="text" name="custompage" value="1"></label>
          <a href="home.php?mod=space&do=friend&view=blacklist&uid=561399&page=2">下一页</a>
        </div>
        </body></html>
        """
        let page = HTMLParsers.webBlacklist(html)
        XCTAssertEqual(page.users.count, 2)
        XCTAssertEqual(page.users[0].uid, 539063)
        XCTAssertEqual(page.users[0].name, "咖啡渣")
        XCTAssertEqual(page.users[1].uid, 42)
        XCTAssertEqual(page.users[1].name, "某人")
        XCTAssertEqual(page.page, 1)
        XCTAssertEqual(page.maxPage, 3)
    }

    func testWebBlacklistWithoutPagination() {
        let html = """
        <div id="friend_ul"><ul><li><h4><a href="space-uid-7.html">甲</a></h4></li></ul></div>
        """
        let page = HTMLParsers.webBlacklist(html)
        XCTAssertEqual(page.users.map(\.uid), [7])
        XCTAssertEqual(page.page, 1)
        XCTAssertEqual(page.maxPage, 1)
    }
}
