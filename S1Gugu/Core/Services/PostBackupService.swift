import Foundation
import SwiftyJSON

/// 帖子离线备份:整帖各页原始 postlist JSON 存 SQLiteData,离线时重跑渲染管线。
enum PostBackupService {

    struct Page: Codable, Sendable {
        let page: Int
        /// 该页 postlist 数组的原始 JSON 字符串
        let raw: String
    }

    struct Payload: Codable, Sendable {
        var subject: String
        var pages: [Page]
    }

    struct OfflinePage: Sendable {
        let page: Int
        let posts: [RawPost]
    }

    // MARK: - 查询

    static func entry(threadId: Int) async -> PostBackupEntry? {
        try? await AppDatabase.shared.read { database in
            try PostBackupEntry.find(threadId).fetchOne(database)
        }
    }

    static func entries() async -> [PostBackupEntry] {
        (try? await AppDatabase.shared.read { database in
            try PostBackupEntry.order { $0.timestamp.desc() }.fetchAll(database)
        }) ?? []
    }

    // MARK: - 保存(整帖)

    /// 抓取全部页并存档。onProgress 回传 (已完成页, 总页数)。
    static func backupWholeThread(
        threadId: Int,
        pageCount: Int,
        onProgress: @escaping @MainActor (Int, Int, String) -> Void
    ) async throws {
        var pages: [Page] = []
        var subject = ""
        let total = max(pageCount, 1)
        for page in 1...total {
            let result = try await DiscuzAPI.shared.posts(tid: threadId, page: page)
            if subject.isEmpty { subject = result.thread?.subject ?? "" }
            guard let raw = result.rawPageJSON else {
                throw APIError.server("第 \(page) 页数据异常")
            }
            pages.append(Page(page: page, raw: raw))
            let subjectNow = subject
            await MainActor.run { onProgress(page, total, subjectNow) }
            // 轻微间隔,避免对服务器连发
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        let payload = Payload(subject: subject, pages: pages)
        let data = try JSONEncoder().encode(payload)
        let title = subject.isEmpty ? (await HistoryService.title(of: threadId)) ?? "" : subject
        _ = try? await AppDatabase.shared.write { database in
            try PostBackupEntry.upsert {
                PostBackupEntry(
                    threadId: threadId,
                    title: title,
                    pageCount: total,
                    payload: String(data: data, encoding: .utf8) ?? "",
                    timestamp: Int(Date().timeIntervalSince1970)
                )
            }.execute(database)
        }
    }

    // MARK: - 离线读取

    static func offlinePages(threadId: Int) async -> (subject: String, pages: [OfflinePage])? {
        guard let entry = await entry(threadId: threadId),
              let data = entry.payload.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { return nil }
        let pages = payload.pages
            .sorted { $0.page < $1.page }
            .compactMap { page -> OfflinePage? in
                guard let jsonData = page.raw.data(using: .utf8),
                      let json = try? JSON(data: jsonData)
                else { return nil }
                let posts = json.arrayValue.map { RawPost(json: $0) }
                return OfflinePage(page: page.page, posts: posts)
            }
        return (payload.subject, pages)
    }

    // MARK: - 删除

    static func remove(threadId: Int) async {
        _ = try? await AppDatabase.shared.write { database in
            try PostBackupEntry.find(threadId).delete().execute(database)
        }
    }
}
