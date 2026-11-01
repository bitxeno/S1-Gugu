import XCTest
import SwiftyJSON
@testable import S1Gugu

final class NewReplyCountTests: XCTestCase {

    private func thread(json: String) -> S1Gugu.Thread {
        S1Gugu.Thread(json: JSON(parseJSON: json))
    }

    /// 没浏览过(lastReplyCount == 0)不显示 +N
    func testNoMarkWhenNeverViewed() {
        var t = thread(json: #"{"tid":"1","replies":"10","subject":"A"}"#)
        t.lastReplyCount = 0
        XCTAssertNil(t.newReplyCount)
    }

    /// 回复无增长不显示 +N
    func testNoMarkWhenNoNewReplies() {
        var t = thread(json: #"{"tid":"1","replies":"10","subject":"A"}"#)
        t.lastReplyCount = 10
        XCTAssertNil(t.newReplyCount)
    }

    /// 本地记录比服务端新(缓存回退场景)不显示 +N
    func testNoMarkWhenLocalAhead() {
        var t = thread(json: #"{"tid":"1","replies":"8","subject":"A"}"#)
        t.lastReplyCount = 10
        XCTAssertNil(t.newReplyCount)
    }

    /// 有新回复时返回差值
    func testPositiveDelta() {
        var t = thread(json: #"{"tid":"1","replies":"15","subject":"A"}"#)
        t.lastReplyCount = 10
        XCTAssertEqual(t.newReplyCount, 5)
    }

    /// replies 数字/字符串混用(Discuz 手拼 JSON)都能解析
    func testStringAndNumberRepliesAgree() {
        var numeric = thread(json: #"{"tid":"1","replies":36,"subject":"A"}"#)
        var string = thread(json: #"{"tid":"1","replies":"36","subject":"A"}"#)
        numeric.lastReplyCount = 30
        string.lastReplyCount = 30
        XCTAssertEqual(numeric.newReplyCount, 6)
        XCTAssertEqual(string.newReplyCount, 6)
    }
}