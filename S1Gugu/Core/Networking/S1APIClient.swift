import Foundation
import OSLog

/// Stage1st 论坛底层 HTTP 客户端。
/// 登录态完全依赖系统 `HTTPCookieStorage.shared`(Discuz `_saltkey`/`_auth` cookie 自动持久化)。
final class S1APIClient: Sendable {

    static let shared = S1APIClient()

    var baseURL: URL { AppSettings.effectiveBaseURL }
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 90
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        self.session = URLSession(configuration: configuration)
    }

    func get(path: String, query: [String: String] = [:]) async throws -> Data {
        try await request(buildURL(path: path, query: query), method: "GET", form: nil)
    }

    func postForm(path: String, query: [String: String] = [:], form: [String: String]) async throws -> Data {
        try await request(buildURL(path: path, query: query), method: "POST", form: form.map { ($0.key, $0.value) })
    }

    /// 支持重复 key 的表单(如投票 pollanswers[])
    func postFormPairs(path: String, query: [String: String], form: [(String, String)]) async throws -> Data {
        try await request(buildURL(path: path, query: query), method: "POST", form: form)
    }

    /// 直接向完整 URL 提交表单(web 表单通道,action 可能指向 forum.php 各变体)
    func postFormToURL(url: URL, form: [String: String]) async throws -> Data {
        try await request(url, method: "POST", form: form.map { ($0.key, $0.value) })
    }

    /// 直接 GET 完整 URL(HTML 页面:搜索翻页等)
    func getToURL(url: URL) async throws -> Data {
        try await request(url, method: "GET", form: nil)
    }

    /// multipart/form-data(swfupload 附件上传)
    func postMultipart(
        url: URL,
        fields: [String: String],
        fileFieldName: String,
        fileName: String,
        mimeType: String,
        fileData: Data
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let boundary = "s1gugu-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(url.host ?? "stage1st.com", forHTTPHeaderField: "Origin")
        request.setValue(url.absoluteString, forHTTPHeaderField: "Referer")

        var body = Data()
        func appendLine(_ string: String) {
            body.append(Data(string.utf8))
            body.append(Data("\r\n".utf8))
        }
        for (key, value) in fields.sorted(by: { $0.key < $1.key }).map({ ($0.key, $0.value) }) {
            appendLine("--\(boundary)")
            appendLine("Content-Disposition: form-data; name=\"\(key)\"")
            appendLine("")
            appendLine(value)
        }
        appendLine("--\(boundary)")
        appendLine("Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(fileName)\"")
        appendLine("Content-Type: \(mimeType)")
        appendLine("")
        body.append(fileData)
        appendLine("")
        appendLine("--\(boundary)--")
        request.httpBody = body

        NetworkLog.net.debug("MULTIPART \(url.absoluteString, privacy: .public)")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                throw APIError.server("HTTP \(http.statusCode)")
            }
            return data
        } catch let error as APIError {
            throw error
        } catch let error as URLError {
            throw APIError.network(error)
        } catch {
            throw APIError.invalidResponse
        }
    }

    // MARK: - Private

    private func buildURL(path: String, query: [String: String]) throws -> URL {
        guard var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidResponse
        }
        // Discuz 移动 API 缺 version 参数时会在 JSON 前输出 PHP Warning,统一补齐(对齐 S1-Next ApiVersionInterceptor)
        // 仅移动 API 需要;forum.php/plugin.php 等网页通道带了反而走错插件路由
        var effectiveQuery = query
        if path.contains("api/mobile/index.php"), effectiveQuery["version"] == nil {
            effectiveQuery["version"] = "1"
        }
        components.queryItems = effectiveQuery
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw APIError.invalidResponse }
        return url
    }

    private func request(_ url: URL, method: String, form: [(String, String)]?) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let form {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var parts: [String] = []
            for entry in form {
                let key: String = entry.0.addingPercentEncoding(withAllowedCharacters: .formURLEncoded) ?? entry.0
                let value: String = entry.1.addingPercentEncoding(withAllowedCharacters: .formURLEncoded) ?? entry.1
                parts.append("\(key)=\(value)")
            }
            let body: String = parts.joined(separator: "&")
            request.httpBody = body.data(using: .utf8)
        }

        NetworkLog.net.debug("\(method, privacy: .public) \(url.absoluteString, privacy: .public)")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                throw APIError.server("HTTP \(http.statusCode)")
            }
            return data
        } catch let error as APIError {
            throw error
        } catch let error as URLError {
            throw APIError.network(error)
        } catch {
            throw APIError.invalidResponse
        }
    }
}

extension CharacterSet {
    /// application/x-www-form-urlencoded(RFC 3986,空格转 %20)
    static let formURLEncoded: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}

// MARK: - 图片请求头

import Kingfisher
import OSLog

private let imageRequestLogger = Logger(subsystem: "app.bitxeno.s1gugu", category: "image")

/// S1 图床/附件图对站外直链有校验:图片请求统一携带站内 Referer,
/// 并手动补上论坛域的登录 Cookie——图床(img.stage1st.com)与论坛
/// (www.saraba1st.com)不同域,HTTPCookieStorage 按域匹配不会自动携带,
/// 不带 Cookie 附件图一律 403。全局经 Kingfisher defaultOptions 生效。
struct S1ImageRequestModifier: ImageDownloadRequestModifier {

    private static let forumURL = URL(string: "https://www.saraba1st.com/2b/")

    private static func cookieHeader(for requestURL: URL?) -> String {
        let storage = HTTPCookieStorage.shared
        var cookies: [HTTPCookie] = []
        if let requestURL {
            cookies += storage.cookies(for: requestURL) ?? []
        }
        if let forumURL {
            cookies += storage.cookies(for: forumURL) ?? []
        }
        var seen = Set<String>()
        var parts: [String] = []
        for cookie in cookies where seen.insert(cookie.name).inserted {
            parts.append("\(cookie.name)=\(cookie.value ?? "")")
        }
        return parts.joined(separator: "; ")
    }

    func modified(for request: URLRequest) -> URLRequest? {
        var request = request
        request.setValue("https://www.saraba1st.com/2b/", forHTTPHeaderField: "Referer")
        let header = Self.cookieHeader(for: request.url)
        if !header.isEmpty {
            request.setValue(header, forHTTPHeaderField: "Cookie")
        }
        return request
    }
}
