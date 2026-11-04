import UIKit
import SnapKit

// MARK: - Cell

final class ThreadCell: UICollectionViewListCell {

    private let replyCountChip = UIView()
    private let replyCountLabel = UILabel()
    private let newReplyLabel = UILabel()
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        applyFlatListBackground()

        // 回复数徽标(参考 S1 移动版列表:前置定宽灰底数字,≥1 万缩写为 K)
        replyCountLabel.font = .preferredFont(forTextStyle: .footnote)
        replyCountLabel.textColor = Theme.replyChipUnreadText
        replyCountLabel.adjustsFontForContentSizeCategory = true
        // 定宽徽标:极端大字体下缩字兜底
        replyCountLabel.adjustsFontSizeToFitWidth = true
        replyCountLabel.minimumScaleFactor = 0.75
        replyCountLabel.textAlignment = .center
        replyCountLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        replyCountChip.backgroundColor = Theme.replyChipUnreadBackground
        replyCountChip.layer.cornerRadius = 6
        replyCountChip.clipsToBounds = true
        replyCountChip.addSubview(replyCountLabel)
        replyCountLabel.snp.makeConstraints { make in
            make.leading.greaterThanOrEqualToSuperview().inset(4)
            make.trailing.lessThanOrEqualToSuperview().inset(4)
            make.centerX.equalToSuperview()
            make.top.bottom.equalToSuperview().inset(3)
        }

        // 徽标下方的「+N」新回复数(accent 色小字,无新回复时隐藏)
        newReplyLabel.font = .preferredFont(forTextStyle: .caption2)
        newReplyLabel.textColor = Theme.replyChipNewReply
        newReplyLabel.adjustsFontForContentSizeCategory = true
        newReplyLabel.textAlignment = .center
        newReplyLabel.isHidden = true
        contentView.addSubview(newReplyLabel)

        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontForContentSizeCategory = true

        metaLabel.font = .preferredFont(forTextStyle: .footnote)
        metaLabel.textColor = Theme.secondaryLabel
        metaLabel.adjustsFontForContentSizeCategory = true

