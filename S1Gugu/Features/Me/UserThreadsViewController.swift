import UIKit
import SnapKit

/// TA 的主题 / TA 的回复(HTML 列表解析,分页)。
@MainActor
final class UserThreadsViewController: UIViewController {

    enum Mode { case threads, replies }

    private let uid: String
    private let userName: String?
    private let mode: Mode

    private var tableView: UITableView!
    private let placeholder = StatefulPlaceholderView()

    private var threadItems: [HomeThreadItem] = []
    private var replyItems: [HomeReplyItem] = []
    private var page = 0
    private var canLoadMore = true
    private var isLoading = false

    init(uid: String, userName: String?, mode: Mode) {
        self.uid = uid
        self.userName = userName
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
        title = mode == .threads ? "TA 的主题" : "TA 的回复"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.backgroundColor = Theme.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "homeitem")
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
        placeholder.state = .loading("加载中")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if page == 0 { loadNextPage() }
    }

    private func loadNextPage() {
        guard !isLoading, canLoadMore else { return }
        isLoading = true
        let targetPage = page + 1
        Task { [weak self] in
            guard let self else { return }
            do {
                var hasMore = false
                switch self.mode {
                case .threads:
                    let (items, more) = try await DiscuzAPI.shared.homeThreads(uid: self.uid, page: targetPage)
                    self.threadItems.appendUniqued(contentsOf: items, by: \.url)
                    hasMore = more
                case .replies:
                    let (items, more) = try await DiscuzAPI.shared.homeReplies(uid: self.uid, page: targetPage)
                    self.replyItems.appendUniqued(contentsOf: items, by: \.url)
                    hasMore = more
                }
                self.page = targetPage
                self.canLoadMore = hasMore
                self.isLoading = false
                self.placeholder.isHidden = true
                self.tableView.reloadData()
                if self.currentCount() == 0, !hasMore {
                    self.placeholder.state = .empty(
                        icon: "doc.text.magnifyingglass",
                        title: self.mode == .threads ? "没有主题" : "没有回复",
                        message: nil
                    )
                    self.placeholder.isHidden = false
                }
            } catch {
                self.isLoading = false
                if self.currentCount() == 0 {
                    self.placeholder.state = .error(
                        icon: "wifi.exclamationmark",
                        title: "加载失败",
                        message: (error as? LocalizedError)?.errorDescription ?? "该内容可能需要对方开放访问权限",
                        retry: { [weak self] in self?.loadNextPage() }
                    )
                    self.placeholder.isHidden = false
                } else {
                    self.canLoadMore = false
                    Toast.show((error as? LocalizedError)?.errorDescription ?? "加载失败", in: self.view)
                }
            }
        }
    }

    private func currentCount() -> Int {
        mode == .threads ? threadItems.count : replyItems.count
    }
}

extension UserThreadsViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        currentCount()
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "homeitem", for: indexPath)
        cell.applyFlatListBackground()
        var config = cell.defaultContentConfiguration()
        config.textProperties.numberOfLines = 2
        config.secondaryTextProperties.color = Theme.secondaryLabel
        config.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1)
        switch mode {
        case .threads:
            let item = threadItems[indexPath.row]
            config.text = item.title
            var meta: [String] = []
            if let forum = item.forum, !forum.isEmpty { meta.append(forum) }
            if let reply = item.replyCount, !reply.isEmpty { meta.append("回复 \(reply)") }
            if let view = item.viewCount, !view.isEmpty { meta.append("浏览 \(view)") }
            if let replier = item.lastReplier, !replier.isEmpty {
                meta.append("最后:\(replier) \(item.lastReplyDate ?? "")")
            }
            config.secondaryText = meta.joined(separator: " · ")
            config.image = UIImage(systemName: "doc.text")
        case .replies:
            let item = replyItems[indexPath.row]
            config.text = item.reply
            config.secondaryText = nil
            config.image = UIImage(systemName: "bubble.right")
        }
        config.imageProperties.tintColor = Theme.accent
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let threadId: Int
        let title: String
        switch mode {
        case .threads:
            let item = threadItems[indexPath.row]
            threadId = item.threadId
            title = item.title
        case .replies:
            let item = replyItems[indexPath.row]
            threadId = item.threadId
            title = item.reply
        }
        guard threadId > 0 else {
            Toast.show("无法识别帖子链接", in: view)
            return
        }
        navigationController?.pushViewController(
            PostListViewController(threadId: threadId, threadTitle: title),
            animated: true
        )
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard indexPath.row >= currentCount() - 3 else { return }
        loadNextPage()
    }
}
