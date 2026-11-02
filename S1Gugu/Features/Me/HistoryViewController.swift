import UIKit
import SnapKit

/// 浏览历史:本地 History 表(300 条上限),支持搜索、单条删除、清空。
@MainActor
final class HistoryViewController: UIViewController {

    private var tableView: UITableView!
    private var dataSource: UITableViewDiffableDataSource<Int, HistoryEntry>!
    private var searchController: UISearchController!
    private let placeholder = StatefulPlaceholderView()

    private var entries: [HistoryEntry] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationItem.title = "浏览历史"

        tableView = UITableView(frame: view.bounds, style: .insetGrouped)
        tableView.backgroundColor = Theme.background
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "history")

        let clearAction = UIAction(title: "清空历史", image: UIImage(systemName: "trash")) { [weak self] _ in
            self?.confirmClear()
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "清空", menu: UIMenu(children: [clearAction]))

        dataSource = UITableViewDiffableDataSource<Int, HistoryEntry>(tableView: tableView) { [weak self] tableView, indexPath, entry in
            self?.configureCell(tableView, at: indexPath, entry: entry)
        }

        searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "搜索标题"
        navigationItem.searchController = searchController

        view.addSubview(tableView)
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.topAnchor.constraint(equalTo: view.topAnchor),
            placeholder.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            placeholder.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            placeholder.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    /// 供容器(收藏页「浏览历史」Tab)触发的「清空历史」入口
    func requestClear() {
        confirmClear()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { await reload() }
    }

    private func configureCell(_ tableView: UITableView, at indexPath: IndexPath, entry: HistoryEntry) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "history", for: indexPath)
        cell.applyFlatListBackground()
        var config = cell.defaultContentConfiguration()
        config.text = entry.title
        config.secondaryText = Thread.formatDate(String(entry.timestamp))
        config.textProperties.font = .preferredFont(forTextStyle: .subheadline)
        config.textProperties.numberOfLines = 2
        config.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1)
        config.secondaryTextProperties.color = Theme.tertiaryLabel
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    private func reload(query: String? = nil) async {
        entries = await HistoryService.entries(query: query)
        placeholder.isHidden = !entries.isEmpty
        if entries.isEmpty {
            placeholder.state = .empty(
                icon: "clock.arrow.circlepath",
                title: query?.isEmpty == false ? "没有匹配的历史" : "暂无浏览历史",
                message: query?.isEmpty == false ? "换个关键词试试" : "打开过的帖子会记录在这里"
            )
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, HistoryEntry>()
        snapshot.appendSections([0])
        snapshot.appendItems(entries)
        await dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func confirmClear() {
        let alert = UIAlertController(title: "清空浏览历史", message: "将删除全部 \(entries.count) 条记录,此操作不可撤销。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "清空", style: .destructive) { [weak self] _ in
            Task {
                await HistoryService.clear()
                await self?.reload()
            }
        })
        present(alert, animated: true)
    }
}

extension HistoryViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let entry = dataSource.itemIdentifier(for: indexPath) else { return }
        let controller = PostListViewController(threadId: entry.threadId, threadTitle: entry.title)
        navigationController?.pushViewController(controller, animated: true)
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let entry = dataSource.itemIdentifier(for: indexPath) else { return nil }
        let delete = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completion in
            Task {
                await HistoryService.remove(threadId: entry.threadId)
                await self?.reload(query: self?.searchController.searchBar.text)
                completion(true)
            }
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }
}

extension HistoryViewController: UISearchResultsUpdating {

    func updateSearchResults(for searchController: UISearchController) {
        Task { await reload(query: searchController.searchBar.text) }
    }
}
