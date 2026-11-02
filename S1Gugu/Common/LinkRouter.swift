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

    /// 剪贴板自动跳转:回到 Tab 首页后再打开目标页面,
    /// 避免在已有多层页面上继续叠加导航栈。
    static func openFromClipboard(_ url: URL, from viewController: UIViewController) {
        guard let thread = parseThread(url) else {
            handle(url, from: viewController)
            return
        }
        let navigation = viewController.navigationController
        navigation?.popToRootViewController(animated: false)
        let controller = PostListViewController(threadId: thread.tid, threadTitle: "主题 #\(thread.tid)", jumpPage: thread.page)
        navigation?.pushViewController(controller, animated: true)
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

    /// 剪贴板文本 → 可进 App 的站内 URL。
    ///
    /// 兼容复制来的裸链接(无 http:// 前缀),例如
    /// `stage1st.com/2b/thread-2293055-1-1.html`。
    static func parseClipboardURL(_ raw: String) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let candidate: URL?
        if let url = URL(string: text), url.scheme != nil {
            candidate = url
        } else if let url = URL(string: "https://\(text)") {
            candidate = url
        } else {
            candidate = nil
        }
        guard let url = candidate, let host = url.host, isForumHost(host) else { return nil }
        // 只接管能落到具体页面的链接,其余交给系统或 Safari 处理
        guard parseThread(url) != nil || parseForum(url) != nil else { return nil }
        return url
    }

    static func threadURL(tid: Int, page: Int) -> URL {
        URL(string: "https://stage1st.com/2b/thread-\(tid)-\(max(page, 1))-1.html")!
    }
}

extension UIViewController {
    /// 当前最顶层的可见控制器(含 presented / 导航 / Tab 容器展开)
    var topMostViewController: UIViewController {
        if let presented = presentedViewController {
            return presented.topMostViewController
        }
        if let navigation = self as? UINavigationController {
            return (navigation.visibleViewController ?? navigation).topMostViewController
        }
        if let tab = self as? UITabBarController {
            return (tab.selectedViewController ?? tab).topMostViewController
        }
        return self
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