        contentView.addSubview(replyCountChip)
        contentView.addSubview(titleLabel)
        contentView.addSubview(metaLabel)
        replyCountChip.snp.makeConstraints { make in
            make.leading.equalTo(contentView.layoutMarginsGuide.snp.leading)
            make.top.equalToSuperview().inset(12)
            make.width.equalTo(40)
        }
        newReplyLabel.snp.makeConstraints { make in
            make.centerX.equalTo(replyCountChip)
            make.top.equalTo(replyCountChip.snp.bottom).offset(1)
            make.leading.greaterThanOrEqualToSuperview().inset(2)
            make.trailing.lessThanOrEqualToSuperview().inset(2)
        }
        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(replyCountChip.snp.trailing).offset(10)
            make.top.equalToSuperview().inset(10)
            make.trailing.equalTo(contentView.layoutMarginsGuide.snp.trailing)
        }
        metaLabel.snp.makeConstraints { make in
            make.leading.equalTo(replyCountChip.snp.trailing).offset(10)
            make.top.equalTo(titleLabel.snp.bottom).offset(Theme.Spacing.titleToSecondary)
            make.trailing.equalTo(contentView.layoutMarginsGuide.snp.trailing)
            make.bottom.lessThanOrEqualToSuperview().inset(10)
        }
        // 分隔线从标题 leading 开始,不伸进左侧回复数徽标区域
        separatorLayoutGuide.leadingAnchor
            .constraint(equalTo: titleLabel.leadingAnchor)
            .isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 收藏 / 浏览历史等「标题 + 备注 + 回复数」列表复用主题列表的行布局。
    /// 不展示置顶/投票徽标,其余与 `configure(_:isRead:)` 一致。
    func configure(title: String, meta: String, replyCount: Int, newReplyCount: Int = 0, isRead: Bool) {
        applyReplyChipStyle(isRead: isRead)
        replyCountLabel.text = Self.replyCountText(replyCount)
        if newReplyCount > 0 {
            newReplyLabel.text = "+\(newReplyCount)"
            newReplyLabel.isHidden = false
        } else {
            newReplyLabel.text = nil
            newReplyLabel.isHidden = true
        }

        titleLabel.attributedText = nil
        titleLabel.text = title
        titleLabel.textColor = Theme.label
        metaLabel.text = meta
        metaLabel.textColor = Theme.secondaryLabel
    }

    func configure(_ thread: Thread, isRead: Bool) {
        applyReplyChipStyle(isRead: isRead)
        replyCountLabel.text = Self.replyCountText(thread.replyCount)
        if let newCount = thread.newReplyCount {
            newReplyLabel.text = "+\(newCount)"
            newReplyLabel.isHidden = false
        } else {
            newReplyLabel.text = nil
            newReplyLabel.isHidden = true
        }

        if thread.isHiddenByBlacklist {
            titleLabel.attributedText = nil
            titleLabel.text = "已屏蔽主题"
            titleLabel.textColor = Theme.tertiaryLabel
            metaLabel.text = thread.blacklistRemark.map { "\(thread.author) · \($0)" } ?? thread.author
            metaLabel.textColor = Theme.tertiaryLabel
            return
        }

        // 置顶/投票方框徽标以文本附件形式内联在标题前:换行自然,
        // 第二行从标题 leading 起始,徽标只占第一行前缀
        let titleFont = UIFont.preferredFont(forTextStyle: .body)
        let titleColor: UIColor = isRead ? Theme.secondaryLabel : Theme.label
        let accent = Theme.accent.resolvedColor(with: traitCollection)
        let content = NSMutableAttributedString()
        if thread.isSticky {
            content.append(NSAttributedString(attachment: Self.badgeAttachment(text: "置顶", accent: accent, titleFont: titleFont, scale: traitCollection.displayScale)))
        }
        if thread.isVote {
            content.append(NSAttributedString(attachment: Self.badgeAttachment(text: "投票", accent: accent, titleFont: titleFont, scale: traitCollection.displayScale)))
        }
        if content.length > 0 {
            content.append(NSAttributedString(string: " ", attributes: [.font: titleFont]))
        }
        content.append(NSAttributedString(
            string: thread.title,
            attributes: [.font: titleFont, .foregroundColor: titleColor]
        ))
        titleLabel.attributedText = content

        var meta: [String] = []
        if !thread.author.isEmpty { meta.append(thread.author) }
        let published = thread.relativePublishedText
        if !published.isEmpty { meta.append(published) }
        metaLabel.text = meta.joined(separator: " · ")
        metaLabel.textColor = Theme.secondaryLabel
    }

    /// 已读:深橄榄底白字;未读:浅橄榄底绿字;「+N」统一用未读绿
    private func applyReplyChipStyle(isRead: Bool) {
        replyCountChip.backgroundColor = isRead ? Theme.replyChipReadBackground : Theme.replyChipUnreadBackground
        replyCountLabel.textColor = isRead ? Theme.replyChipReadText : Theme.replyChipUnreadText
        newReplyLabel.textColor = Theme.replyChipNewReply
    }

    // MARK: 内联方框徽标

    private static var badgeImageCache: [String: UIImage] = [:]

    /// 方框徽标渲染为图片(accent 描边 + 圆角,内留 padding),按颜色/倍率缓存
    private static func badgeImage(text: String, accent: UIColor, scale: CGFloat) -> UIImage {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        accent.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let key = "\(text)|\(Int(red * 255)),\(Int(green * 255)),\(Int(blue * 255))|\(scale)"
        if let cached = badgeImageCache[key] { return cached }

        let font = UIFont.preferredFont(forTextStyle: .caption1)
        let insets = UIEdgeInsets(top: 2, left: 5, bottom: 2, right: 5)
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let size = CGSize(
            width: ceil(textSize.width) + insets.left + insets.right + 1,
            height: ceil(textSize.height) + insets.top + insets.bottom + 1
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = max(scale, 1)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let border = UIBezierPath(
                roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5),
                cornerRadius: 3
            )
            accent.withAlphaComponent(0.45).setStroke()
            border.lineWidth = 1
            border.stroke()
            (text as NSString).draw(
                at: CGPoint(x: insets.left, y: insets.top),
                withAttributes: [.font: font, .foregroundColor: accent]
            )
        }
        badgeImageCache[key] = image
        return image
    }

    /// 文本附件:chip 图片相对标题首行 cap 高度垂直居中
    private static func badgeAttachment(text: String, accent: UIColor, titleFont: UIFont, scale: CGFloat) -> NSTextAttachment {
        let image = badgeImage(text: text, accent: accent, scale: scale)
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(
            x: 0,
            y: ((titleFont.capHeight - image.size.height) / 2).rounded(),
            width: image.size.width,
            height: image.size.height
        )
        return attachment
    }

    /// 8891 → "8891",13041 → "13.0K"
    private static func replyCountText(_ count: Int) -> String {
        count >= 10_000 ? String(format: "%.1fK", Double(count) / 1000) : "\(count)"
    }
}

