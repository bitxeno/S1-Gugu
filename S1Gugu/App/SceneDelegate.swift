import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = RootTabBarController()
        window.overrideUserInterfaceStyle = AppSettings.appearanceMode.interfaceStyle
        window.makeKeyAndVisible()
        self.window = window
        // 冷启动深链
        if !connectionOptions.urlContexts.isEmpty {
            handleURLContexts(connectionOptions.urlContexts)
        }
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
