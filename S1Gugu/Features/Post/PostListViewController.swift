import UIKit
import SnapKit

/// 帖子详情:每楼层一个 Section(楼层头 + 内容块 + 屏蔽占位),40 楼/页。
@MainActor
final class PostListViewController: UIViewController {

    // MARK: - Section / Item

    private enum Item: Hashable {
        case header(PostHeaderModel)
        case block(PostBlock)
        case hidden(remark: String?)
        case vote(VoteInfo)
    }

    // MARK: - State

    private let threadId: Int
    private let threadTitle: String
    private var forumId: Int?
    private var filterAuthorId: Int?
    private var initialPage: Int?
    private var initialAnchorPid: Int?

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, Item>!
    private let placeholder = StatefulPlaceholderView()

    private var posts: [Post] = []
    private var currentVote: VoteInfo?
    private var blocksByPid: [Int: [PostBlock]] = [:]
    private var galleryImages: [PostImage] = []
    private var currentPage = 0
    private var pageCount = 1
    private var isLoading = false
    private var footerError: String?
    private var loadTask: Task<Void, Never>?
    private var didRecordHistory = false
    private let quickSideBar = QuickSideBarView(frame: .zero)
    private let sideBarBubble = UILabel()
    private let pagerBar = PostPagerBar()

    init(threadId: Int, threadTitle: String, jumpPage: Int? = nil, anchorPid: Int? = nil) {
        self.threadId = threadId
        self.threadTitle = threadTitle
        self.initialPage = jumpPage
        self.initialAnchorPid = anchorPid
        super.init(nibName: nil, bundle: nil)
        // 帖子详情沉浸阅读:隐藏全局 TabBar,改用底部功能栏(导航栏保留)
        hidesBottomBarWhenPushed = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.contentBackground
        navigationItem.title = threadTitle
        setupPagerBar()
        setupCollectionView()
        setupPageNavigation()
        NotificationCenter.default.addObserver(
            self, selector: #selector(postDidChange),
            name: .postDidChange, object: nil
        )
        setupQuickSideBar()

        Task { [weak self] in
            await BlacklistService.shared.reloadIfNeeded()
            guard let self else { return }
            if self.initialPage == nil, AppSettings.autoRestoreProgress,
               let progress = await ReadProgressService.progress(for: self.threadId) {
                self.initialPage = progress.page
                self.initialAnchorPid = progress.anchorPid
            }
            self.loadPage(initialPage ?? 1, anchorPid: initialAnchorPid, replace: true)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveReadProgress()
    }

    private func setupQuickSideBar() {
        guard AppSettings.quickSideBarEnabled else { return }
        quickSideBar.isHidden = true
        view.addSubview(quickSideBar)
        quickSideBar.snp.makeConstraints { make in
            make.trailing.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide).offset(24)
            make.bottom.equalTo(pagerBar.snp.top).offset(-24)
            make.width.equalTo(20)
        }
        quickSideBar.onIndexChange = { [weak self] index in
            self?.jumpToSidebarIndex(index)
        }
        quickSideBar.onTouchEnd = { [weak self] in
            self?.sideBarBubble.removeFromSuperview()
        }

        sideBarBubble.numberOfLines = 0
        sideBarBubble.textAlignment = .center
        sideBarBubble.font = .monospacedDigitSystemFont(ofSize: 20, weight: .bold)
        sideBarBubble.textColor = .white
        sideBarBubble.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        sideBarBubble.layer.cornerRadius = 12
        sideBarBubble.clipsToBounds = true
    }