final class FooterCell: UICollectionViewCell {

    private let spinner = UIActivityIndicatorView(style: .medium)
    private let textLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private var retryAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        textLabel.font = .preferredFont(forTextStyle: .footnote)
        textLabel.textColor = Theme.tertiaryLabel
        textLabel.adjustsFontForContentSizeCategory = true

        retryButton.configuration = {
            var config = UIButton.Configuration.gray()
            config.title = "重试"
            config.cornerStyle = .capsule
            return config
        }()
        retryButton.addAction(UIAction { [weak self] _ in self?.retryAction?() }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [spinner, textLabel, retryButton])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        contentView.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().inset(16)
            make.bottom.equalToSuperview().inset(16)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(isLoading: Bool, canLoadMore: Bool, error: String?, retry: (() -> Void)?) {
        spinner.isHidden = !isLoading
        if isLoading { spinner.startAnimating() } else { spinner.stopAnimating() }
        retryAction = retry
        retryButton.isHidden = (error == nil)
        if let error {
            textLabel.text = error
            textLabel.textColor = Theme.secondaryLabel
        } else {
            textLabel.text = canLoadMore ? "" : "没有更多了"
            textLabel.textColor = Theme.tertiaryLabel
        }
    }
}

// MARK: - ViewController

/// 版块主题列表:50 条/页无限滚动;黑名单在模型组装层过滤。
@MainActor
final class ThreadListViewController: UIViewController {

    enum ListItem: Hashable {
        case thread(Thread)
        case footer(isLoading: Bool, canLoadMore: Bool, error: String?)
    }

    private let forum: Forum
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, ListItem>!

    private let placeholder = StatefulPlaceholderView()

    private var threads: [Thread] = []
    private var page = 0
    private var canLoadMore = true
    private var isLoading = false
    private var footerError: String?
    private var loadTask: Task<Void, Never>?
    private var readThreadIds: Set<Int> = []
    private var lastReplyCounts: [Int: Int] = [:]
    private var threadTypes: [String: String] = [:]
    private var subForums: [Forum] = []
    private var selectedTypeId: String?
    private var isForumFavorite = false
    private var needsBlacklistReload = false

