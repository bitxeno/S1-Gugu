import UIKit
import SnapKit

/// Tab 1 首页:顶部「收藏」区块(本地 forumfavorite 表,无收藏时不显示)+
/// 版块组列表(forumindex 一次全量,按分类分组)。收藏区块支持拖动排序。
@MainActor
final class ForumGroupsViewController: UIViewController {

    /// Section 标识:收藏区块用专用标识避免与分类名冲突,其余为分类名
    enum Section {
        static let favorites = "\u{0}favorites"
    }

    /// 列表条目:收藏条目以本地 entry 为标识(同一版块可同时出现在收藏与分类区块)
    enum ListItem: Hashable {
        case favorite(ForumFavoriteEntry)
        case forum(Forum)
    }

    /// 分类名作为 Section 标题;收藏区块标题「收藏」
    final class DataSource: UITableViewDiffableDataSource<String, ListItem> {
        override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
            sectionIdentifier(for: section) == Section.favorites ? "收藏" : sectionIdentifier(for: section)
        }

        override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
            sectionIdentifier(for: indexPath.section) == Section.favorites
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

        dataSource = DataSource(tableView: tableView) { [weak self] tableView, indexPath, item in
            self?.configureCell(tableView, at: indexPath, item: item) ?? UITableViewCell()
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

    private func configureCell(_ tableView: UITableView, at indexPath: IndexPath, item: ListItem) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "forum", for: indexPath)
        cell.applyFlatListBackground()
        var config = cell.defaultContentConfiguration()
        switch item {
        case let .favorite(entry):
            config.text = entry.name
            config.image = UIImage(systemName: "star.fill")
            config.imageProperties.tintColor = .systemYellow
            if let forum = favoriteForumsById[entry.forumId] {
                config.secondaryText = "主题 \(forum.threads) · 今日 \(forum.todayposts)"
            }
        case let .forum(forum):
            config.text = forum.displayName
            config.secondaryText = "主题 \(forum.threads) · 今日 \(forum.todayposts)"
            config.image = UIImage(systemName: "number")
            config.imageProperties.tintColor = Theme.accent
        }
        config.textProperties.font = .preferredFont(forTextStyle: .body)
        config.textProperties.color = Theme.label
        config.secondaryTextProperties.font = .preferredFont(forTextStyle: .footnote)
        config.secondaryTextProperties.color = Theme.secondaryLabel
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
                await self.renderWithFavorites(DiscuzAPI.parseForumIndex(cached))
            } else if showSpinner {
                placeholder.state = .loading("正在加载版块")
            }

            do {
                let sections = try await DiscuzAPI.shared.forumIndex()
                guard !Task.isCancelled else { return }
                await self.renderWithFavorites(sections)
            } catch {
                guard !Task.isCancelled else { return }
                // 缓存已渲染:静默保留,不弹错误页
                if dataSource.snapshot().numberOfItems == 0 {
                    self.renderError(error)
                }
            }
        }
    }

    /// 渲染版块分组 + 顶部收藏区块(无收藏时自动不出现)
    private func renderWithFavorites(_ sections: [ForumSection]) async {
        let favorites = await ForumFavoriteService.entries()
        render(sections, favorites: favorites)
    }

    /// 从版块页返回时刷新收藏区块与版块统计(静默,不转圈)
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard dataSource != nil, view.window != nil else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                let sections = try await DiscuzAPI.shared.forumIndex()
                await self.renderWithFavorites(sections)
            } catch {
                // 网络失败保留当前渲染,收藏增删仍走本地刷新
                let snapshot = self.dataSource.snapshot()
                let sections = snapshot.sectionIdentifiers
                    .filter { $0 != Section.favorites }
                    .compactMap { id -> ForumSection? in
                        guard id != Section.favorites else { return nil }
                        let items = snapshot.itemIdentifiers(inSection: id).compactMap {
                            if case let .forum(forum) = $0 { return forum } else { return nil }
                        }
                        guard !items.isEmpty else { return nil }
                        return ForumSection(id: id, categoryName: id, forums: items)
                    }
                await self.renderWithFavorites(sections)
            }
        }
    }

    private func render(_ sections: [ForumSection], favorites: [ForumFavoriteEntry]) {
        placeholder.isHidden = true
        tableView.refreshControl?.endRefreshing()
        // 收藏条目的主题数/今日数取 forumindex 实时数据
        let forumsById = Dictionary(sections.flatMap(\.forums).map { ($0.id, $0) },
                                    uniquingKeysWith: { first, _ in first })
        var snapshot = NSDiffableDataSourceSnapshot<String, ListItem>()
        if !favorites.isEmpty {
            snapshot.appendSections([Section.favorites])
            snapshot.appendItems(favorites.map { .favorite($0) }, toSection: Section.favorites)
        }
        for section in sections {
            snapshot.appendSections([section.categoryName])
            snapshot.appendItems(section.forums.map { .forum($0) }, toSection: section.categoryName)
        }
        // apply 会同步走 cell provider,统计映射必须先就位
        favoriteForumsById = forumsById
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    /// 收藏 forumId → forumindex 实时版块数据(渲染收藏条目统计用)
    private var favoriteForumsById: [Int: Forum] = [:]

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
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        let forum: Forum
        switch item {
        case let .favorite(entry):
            forum = favoriteForumsById[entry.forumId] ?? Forum(fid: String(entry.forumId), name: entry.name)
        case let .forum(forumData):
            forum = forumData
        }
        navigationController?.pushViewController(ThreadListViewController(forum: forum), animated: true)
    }

    // MARK: 拖动排序(仅收藏区块,长按拖动,无需编辑模式)

    func tableView(_ tableView: UITableView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        guard dataSource.sectionIdentifier(for: indexPath.section) == Section.favorites,
              case let .favorite(entry)? = dataSource.itemIdentifier(for: indexPath) else { return [] }
        let dragItem = UIDragItem(itemProvider: NSItemProvider(object: entry.name as NSString))
        dragItem.localObject = entry
        return [dragItem]
    }

    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        guard dataSource.sectionIdentifier(for: sourceIndexPath.section) == Section.favorites,
              dataSource.sectionIdentifier(for: destinationIndexPath.section) == Section.favorites else { return }
        var snapshot = dataSource.snapshot()
        let favorites = snapshot.itemIdentifiers(inSection: Section.favorites)
        guard favorites.indices.contains(sourceIndexPath.row),
              favorites.indices.contains(destinationIndexPath.row) else { return }
        let moved = favorites[sourceIndexPath.row]
        var reordered = favorites
        reordered.move(fromOffsets: IndexSet(integer: sourceIndexPath.row), toOffset: destinationIndexPath.row)
        guard reordered != favorites else { return }
        // 用移动后相邻条目作锚点,把重排以增量 move 应用到当前快照
        let movedIndex = reordered.firstIndex(of: moved) ?? 0
        if movedIndex + 1 < reordered.count {
            snapshot.moveItem(moved, beforeItem: reordered[movedIndex + 1])
        } else if movedIndex >= 1 {
            snapshot.moveItem(moved, afterItem: reordered[movedIndex - 1])
        }
        dataSource.apply(snapshot, animatingDifferences: false)
        Task {
            await ForumFavoriteService.saveOrder(ids: reordered.compactMap {
                if case let .favorite(entry) = $0 { return entry.forumId } else { return nil }
            })
        }
    }
}