    /// 字母索引 → 楼层 section 等比映射 + 中央气泡
    private func jumpToSidebarIndex(_ index: Int) {
        guard !posts.isEmpty else { return }
        let target = min(index * posts.count / QuickSideBarView.letters.count, posts.count - 1)
        collectionView.scrollToItem(at: IndexPath(item: 0, section: target), at: .top, animated: false)
        let letter = QuickSideBarView.letters[index]
        let floor = posts[target].floor ?? target + 1
        if sideBarBubble.superview == nil {
            view.addSubview(sideBarBubble)
        }
        sideBarBubble.text = "\(letter)\n\(floor)楼"
        sideBarBubble.snp.remakeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalTo(88)
            make.height.equalTo(88)
        }
        view.bringSubviewToFront(sideBarBubble)
    }

    /// 楼层加载后显隐侧边条
    private func updateSideBarVisibility() {
        guard AppSettings.quickSideBarEnabled else { return }
        quickSideBar.isHidden = posts.count < 5
    }

    @objc private func postDidChange() {
        guard currentPage > 0 else { return }
        loadPage(currentPage, replace: true)
    }

    private func openReply(quotePost: Post?) {
        guard SessionStore.shared.state.isLoggedIn else {
            present(LoginViewController(), animated: true)
            return
        }
        present(UINavigationController(rootViewController: ReplyViewController(threadId: threadId, quotePost: quotePost)), animated: true)
    }

    // MARK: - UI Setup

    private func setupCollectionView() {
        let layout = UICollectionViewCompositionalLayout { [weak self] sectionIndex, environment in
            self?.makeSectionLayout(environment: environment) ?? NSCollectionLayoutSection(group: .vertical(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(1)), subitems: []))
        }
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = Theme.contentBackground
        collectionView.delegate = self

        let headerRegistration = UICollectionView.CellRegistration<PostHeaderCell, PostHeaderModel> { [weak self] cell, _, model in
            cell.configure(model)
            cell.onAvatarTap = {
                guard let self, model.authorId > 0 else { return }
                self.navigationController?.pushViewController(UserHomeViewController(uid: String(model.authorId)), animated: true)
            }
        }
        let textRegistration = UICollectionView.CellRegistration<TextBlockCell, AttributedText> { [weak self] cell, _, attributed in
            cell.configure(attributed.value)
            cell.onLinkTap = { url in
                guard let self else { return }
                LinkRouter.handle(url, from: self)
            }
        }
        let imageRegistration = UICollectionView.CellRegistration<ImageBlockCell, PostImage> { [weak self] cell, _, image in
            cell.configure(image, index: 0) { [weak self] postImage in
                self?.openGallery(postImage)
            }
        }
        let quoteRegistration = UICollectionView.CellRegistration<QuoteBlockCell, (String?, AttributedText)> { [weak self] cell, _, payload in
            cell.configure(author: payload.0, attributed: payload.1.value)
            cell.onLinkTap = { url in
                guard let self else { return }
                LinkRouter.handle(url, from: self)
            }
        }
        let codeRegistration = UICollectionView.CellRegistration<CodeBlockCell, String> { cell, _, code in
            cell.configure(code)
        }
        let fileRegistration = UICollectionView.CellRegistration<FileAttachmentCell, PostFileAttachment> { [weak self] cell, _, file in
            cell.configure(file) { [weak self] url in
                guard let self else { return }
                let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                self.present(activity, animated: true)
            }
        }
        let hiddenRegistration = UICollectionView.CellRegistration<HiddenPostCell, String?> { cell, _, remark in
            cell.configure(remark: remark)
        }
        let voteRegistration = UICollectionView.CellRegistration<VoteCell, VoteInfo> { [weak self] cell, _, vote in
            cell.configure(vote) { [weak self] optionIds in
                self?.submitVote(optionIds)
            }
        }

        dataSource = UICollectionViewDiffableDataSource<Int, Item>(collectionView: collectionView) { [weak self] collectionView, indexPath, item in
            guard let self else { return UICollectionViewCell() }
            switch item {
            case let .header(model):
                return collectionView.dequeueConfiguredReusableCell(using: headerRegistration, for: indexPath, item: model)
            case let .block(block):
                switch block {
                case let .text(attributed):
                    return collectionView.dequeueConfiguredReusableCell(using: textRegistration, for: indexPath, item: attributed)
                case let .image(image):
                    return collectionView.dequeueConfiguredReusableCell(using: imageRegistration, for: indexPath, item: image)
                case let .quote(author, attributed):
                    return collectionView.dequeueConfiguredReusableCell(using: quoteRegistration, for: indexPath, item: (author, attributed))
                case let .code(code):
                    return collectionView.dequeueConfiguredReusableCell(using: codeRegistration, for: indexPath, item: code)
                case let .fileAttachment(file):
                    return collectionView.dequeueConfiguredReusableCell(using: fileRegistration, for: indexPath, item: file)
                case let .fallback(attributed):
                    return collectionView.dequeueConfiguredReusableCell(using: textRegistration, for: indexPath, item: attributed)
                }
            case let .hidden(remark):
                return collectionView.dequeueConfiguredReusableCell(using: hiddenRegistration, for: indexPath, item: remark)
            case let .vote(vote):
                return collectionView.dequeueConfiguredReusableCell(using: voteRegistration, for: indexPath, item: vote)
            }
        }

        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(pagerBar.snp.top)
        }
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.topAnchor.constraint(equalTo: collectionView.topAnchor),
            placeholder.bottomAnchor.constraint(equalTo: collectionView.bottomAnchor),
            placeholder.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            placeholder.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        // 底部功能栏需始终浮在列表/占位之上
        view.bringSubviewToFront(pagerBar)
    }

    private func makeSectionLayout(environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        var config = UICollectionLayoutListConfiguration(appearance: .plain)
        config.showsSeparators = false
        // list section 默认自绘系统背景,必须显式指定,否则盖住页面米白
        config.backgroundColor = Theme.contentBackground
        return NSCollectionLayoutSection.list(using: config, layoutEnvironment: environment)
    }

    private func setupPageNavigation() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: makeMenu()
        )
    }

    private func setupPagerBar() {
        view.addSubview(pagerBar)
        pagerBar.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalToSuperview()
        }
        pagerBar.onPrevious = { [weak self] in
            guard let self, let target = PostPagerState(currentPage: self.currentPage, pageCount: self.pageCount).previousTarget else { return }
            self.jumpToPage(target)
        }
        pagerBar.onNext = { [weak self] in
            guard let self, let target = PostPagerState(currentPage: self.currentPage, pageCount: self.pageCount).nextTarget else { return }
            self.jumpToPage(target)
        }
        pagerBar.onProgress = { [weak self] in
            self?.presentPageJumpSheet()
        }
        pagerBar.onReply = { [weak self] in
            self?.openReply(quotePost: nil)
        }
        pagerBar.onShare = { [weak self] in
            self?.shareCurrentPage()
        }
    }

    private func refreshPagerBar() {
        pagerBar.update(currentPage: currentPage, pageCount: pageCount)
    }

    private func presentPageJumpSheet() {
        guard pageCount >= 1, currentPage >= 1 else { return }
        let sheet = PageJumpSheetViewController(total: pageCount, current: currentPage) { [weak self] page in
            self?.jumpToPage(page)
        }
        present(sheet, animated: true)
    }

    private func shareCurrentPage() {
        let url = LinkRouter.threadURL(tid: threadId, page: max(currentPage, 1))
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = pagerBar
        present(activity, animated: true)
    }

    private func makeMenu() -> UIMenu {
        var actions: [UIAction] = []
        actions.append(UIAction(title: "收藏本帖", image: UIImage(systemName: "star")) { [weak self] _ in
            self?.addFavorite()
        })
        actions.append(UIAction(title: "页内搜索", image: UIImage(systemName: "text.magnifyingglass")) { [weak self] _ in
            self?.showInPageSearch()
        })
        actions.append(UIAction(title: "只看楼主", image: UIImage(systemName: "person.crop.circle.badge.clock")) { [weak self] _ in
            guard let self, let authorId = self.posts.first(where: { $0.isFirst })?.authorId, authorId > 0 else { return }
            self.toggleAuthorFilter(authorId: authorId, name: self.posts.first(where: { $0.isFirst })?.author)
        })
        if filterAuthorId != nil {
            actions.append(UIAction(title: "显示全部楼层", image: UIImage(systemName: "line.3.horizontal")) { [weak self] _ in
                self?.toggleAuthorFilter(authorId: nil, name: nil)
            })
        }
        actions.append(UIAction(title: "备份全帖(离线)", image: UIImage(systemName: "arrow.down.doc")) { [weak self] _ in
            self?.backupWholeThread()
        })
        actions.append(UIAction(title: "在浏览器打开", image: UIImage(systemName: "safari")) { [weak self] _ in
            guard let self else { return }
            LinkRouter.handle(LinkRouter.threadURL(tid: self.threadId, page: max(self.currentPage, 1)), from: self)
        })
        return UIMenu(children: actions)
    }

    // MARK: - Data

    private func loadPage(_ page: Int, anchorPid: Int? = nil, replace: Bool) {
        guard !isLoading else { return }
        isLoading = true
        if replace {
            placeholder.state = .loading("正在加载帖子")
        }
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            // 缓存先行(replace 时秒开,后台继续刷新)
            if replace, let cached = await ResponseCacheService.json(
                forKey: await ResponseCacheService.postsKey(tid: self.threadId, page: page, authorId: self.filterAuthorId)
            ) {
                let cachedResult = DiscuzAPI.parsePosts(cached)
                guard !Task.isCancelled else { return }
                self.forumId = cachedResult.forumId
                let filtered = self.filterPosts(cachedResult.posts)
                self.pageCount = max(cachedResult.pageCount, 1)
                let (parsedBlocks, pageImages) = await self.parseBlocks(posts: filtered)
                self.posts = filtered
                self.blocksByPid = parsedBlocks
                self.galleryImages = pageImages
                self.currentVote = cachedResult.vote
                self.currentPage = page
                self.isLoading = true
                self.footerError = nil
                self.applySnapshot()
                self.updateSideBarVisibility()
                self.placeholder.isHidden = !self.posts.isEmpty
                if self.posts.isEmpty {
                    self.placeholder.state = .empty(icon: "doc.text", title: "暂无内容", message: "这个主题还没有可显示的楼层")
                    self.placeholder.isHidden = false
                }
                if let anchorPid, let index = self.posts.firstIndex(where: { $0.pid == anchorPid }) {
                    DispatchQueue.main.async { [weak self] in
                        self?.collectionView.scrollToItem(at: IndexPath(item: 0, section: index), at: .top, animated: false)
                    }
                }
            }
            do {
                let result = try await DiscuzAPI.shared.posts(tid: self.threadId, page: page, authorId: self.filterAuthorId)
                guard !Task.isCancelled else { return }

                self.forumId = result.forumId
                let filtered = self.filterPosts(result.posts)
                self.pageCount = max(result.pageCount, 1)
                let (parsedBlocks, pageImages) = await self.parseBlocks(posts: filtered)

                guard !Task.isCancelled else { return }
                if replace {
                    self.posts = filtered
                    self.blocksByPid = [:]
                    self.galleryImages = []
                    self.currentVote = result.vote
                } else {
                    // 翻页边界 API 可能重复返回上一页末楼
                    self.posts.appendUniqued(contentsOf: filtered, by: \.pid)
                }
                for (pid, blocks) in parsedBlocks {
                    self.blocksByPid[pid] = blocks
                }
                self.galleryImages += pageImages
                self.currentPage = page
                self.isLoading = false
                self.footerError = nil
                // 跳转进入时的标题是占位(主题 #tid),用接口返回的真实标题覆盖
                if let subject = result.thread?.subject, !subject.isEmpty {
                    self.navigationItem.title = subject
                }
                self.applySnapshot()
                self.updateSideBarVisibility()
                self.placeholder.isHidden = !self.posts.isEmpty
                if self.posts.isEmpty {
                    self.placeholder.state = .empty(icon: "doc.text", title: "暂无内容", message: "这个主题还没有可显示的楼层")
                }
                if !self.didRecordHistory {
                    self.didRecordHistory = true
                    await HistoryService.add(threadId: self.threadId, title: result.thread?.subject ?? self.threadTitle)
                }
                // 记录本次浏览时的回复总数,供版块列表计算「+N 新回复」
                if let replies = result.thread?.replies, let count = Int(replies), count > 0 {
                    await DbThreadService.save(threadId: self.threadId, replyCount: count)
                }
                // 阅读进度恢复:定位到锚点楼层
                if let anchorPid, let index = self.posts.firstIndex(where: { $0.pid == anchorPid }), replace {
                    DispatchQueue.main.async { [weak self] in
                        self?.collectionView.scrollToItem(at: IndexPath(item: 0, section: index), at: .top, animated: false)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                // 离线回退:有整帖备份时读备份
                if self.posts.isEmpty, let offline = await PostBackupService.offlinePages(threadId: self.threadId),
                   let target = offline.pages.first(where: { $0.page == page }) {
                    let summary = PostsResult.ThreadSummary(tid: String(self.threadId), subject: offline.subject, replies: "0", author: "", authorId: 0, maxposition: nil)
                    let assembled = target.posts.map { PostAssembler.assemble($0, threadAuthor: summary.author) }
                    self.forumId = nil
                    self.posts = self.filterPosts(assembled)
                    let parsed = await self.parseBlocks(posts: self.posts)
                    self.blocksByPid = parsed.blocks
                    self.galleryImages = self.collectImages()
                    self.currentPage = page
                    self.pageCount = offline.pages.count
                    self.isLoading = false
                    self.applySnapshot()
                    self.placeholder.isHidden = true
                    Toast.show("离线备份内容(第 \(page) 页)", in: self.view)
                    return
                }
                self.isLoading = false
                if self.posts.isEmpty {
                    self.renderError(error)
                } else {
                    // 目标页加载失败但仍保留着上一页内容(典型:胶囊跳页回第一页时服务端 503)。
                    // 必须收起整页 loading,否则会一直停在「正在加载帖子」——既看不到内容也没有报错。
                    let reason = (error as? LocalizedError)?.errorDescription ?? "加载失败"
                    self.footerError = reason
                    self.applySnapshot()
                    self.placeholder.isHidden = true
                    Toast.show("第 \(page) 页加载失败:\(reason)", in: self.view)
                }
            }
        }
    }

    private func loadNextPage() {
        guard !isLoading, currentPage > 0, currentPage < pageCount else { return }
        loadPage(currentPage + 1, replace: false)
    }

    private func jumpToPage(_ page: Int) {
        guard page >= 1, page <= pageCount, page != currentPage else { return }
        loadPage(page, replace: true)
    }

    /// 黑名单/屏蔽词过滤(模型组装层,对齐 S1-Next Posts.filterPostList)
    private func filterPosts(_ input: [Post]) -> [Post] {
        let snapshot = BlacklistService.shared.snapshot
        var output: [Post] = []
        output.reserveCapacity(input.count)
        for var post in input.uniqued(by: \.pid) {
            if post.isFirst {
                // 主楼标题也可命中屏蔽词
                if snapshot.wordLevel(in: threadTitle) == 2 { continue }
            }
            switch snapshot.postLevel(uid: post.authorId, name: post.author) {
            case 2: continue
            case 1:
                post.hideFlag = 1
                post.hideRemark = snapshot.matchedRemark(uid: post.authorId, name: post.author)
            default: break
            }
            if post.hideFlag == 0, snapshot.wordLevel(in: post.preprocessedHTML) == 2 { continue }
            if post.hideFlag == 0, snapshot.wordLevel(in: post.preprocessedHTML) == 1 {
                post.hideFlag = 1
                post.hideRemark = nil
            }
            output.append(post)
        }
        return output
    }

    private func collectImages() -> [PostImage] {
        posts.flatMap { post in
            (blocksByPid[post.pid] ?? []).compactMap { block -> PostImage? in
                if case let .image(image) = block { return image }
                return nil
            }
        }
    }

    private func parseBlocks(posts: [Post]) async -> (blocks: [Int: [PostBlock]], images: [PostImage]) {
        let snapshot = BlacklistService.shared.snapshot
        let quoteReplacer: @Sendable (String) -> String? = { snapshot.quoteReplacement(author: $0) }
        let baseURL = S1APIClient.shared.baseURL
        let result = await Task.detached(priority: .userInitiated) { () -> ([Int: [PostBlock]], [PostImage]) in
            var blocksMap: [Int: [PostBlock]] = [:]
            var images: [PostImage] = []
            for post in posts {
                // 全部附件(含图片附件)交给拆分器:移动 API 游客态不内嵌附件图,补到块尾
                let extras = post.attachments.sorted(by: { $0.key < $1.key }).map(\.value)
                let blocks = BlockSplitter.split(
                    html: post.preprocessedHTML,
                    baseURL: baseURL,
                    quoteReplacer: quoteReplacer,
                    extraAttachments: extras
                )
                blocksMap[post.pid] = blocks
                for block in blocks {
                    if case let .image(image) = block { images.append(image) }
                }
            }
            return (blocksMap, images)
        }.value
        return (result.0, result.1)
    }

    // MARK: - Snapshot

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, Item>()
        // 兜底:同一 pid 两次出现会让 diffable data source 抛 IDENTIFIER_ALREADY_EXISTS
        for post in posts.uniqued(by: \.pid) {
            snapshot.appendSections([post.pid])
            if post.hideFlag == 1 {
                snapshot.appendItems([.hidden(remark: post.hideRemark)], toSection: post.pid)
                continue
            }
            let header = PostHeaderModel(
                pid: post.pid,
                author: post.author,
                authorId: post.authorId,
                avatarURL: post.avatarURL,
                dateTimeText: post.dateTimeText,
                floor: post.floor,
                isOp: post.isOp
            )
            snapshot.appendItems([.header(header)], toSection: post.pid)
            if post.isFirst, let vote = currentVote {
                snapshot.appendItems([.vote(vote)], toSection: post.pid)
            }
            for block in blocksByPid[post.pid] ?? [] {
                snapshot.appendItems([.block(block)], toSection: post.pid)
            }
        }
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            self?.updateTitleView()
        }
    }

    private func updateTitleView() {
        title = "\(threadTitle)(\(currentPage)/\(pageCount))"
        navigationItem.rightBarButtonItem?.menu = makeMenu()
        refreshPagerBar()
    }

    private func renderError(_ error: Error) {
        NetworkLog.net.error("帖子加载失败 tid=\(self.threadId, privacy: .public) page=\(self.currentPage, privacy: .public) error=\(String(describing: error), privacy: .public)")
        placeholder.state = .error(
            icon: "wifi.exclamationmark",
            title: "帖子加载失败",
            message: (error as? LocalizedError)?.errorDescription ?? "请稍后重试",
            retry: { [weak self] in
                self?.initialPage = max(self?.currentPage ?? 1, 1)
                self?.loadPage(self?.initialPage ?? 1, replace: true)
            }
        )
    }

    // MARK: - 阅读进度

    private func saveReadProgress() {
        guard AppSettings.autoSaveProgress, currentPage > 0 else { return }
        let visibleSections = collectionView.indexPathsForVisibleItems.map(\.section)
        guard let firstSection = visibleSections.min(), posts.indices.contains(firstSection) else { return }
        let anchorPid = posts[firstSection].pid
        let page = currentPage
        Task { await ReadProgressService.save(threadId: threadId, page: page, anchorPid: anchorPid) }
    }

    // MARK: - M3:投票 / 备份 / 长图 / 页内搜索 / 只看他

    private func submitVote(_ optionIds: [Int]) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await DiscuzAPI.shared.votePoll(tid: self.threadId, optionIds: optionIds)
                Toast.show("投票成功", in: self.view ?? UIView())
                self.loadPage(self.currentPage, replace: true)
            } catch {
                Toast.show((error as? LocalizedError)?.errorDescription ?? "投票失败", in: self.view ?? UIView())
            }
        }
    }

    private func backupWholeThread() {
        let alert = UIAlertController(title: "备份全帖", message: "将逐页抓取全部 \(pageCount) 页并保存到本机(约 \(pageCount * 1)s)", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "开始备份", style: .default) { [weak self] _ in
            guard let self else { return }
            Task {
                do {
                    try await PostBackupService.backupWholeThread(threadId: self.threadId, pageCount: self.pageCount) { done, total, _ in
                        Toast.show("备份中 \(done)/\(total) 页…", in: self.view ?? UIView())
                    }
                    Toast.show("备份完成,可在「我的 - 帖子备份」离线阅读", in: self.view ?? UIView())
                } catch {
                    Toast.show((error as? LocalizedError)?.errorDescription ?? "备份失败", in: self.view ?? UIView())
                }
            }
        })
        present(alert, animated: true)
    }

    private func sharePostAsImage(_ post: Post) {
        let blocks = blocksByPid[post.pid] ?? []
        let url = LinkRouter.threadURL(tid: threadId, page: max(currentPage, 1))
        Task { [weak self] in
            guard let self else { return }
            let image = await ShareCardRenderer.render(
                post: post,
                blocks: blocks,
                threadTitle: self.navigationItem.title ?? self.threadTitle,
                threadURL: url
            )
            let activity = UIActivityViewController(activityItems: [image], applicationActivities: nil)
            self.present(activity, animated: true)
        }
    }

    private func showInPageSearch() {
        let alert = UIAlertController(title: "页内搜索", message: "在已加载的楼层中搜索", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "关键词或用户名" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "搜索", style: .default) { [weak self] _ in
            guard let self, let keyword = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !keyword.isEmpty
            else { return }
            self.locateInPage(keyword: keyword)
        })
        present(alert, animated: true)
    }

    private func locateInPage(keyword: String) {
        for (index, post) in posts.enumerated() where post.hideFlag == 0 {
            let hitAuthor = post.author.localizedCaseInsensitiveContains(keyword)
            let hitBody = blocksByPid[post.pid]?.contains { block in
                switch block {
                case let .text(attributed), let .fallback(attributed), let .quote(_, attributed):
                    return attributed.value.string.localizedCaseInsensitiveContains(keyword)
                case let .code(code):
                    return code.localizedCaseInsensitiveContains(keyword)
                default: return false
                }
            } ?? false
            if hitAuthor || hitBody {
                collectionView.scrollToItem(at: IndexPath(item: 0, section: index), at: .top, animated: true)
                Toast.show("定位到 \(post.floor ?? index + 1) 楼", in: view)
                return
            }
        }
        Toast.show("已加载楼层中未找到", in: view)
    }

    private func toggleAuthorFilter(authorId: Int?, name: String?) {
        filterAuthorId = authorId
        reloadWithFilter(name: name)
    }

    private func reloadWithFilter(name: String?) {
        let base = threadTitle
        navigationItem.title = filterAuthorId != nil ? "\(name ?? "只看该用户")的楼层" : base
        loadPage(1, replace: true)
    }

    // MARK: - 收藏

    private func addFavorite() {
        guard SessionStore.shared.state.isLoggedIn else {
            present(LoginViewController(), animated: true)
            return
        }
        let alert = UIAlertController(title: "收藏本帖", message: threadTitle, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "备注(可选)"
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "收藏", style: .default) { [weak self] _ in
            guard let self else { return }
            Task {
                do {
                    try await DiscuzAPI.shared.addFavorite(tid: self.threadId, description: alert.textFields?.first?.text ?? "")
                    Toast.show("已收藏", in: self.view ?? UIView())
                } catch {
                    Toast.show((error as? LocalizedError)?.errorDescription ?? "收藏失败", in: self.view ?? UIView())
                }
            }
        })
        present(alert, animated: true)
    }

    // MARK: - Gallery

    private func openGallery(_ tapped: PostImage) {
        guard let index = galleryImages.firstIndex(where: { $0.url == tapped.url }) else { return }
        let gallery = GalleryViewController(images: galleryImages, startIndex: index)
        present(gallery, animated: false)
    }
}

