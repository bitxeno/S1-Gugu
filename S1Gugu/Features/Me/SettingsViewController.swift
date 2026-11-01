import UIKit
import Kingfisher
import SnapKit

/// 基础设置(M1):图片策略、阅读进度、关于。
@MainActor
final class SettingsViewController: UIViewController {

    private enum Section: Int, CaseIterable { case image, read, display, network, about }
    private enum Row: Int { case wifiOnly, clearCache, autoSave, autoRestore, fontScale, customHostEnabled, customHost, version, license }

    private var tableView: UITableView!
    private var cachedImageSizeText = "计算中…"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationItem.title = "设置"
        tableView = UITableView(frame: view.bounds, style: .insetGrouped)
        tableView.backgroundColor = Theme.background
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "setting")
        view.addSubview(tableView)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshCacheSize()
    }

    private func showAppearancePicker() {
        let alert = UIAlertController(title: "外观", message: nil, preferredStyle: .actionSheet)
        for mode in [AppearanceMode.system, .light, .dark] {
            alert.addAction(UIAlertAction(title: mode.displayName, style: .default) { _ in
                AppSettings.appearanceMode = mode
                self.applyAppearanceToAllWindows()
                self.tableView.reloadData()
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = self.view
            popover.sourceRect = CGRect(x: self.view.bounds.midX, y: 150, width: 1, height: 1)
        }
        present(alert, animated: true)
    }

    /// 外观切换立即应用到所有已连接窗口
    private func applyAppearanceToAllWindows() {
        let style = AppSettings.appearanceMode.interfaceStyle
        for scene in UIApplication.shared.connectedScenes {
            (scene as? UIWindowScene)?.windows.forEach {
                $0.overrideUserInterfaceStyle = style
            }
        }
    }

    /// 浅色 / 深色主题选择(行点击与菜单按钮共用)
    private func showThemePicker(isLight: Bool) {
        let variants: [ThemeVariant] = isLight ? [.default, .custard] : [.default]
        let current = isLight ? AppSettings.lightTheme : AppSettings.darkTheme
        let alert = UIAlertController(
            title: isLight ? "浅色主题" : "深色主题",
            message: nil,
            preferredStyle: .actionSheet
        )
        for variant in variants {
            alert.addAction(UIAlertAction(title: variant.displayName, style: .default) { _ in
                guard variant != current else { return }
                if isLight {
                    AppSettings.lightTheme = variant
                } else {
                    AppSettings.darkTheme = variant
                }
                Theme.applyThemeChange()
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = self.view
            popover.sourceRect = CGRect(x: self.view.bounds.midX, y: 150, width: 1, height: 1)
        }
        present(alert, animated: true)
    }

    private func showCustomHostEditor() {
        let alert = UIAlertController(title: "备用域名", message: "例如 bbs.saraba1st.com/2b(可含 https:// 前缀)", preferredStyle: .alert)
        alert.addTextField { $0.text = AppSettings.customHost; $0.placeholder = "域名/2b" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { _ in
            AppSettings.customHost = alert.textFields?.first?.text ?? ""
            self.tableView.reloadData()
            Toast.show("已保存,下次请求生效", in: self.view ?? UIView())
        })
        present(alert, animated: true)
    }

    private func refreshCacheSize() {
        Task { [weak self] in
            let size = (try? await ImageCache.default.diskStorageSize) ?? 0
            guard let self else { return }
            self.cachedImageSizeText = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            self.tableView?.reloadData()
        }
    }

    private func toggleCell(_ cell: UITableViewCell, title: String, subtitle: String?, isOn: Bool, action: @escaping (Bool) -> Void) -> UITableViewCell {
        var config = cell.defaultContentConfiguration()
        config.text = title
        config.textProperties.font = .preferredFont(forTextStyle: .body)
        if let subtitle {
            config.secondaryText = subtitle
            config.secondaryTextProperties.font = .preferredFont(forTextStyle: .footnote)
            config.secondaryTextProperties.color = Theme.secondaryLabel
        }
        cell.contentConfiguration = config
        let toggle = UISwitch()
        toggle.isOn = isOn
        toggle.onTintColor = Theme.accent
        toggle.addAction(UIAction { handler in
            action((handler.sender as? UISwitch)?.isOn ?? false)
        }, for: .valueChanged)
        cell.accessoryView = toggle
        cell.accessoryType = .none
        return cell
    }
}

extension SettingsViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .image: return 2
        case .read: return 3
        case .display: return 4
        case .network: return 3
        default: return 2
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .image: return "图片"
        case .read: return "阅读"
        case .display: return "显示"
        case .network: return "网络"
        default: return "关于"
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "setting", for: indexPath)
        cell.applyFlatListBackground()
        cell.accessoryView = nil
        switch Section(rawValue: indexPath.section) {
        case .image:
            if indexPath.row == 0 {
                return toggleCell(
                    cell,
                    title: "仅 Wi-Fi 加载图片",
                    subtitle: "帖子大图在蜂窝网络下需手动点击加载",
                    isOn: AppSettings.wifiOnlyImages
                ) { AppSettings.wifiOnlyImages = $0 }
            }
            var config = cell.defaultContentConfiguration()
            config.text = "清除图片缓存"
            config.textProperties.font = .preferredFont(forTextStyle: .body)
            config.secondaryText = cachedImageSizeText
            config.secondaryTextProperties.color = Theme.secondaryLabel
            config.secondaryTextProperties.font = .preferredFont(forTextStyle: .footnote)
            cell.contentConfiguration = config
            cell.accessoryType = .none
            return cell
        case .read:
            switch indexPath.row {
            case 0:
                return toggleCell(cell, title: "自动保存阅读进度", subtitle: nil, isOn: AppSettings.autoSaveProgress) {
                    AppSettings.autoSaveProgress = $0
                }
            case 1:
                return toggleCell(cell, title: "自动恢复阅读进度", subtitle: nil, isOn: AppSettings.autoRestoreProgress) {
                    AppSettings.autoRestoreProgress = $0
                }
            default:
                return toggleCell(cell, title: "楼层快速侧边条", subtitle: "帖子右侧字母条,滑动快速跳转楼层", isOn: AppSettings.quickSideBarEnabled) {
                    AppSettings.quickSideBarEnabled = $0
                }
            }
        case .display:
            switch indexPath.row {
            case 0:
                var config = cell.defaultContentConfiguration()
                config.text = "外观"
                config.secondaryText = AppSettings.appearanceMode.displayName
                config.textProperties.font = .preferredFont(forTextStyle: .body)
                config.secondaryTextProperties.color = Theme.secondaryLabel
                cell.contentConfiguration = config
                cell.accessoryType = .none
                let menuButton = UIButton(type: .system)
                menuButton.setImage(UIImage(systemName: "chevron.up.chevron.down"), for: .normal)
                menuButton.showsMenuAsPrimaryAction = true
                menuButton.menu = UIMenu(children: [AppearanceMode.system, .light, .dark].map { mode in
                    UIAction(title: mode.displayName, state: mode == AppSettings.appearanceMode ? .on : .off) { _ in
                        AppSettings.appearanceMode = mode
                        self.applyAppearanceToAllWindows()
                        self.tableView.reloadData()
                    }
                })
                cell.accessoryView = menuButton
                cell.accessoryType = .none
                return cell
            case 1, 2:
                // 1 = 浅色主题(默认 / 奶黄,默认奶黄);2 = 深色主题(暂仅默认,预留扩展)
                let isLight = indexPath.row == 1
                let variants: [ThemeVariant] = isLight ? [.default, .custard] : [.default]
                let current = isLight ? AppSettings.lightTheme : AppSettings.darkTheme
                var config = cell.defaultContentConfiguration()
                config.text = isLight ? "浅色主题" : "深色主题"
                config.secondaryText = current.displayName
                config.textProperties.font = .preferredFont(forTextStyle: .body)
                config.secondaryTextProperties.color = Theme.secondaryLabel
                cell.contentConfiguration = config
                cell.accessoryType = .none
                let menuButton = UIButton(type: .system)
                menuButton.setImage(UIImage(systemName: "chevron.up.chevron.down"), for: .normal)
                menuButton.showsMenuAsPrimaryAction = true
                menuButton.menu = UIMenu(children: variants.map { variant in
                    UIAction(title: variant.displayName, state: variant == current ? .on : .off) { _ in
                        if isLight {
                            AppSettings.lightTheme = variant
                        } else {
                            AppSettings.darkTheme = variant
                        }
                        Theme.applyThemeChange()
                    }
                })
                cell.accessoryView = menuButton
                cell.accessoryType = .none
                return cell
            default:
                var config = cell.defaultContentConfiguration()
                config.text = "帖子字号"
                config.textProperties.font = .preferredFont(forTextStyle: .body)
                let scale = AppSettings.fontScale
                config.secondaryText = scale == 1.0 ? "默认" : "\(Int(scale * 100))%"
                config.secondaryTextProperties.color = Theme.secondaryLabel
                cell.contentConfiguration = config
                cell.accessoryType = .none
                let menuButton = UIButton(type: .system)
                menuButton.setImage(UIImage(systemName: "chevron.up.chevron.down"), for: .normal)
                menuButton.showsMenuAsPrimaryAction = true
                menuButton.menu = UIMenu(children: [
                    0.85, 1.0, 1.15, 1.3
                ].map { scale in
                    UIAction(title: scale == 1.0 ? "默认" : "\(Int(scale * 100))%", state: scale == AppSettings.fontScale ? .on : .off) { _ in
                        AppSettings.fontScale = scale
                        self.tableView.reloadData()
                        Toast.show("重新打开帖子后生效", in: self.view ?? UIView())
                    }
                })
                cell.accessoryView = menuButton
                cell.accessoryType = .none
                return cell
            }
        case .network:
            if indexPath.row == 0 {
                return toggleCell(
                    cell,
                    title: "自定义域名",
                    subtitle: "论坛主站被墙时切换备用域名",
                    isOn: AppSettings.customHostEnabled
                ) { enabled in
                    AppSettings.customHostEnabled = enabled
                }
            }
            if indexPath.row == 1 {
                var config = cell.defaultContentConfiguration()
                config.text = "备用域名"
                let host = AppSettings.customHost
                config.secondaryText = host.isEmpty ? "未设置(默认 stage1st.com)" : host
                config.textProperties.font = .preferredFont(forTextStyle: .body)
                config.secondaryTextProperties.color = Theme.secondaryLabel
                config.secondaryTextProperties.numberOfLines = 2
                cell.contentConfiguration = config
                cell.accessoryType = .disclosureIndicator
                return cell
            }
            var config = cell.defaultContentConfiguration()
            config.text = "清空列表缓存"
            config.secondaryText = "版块/主题/帖子的秒开缓存"
            config.textProperties.font = .preferredFont(forTextStyle: .body)
            config.secondaryTextProperties.font = .preferredFont(forTextStyle: .footnote)
            config.secondaryTextProperties.color = Theme.secondaryLabel
            cell.contentConfiguration = config
            cell.accessoryType = .none
            return cell
        default:
            if indexPath.row == 0 {
                var config = cell.defaultContentConfiguration()
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                config.text = "版本"
                config.secondaryText = "\(version)(M3)"
                config.textProperties.font = .preferredFont(forTextStyle: .body)
                config.secondaryTextProperties.color = Theme.secondaryLabel
                cell.contentConfiguration = config
                cell.accessoryType = .none
                return cell
            }
            var config = cell.defaultContentConfiguration()
            config.text = "开源许可"
            config.textProperties.font = .preferredFont(forTextStyle: .body)
            cell.contentConfiguration = config
            cell.accessoryType = .disclosureIndicator
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if Section(rawValue: indexPath.section) == .display {
            switch indexPath.row {
            case 0: showAppearancePicker()
            case 1: showThemePicker(isLight: true)
            case 2: showThemePicker(isLight: false)
            default: break
            }
            return
        }
        if Section(rawValue: indexPath.section) == .network {
            if indexPath.row == 1 {
                showCustomHostEditor()
            } else if indexPath.row == 2 {
                Task {
                    await ResponseCacheService.clearAll()
                    Toast.show("列表缓存已清空", in: self.view ?? UIView())
                }
            }
            return
        }
        guard Section(rawValue: indexPath.section) == .image, indexPath.row == 1 else {
            if Section(rawValue: indexPath.section) == .about, indexPath.row == 1 {
                navigationController?.pushViewController(AboutViewController(), animated: true)
            }
            return
        }
        ImageCache.default.clearDiskCache { [weak self] in
            Task { @MainActor in
                Toast.show("图片缓存已清除", in: self?.view ?? UIView())
                self?.refreshCacheSize()
            }
        }
    }
}

/// 开源许可与致谢。
@MainActor
final class AboutViewController: UIViewController {

    private let textView = UITextView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.contentBackground
        navigationItem.title = "关于"

        let licenses = """
        S1 Gugu

        Stage1st 论坛第三方 iOS 客户端(UIKit + SQLiteData 原生实现)。
        功能设计参考 Android 端开源项目 S1-Next(ykrank),谨致谢意。

        开源组件:
        · SQLiteData(Point-Free)— MIT
        · GRDB (groue) — MIT
        · StructuredQueries(Point-Free)— MIT
        · Kingfisher(onevcat)— MIT
        · SwiftSoup(scinfu)— MIT
        · SnapKit(SnapKit Team)— MIT

        论坛内容版权归 STAGE1ST 及其用户所有。
        """

        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.isEditable = false
        textView.textContainerInset = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        textView.text = licenses
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.topAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }
}
