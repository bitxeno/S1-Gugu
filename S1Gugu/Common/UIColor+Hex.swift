import UIKit

extension UIColor {
    /// 解析 Discuz 帖子里的 `#RRGGBB` / `#RGB` 颜色;失败返回 nil(调用方回退语义色)。
    convenience init?(discuzHex: String) {
        var hex = discuzHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 3 || hex.count == 6, hex.allSatisfy(\.isHexDigit) else { return nil }

        let values: [CGFloat]
        if hex.count == 3 {
            values = hex.map { CGFloat(Int(String($0), radix: 16) ?? 0) / 15.0 }
        } else {
            var scalars = Array(hex)
            var parsed: [CGFloat] = []
            while !scalars.isEmpty {
                let pair = String(scalars.prefix(2))
                parsed.append(CGFloat(Int(pair, radix: 16) ?? 0) / 255.0)
                scalars.removeFirst(2)
            }
            values = parsed
        }
        guard values.count == 3 else { return nil }
        self.init(red: values[0], green: values[1], blue: values[2], alpha: 1)
    }
}

import SwiftSoup

/// 服务端返回的通知/签名等富文本字段 → 纯文本(链接保留文字)
enum HTMLTextCleaner {
    static func plain(_ html: String?) -> String {
        guard let html, !html.isEmpty else { return "" }
        guard let document = try? SwiftSoup.parse(html),
              let text = try? document.text()
        else { return html }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