// MARK: - UICollectionViewDelegate

extension PostListViewController: UICollectionViewDelegate {

    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        // 滚动到最后一节时加载下一页
        if indexPath.section >= posts.count - 2, !isLoading, currentPage > 0, currentPage < pageCount, footerError == nil {
            loadNextPage()
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard posts.indices.contains(indexPath.section) else { return nil }
        let post = posts[indexPath.section]
        guard post.hideFlag == 0 else { return nil }

        let copyText = UIAction(
            title: "复制楼层文本",
            image: UIImage(systemName: "doc.on.doc")
        ) { [weak self] _ in
            guard let self else { return }
            let blocks = self.blocksByPid[post.pid] ?? []
            let text = blocks.compactMap { block -> String? in
                switch block {
                case let .text(attributed), let .fallback(attributed), let .quote(_, attributed):
                    return attributed.value.string
                case let .code(code):
                    return code
                default: return nil
                }
            }.joined(separator: "\n")
            UIPasteboard.general.string = text
            Toast.show("已复制", in: self.view ?? UIView())
        }
        let copyLink = UIAction(
            title: "复制楼层链接",
            image: UIImage(systemName: "link")
        ) { [weak self] _ in
            guard let self else { return }
            UIPasteboard.general.string = LinkRouter.threadURL(tid: self.threadId, page: max(self.currentPage, 1)).absoluteString
            Toast.show("已复制链接", in: self.view ?? UIView())
        }
        let favorite = UIAction(
            title: "收藏本帖",
            image: UIImage(systemName: "star")
        ) { [weak self] _ in
            self?.addFavorite()
        }
        let shareCard = UIAction(
            title: "生成长图",
            image: UIImage(systemName: "photo.on.rectangle.angled")
        ) { [weak self] _ in
            guard let self else { return }
            self.sharePostAsImage(post)
        }
        let reply = UIAction(
            title: "回复",
            image: UIImage(systemName: "arrowshape.turn.up.left")
        ) { [weak self] _ in
            self?.openReply(quotePost: nil)
        }
        let quoteReply = UIAction(
            title: "引用回复",
            image: UIImage(systemName: "quote.opening")
        ) { [weak self] _ in
            self?.openReply(quotePost: post)
        }
        let rate = UIAction(
            title: "评分",
            image: UIImage(systemName: "star.circle")
        ) { [weak self] _ in
            guard let self else { return }
            self.present(RateViewController(threadId: self.threadId, postId: post.pid, authorName: post.author), animated: true)
        }
        let rateDetails = UIAction(
            title: "评分明细",
            image: UIImage(systemName: "list.star")
        ) { [weak self] _ in
            guard let self else { return }
            self.navigationController?.pushViewController(
                RateDetailsViewController(threadId: self.threadId, postId: post.pid, authorName: post.author),
                animated: true
            )
        }
        let report = UIAction(
            title: "举报",
            image: UIImage(systemName: "exclamationmark.shield"),
            attributes: .destructive
        ) { [weak self] _ in
            guard let self else { return }
            ReportFlow.present(from: self, threadId: self.threadId, postId: post.pid)
        }
        var children: [UIAction] = [reply, quoteReply, copyText, copyLink, favorite, rate, rateDetails, shareCard, report]
        // 自己的帖子:编辑(需要 fid——从当前 URL 上下文取不到时退化为隐藏)
        if post.authorId == SessionStore.shared.state.uid, let fid = self.forumId {
            let edit = UIAction(
                title: "编辑",
                image: UIImage(systemName: "pencil")
            ) { [weak self] _ in
                guard let self else { return }
                self.present(UINavigationController(rootViewController: EditPostViewController(forumId: fid, threadId: self.threadId, postId: post.pid)), animated: true)
            }
            children.append(edit)
        }
        return UIContextMenuConfiguration(actionProvider: { _ in
            UIMenu(children: children)
        })
    }
}
