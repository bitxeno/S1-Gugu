import UIKit
import SnapKit

/// Tab 2「收藏」:收藏 + 浏览历史,复用 `TabbedPageViewController` 的顶部文字 Tab,
/// 支持左右滑动切换;本页隐藏导航栏,push 进帖子时恢复。
@MainActor
final class FavoritesViewController: TabbedPageViewController {

    private let favoritesList = FavoritesListViewController()
    private let historyList = HistoryViewController()
    private let clearButton = UIButton(type: .system)

    init() {
        super.init(tabs: [
            Tab(title: "收藏", controller: favoritesList),
            Tab(title: "浏览历史", controller: historyList),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 「浏览历史」页右侧提供清空入口(收藏页无操作按钮)
    override func headerToolViews(for index: Int) -> [UIView] {
        guard index == 1 else { return [] }
        clearButton.tintColor = Theme.barForeground
        clearButton.accessibilityLabel = "清空浏览历史"
        if #available(iOS 26.0, *) {
            var config = UIButton.Configuration.glass()
            config.image = UIImage(systemName: "trash")
            config.cornerStyle = .capsule
            config.baseForegroundColor = Theme.barForeground
            config.contentInsets = .zero
            clearButton.configuration = config
        } else {
            clearButton.setImage(UIImage(systemName: "trash"), for: .normal)
        }
        clearButton.addAction(UIAction { [weak self] _ in
            self?.historyList.requestClear()
        }, for: .touchUpInside)
        return [clearButton]
    }
}

/// 收藏列表:论坛收藏主题(50/页),滑动移除收藏。
@MainActor
final class FavoritesListViewController: UIViewController {

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, Favourite>!
    private let placeholder = StatefulPlaceholderView()

    private var favorites: [Favourite] = []
    private var page = 0
    private var canLoadMore = true
    private var isLoading = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        setupCollectionView()

        NotificationCenter.default.addObserver(
            self, selector: #selector(sessionChanged),
            name: SessionStore.didChangeNotification, object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if SessionStore.shared.state.isLoggedIn, favorites.isEmpty {
            reloadFirstPage()
        } else {
            renderLoginState()
        }
    }

    @objc private func sessionChanged() {
        favorites = []
        page = 0
        canLoadMore = true
        renderLoginState()
        if SessionStore.shared.state.isLoggedIn {
            reloadFirstPage()
        }
    }

    private func setupCollectionView() {
        var listConfig = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        listConfig.showsSeparators = true
        // list section 默认自绘系统背景,必须显式指定,否则盖住页面米白
        listConfig.backgroundColor = Theme.background
        let layout = UICollectionViewCompositionalLayout { _, environment in
            NSCollectionLayoutSection.list(using: listConfig, layoutEnvironment: environment)
        }
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = Theme.background
        collectionView.delegate = self

        let refresh = UIRefreshControl()
        refresh.addAction(UIAction { [weak self] _ in self?.reloadFirstPage() }, for: .valueChanged)
        collectionView.refreshControl = refresh

        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, Favourite> { cell, _, favorite in
            cell.applyFlatListBackground()
            var config = cell.defaultContentConfiguration()
            config.text = favorite.displayName
            config.secondaryText = favorite.description ?? Thread.formatDate(favorite.dateline)
            config.textProperties.font = .preferredFont(forTextStyle: .subheadline)
            config.textProperties.numberOfLines = 2
            config.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1)
            config.secondaryTextProperties.color = Theme.tertiaryLabel
            config.text = favorite.displayName
            cell.contentConfiguration = config
        }
        dataSource = UICollectionViewDiffableDataSource<Int, Favourite>(collectionView: collectionView) { collectionView, indexPath, favorite in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: favorite)
        }

        view.addSubview(collectionView)
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.topAnchor.constraint(equalTo: view.topAnchor),
            placeholder.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            placeholder.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            placeholder.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func renderLoginState() {
        collectionView.refreshControl?.endRefreshing()
        guard !SessionStore.shared.state.isLoggedIn else {
            placeholder.isHidden = !favorites.isEmpty
            if favorites.isEmpty {
                placeholder.state = .empty(icon: "star", title: "暂无收藏", message: "在帖子页可以收藏主题")
            }
            return
        }
        placeholder.state = .empty(
            icon: "person.crop.circle",
            title: "请先登录",
            message: "登录后即可查看收藏的主题"
        )
        placeholder.isHidden = false
    }

    // MARK: - Data

    private func reloadFirstPage() {
        guard !isLoading else { return }
        guard SessionStore.shared.state.isLoggedIn else {
            renderLoginState()
            return
        }
        isLoading = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await DiscuzAPI.shared.favorites(page: 1)
                self.favorites = result.items.uniqued(by: \.id)
                self.page = 1
                self.canLoadMore = result.hasMore
                self.isLoading = false
                self.applySnapshot()
                self.renderLoginState()
            } catch {
                self.isLoading = false
                self.collectionView.refreshControl?.endRefreshing()
                if self.favorites.isEmpty {
                    self.placeholder.state = .error(
                        icon: "wifi.exclamationmark",
                        title: "收藏加载失败",
                        message: (error as? LocalizedError)?.errorDescription ?? "请稍后重试",
                        retry: { self.reloadFirstPage() }
                    )
                    self.placeholder.isHidden = false
                }
            }
        }
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, Favourite>()
        snapshot.appendSections([0])
        snapshot.appendItems(favorites)
        dataSource.apply(snapshot, animatingDifferences: false)
    }
}

extension FavoritesListViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let favorite = dataSource.itemIdentifier(for: indexPath) else { return }
        let controller = PostListViewController(threadId: favorite.threadId, threadTitle: favorite.displayName)
        navigationController?.pushViewController(controller, animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard indexPath.item >= favorites.count - 5, !isLoading, canLoadMore, page > 0 else { return }
        isLoading = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await DiscuzAPI.shared.favorites(page: self.page + 1)
                self.favorites.appendUniqued(contentsOf: result.items, by: \.id)
                self.page += 1
                self.canLoadMore = result.hasMore
            } catch {
                self.canLoadMore = false
            }
            self.isLoading = false
            self.applySnapshot()
        }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let favorite = dataSource.itemIdentifier(for: indexPath) else { return nil }
        let remove = UIAction(title: "移除收藏", image: UIImage(systemName: "star.slash"), attributes: .destructive) { [weak self] _ in
            guard let self, let favId = favorite.favid else { return }
            Task {
                do {
                    try await DiscuzAPI.shared.removeFavorite(favId: favId)
                    self.favorites.removeAll { $0.id == favorite.id }
                    self.applySnapshot()
                    self.renderLoginState()
                    Toast.show("已移除收藏", in: self.view ?? UIView())
                } catch {
                    Toast.show((error as? LocalizedError)?.errorDescription ?? "移除失败", in: self.view ?? UIView())
                }
            }
        }
        return UIContextMenuConfiguration(actionProvider: { _ in UIMenu(children: [remove]) })
    }
}
