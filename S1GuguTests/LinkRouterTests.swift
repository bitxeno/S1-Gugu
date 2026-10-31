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
}
