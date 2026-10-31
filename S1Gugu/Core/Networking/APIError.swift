import Foundation

enum APIError: Error, LocalizedError, Sendable {
    /// 顶层 `error` 字段
    case server(String)
    /// `Message.messageval` 非成功后缀,取 messagestr
    case actionFailed(String)
    case needLogin
    case authenticityTokenMissing
    case invalidResponse
    case decoding(String)
    case network(URLError)

    var errorDescription: String? {
        switch self {
        case let .server(message):
            return message.isEmpty ? "服务器返回错误" : message
        case let .actionFailed(message):
            return message
        case .needLogin:
            return "请先登录"
        case .authenticityTokenMissing:
            return "会话校验失败,请重新进入页面"
        case .invalidResponse:
            return "服务器响应格式异常"
        case let .decoding(detail):
            return "数据解析失败:\(detail)"
        case let .network(error):
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "网络不可用,请检查网络连接"
            case .timedOut:
                return "连接超时,请稍后重试"
            default:
                return "网络请求失败(\(error.code.rawValue))"
            }
        }
    }
}