    init(forum: Forum) {
        self.forum = forum
        super.init(nibName: nil, bundle: nil)
        // 帖子列表沉浸浏览:隐藏全局 TabBar,返回论坛首页时自动恢复
        hidesBottomBarWhenPushed = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationItem.title = forum.name ?? "主题列表"
        setupCollectionView()
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), menu: makeMenu())
        setupPlaceholder()
        NotificationCenter.default.addObserver(
            self, selector: #selector(blacklistDidChange),
            name: BlacklistService.didChangeNotification, object: nil
        )
        Task { [weak self] in
            await BlacklistService.shared.reloadIfNeeded()
            guard let self else { return }
            self.isForumFavorite = await ForumFavoriteService.isFavorite(forumId: self.forum.id)
            await self.reloadReadState()
            self.reloadFirstPage()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if needsBlacklistReload, !isLoading {
            needsBlacklistReload = false
            reloadFirstPage()
        }
        // 从帖子返回时刷新已读状态、上次浏览回复数、版块收藏状态与相对时间文案
        Task { [weak self] in
            guard let self else { return }
            self.isForumFavorite = await ForumFavoriteService.isFavorite(forumId: self.forum.id)
            await self.reloadReadState(refreshTimes: true)
        }
    }

    /// 黑名单或屏蔽词变更:当前可见就重新拉取第一页,否则等下次进入列表时刷新
    @objc private func blacklistDidChange() {
        guard viewIfLoaded?.window != nil, navigationController?.topViewController === self else {
            needsBlacklistReload = true
            return
        }
        if isLoading {
            needsBlacklistReload = true
        } else {
            reloadFirstPage()
        }
    }

    private func reloadReadState(refreshTimes: Bool = false) async {
        let history = await HistoryService.entries()
        let ids = Set(history.map(\.threadId))
        let counts = await DbThreadService.entries(threadIds: ids.sorted())
        var changed = false
        if ids != readThreadIds {
            readThreadIds = ids
            changed = true
        }
        let newCounts = counts.mapValues(\.lastCountWhenView)
        if newCounts != lastReplyCounts {
            lastReplyCounts = newCounts
            changed = true
        }
        // 相对时间会随停留时间变旧,回到列表时即使已读状态没变也重跑一次配置
        if changed || refreshTimes {
            reconfigureThreadCells()
        }
    }

    /// 已读状态与相对时间烘在 cell 配置里:对现有 item 走 reconfigure 重跑 cell provider,
    /// 不能用 reloadData(与 diffable data source 混用会破坏其内部快照状态)
    private func reconfigureThreadCells() {
        guard let dataSource else { return }
        var snapshot = dataSource.snapshot()
        let threadItems = snapshot.itemIdentifiers.filter {
            if case .thread = $0 { return true } else { return false }
        }
        guard !threadItems.isEmpty else { return }
        snapshot.reconfigureItems(threadItems)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func setupCollectionView() {
        var listConfig = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        listConfig.showsSeparators = true
        // list section 默认自绘系统背景,必须显式指定,否则盖住页面米白
        listConfig.backgroundColor = Theme.background
        let layout = UICollectionViewCompositionalLayout { sectionIndex, environment in
            let section = NSCollectionLayoutSection.list(using: listConfig, layoutEnvironment: environment)
            // insetGrouped 的 section 横向 inset 会与 cell 的 16pt 内容边距叠加,
            // 归零后左右回到系统标准的 16pt 内容边距。
            section.contentInsets.leading = 0
            section.contentInsets.trailing = 0
            return section
        }
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = Theme.background
        collectionView.delegate = self

        let refresh = UIRefreshControl()
        refresh.addAction(UIAction { [weak self] _ in self?.reloadFirstPage(forceRefresh: true) }, for: .valueChanged)
        collectionView.refreshControl = refresh

        let threadRegistration = UICollectionView.CellRegistration<ThreadCell, Thread> { [weak self] cell, _, thread in
            guard let self else { return }
            var thread = thread
            thread.lastReplyCount = self.lastReplyCounts[thread.id] ?? 0
            let isRead = self.readThreadIds.contains(thread.id)
            cell.configure(thread, isRead: isRead)
        }
        let footerRegistration = UICollectionView.CellRegistration<FooterCell, ListItem> { [weak self] cell, _, item in
            if case let .footer(isLoading, canLoadMore, error) = item {
                cell.configure(isLoading: isLoading, canLoadMore: canLoadMore, error: error) {
                    self?.loadNextPage()
                }
            }
        }

        dataSource = UICollectionViewDiffableDataSource<Int, ListItem>(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case let .thread(thread):
                return collectionView.dequeueConfiguredReusableCell(using: threadRegistration, for: indexPath, item: thread)
            case .footer:
                return collectionView.dequeueConfiguredReusableCell(using: footerRegistration, for: indexPath, item: item)
            }
        }

        view.addSubview(collectionView)
        setupPlaceholder()
    }

    private func makeMenu() -> UIMenu {
        var children: [UIMenuElement] = []
        children.append(UIAction(title: "发新主题", image: UIImage(systemName: "square.and.pencil")) { [weak self] _ in
            guard let self else { return }
            guard SessionStore.shared.state.isLoggedIn else {
                self.present(LoginViewController(), animated: true)
                return
            }
            self.present(UINavigationController(rootViewController: NewThreadViewController(forumId: self.forum.id, forumName: self.forum.name)), animated: true)
        })
        if !threadTypes.isEmpty {
            var typeActions: [UIAction] = [
                UIAction(title: "全部类型", state: selectedTypeId == nil ? .on : .off) { [weak self] _ in
                    self?.selectedTypeId = nil
                    self?.reloadFirstPage()
                }
            ]
            for (id, name) in threadTypes.sorted(by: { $0.key < $1.key }) {
                typeActions.append(UIAction(title: name, state: selectedTypeId == id ? .on : .off) { [weak self] _ in
                    self?.selectedTypeId = id
                    self?.reloadFirstPage()
                })
            }
            children.append(UIMenu(title: "按类型筛选", image: UIImage(systemName: "line.3.horizontal.decrease"), children: typeActions))
        }
        if !subForums.isEmpty {
            children.append(UIMenu(
                title: "子版块",
                image: UIImage(systemName: "square.stack.3d.up"),
                children: subForums.map { forum in
                    UIAction(title: forum.displayName) { [weak self] _ in
                        self?.navigationController?.pushViewController(ThreadListViewController(forum: forum), animated: true)
                    }
                }
            ))
        }
        children.append(makeFavoriteMenuAction())
        return UIMenu(children: children)
    }

    /// 收藏/取消收藏当前版块(本地 forumfavorite 表)
    private func makeFavoriteMenuAction() -> UIAction {
        UIAction(
            title: isForumFavorite ? "取消收藏版块" : "收藏版块",
            image: UIImage(systemName: isForumFavorite ? "star.slash" : "star"),
        ) { [weak self] _ in
            guard let self else { return }
            Task {
                await ForumFavoriteService.toggle(forum: self.forum)
                self.isForumFavorite.toggle()
                Toast.show(self.isForumFavorite ? "已收藏版块" : "已取消收藏", in: self.view)
            }
        }
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

    // MARK: - Data

    private func reloadFirstPage(forceRefresh: Bool = false) {
        guard !isLoading else { return }
        isLoading = true
        canLoadMore = true
        footerError = nil
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            let cacheKey = await ResponseCacheService.threadsKey(fid: forum.id, typeId: selectedTypeId, page: 1)

            // 缓存先行:秒开,后台继续刷新(下拉刷新跳过)
            if !forceRefresh, let cached = await ResponseCacheService.json(forKey: cacheKey) {
                let cachedResult = DiscuzAPI.parseThreads(cached)
                guard !Task.isCancelled else { return }
                self.threads = self.filter(cachedResult.threads)
                self.threadTypes = cachedResult.threadTypes
                self.subForums = cachedResult.subForums
                self.page = 1
                self.canLoadMore = !cachedResult.threads.isEmpty
                self.applySnapshot(animating: false)
                self.placeholder.isHidden = !self.threads.isEmpty
                self.collectionView.refreshControl?.endRefreshing()
            } else {
                placeholder.state = .loading("正在加载主题")
            }

            do {
                let result = try await DiscuzAPI.shared.threads(fid: forum.id, page: 1, typeId: self.selectedTypeId)
                guard !Task.isCancelled else { return }
                self.threads = self.filter(result.threads)
                self.threadTypes = result.threadTypes
                self.subForums = result.subForums
                self.page = 1
                self.canLoadMore = !result.threads.isEmpty
                self.isLoading = false
                self.footerError = nil
                self.applySnapshot(animating: false)
                self.placeholder.isHidden = !self.threads.isEmpty
                if self.threads.isEmpty {
                    self.placeholder.state = .empty(icon: "tray", title: "暂无主题", message: "这个版块还没有主题")
                }
                self.collectionView.refreshControl?.endRefreshing()
            } catch {
                guard !Task.isCancelled else { return }
                self.isLoading = false
                self.collectionView.refreshControl?.endRefreshing()
                // 已有缓存内容:静默降级为 footer 提示,不清屏
                if !self.threads.isEmpty {
                    self.footerError = (error as? LocalizedError)?.errorDescription ?? "加载失败"
                    self.applySnapshot(animating: false)
                    return
                }
                if self.threads.isEmpty {
                    self.renderError(error)
                } else {
                    self.footerError = (error as? LocalizedError)?.errorDescription ?? "加载失败"
                    self.applySnapshot(animating: false)
                }
            }
        }
    }

    private func loadNextPage() {
        guard !isLoading, canLoadMore, page > 0 else { return }
        isLoading = true
        footerError = nil
        applySnapshot(animating: false)
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await DiscuzAPI.shared.threads(fid: forum.id, page: self.page + 1, typeId: self.selectedTypeId)
                guard !Task.isCancelled else { return }
                // 分页接口每页都会重复携带置顶帖
                self.threads.appendUniqued(contentsOf: self.filter(result.threads), by: \.id)
                self.page += 1
                self.canLoadMore = !result.threads.isEmpty
                self.isLoading = false
                self.applySnapshot(animating: false)
            } catch {
                guard !Task.isCancelled else { return }
                self.isLoading = false
                self.footerError = (error as? LocalizedError)?.errorDescription ?? "加载失败"
                self.applySnapshot(animating: false)
            }
        }
    }

    /// 黑名单 + 屏蔽词过滤(模型组装层,对齐 S1-Next Threads.getFilterThread)
    private func filter(_ input: [Thread]) -> [Thread] {
        let snapshot = BlacklistService.shared.snapshot
        var output: [Thread] = []
        output.reserveCapacity(input.count)
        for var thread in input.uniqued(by: \.id) {
            switch snapshot.forumLevel(uid: thread.authorId, name: thread.author) {
            case 4: continue
            case 3: thread.isHiddenByBlacklist = true
            default: break
            }
            if !thread.isHiddenByBlacklist {
                switch snapshot.wordLevel(in: thread.title) {
                case 2: continue
                case 1: thread.isHiddenByBlacklist = true
                default: break
                }
            }
            output.append(thread)
        }
        return output
    }

    private func applySnapshot(animating: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Int, ListItem>()
        snapshot.appendSections([0])
        // 兜底:同一 tid 两次出现会让 diffable data source 抛 IDENTIFIER_ALREADY_EXISTS
        var items = threads.uniqued(by: \.id).map { ListItem.thread($0) }
        items.append(.footer(isLoading: isLoading, canLoadMore: canLoadMore, error: footerError))
        snapshot.appendItems(items)
        dataSource.apply(snapshot, animatingDifferences: animating)
    }

    private func renderError(_ error: Error) {
        placeholder.state = .error(
            icon: "wifi.exclamationmark",
            title: "主题加载失败",
            message: (error as? LocalizedError)?.errorDescription ?? "请稍后重试",
            retry: { [weak self] in self?.reloadFirstPage() }
        )
    }
}

extension ThreadListViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath), case let .thread(thread) = item else { return }
        guard !thread.isHiddenByBlacklist else { return }
        let controller = PostListViewController(threadId: thread.id, threadTitle: thread.title)
        navigationController?.pushViewController(controller, animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath), case .footer = item else { return }
        if !isLoading, canLoadMore, footerError == nil {
            loadNextPage()
        }
    }
}
