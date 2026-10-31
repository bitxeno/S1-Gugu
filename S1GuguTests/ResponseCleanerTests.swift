import XCTest
import SwiftyJSON
@testable import S1Gugu

final class ResponseCleanerTests: XCTestCase {

    func testCleanKeepsValidJSONUntouched() throws {
        let original = #"{"Variables":{"member_uid":"0","list":[{"tid":"1"}]}}"#
        let cleaned = ResponseCleaner.clean(Data(original.utf8))
        XCTAssertEqual(String(data: cleaned, encoding: .utf8), original)
    }

    func testCleanFixesNullValues() {
        // `:,` → `:null,`;`: ]` 缺值 → `:null]`
        XCTAssertEqual(
            String(data: ResponseCleaner.clean(Data(#"{"a":,]"#.utf8)), encoding: .utf8),
            #"{"a":null,]"#
        )
        XCTAssertEqual(
            String(data: ResponseCleaner.clean(Data(#"{"a":1,"b":,}"#.utf8)), encoding: .utf8),
            #"{"a":1,"b":null,}"#
        )
        XCTAssertEqual(
            String(data: ResponseCleaner.clean(Data(#"{"a":]"#.utf8)), encoding: .utf8),
            #"{"a":null]"#
        )
    }

    func testCleanStripsHTMLWarningPrefix() {
        let dirty = "<br />\n<b>Warning</b>: Undefined array key in mobile.php\n" + #"{"Variables":{}}"#
        XCTAssertEqual(
            String(data: ResponseCleaner.clean(Data(dirty.utf8)), encoding: .utf8),
            #"{"Variables":{}}"#
        )
    }

    func testDecodeUnicodeEscapes() {
        // 单转义 → 解码
        XCTAssertEqual(ResponseCleaner.decodeUnicodeEscapes(#"a\u6211b"#), "a我b")
        // 双反斜杠 + u:保留(与 S1-Next uniDecode 行为一致,残层由非法转义修复兜底)
        XCTAssertEqual(ResponseCleaner.decodeUnicodeEscapes(#"\\u8fd8"#), #"\\u8fd8"#)
        // 结构敏感字符保留原样,交给 JSON 解码器
        XCTAssertEqual(ResponseCleaner.decodeUnicodeEscapes(#"\u0022\u005c"#), #"\u0022\u005c"#)
        // 残缺转义:丢弃反斜杠,保留字面字符
        XCTAssertEqual(ResponseCleaner.decodeUnicodeEscapes(#"a\u12b"#), "a12b")
        XCTAssertEqual(ResponseCleaner.decodeUnicodeEscapes(#"a\ub"#), "ab")
    }

    func testEscapeRawControlCharacters() {
        // 字符串内裸换行转义
        let withNewline = #"""
        {"message":"line1
        line2"}
        """#
        XCTAssertEqual(
            ResponseCleaner.escapeRawControlCharacters(withNewline),
            #"{"message":"line1\nline2"}"#
        )
        // 非法转义 \> 丢反斜杠(仅字符串字面量内,与 JSON 上下文一致)
        XCTAssertEqual(
            ResponseCleaner.escapeRawControlCharacters(#"{"m":"<br \>x"}"#),
            #"{"m":"<br >x"}"#
        )
        // 合法转义保留
        XCTAssertEqual(
            ResponseCleaner.escapeRawControlCharacters(#"a\"b\\c\/d"#),
            #"a\"b\\c\/d"#
        )
        // \u 序列保留(交给 JSON 解码器)
        XCTAssertEqual(ResponseCleaner.escapeRawControlCharacters(#"\u6211"#), #"\u6211"#)
    }

    func testEndToEndDirtyResponseDecodes() throws {
        // 模拟 Discuz 真实脏响应:HTML 前缀 + 非法转义 \> + \u 转义中文
        let dirty = """
        <br /><b>Warning</b>: x\\n{"Variables":{"member_uid":"1","member_username":"tester","formhash":"abc123","postlist":[{"pid":"1","author":"author\\u6d4b\\u8bd5","authorid":"42","first":"1","number":"1","dbdateline":"1700000000","message":"<br \\>\\u4f60\\u597d"}]}}
        """
        let cleaned = ResponseCleaner.clean(Data(dirty.utf8))
        let json = try JSON(data: cleaned)
        XCTAssertEqual(json["Variables"]["member_uid"].string, "1")
        XCTAssertEqual(json["Variables"]["formhash"].string, "abc123")
        XCTAssertEqual(json["Variables"]["postlist"][0]["author"].string, "author测试")
        XCTAssertTrue(json["Variables"]["postlist"][0]["message"].stringValue.contains(">你好"))
    }
}
