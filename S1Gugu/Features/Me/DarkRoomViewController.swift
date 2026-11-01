import UIKit
import SnapKit

/// 小黑屋(showdarkroom JSON,按 cid 锚点分页)。
@MainActor
final class DarkRoomViewController: UIViewController {

    private var tableView: UITableView!
    private var items: [DarkRoomItem] = []
    private var nextCid: String?
    private var canLoadMore = true
    private var isLoading = false
    private let placeholder = StatefulPlaceholderView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationItem.title = "小黑屋"

        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.backgroundColor = Theme.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "darkroom")
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }

        placeholder.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.topAnchor.constraint(equalTo: view.topAnchor),
            placeholder.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            placeholder.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            placeholder.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        placeholder.state = .loading("加载小黑屋")
        loadMore()
    }

    private func loadMore() {
        guard !isLoading, canLoadMore else { return }
        isLoading = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await DiscuzAPI.shared.darkRoom(anchorCid: self.nextCid)
                self.items.appendUniqued(contentsOf: page.items, by: \.cid)
                self.nextCid = page.nextCid
                self.canLoadMore = page.nextCid != nil && !page.items.isEmpty
                self.isLoading = false
                self.placeholder.isHidden = !self.items.isEmpty
                if self.items.isEmpty {
                    self.placeholder.state = .empty(icon: "figure.wave", title: "小黑屋是空的", message: "目前没有违规用户")
                }
                self.tableView.reloadData()
            } catch {
                self.isLoading = false
                self.placeholder.state = .error(
                    icon: "wifi.exclamationmark",
                    title: "加载失败",
                    message: (error as? LocalizedError)?.errorDescription ?? "请稍后重试",
                    retry: { [weak self] in self?.loadMore() }
                )
                self.placeholder.isHidden = false
            }
        }
    }
}

extension DarkRoomViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "darkroom", for: indexPath)
        cell.applyFlatListBackground()
        let item = items[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = "\(item.username ?? "UID \(item.uid)") · \(item.action ?? "处罚")"
        var detail: [String] = []
        if let reason = item.reason, !reason.isEmpty { detail.append("理由:\(reason)") }
        if let operatorName = item.operatorName, !operatorName.isEmpty { detail.append("执行:\(operatorName)") }
        if let expiry = item.groupExpiry, !expiry.isEmpty { detail.append("解禁:\(expiry)") }
        config.secondaryText = detail.joined(separator: "\n")
        config.textProperties.font = .preferredFont(forTextStyle: .subheadline)
        config.secondaryTextProperties.font = .preferredFont(forTextStyle: .footnote)
        config.secondaryTextProperties.color = Theme.secondaryLabel
        config.secondaryTextProperties.numberOfLines = 0
        config.image = UIImage(systemName: "figure.fall")
        config.imageProperties.tintColor = .systemRed
        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard indexPath.row >= items.count - 5 else { return }
        loadMore()
    }
}

/// 帖子离线备份管理。
@MainActor
final class PostBackupsViewController: UIViewController {

    private var tableView: UITableView!
    private var entries: [PostBackupEntry] = []
    private let placeholder = StatefulPlaceholderView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationItem.title = "帖子备份"

        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.dataSource = self
        tableView.backgroundColor = Theme.background
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "backup")
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }

        placeholder.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.topAnchor.constraint(equalTo: view.topAnchor),
            placeholder.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            placeholder.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            placeholder.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { await reload() }
    }

    private func reload() async {
        entries = await PostBackupService.entries()
        placeholder.isHidden = !entries.isEmpty
        if entries.isEmpty {
            placeholder.state = .empty(
                icon: "arrow.down.doc",
                title: "暂无备份",
                message: "在帖子菜单选择「备份全帖」后可离线阅读"
            )
        }
        tableView.reloadData()
    }
}

extension PostBackupsViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        entries.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "backup", for: indexPath)
        let entry = entries[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = entry.title.isEmpty ? "主题 #\(entry.threadId)" : entry.title
        config.secondaryText = "\(entry.pageCount) 页 · 备份于 \(Thread.formatDate(String(entry.timestamp)))"
        config.textProperties.numberOfLines = 2
        config.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1)
        config.secondaryTextProperties.color = Theme.tertiaryLabel
        config.image = UIImage(systemName: "arrow.down.doc")
        config.imageProperties.tintColor = Theme.accent
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let entry = entries[indexPath.row]
        let controller = PostListViewController(threadId: entry.threadId, threadTitle: entry.title)
        navigationController?.pushViewController(controller, animated: true)
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let entry = entries[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completion in
            Task {
                await PostBackupService.remove(threadId: entry.threadId)
                await self?.reload()
                completion(true)
            }
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }
}
