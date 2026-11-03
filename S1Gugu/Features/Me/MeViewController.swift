import UIKit
import SnapKit
import Kingfisher

/// Tab 4「我的」:账号、历史、过滤、设置入口。
@MainActor
final class MeViewController: UIViewController {

    private enum Row: Int, CaseIterable {
        case account
        case history
        case backup
        case blacklist
        case blackWord
        case sign
        case darkroom
        case settings
        case about
    }

    private var tableView: UITableView!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationItem.title = "我的"
        tableView = UITableView(frame: view.bounds, style: .insetGrouped)
        tableView.backgroundColor = Theme.background
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        view.addSubview(tableView)

        // 添加账号 / 切换账号 / 退出登录统一收进导航栏最右侧的菜单
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: makeAccountMenu()
        )

        NotificationCenter.default.addObserver(
            self, selector: #selector(sessionChanged),
            name: SessionStore.didChangeNotification, object: nil
        )
    }

    @objc private func sessionChanged() {
        tableView.reloadData()
        // 登录态变化后同步右上角菜单(切换 / 退出登录是否可用)
        navigationItem.rightBarButtonItem?.menu = makeAccountMenu()
    }

    /// 右上角账号操作菜单:切换账号 / 添加账号 / 退出登录。
    private func makeAccountMenu() -> UIMenu {
        var children: [UIMenuElement] = []

        if SessionStore.shared.state.isLoggedIn {
            // 已保存的其他账号在展开时异步读取,避免 await 阻塞菜单构建
            children.append(UIMenu(title: "切换账号", children: [
                UIDeferredMenuElement.uncached { [weak self] completion in
                    Task { @MainActor in
                        guard let self else { completion([]); return }
                        let accounts = await AccountService.shared.list()
                        let currentName = SessionStore.shared.state.name
                        let actions = accounts
                            .filter { $0.name != currentName }
                            .map { entry in
                                UIAction(title: entry.name) { [weak self] _ in
                                    self?.switchAccount(to: entry.name)
                                }
                            }
                        completion(actions.isEmpty
                            ? [UIAction(title: "暂无其他账号", attributes: .disabled) { _ in }]
                            : actions)
                    }
                }
            ]))
        }

        children.append(UIAction(
            title: "添加账号",
            image: UIImage(systemName: "person.badge.plus")
        ) { [weak self] _ in
            self?.navigationController?.pushViewController(LoginViewController(), animated: true)
        })

        if SessionStore.shared.state.isLoggedIn {
            children.append(UIAction(
                title: "退出登录",
                image: UIImage(systemName: "rectangle.portrait.and.arrow.right"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.logoutConfirmation()
            })
        }

        return UIMenu(children: children)
    }

    private func configure(cell: UITableViewCell, row: Row) {
        var config = cell.defaultContentConfiguration()
        cell.accessoryType = .disclosureIndicator

        switch row {
        case .account:
            break   // 账号行由 configureAccountCell 单独处理
        case .backup:
            config.text = "帖子备份"
            config.secondaryText = "已备份的帖子可离线阅读"
            config.image = UIImage(systemName: "arrow.down.doc")
        case .sign:
            config.text = "每日签到"
            config.secondaryText = "打卡 Stage1st 每日签到"
            config.image = UIImage(systemName: "checkmark.seal")
            cell.accessoryType = .none
        case .darkroom:
            config.text = "小黑屋"
            config.image = UIImage(systemName: "figure.fall")
        case .history:
            config.text = "浏览历史"
            config.image = UIImage(systemName: "clock.arrow.circlepath")
        case .blacklist:
            config.text = "黑名单"
            config.image = UIImage(systemName: "eye.slash")
        case .blackWord:
            config.text = "屏蔽词"
            config.image = UIImage(systemName: "text.badge.minus")
        case .settings:
            config.text = "设置"
            config.image = UIImage(systemName: "gearshape")
        case .about:
            config.text = "关于 S1 Gugu"
            config.image = UIImage(systemName: "info.circle")
        }
        config.imageProperties.tintColor = Theme.accent
        config.textProperties.font = .preferredFont(forTextStyle: .body)
        cell.contentConfiguration = config
    }

    private func performAutoSign() {
        guard SessionStore.shared.state.isLoggedIn else {
            navigationController?.pushViewController(LoginViewController(), animated: true)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                let sid = try await SessionStore.shared.ensureAppSession()
                let result = try await DiscuzAPI.shared.appSign(uid: SessionStore.shared.state.uid ?? 0, sid: sid)
                Toast.show(result.message, in: self.view ?? UIView())
            } catch APIError.actionFailed(let message) where message.contains("重新登录") || message.contains("请先登录") {
                // sid 失效:强制重新走 App 登录一次
                do {
                    let sid = try await SessionStore.shared.ensureAppSession(force: true)
                    let result = try await DiscuzAPI.shared.appSign(uid: SessionStore.shared.state.uid ?? 0, sid: sid)
                    Toast.show(result.message, in: self.view ?? UIView())
                } catch {
                    Toast.show((error as? LocalizedError)?.errorDescription ?? "签到失败", in: self.view ?? UIView())
                }
            } catch {
                Toast.show((error as? LocalizedError)?.errorDescription ?? "签到失败", in: self.view ?? UIView())
            }
        }
    }

    private func switchAccount(to name: String) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await AccountService.shared.switchTo(name: name)
                Toast.show("已切换到 \(name)", in: self.view ?? UIView())
            } catch {
                Toast.show((error as? LocalizedError)?.errorDescription ?? "切换失败", in: self.view ?? UIView())
            }
        }
    }

    // MARK: - 账号行

    /// 账号行:真实头像 + 账号名 + UID,点击进入个人空间。
    /// 添加账号 / 切换 / 退出登录统一放在导航栏最右侧菜单。
    private func configureAccountCell(_ cell: UITableViewCell) {
        cell.applyFlatListBackground()

        var config = cell.defaultContentConfiguration()
        config.imageProperties.cornerRadius = 22
        config.imageProperties.maximumSize = CGSize(width: 44, height: 44)
        config.imageProperties.reservedLayoutSize = CGSize(width: 44, height: 44)

        let state = SessionStore.shared.state
        if let uid = state.uid, uid != 0 {
            config.text = state.name ?? "已登录"
            config.secondaryText = "UID \(uid) · 进入个人空间"
            config.image = cachedAvatar(uid: uid)
            loadAvatarIfNeeded(uid: uid)
        } else {
            config.text = "未登录"
            config.secondaryText = "点按登录以使用收藏、私信等功能"
            config.image = UIImage(systemName: "person.crop.circle")
            config.imageProperties.tintColor = Theme.accent
        }
        config.secondaryTextProperties.color = Theme.secondaryLabel
        cell.accessoryType = .disclosureIndicator
        cell.contentConfiguration = config
    }

    /// 已发起预取的 uid,避免重复请求
    private var avatarPrefetchingUIDs: Set<Int> = []

    /// 从图片缓存同步取头像(未命中回退默认头像)
    private func cachedAvatar(uid: Int) -> UIImage {
        guard let url = AvatarURL.url(uid: uid) else { return DefaultAvatar.image }
        return ImageCache.default.retrieveImageInMemoryCache(forKey: url.absoluteString) ?? DefaultAvatar.image
    }

    /// 未命中缓存时后台预取,成功后仅刷新账号行
    private func loadAvatarIfNeeded(uid: Int) {
        guard let url = AvatarURL.url(uid: uid) else { return }
        if ImageCache.default.retrieveImageInMemoryCache(forKey: url.absoluteString) != nil { return }
        guard !avatarPrefetchingUIDs.contains(uid) else { return }
        avatarPrefetchingUIDs.insert(uid)
        KingfisherManager.shared.retrieveImage(with: url) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.avatarPrefetchingUIDs.remove(uid)
                if case .success = result, SessionStore.shared.state.uid == uid {
                    self.tableView.reloadRows(at: [IndexPath(row: 0, section: 0)], with: .none)
                }
            }
        }
    }

    private func logoutConfirmation() {
        let alert = UIAlertController(title: "登出", message: "确定退出当前账号吗?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "登出", style: .destructive) { _ in
            SessionStore.shared.logout()
            Toast.show("已登出", in: self.view ?? UIView())
        })
        present(alert, animated: true)
    }
}

