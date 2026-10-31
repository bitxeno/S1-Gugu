import UIKit
import SnapKit

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
        view.backgroundColor = .systemGroupedBackground
        navigationItem.title = "我的"
        tableView = UITableView(frame: view.bounds, style: .insetGrouped)
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        view.addSubview(tableView)

        NotificationCenter.default.addObserver(
            self, selector: #selector(sessionChanged),
            name: SessionStore.didChangeNotification, object: nil
        )
    }

    @objc private func sessionChanged() {
        tableView.reloadData()
    }

    private func configure(cell: UITableViewCell, row: Row) {
        var config = cell.defaultContentConfiguration()
        cell.accessoryType = .disclosureIndicator

        switch row {
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
        case .account:
            let state = SessionStore.shared.state
            if state.isLoggedIn {
                config.text = state.name ?? "已登录"
                config.secondaryText = "UID \(state.uid ?? 0)"
                config.image = UIImage(systemName: "person.crop.circle.fill")
            } else {
                config.text = "未登录"
                config.secondaryText = "点按登录以使用收藏、私信等功能"
                config.image = UIImage(systemName: "person.crop.circle")
            }
            config.imageProperties.tintColor = Theme.accent
            config.secondaryTextProperties.color = .secondaryLabel
            cell.accessoryType = state.isLoggedIn ? .none : .disclosureIndicator
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

    /// 账号面板:切换账号 / 添加账号 / 登出
    private func showAccountPanel() {
        Task { [weak self] in
            guard let self else { return }
            let accounts = await AccountService.shared.list()
            let currentName = SessionStore.shared.state.name

            let alert = UIAlertController(title: "账号", message: "当前:\(currentName ?? "-")", preferredStyle: .actionSheet)

            for entry in accounts where entry.name != currentName {
                alert.addAction(UIAlertAction(title: "切换到 \(entry.name)", style: .default) { _ in
                    self.switchAccount(to: entry.name)
                })
            }
            alert.addAction(UIAlertAction(title: "添加账号", style: .default) { _ in
                self.navigationController?.pushViewController(LoginViewController(), animated: true)
            })
            alert.addAction(UIAlertAction(title: "登出当前账号", style: .destructive) { _ in
                self.logoutConfirmation()
            })
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            // iPad 锚点
            if let popover = alert.popoverPresentationController {
                popover.sourceView = self.view
                popover.sourceRect = CGRect(x: self.view.bounds.midX, y: 120, width: 1, height: 1)
            }
            self.present(alert, animated: true)
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
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        let row: Row
        switch indexPath.section {
        case 0: row = .account
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
            if SessionStore.shared.state.isLoggedIn {
                showAccountPanel()
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
