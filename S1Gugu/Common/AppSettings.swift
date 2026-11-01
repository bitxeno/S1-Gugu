import Foundation
import UIKit

/// 外观模式
enum AppearanceMode: String {
    case system
    case light
    case dark

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

/// 列表主题配色。「默认」为 iOS 原生观感;「奶黄」复刻自 S1-Next 的午后红茶主题。
enum ThemeVariant: String {
    case `default`
    case custard

    var displayName: String {
        switch self {
        case .default: return "默认"
        case .custard: return "奶黄"
        }
    }
}

/// UserDefaults 设置项(见 docs/04-数据模型.md §3)
enum AppSettings {

    private static var defaults: UserDefaults { UserDefaults.standard }
    private static let wifiOnlyImagesKey = "wifiOnlyImages"
    private static let autoSaveProgressKey = "autoSaveProgress"
    private static let autoRestoreProgressKey = "autoRestoreProgress"
    private static let customHostEnabledKey = "customHostEnabled"
    private static let customHostKey = "customHost"
    private static let fontScaleKey = "fontScale"

    static func registerDefaults() {
        defaults.register(defaults: [
            wifiOnlyImagesKey: false,
            autoSaveProgressKey: true,
            autoRestoreProgressKey: true,
        ])
    }

    /// 仅 Wi-Fi 加载帖子大图(头像不受限)
    static var wifiOnlyImages: Bool {
        get { defaults.bool(forKey: wifiOnlyImagesKey) }
        set { defaults.set(newValue, forKey: wifiOnlyImagesKey) }
    }

    static var autoSaveProgress: Bool {
        get { defaults.bool(forKey: autoSaveProgressKey) }
        set { defaults.set(newValue, forKey: autoSaveProgressKey) }
    }

    static var autoRestoreProgress: Bool {
        get { defaults.bool(forKey: autoRestoreProgressKey) }
        set { defaults.set(newValue, forKey: autoRestoreProgressKey) }
    }

    // MARK: M3 网络/显示

    static var customHostEnabled: Bool {
        get { defaults.bool(forKey: customHostEnabledKey) }
        set { defaults.set(newValue, forKey: customHostEnabledKey) }
    }

    /// 形如 "https://www.saraba1st.com/2b/"(含路径)
    static var customHost: String {
        get { defaults.string(forKey: customHostKey) ?? "" }
        set { defaults.set(newValue, forKey: customHostKey) }
    }

    /// 帖子正文字号缩放
    static var fontScale: Double {
        get { defaults.object(forKey: fontScaleKey) == nil ? 1.0 : defaults.double(forKey: fontScaleKey) }
        set { defaults.set(newValue, forKey: fontScaleKey) }
    }

    /// 外观模式(跟随系统 / 浅色 / 深色)
    static var appearanceMode: AppearanceMode {
        get {
            AppearanceMode(rawValue: defaults.string(forKey: "appearanceMode") ?? "") ?? .system
        }
        set { defaults.set(newValue.rawValue, forKey: "appearanceMode") }
    }

    /// 浅色主题,默认「奶黄」
    static var lightTheme: ThemeVariant {
        get { ThemeVariant(rawValue: defaults.string(forKey: "lightTheme") ?? "") ?? .custard }
        set { defaults.set(newValue.rawValue, forKey: "lightTheme") }
    }

    /// 深色主题,目前仅「默认」,后续扩展其它深色配色
    static var darkTheme: ThemeVariant {
        get { ThemeVariant(rawValue: defaults.string(forKey: "darkTheme") ?? "") ?? .default }
        set { defaults.set(newValue.rawValue, forKey: "darkTheme") }
    }

    /// 楼层快速侧边条(帖子详情右侧字母条),默认关闭
    static var quickSideBarEnabled: Bool {
        get { defaults.bool(forKey: "quickSideBarEnabled") }
        set { defaults.set(newValue, forKey: "quickSideBarEnabled") }
    }

    /// 每日签到入口开关。服务端 web 打卡插件已下线,App 后端通道保留;
    /// 恢复上线时改回 true 即可。
    static let signInEnabled = false

    /// 实际使用的 Base URL(自定义 host 开启且合法时生效)
    static var effectiveBaseURL: URL {
        let fallback = URL(string: "https://stage1st.com/2b/")!
        guard customHostEnabled else { return fallback }
        var host = customHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return fallback }
        if !host.hasPrefix("http") { host = "https://\(host)" }
        if !host.hasSuffix("/") { host += "/" }
        return URL(string: host) ?? fallback
    }
}
