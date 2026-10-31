import Foundation
import Network
import SafariServices
import UIKit

/// 站内链接进 App,站外链接用 Safari 场内打开。
@MainActor
enum LinkRouter {

    static func handle(_ url: URL, from viewController: UIViewController) {
        if let thread = parseThread(url) {
            let controller = PostListViewController(threadId: thread.tid, threadTitle: "主题 #\(thread.tid)", jumpPage: thread.page)
            viewController.navigationController?.pushViewController(controller, animated: true)
            return
        }
        if let forum = parseForum(url) {
            let controller = ThreadListViewController(forum: Forum(fid: String(forum.fid), name: "版块 \(forum.fid)"))
            viewController.navigationController?.pushViewController(controller, animated: true)
            return
        }
        let safari = SFSafariViewController(url: url)
        viewController.present(safari, animated: true)
    }

    struct ThreadTarget: Equatable {
        let tid: Int
        let page: Int?
    }

    struct ForumTarget: Equatable {
        let fid: Int
    }

    /// thread-123456-2-1.html
    static func parseThread(_ url: URL) -> ThreadTarget? {
        guard let host = url.host, isForumHost(host) else { return nil }
        if let match = url.path.firstMatch(of: /thread-(\d+)(?:-(\d+))?/) {
            let tid = Int(String(match.1)) ?? 0
            guard tid > 0 else { return nil }
            let page = match.2.flatMap { Int(String($0)) }
            return ThreadTarget(tid: tid, page: page)
        }
        if url.path.contains("forum.php"), let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            if query["mod"] == "viewthread", let tid = Int(query["tid"] ?? "") {
                let page = Int(query["page"] ?? "")
                return ThreadTarget(tid: tid, page: page)
            }
        }
        return nil
    }

    /// forum-12-1.html
    static func parseForum(_ url: URL) -> ForumTarget? {
        guard let host = url.host, isForumHost(host) else { return nil }
        if let match = url.path.firstMatch(of: /forum-(\d+)(?:-\d+)?\.html/) {
            let fid = Int(String(match.1)) ?? 0
            return fid > 0 ? ForumTarget(fid: fid) : nil
        }
        if url.path.contains("forum.php"), let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            if query["mod"] == "forumdisplay", let fid = Int(query["fid"] ?? "") {
                return ForumTarget(fid: fid)
            }
        }
        return nil
    }

    static func isForumHost(_ host: String) -> Bool {
        let hosts = ["stage1st.com", "saraba1st.com"]
        return hosts.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    static func threadURL(tid: Int, page: Int) -> URL {
        URL(string: "https://stage1st.com/2b/thread-\(tid)-\(max(page, 1))-1.html")!
    }
}

/// Wi-Fi 判定(wifiOnlyImages 设置用)
final class NetworkMonitor: @unchecked Sendable {

    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var _isExpensive = true

    var isExpensive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isExpensive
    }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self._isExpensive = path.isExpensive
            self.lock.unlock()
        }
        monitor.start(queue: DispatchQueue(label: "app.bitxeno.s1gugu.network-monitor"))
    }
}
