import SwiftyJSON

// 缓存解析出的 JSON 值按值跨隔离传递且不再被共享修改，
// 显式声明 Sendable 以通过 Swift 6 严格并发检查。
extension JSON: @retroactive @unchecked Sendable {}
