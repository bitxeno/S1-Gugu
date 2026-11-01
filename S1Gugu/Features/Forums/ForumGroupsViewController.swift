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

    /// 分类名作为 Section 标题;收藏区块标题「收藏」。
    /// moveRowAt 必须由数据源实现,UIKit 据此决定是否显示拖动滑块
    final class DataSource: UITableViewDiffableDataSource<String, ListItem> {
        /// 收藏行拖动落地(source/destination row,均在收藏区块内)
        var onMoveRow: ((Int, Int) -> Void)?

        override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
            sectionIdentifier(for: section) == Section.favorites ? "收藏" : sectionIdentifier(for: section)
        }

        override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
            sectionIdentifier(for: indexPath.section) == Section.favorites
        }

        override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
            onMoveRow?(sourceIndexPath.row, destinationIndexPath.row)
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
        dataSource.onMoveRow = { [weak self] sourceRow, destinationRow in
            self?.handleMoveRow(sourceRow: sourceRow, destinationRow: destinationRow)
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
        // 编辑模式(拖动排序)下点击行 = 退出排序模式,不进版块
        if tableView.isEditing {
            setEditingMode(false)
            return
        }
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

    // MARK: 收藏区块:拖动排序模式 + 左滑删除

    /// 长按进入/点击退出的拖动排序模式(仅收藏区块)
    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard dataSource.sectionIdentifier(for: indexPath.section) == Section.favorites,
              case .favorite = dataSource.itemIdentifier(for: indexPath) else { return nil }
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            UIMenu(children: [
                UIAction(title: "调整排序", image: UIImage(systemName: "arrow.up.arrow.down")) { [weak self] _ in
                    self?.setEditingMode(true)
                },
                UIAction(title: "取消收藏", image: UIImage(systemName: "star.slash"), attributes: .destructive) { [weak self] _ in
                    self?.removeFavorite(at: indexPath)
                },
            ])
        })
    }

    /// 编辑模式只用于拖动排序:所有行都不出现插入/删除圆钮(删除走左滑),
    /// 可拖动的行由 canMoveRowAt 限制在收藏区块
    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        .none
    }

    func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        false
    }

    /// 收藏行左滑删除
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard dataSource.sectionIdentifier(for: indexPath.section) == Section.favorites,
              case let .favorite(entry)? = dataSource.itemIdentifier(for: indexPath) else { return nil }
        let delete = UIContextualAction(style: .destructive, title: "取消收藏") { [weak self] _, _, completion in
            self?.removeFavoriteEntry(entry)
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    private func setEditingMode(_ editing: Bool) {
        guard let tableView else { return }
        tableView.setEditing(editing, animated: true)
        // 编辑中右上角变「完成」;平时恢复搜索按钮(排序入口在收藏行长按菜单里)
        if editing {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: "完成",
                primaryAction: UIAction { [weak self] _ in
                    self?.setEditingMode(false)
                }
            )
        } else {
            navigationItem.rightBarButtonItem = UIBarButtonItem(primaryAction: UIAction(
                title: "搜索",
                image: UIImage(systemName: "magnifyingglass")
            ) { [weak self] _ in
                self?.navigationController?.pushViewController(SearchViewController(), animated: true)
            })
        }
    }

    private func removeFavorite(at indexPath: IndexPath) {
        guard case let .favorite(entry)? = dataSource.itemIdentifier(for: indexPath) else { return }
        removeFavoriteEntry(entry)
    }

    private func removeFavoriteEntry(_ entry: ForumFavoriteEntry) {
        Task { [weak self] in
            _ = try? await AppDatabase.shared.write { database in
                try ForumFavoriteEntry.find(entry.forumId).delete().execute(database)
            }
            guard let self else { return }
            // 编辑模式中删空收藏则整体退出;否则只重渲染收藏区块
            if tableView.isEditing, await ForumFavoriteService.entries().isEmpty {
                setEditingMode(false)
            }
            let snapshot = dataSource.snapshot()
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
            await renderWithFavorites(sections)
            Toast.show("已取消收藏「\(entry.name)」", in: view)
        }
    }

    func tableView(_ tableView: UITableView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        guard dataSource.sectionIdentifier(for: indexPath.section) == Section.favorites,
              case let .favorite(entry)? = dataSource.itemIdentifier(for: indexPath) else { return [] }
        let dragItem = UIDragItem(itemProvider: NSItemProvider(object: entry.name as NSString))
        dragItem.localObject = entry
        return [dragItem]
    }

    // MARK: 拖动排序落地(DataSource.moveRowAt 转发,行均在收藏区块内)

    private func handleMoveRow(sourceRow: Int, destinationRow: Int) {
        var snapshot = dataSource.snapshot()
        let favorites = snapshot.itemIdentifiers(inSection: Section.favorites)
        guard favorites.indices.contains(sourceRow),
              favorites.indices.contains(destinationRow) else { return }
        let moved = favorites[sourceRow]
        var reordered = favorites
        reordered.move(fromOffsets: IndexSet(integer: sourceRow), toOffset: destinationRow)
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
