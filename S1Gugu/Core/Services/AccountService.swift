import Foundation
import OSLog

/// 多账号管理:元数据在 SQLiteData `accounts` 表,凭据在 Keychain(按用户名索引)。
/// 「当前账号」仍存 Keychain `primary` 槽位(SessionStore 兼容不变)。
@MainActor
final class AccountService {

    static let shared = AccountService()

    private init() {}

    // MARK: - 查询

    func list() async -> [AccountEntry] {
        (try? await AppDatabase.shared.read { database in
            try AccountEntry.order { $0.lastUsedAt.desc() }.fetchAll(database)
        }) ?? []
    }

    // MARK: - 登录后登记

    func upsertAfterLogin(uid: Int, name: String, password: String, questionId: Int, answer: String) async {
        guard !name.isEmpty else { return }
        try? KeychainStore.save(
            KeychainStore.Credentials(uid: uid, name: name, password: password, questionId: questionId, answer: answer),
            forUser: name
        )
        _ = try? await AppDatabase.shared.write { database in
            let existing = try AccountEntry.where { $0.name.eq(name) }.fetchOne(database)
            if var entry = existing {
                entry.uid = uid
                entry.lastUsedAt = Int(Date().timeIntervalSince1970)
                try AccountEntry.update(entry).execute(database)
            } else {
                try AccountEntry.insert {
                    AccountEntry.Draft(uid: uid, name: name, lastUsedAt: Int(Date().timeIntervalSince1970))
                }.execute(database)
            }
        }
    }

    // MARK: - 切换

    /// 切换到指定账号:加载凭据 → 重建 cookie 会话 → 写入当前槽位
    func switchTo(name: String) async throws {
        guard let credentials = KeychainStore.load(forUser: name) else {
            throw APIError.server("账号 \(name) 的凭据缺失,请重新登录该账号")
        }
        // 新会话:清旧 cookie 与 App 后端 sid
        SessionStore.shared.resetSession()
        try await DiscuzAPI.shared.performLogin(
            username: credentials.name,
            password: credentials.password,
            questionId: credentials.questionId,
            answer: credentials.answer
        )
        try await DiscuzAPI.shared.refreshFormhash()
        // 写入当前槽位与账号表
        try? KeychainStore.save(credentials)
        await upsertAfterLogin(
            uid: credentials.uid,
            name: credentials.name,
            password: credentials.password,
            questionId: credentials.questionId,
            answer: credentials.answer
        )
        NetworkLog.session.info("已切换账号 \\(name, privacy: .public)")
    }

    // MARK: - 删除

    func remove(name: String) async {
        KeychainStore.delete(forUser: name)
        _ = try? await AppDatabase.shared.write { database in
            try AccountEntry.where { $0.name.eq(name) }.delete().execute(database)
        }
    }
}
