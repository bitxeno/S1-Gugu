import Foundation
import OSLog

/// Discuz 移动 API 返回的 JSON 不严格,解码前需修复(对齐 S1-Next RawJsonConverterFactory):
/// 1. 空值 `:,` → `:null,`(顺带覆盖 `:,}`);`: ]` 缺值同理。
/// 2. 坏的 `\u` 转义(不足 4 位十六进制)剥离,避免整包解码失败。
/// 3. 未加引号的 key 由 JSON5 兜底解码处理(见 S1APIClient)。
enum ResponseCleaner {

    /// HTML / inajax 响应解码:直接按 UTF-8 还原,**不做 JSON 修复**。
    /// 早期这里误用 `clean()`(JSON 清洗),它会把「第一个 `{` 之前的含 `<` 前缀」整段截掉,
    /// 而 Discuz 的 inajax HTML 形如 `<?xml…><root><![CDATA[<script>…{…}`,
    /// 表单(id=postform、formhash 等)恰在第一个 `{` 之前,会被一并切掉,
    /// 导致编辑器/投票等表单解析失败(典型表现:「获取编辑器信息失败」)。
    static func htmlString(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? ""
    }

    static func clean(_ data: Data) -> Data {
        guard var text = String(data: data, encoding: .utf8) else { return data }

        // 服务器偶发在 JSON 前输出 PHP Warning/HTML,截取第一个 '{' 之后的内容
        if let firstBrace = text.firstIndex(of: "{"), firstBrace != text.startIndex {
            let prefix = text[..<firstBrace]
            if prefix.contains("<") {
                text = String(text[firstBrace...])
            }
        }

        // \uXXXX 统一还原(Discuz 手拼 JSON 存在双重转义 \uXXXX;S1-Next 同款 uniDecode 方案)
        if text.contains("\\u") {
            text = decodeUnicodeEscapes(text)
        }
        // 非法转义(\> 等)+ 字符串内裸控制字符
        text = escapeRawControlCharacters(text)

        if text.contains(":,") {
            text = text.replacingOccurrences(of: ":,", with: ":null,")
        }
        if text.contains(":]") {
            text = text.replacingOccurrences(of: ":]", with: ":null]")
        }
        return Data(text.utf8)
    }

    /// 把 \uXXXX 解码为真实字符。目标为 " 或 \ 时保留原样(避免破坏 JSON 结构);
    /// 不足 4 位 hex 的残缺转义丢弃反斜杠保留字面字符。
    static func decodeUnicodeEscapes(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        var iterator = text.unicodeScalars.makeIterator()
        while let scalar = iterator.next() {
            guard scalar == "\\" else {
                result.append(scalar)
                continue
            }
            guard let next = iterator.next() else {
                result.append(scalar)
                break
            }
            guard next == "u" else {
                result.append(scalar)
                result.append(next)
                continue
            }
            var hexChars: [Unicode.Scalar] = []
            for _ in 0..<4 {
                guard let hex = iterator.next(), hex.properties.isASCIIHexDigit else { break }
                hexChars.append(hex)
            }
            guard hexChars.count == 4,
                  let value = UInt32(String(String.UnicodeScalarView(hexChars)), radix: 16),
                  let decoded = Unicode.Scalar(value)
            else {
                // 残缺转义:丢反斜杠,已读字符原样保留
                if next != "u" { result.append(next) }
                result.append(contentsOf: hexChars)
                continue
            }
            if decoded == "\"" || decoded == "\\" {
                // 结构敏感字符保留原样,交给 JSON 解码器
                result.append("\\")
                result.append("u")
                result.append(contentsOf: hexChars)
            } else {
                result.append(decoded)
            }
        }
        return String(result)
    }

    /// 未加引号的 key 修复(裸数字/标识符)。仅对已知需要的接口使用——
    /// 全局应用会误伤字符串值内的 ",xxx:" 模式。
    static func repairUnquotedKeys(_ text: String) -> String {
        guard text.contains("{") else { return text }
        return text.replacing(/([{,])(\s*)([A-Za-z0-9_-]+)(\s*:)/) { match in
            "\(match.1)\(match.2)\"\(match.3)\"\(match.4)"
        }
    }

    /// 字符串字面量内的两类脏数据修复:
    /// 1. 裸控制字符(<0x20)转义为合法形式;
    /// 2. 非法转义序列(\>、\<、\ 、\a 等非 JSON 合法转义)丢弃反斜杠保留字面字符。
    /// Discuz 移动 API 为手工拼接 JSON,两类问题都高频出现。
    static func escapeRawControlCharacters(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        var inString = false
        var isEscaped = false

        func appendControlEscape(_ scalar: Unicode.Scalar) {
            switch scalar {
            case "\n": result.append(contentsOf: "\\n".unicodeScalars)
            case "\r": result.append(contentsOf: "\\r".unicodeScalars)
            case "\t": result.append(contentsOf: "\\t".unicodeScalars)
            default:
                let hex = String(scalar.value, radix: 16)
                result.append(contentsOf: "\\u\(String(repeating: "0", count: max(0, 4 - hex.count)))\(hex)".unicodeScalars)
            }
        }

        for scalar in text.unicodeScalars {
            if isEscaped {
                isEscaped = false
                switch scalar {
                case "\"", "\\", "/", "b", "f", "n", "r", "t":
                    result.append("\\")
                    result.append(scalar)
                case "u":
                    result.append("\\")
                    result.append("u")
                default:
                    if scalar.value < 0x20 {
                        appendControlEscape(scalar)
                    } else {
                        result.append(scalar)
                    }
                }
                continue
            }
            if inString {
                switch scalar {
                case "\\":
                    isEscaped = true
                case "\"":
                    inString = false
                    result.append(scalar)
                default:
                    if scalar.value < 0x20 {
                        appendControlEscape(scalar)
                    } else {
                        result.append(scalar)
                    }
                }
                continue
            }
            if scalar == "\"" {
                inString = true
            }
            result.append(scalar)
        }
        return String(result)
    }
}

enum NetworkLog {
    static let net = Logger(subsystem: "app.bitxeno.s1gugu", category: "net")
    static let decode = Logger(subsystem: "app.bitxeno.s1gugu", category: "decode")
    static let session = Logger(subsystem: "app.bitxeno.s1gugu", category: "session")
    static let db = Logger(subsystem: "app.bitxeno.s1gugu", category: "db")
}
