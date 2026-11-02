import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    /// 上次已处理(或已提示)的剪贴板内容,避免重复识别/跳转
    private var lastClipboardChangeCount = -1
    private var clipboardObserver: NSObjectProtocol?
    private var isCheckingClipboard = false

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        Theme.configureGlobalAppearance()
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = RootTabBarController()
        window.overrideUserInterfaceStyle = AppSettings.appearanceMode.interfaceStyle
        window.makeKeyAndVisible()
        self.window = window
        // 冷启动深链
        if !connectionOptions.urlContexts.isEmpty {
            handleURLContexts(connectionOptions.urlContexts)
        }
        // 冷启动以当前剪贴板为基线:只有之后新复制的内容才自动跳转
        lastClipboardChangeCount = UIPasteboard.general.changeCount
        observeClipboard()
    }

    private func observeClipboard() {
        clipboardObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // didBecomeActive 在主线程发送
            MainActor.assumeIsolated {
                self?.checkClipboardForLink()
            }
        }
    }

    /// 回到前台时识别剪贴板里的论坛链接并自动打开对应主题。
    ///
    /// 两段式,尽量不打扰用户:
    /// 1) `detectedPatterns` 只探测「是否含链接」这类元数据,不读取内容、不触发粘贴授权;
    /// 2) 确认是链接后才 `detectedValues` 取文本 —— 只有这一步才可能弹出系统授权。
    /// 同一份剪贴板内容只尝试一次,用户拒绝授权后不会反复弹窗。
    @MainActor
    private func checkClipboardForLink() {
        guard AppSettings.clipboardLinkEnabled, #available(iOS 16.0, *) else { return }
        let changeCount = UIPasteboard.general.changeCount
        guard changeCount != lastClipboardChangeCount, !isCheckingClipboard else { return }
        isCheckingClipboard = true
        Task { [weak self] in
            defer { self?.isCheckingClipboard = false }
            guard let self else { return }
            // 第一段:只做元数据探测,不读取具体内容
            guard let patterns = try? await UIPasteboard.general.detectedPatterns(for: [\.probableWebURL]),
                  patterns.contains(\.probableWebURL) else { return }
            // 内容含链接:标记为已处理,后续同一内容不再重复读取(无论授权是否被拒)
            self.lastClipboardChangeCount = changeCount
            // 第二段:读取链接文本(app 自身写入的剪贴板或已授权时静默完成)
            guard let detected = try? await UIPasteboard.general.detectedValues(for: [\.probableWebURL]),
                  let url = LinkRouter.parseClipboardURL(detected.probableWebURL),
                  let top = self.window?.rootViewController?.topMostViewController else { return }
            LinkRouter.openFromClipboard(url, from: top)
        }
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // 进入后台时记录剪贴板基线:之后用户新复制的内容才需要自动跳转
        lastClipboardChangeCount = UIPasteboard.general.changeCount
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        handleURLContexts(URLContexts)
    }

    /// s1gugu://thread/123?page=2 | s1gugu://forum/87
    private func handleURLContexts(_ contexts: Set<UIOpenURLContext>) {
        guard let url = contexts.first?.url, url.scheme == "s1gugu" else { return }
        guard let tabBarController = window?.rootViewController as? UITabBarController else { return }
        tabBarController.selectedIndex = 0
        guard let navigation = (tabBarController.selectedViewController as? UINavigationController) else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        switch url.host ?? "" {
        case "thread":
            let tidString = url.pathComponents.last ?? query["tid"] ?? ""
            guard let tid = Int(tidString), tid > 0 else { return }
            let page = Int(query["page"] ?? "")
            let controller = PostListViewController(threadId: tid, threadTitle: "主题 #\(tid)", jumpPage: page)
            navigation.pushViewController(controller, animated: true)
        case "forum":
            let fidString = url.pathComponents.last ?? query["fid"] ?? ""
            guard let fid = Int(fidString), fid > 0 else { return }
            navigation.pushViewController(
                ThreadListViewController(forum: Forum(fid: String(fid), name: "版块 \(fid)")),
                animated: true
            )
        default:
            break
        }
    }
}
