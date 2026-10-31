import Foundation
import OSLog

/// 登录态与 formhash。每次 API 响应都会 ingest;uid 变为 0 视为掉线。
@MainActor
final class SessionStore {

    static let shared = SessionStore()

    static let didChangeNotification = Notification.Name("app.bitxeno.s1gugu.sessionDidChange")

    struct State: Equatable, Sendable {
        var uid: Int?
        var name: String?
        var formhash: String?
        var isLoggedIn: Bool { uid != nil && uid != 0 }
    }

    private(set) var state = State()

    /// App 后端会话令牌(签到等),失效时用 Keychain 凭据自动重取
    private var appSid: String?

    private init() {
        // 冷启动先以 Keychain 凭据占位:cookie 若仍有效,首个响应会确认 uid
        if let credentials = KeychainStore.load() {
            state.uid = credentials.uid
            state.name = credentials.name
        }
    }

    func ingest(memberUid: String?, memberUsername: String?, formhash: String?) {
        var changed = false
        if let uidString = memberUid, !uidString.isEmpty {
            let uid = Int(uidString) ?? 0
            let newUID: Int? = uid == 0 ? nil : uid
            if newUID != state.uid {
                state.uid = newUID
                changed = true
                if newUID == nil { state.name = nil }
            }
            if let username = memberUsername, !username.isEmpty, username != state.name {
                state.name = username
                changed = true
            }
        }
        if let fresh = formhash, !fresh.isEmpty, fresh != state.formhash {
            state.formhash = fresh
            changed = true
        }
        if changed {
            let loggedUID = state.uid ?? -1
            let loggedName = state.name ?? "-"
            NetworkLog.session.info("会话变化 uid=\(loggedUID) name=\(loggedName, privacy: .public)")
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    /// 写操作前取 formhash;缺失则自动请求 toplist 刷新。
    func requireFormhash() async throws -> String {
        if let formhash = state.formhash, !formhash.isEmpty { return formhash }
        try await DiscuzAPI.shared.refreshFormhash()
        guard let formhash = state.formhash, !formhash.isEmpty else {
            throw APIError.authenticityTokenMissing
        }
        return formhash
    }

    /// 清空会话(cookie/sid/state),不删除 Keychain 凭据。多账号切换前置步骤。
    func resetSession() {
        clearCookies()
        appSid = nil
        state = State()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    /// 确保 App 后端 sid 可用(自动静默登录)
    func ensureAppSession(force: Bool = false) async throws -> String {
        if !force, let appSid, !appSid.isEmpty { return appSid }
        guard let credentials = KeychainStore.load() else {
            throw APIError.needLogin
        }
        let result = try await DiscuzAPI.shared.appLogin(
            username: credentials.name,
            password: credentials.password,
            questionId: credentials.questionId,
            answer: credentials.answer
        )
        appSid = result.sid
        return result.sid
    }

    func login(username: String, password: String, questionId: Int, answer: String) async throws {
        try await DiscuzAPI.shared.performLogin(
            username: username,
            password: password,
            questionId: questionId,
            answer: answer
        )
        try await DiscuzAPI.shared.refreshFormhash()
        // cookie 未生效(如需要验证码/安全提问不符)时给明确失败,而非假装成功
        guard state.isLoggedIn else {
            throw APIError.actionFailed("登录未生效,请检查账号信息或改用网页登录处理验证码")
        }
        let credentials = KeychainStore.Credentials(
            uid: state.uid ?? 0,
            name: state.name ?? username,
            password: password,
            questionId: questionId,
            answer: answer
        )
        try? KeychainStore.save(credentials)
        await AccountService.shared.upsertAfterLogin(
            uid: credentials.uid,
            name: credentials.name,
            password: password,
            questionId: questionId,
            answer: answer
        )
    }

    func logout() {
        clearCookies()
        state = State()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    /// 清除论坛域名的所有 cookie(saltkey/auth 等)
    private func clearCookies() {
        let storage = HTTPCookieStorage.shared
        let domains = ["stage1st.com", "saraba1st.com", "www.stage1st.com", "www.saraba1st.com", "bbs.saraba1st.com"]
        for domain in domains {
            if let cookies = storage.cookies(for: URL(string: "https://\(domain)/2b/")!) {
                cookies.forEach(storage.deleteCookie)
            }
        }
        for cookie in storage.cookies ?? [] where domains.contains(where: { cookie.domain.hasSuffix($0) }) {
            storage.deleteCookie(cookie)
        }
    }
}
