import XCTest
@testable import S1Gugu

@MainActor
final class LinkRouterTests: XCTestCase {

    func testParseThreadURL() {
        XCTAssertEqual(
            LinkRouter.parseThread(URL(string: "https://stage1st.com/2b/thread-123456-2-1.html")!),
            LinkRouter.ThreadTarget(tid: 123456, page: 2)
        )
        XCTAssertEqual(
            LinkRouter.parseThread(URL(string: "https://bbs.saraba1st.com/2b/thread-99-1-1.html")!),
            LinkRouter.ThreadTarget(tid: 99, page: 1)
        )
        XCTAssertEqual(
            LinkRouter.parseThread(URL(string: "https://stage1st.com/2b/forum.php?mod=viewthread&tid=55&page=3")!),
            LinkRouter.ThreadTarget(tid: 55, page: 3)
        )
        XCTAssertNil(LinkRouter.parseThread(URL(string: "https://example.com/thread-1-1-1.html")!))
    }

    func testParseForumURL() {
        XCTAssertEqual(
            LinkRouter.parseForum(URL(string: "https://stage1st.com/2b/forum-87-1.html")!),
            LinkRouter.ForumTarget(fid: 87)
        )
        XCTAssertEqual(
            LinkRouter.parseForum(URL(string: "https://stage1st.com/2b/forum.php?mod=forumdisplay&fid=12")!),
            LinkRouter.ForumTarget(fid: 12)
        )
    }

    func testAvatarURL() {
        XCTAssertEqual(
            AvatarURL.url(uid: 223963)?.absoluteString,
            "https://avatar.stage1st.com/000/22/39/63_avatar_big.jpg"
        )
        XCTAssertNil(AvatarURL.url(uid: 0))
    }

    func testParseClipboardURL() {
        // 完整链接
        XCTAssertEqual(
            LinkRouter.parseClipboardURL("https://stage1st.com/2b/thread-2293055-1-1.html")?.absoluteString,
            "https://stage1st.com/2b/thread-2293055-1-1.html"
        )
        // 不带 scheme 的裸链接
        XCTAssertEqual(
            LinkRouter.parseClipboardURL(" stage1st.com/2b/thread-2293055-2-1.html\n")?.path,
            "/2b/thread-2293055-2-1.html"
        )
        // 换行/空白包裹
        XCTAssertNotNil(LinkRouter.parseClipboardURL("  https://stage1st.com/2b/forum-87-1.html  "))
        // 站外域名不接管
        XCTAssertNil(LinkRouter.parseClipboardURL("https://example.com/thread-1-1-1.html"))
        // 站内但无法定位到页面的链接不接管
        XCTAssertNil(LinkRouter.parseClipboardURL("https://stage1st.com/2b/"))
        XCTAssertNil(LinkRouter.parseClipboardURL("hello world"))
    }
}
