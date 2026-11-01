import UIKit
import WebKit
import SnapKit

/// WebView 兜底登录:验证码等移动 API 无法处理的场景。
/// 加载论坛页面,检测到 `<前缀>_auth` cookie 后同步到系统 CookieStorage。
@MainActor
final class WebLoginViewController: UIViewController {

    private var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.contentBackground
        navigationItem.title = "网页登录"

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        view.addSubview(webView)
        webView.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }

        let url = URL(string: "https://stage1st.com/2b/forum-27-1.html")!
        webView.load(URLRequest(url: url))
    }

    private func checkLoginCookies() {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            Task { @MainActor in
                guard let self else { return }
                let authCookies = cookies.filter { $0.name.hasSuffix("_auth") }
                guard !authCookies.isEmpty else { return }
                // 同步全部 cookie 到系统存储(会话从此由 URLSession 携带)
                let storage = HTTPCookieStorage.shared
                for cookie in cookies where cookie.domain.contains("stage1st") || cookie.domain.contains("saraba1st") {
                    storage.setCookie(cookie)
                }
                Toast.show("网页登录成功", in: self.view)
                NotificationCenter.default.post(name: SessionStore.didChangeNotification, object: nil)
                self.dismiss(animated: true)
            }
        }
    }
}

extension WebLoginViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        checkLoginCookies()
    }
}
