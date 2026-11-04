import Foundation

/// 列表友好时间:几秒/几分钟/几小时/几天前,超过 7 天回退绝对时间。
///
/// `dbdateline` 通常是 Unix 时间戳串;为兼容服务端格式化串,也接受
/// `yyyy-MM-dd HH:mm`(按论坛所在时区解析)。两种格式都解析失败时返回 nil,
/// 由调用方回退到原始文本,避免相对时间把信息吃掉。
enum RelativeTimeFormatter {

    private static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// 服务端格式化串按论坛时区(中国标准时间)解释,不能按设备时区,
    /// 否则海外用户的相对时间会整体偏移。
    private static let serverFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return formatter
    }()

    /// 解析时间字段并返回相对文案;无法解析时返回 nil。
    static func friendlyText(from value: String?, now: Date = Date()) -> String? {
        guard let date = parse(value) else { return nil }
        return friendlyText(for: date, now: now)
    }

    /// 固定时间点的友好文案。`now` 可注入,便于单元测试。
    static func friendlyText(for date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        guard seconds.isFinite else { return absoluteFormatter.string(from: date) }

        // 10 秒内、以及客户端与服务端时钟偏差导致的未来时间,都按「刚刚」处理。
        if seconds < 10 { return "刚刚" }
        if seconds < 60 { return "\(Int(seconds))秒前" }
        if seconds < 3_600 { return "\(Int(seconds / 60))分钟前" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600))小时前" }
        if seconds < 7 * 86_400 {
            return "\(Int(seconds / 86_400))天前 \(timeFormatter.string(from: date))"
        }
        return absoluteFormatter.string(from: date)
    }

    private static func parse(_ value: String?) -> Date? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let seconds = Double(trimmed), seconds > 0 {
            return Date(timeIntervalSince1970: seconds)
        }
        return serverFormatter.date(from: trimmed)
    }
}
