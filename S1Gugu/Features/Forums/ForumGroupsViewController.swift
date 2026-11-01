import UIKit
import SnapKit

/// Tab 1 首页:版块组列表(forumindex 一次全量,按分类分组)。
@MainActor
final class ForumGroupsViewController: UIViewController {

    /// 分类名作为 Section 标题
    final class DataSource: UITableViewDiffableDataSource<String, Forum> {
        override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
            sectionIdentifier(for: section)
        }
    }

    private var tableView: UITableView!
    private var dataSource: DataSource!
    private var loadTask: Task<Void, Never>?

    private let placeholder = StatefulPlaceholderView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationItem.title = "论坛"
        navigationItem.rightBarButtonItem = UIBarButtonItem(primaryAction: UIAction(
            title: "搜索",
            image: UIImage(systemName: "magnifyingglass")
        ) { [weak self] _ in
            self?.navigationController?.pushViewController(SearchViewController(), animated: true)
        })
        setupTableView()
        setupPlaceholder()
        fetch()
    }

    private func setupTableView() {
        tableView = UITableView(frame: view.bounds, style: .insetGrouped)
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.backgroundColor = Theme.background
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "forum")
        tableView.delegate = self

        let refresh = UIRefreshControl()
        refresh.addAction(UIAction { [weak self] _ in self?.fetch(showSpinner: false) }, for: .valueChanged)
        tableView.refreshControl = refresh

        dataSource = DataSource(tableView: tableView) { [weak self] tableView, indexPath, forum in
            guard let self else { return UITableViewCell() }
            return self.configureCell(tableView, at: indexPath, forum: forum)
        }

        view.addSubview(tableView)
    }

    private func setupPlaceholder() {
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.topAnchor.constraint(equalTo: view.topAnchor),
            placeholder.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            placeholder.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            placeholder.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func configureCell(_ tableView: UITableView, at indexPath: IndexPath, forum: Forum) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "forum", for: indexPath)
        cell.applyFlatListBackground()
        var config = cell.defaultContentConfiguration()
        config.text = forum.displayName
        config.textProperties.font = .preferredFont(forTextStyle: .body)
        config.textProperties.color = Theme.label
        config.secondaryText = "主题 \(forum.threads) · 今日 \(forum.todayposts)"
        config.secondaryTextProperties.font = .preferredFont(forTextStyle: .footnote)
        config.secondaryTextProperties.color = Theme.secondaryLabel
        config.image = UIImage(systemName: "number")
        config.imageProperties.tintColor = Theme.accent
        config.imageProperties.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .body)
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    // MARK: - Data

    private func fetch(showSpinner: Bool = true) {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            let cacheKey = await ResponseCacheService.forumIndexKey()

            // 缓存先行:秒开,后台继续刷新
            if let cached = await ResponseCacheService.json(forKey: cacheKey) {
                guard !Task.isCancelled else { return }
                self.render(DiscuzAPI.parseForumIndex(cached))
            } else if showSpinner {
                placeholder.state = .loading("正在加载版块")
            }

            do {
                let sections = try await DiscuzAPI.shared.forumIndex()
                guard !Task.isCancelled else { return }
                self.render(sections)
            } catch {
                guard !Task.isCancelled else { return }
                // 缓存已渲染:静默保留,不弹错误页
                if dataSource.snapshot().numberOfItems == 0 {
                    self.renderError(error)
                }
            }
        }
    }

    private func render(_ sections: [ForumSection]) {
        placeholder.isHidden = true
        tableView.refreshControl?.endRefreshing()
        var snapshot = NSDiffableDataSourceSnapshot<String, Forum>()
        for section in sections {
            snapshot.appendSections([section.categoryName])
            snapshot.appendItems(section.forums, toSection: section.categoryName)
        }
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func renderError(_ error: Error) {
        tableView.refreshControl?.endRefreshing()
        placeholder.state = .error(
            icon: "wifi.exclamationmark",
            title: "版块加载失败",
            message: (error as? LocalizedError)?.errorDescription ?? "请稍后重试",
            retry: { [weak self] in self?.fetch() }
        )
    }
}

extension ForumGroupsViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let forum = dataSource.itemIdentifier(for: indexPath) else { return }
        navigationController?.pushViewController(ThreadListViewController(forum: forum), animated: true)
    }
}
