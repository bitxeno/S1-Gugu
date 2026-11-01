import UIKit

/// 全局视觉常量。
///
/// 主题由设置选择:浅色默认「奶黄」(复刻 S1-Next 的午后红茶主题:米白页面底 +
/// 奶茶色 chrome + light blue accent),可切回「默认」的 iOS 原生观感;深色目前
/// 仅「默认」,预留后续扩展。页面底色一律走 Theme.background / Theme.contentBackground,
/// 文字走 Theme.label / Theme.secondaryLabel / Theme.tertiaryLabel,
/// 不要直接用 .systemGroupedBackground / .systemBackground / .label 系。
enum Theme {

    /// accent 随主题:奶黄浅色用 light blue A400,默认走 Asset Catalog(含深色变体)
    static var accent: UIColor {
        UIColor { trait in
            if trait.userInterfaceStyle != .dark, AppSettings.lightTheme == .custard {
                return UIColor(hex: 0x00B0FF)
            }
            return (UIColor(named: "Accent") ?? .systemBlue).resolvedColor(with: trait)
        }
    }

    /// 按明暗与主题设置解析:「默认」走系统语义色;奶黄只定义浅色,
    /// 深色目前仅「默认」,后续加深色主题时在此扩展
    private static func resolved(
        light systemLight: UIColor,
        dark systemDark: UIColor,
        custardLight: UIColor
    ) -> UIColor {
        UIColor { trait in
            let isDark = trait.userInterfaceStyle == .dark
            if !isDark, AppSettings.lightTheme == .custard { return custardLight }
            return (isDark ? systemDark : systemLight).resolvedColor(with: trait)
        }
    }

    /// 页面底色(分组列表)
    static var background: UIColor {
        resolved(
            light: .systemGroupedBackground,
            dark: .systemGroupedBackground,
            custardLight: UIColor(hex: 0xF6F7EB)
        )
    }

    /// 内容页底色(帖子/登录/编辑器)
    static var contentBackground: UIColor {
        resolved(
            light: .systemBackground,
            dark: .systemBackground,
            custardLight: UIColor(hex: 0xF6F7EB)
        )
    }

    /// 导航栏:奶黄为奶茶色(saraba_primary)
    static var navigationBarBackground: UIColor {
        resolved(
            light: .systemBackground,
            dark: .systemBackground,
            custardLight: UIColor(hex: 0xD8D8A8)
        )
    }

    /// 标签栏:奶黄为深奶茶(saraba_primary_dark)
    static var tabBarBackground: UIColor {
        resolved(
            light: .systemBackground,
            dark: .systemBackground,
            custardLight: UIColor(hex: 0x999972)
        )
    }

    /// 彩色栏上的前景(标题/栏按钮):奶黄浅色为深灰,其余跟随系统
    static var barForeground: UIColor {
        resolved(
            light: .label,
            dark: .label,
            custardLight: UIColor(hex: 0x333333)
        )
    }

    /// 标签栏选中项:奶黄浅色为白(深奶茶底),其余用 accent
    static var tabBarSelected: UIColor {
        resolved(light: accent, dark: accent, custardLight: .white)
    }

    /// 标签栏未选中项:奶黄浅色为半透明白,其余跟随系统
    static var tabBarUnselected: UIColor {
        resolved(
            light: .secondaryLabel,
            dark: .secondaryLabel,
            custardLight: UIColor.white.withAlphaComponent(0.55)
        )
    }

    /// 主文字:奶黄浅色 = 黑 87%(Android 框架默认,实测渲染约 #202020 暖黑)
    static var label: UIColor {
        resolved(light: .label, dark: .label, custardLight: UIColor.black.withAlphaComponent(0.87))
    }

    /// 次文字:奶黄浅色 = 黑 54%
    static var secondaryLabel: UIColor {
        resolved(
            light: .secondaryLabel,
            dark: .secondaryLabel,
            custardLight: UIColor.black.withAlphaComponent(0.54)
        )
    }

    /// 提示文字:奶黄浅色 = grey_500(S1-Next textColorHint)
    static var tertiaryLabel: UIColor {
        resolved(
            light: .tertiaryLabel,
            dark: .tertiaryLabel,
            custardLight: UIColor(hex: 0x9E9E9E)
        )
    }

    /// 列表 cell 底色:奶黄为扁平米白(与页面同色),「默认」与深色为系统卡片色
    static var listCellBackground: UIColor {
        UIColor { trait in
            if trait.userInterfaceStyle != .dark, AppSettings.lightTheme == .custard {
                return UIColor(hex: 0xF6F7EB)
            }
            return UIColor.secondarySystemGroupedBackground.resolvedColor(with: trait)
        }
    }

    /// 全局外观装配,SceneDelegate 建窗前调用一次;主题切换后由 applyThemeChange 重新调用
    @MainActor
    static func configureGlobalAppearance() {
        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = navigationBarBackground
        navigation.titleTextAttributes = [.foregroundColor: barForeground]
        navigation.largeTitleTextAttributes = [.foregroundColor: barForeground]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation
        UINavigationBar.appearance().tintColor = barForeground

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = tabBarBackground
        tab.stackedLayoutAppearance.selected.iconColor = tabBarSelected
        tab.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: tabBarSelected]
        tab.stackedLayoutAppearance.normal.iconColor = tabBarUnselected
        tab.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: tabBarUnselected]
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        // S1-Next 开关用 accent 色,不用系统绿
        UISwitch.appearance().onTintColor = accent
    }

    /// 主题选择变更后应用:重新装配外观代理并重建各窗口根控制器(导航栈会复位)
    @MainActor
    static func applyThemeChange() {
        configureGlobalAppearance()
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where window.rootViewController is RootTabBarController {
                window.rootViewController = RootTabBarController()
            }
        }
    }

    static let cardCornerRadius: CGFloat = 10
    static let contentInset: CGFloat = 16
}

// MARK: - 扁平列表 cell

/// 奶黄主题的扁平列表:cell 底色与页面同色(卡片色 = 背景色),仅靠分隔线分区,
/// 对齐 S1-Next 的 cardViewBackground = saraba_background;「默认」主题回落系统卡片色。
/// 用 listGroupedCell 预设保留系统选中高亮。
extension UITableViewCell {
    func applyFlatListBackground(color: UIColor = Theme.listCellBackground) {
        var background = UIBackgroundConfiguration.listGroupedCell()
        background.backgroundColor = color
        backgroundConfiguration = background
    }
}

extension UICollectionViewListCell {
    func applyFlatListBackground(color: UIColor = Theme.listCellBackground) {
        var background = UIBackgroundConfiguration.listGroupedCell()
        background.backgroundColor = color
        backgroundConfiguration = background
    }
}
