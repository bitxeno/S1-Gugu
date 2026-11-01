import XCTest
import SwiftyJSON
@testable import S1Gugu

final class VoteInfoTests: XCTestCase {

    /// 样本取自 stage1st 移动 API 真实下发(游客态,tid=2292712):
    /// polloptions 为以 1 起始的字典,选项文字字段是 polloption(含已转义实体)
    private let guestPollJSON: JSON = {
        JSON([
            "polloptions": [
                "1": [
                    "polloptionid": "83082",
                    "polloption": "有pc和ps5，pc配置较低（&lt;5060），买pc版",
                    "votes": "19",
                    "width": "4%",
                    "percent": "3.51",
                    "color": "F2A61F",
                ],
                "2": [
                    "polloptionid": "83080",
                    "polloption": "只有pc没得选",
                    "votes": "162",
                    "width": "30%",
                    "percent": "29.89",
                ],
            ],
            "expirations": "1793624436",
            "multiple": "0",
            "maxchoices": "1",
            "voterscount": "542",
            "visiblepoll": "1",
            "allowvote": "",
        ])
    }()

    func testOptionTextReadsPolloptionFieldAndUnescapesEntities() {
        let vote = VoteInfo(json: guestPollJSON)
        XCTAssertEqual(vote.options.count, 2)
        XCTAssertEqual(vote.options.last?.option, "有pc和ps5，pc配置较低（<5060），买pc版")
        XCTAssertEqual(vote.options.first?.option, "只有pc没得选")
        XCTAssertEqual(vote.options.last?.votes, 19)
        XCTAssertEqual(vote.options.last?.percent, "3.51")
    }

    func testOptionsSortedByPolloptionId() {
        let vote = VoteInfo(json: guestPollJSON)
        XCTAssertEqual(vote.options.map(\.id), [83080, 83082])
    }

    func testGuestSeesReadOnlyResults() {
        let vote = VoteInfo(json: guestPollJSON)
        XCTAssertFalse(vote.allowVote)
        XCTAssertTrue(vote.visiblePoll, "游客/未投票者 visiblepoll=1 表示结果对其隐藏语义,仍展示只读结果")
        XCTAssertFalse(vote.multiple)
    }

    func testMaxChoicesOverOneImpliesMultiple() {
        var json = guestPollJSON
        json["maxchoices"] = JSON("2")
        json["polloptions"] = JSON([
            "1": ["polloptionid": "1", "polloption": "甲", "votes": "1", "percent": "50"],
            "2": ["polloptionid": "2", "polloption": "乙", "votes": "1", "percent": "50"],
        ])
        let vote = VoteInfo(json: json)
        XCTAssertTrue(vote.multiple)
    }
}
