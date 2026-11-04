import XCTest
import SwiftyJSON
@testable import S1Gugu

final class RelativeTimeFormatterTests: XCTestCase {

    /// 固定基准时间,避免真实时钟造成用例抖动
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func assertText(
        secondsAgo: TimeInterval,
        equals expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let date = now.addingTimeInterval(-secondsAgo)
        XCTAssertEqual(
            RelativeTimeFormatter.friendlyText(for: date, now: now),
            expected,
            file: file,
            line: line
        )
    }

    // MARK: - 刚刚 / 秒

    func testJustNowWithinTenSeconds() {
        assertText(secondsAgo: 0, equals: "刚刚")
        assertText(secondsAgo: 9, equals: "刚刚")
    }

    func testFutureTimeFallsBackToJustNow() {
        assertText(secondsAgo: -30, equals: "刚刚")
    }

    func testSecondsAgo() {
        assertText(secondsAgo: 10, equals: "10秒前")
        assertText(secondsAgo: 59, equals: "59秒前")
    }

    // MARK: - 分钟 / 小时

    func testMinutesAgo() {
        assertText(secondsAgo: 60, equals: "1分钟前")
        assertText(secondsAgo: 59 * 60 + 59, equals: "59分钟前")
    }

    func testHoursAgo() {
        assertText(secondsAgo: 3_600, equals: "1小时前")
        assertText(secondsAgo: 23 * 3_600 + 59 * 60, equals: "23小时前")
    }

    // MARK: - 天 / 绝对时间

    func testDaysAgo() {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")

        let oneDayAgo = now.addingTimeInterval(-86_400)
        assertText(
            secondsAgo: 86_400,
            equals: "1天前 \(timeFormatter.string(from: oneDayAgo))"
        )

        let sixDaysAgo = now.addingTimeInterval(-(6 * 86_400 + 3_600))
        assertText(
            secondsAgo: 6 * 86_400 + 3_600,
            equals: "6天前 \(timeFormatter.string(from: sixDaysAgo))"
        )
    }

    func testSevenDaysFallsBackToAbsoluteDate() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let sevenDaysAgo = now.addingTimeInterval(-7 * 86_400)
        XCTAssertEqual(
            RelativeTimeFormatter.friendlyText(for: sevenDaysAgo, now: now),
            formatter.string(from: sevenDaysAgo)
        )
    }

    // MARK: - 输入解析

    func testUnixTimestampString() {
        XCTAssertEqual(
            RelativeTimeFormatter.friendlyText(from: "1699998200", now: now),
            "30分钟前"
        )
    }

    func testServerFormattedStringUsesForumTimeZone() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        let published = "2026-10-31 12:26"
        guard let date = formatter.date(from: published) else {
            return XCTFail("测试数据无法解析")
        }
        XCTAssertEqual(
            RelativeTimeFormatter.friendlyText(from: published, now: date.addingTimeInterval(3 * 3_600)),
            "3小时前"
        )
    }

    func testMissingOrInvalidInputReturnsNil() {
        XCTAssertNil(RelativeTimeFormatter.friendlyText(from: nil, now: now))
        XCTAssertNil(RelativeTimeFormatter.friendlyText(from: "", now: now))
        XCTAssertNil(RelativeTimeFormatter.friendlyText(from: "   ", now: now))
        XCTAssertNil(RelativeTimeFormatter.friendlyText(from: "不是时间", now: now))
        XCTAssertNil(RelativeTimeFormatter.friendlyText(from: "0", now: now))
        XCTAssertNil(RelativeTimeFormatter.friendlyText(from: "-100", now: now))
    }

    // MARK: - Thread 回退

    func testThreadFallsBackToAbsoluteTextWhenUnparseable() {
        let thread = S1Gugu.Thread(json: JSON(parseJSON: #"{"tid":"1","subject":"标题","dbdateline":"时间未知"}"#))
        XCTAssertEqual(thread.relativePublishedText, "时间未知")
    }
}