extension MeViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int { 5 }

    /// 社区区行(签到按开关隐藏)
    private var communityRows: [Row] {
        AppSettings.signInEnabled ? [.sign, .darkroom] : [.darkroom]
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 1
        case 1: return 2   // 历史 / 备份
        case 2: return 2   // 黑名单 / 屏蔽词
        case 3: return communityRows.count
        default: return 2  // 设置 / 关于
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "账号"
        case 1: return "浏览"
        case 2: return "过滤"
        case 3: return "社区"
        default: return "通用"
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // 账号行带真实头像,单独配置;其余行走通用 configure
        if indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
            configureAccountCell(cell)
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        cell.applyFlatListBackground()
        let row: Row
        switch indexPath.section {
        case 1: row = indexPath.row == 0 ? .history : .backup
        case 2: row = indexPath.row == 0 ? .blacklist : .blackWord
        case 3: row = communityRows[indexPath.row]
        default: row = indexPath.row == 0 ? .settings : .about
        }
        configure(cell: cell, row: row)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let row: Row
        switch indexPath.section {
        case 0: row = .account
        case 1: row = indexPath.row == 0 ? .history : .backup
        case 2: row = indexPath.row == 0 ? .blacklist : .blackWord
        case 3: row = communityRows[indexPath.row]
        default: row = indexPath.row == 0 ? .settings : .about
        }
        switch row {
        case .account:
            if let uid = SessionStore.shared.state.uid, uid != 0 {
                // 点击账号行进入个人空间(头像 / 签名 / 好友 / TA 的主题与回复)
                navigationController?.pushViewController(
                    UserHomeViewController(uid: String(uid)),
                    animated: true
                )
            } else {
                navigationController?.pushViewController(LoginViewController(), animated: true)
            }
        case .history:
            navigationController?.pushViewController(HistoryViewController(), animated: true)
        case .backup:
            navigationController?.pushViewController(PostBackupsViewController(), animated: true)
        case .blacklist:
            navigationController?.pushViewController(BlacklistViewController(), animated: true)
        case .blackWord:
            navigationController?.pushViewController(BlackWordViewController(), animated: true)
        case .sign:
            performAutoSign()
        case .darkroom:
            navigationController?.pushViewController(DarkRoomViewController(), animated: true)
        case .settings:
            navigationController?.pushViewController(SettingsViewController(), animated: true)
        case .about:
            navigationController?.pushViewController(AboutViewController(), animated: true)
        }
    }
}
