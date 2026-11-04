import UIKit
import SnapKit

/// 全局搜索:主题(HTML 结果页归因渲染 + 翻页)/ 用户(进个人空间)。
@MainActor
final class SearchViewController: UIViewController {

    private enum Mode: Int { case forum = 0, user = 1 }

    private let searchBar = UISearchBar()
    private let segmented = UISegmentedControl(items: ["主题", "用户"])
    private var tableView: UITableView!
    private let placeholder = StatefulPlaceholderView()

    private var mode: Mode = .forum
    private var isLoading = false

    // 主题结果状态
    private var forumResults: [ForumSearchResult] = []
    private var searchCount = 0
    private var currentPage = 1
    private var maxPage = 1
    private var nextPageTemplate: String?
    private var renderedBodies: [Int: NSAttributedString] = [:]

    // 用户结果状态
    private var userResults: [UserSearchResult] = []
    private var userError: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationItem.title = "搜索"

        searchBar.placeholder = "搜索主题或用户"
        searchBar.searchBarStyle = .minimal
        searchBar.delegate = self
        searchBar.returnKeyType = .search

        segmented.selectedSegmentIndex = 0
        segmented.addAction(UIAction { [weak self] action in
            guard let control = action.sender as? UISegmentedControl else { return }
            self?.mode = Mode(rawValue: control.selectedSegmentIndex) ?? .forum
            self?.renderResults()
        }, for: .valueChanged)

        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.backgroundColor = Theme.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "search")

        let stack = UIStackView(arrangedSubviews: [searchBar, segmented, tableView])
        stack.axis = .vertical
        stack.spacing = 8
        view.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }
        segmented.snp.makeConstraints { make in
            make.height.equalTo(32)
            make.leading.trailing.equalToSuperview().inset(12)
        }

        placeholder.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholder)
        // 只覆盖结果区,不遮挡搜索框与分段控件
        placeholder.snp.makeConstraints { make in
            make.top.equalTo(segmented.snp.bottom).offset(8)
            make.leading.trailing.bottom.equalTo(view.safeAreaLayoutGuide)
        }
        placeholder.state = .empty(icon: "magnifyingglass", title: "搜索 Stage1st", message: "输入关键词搜索主题或用户")
        placeholder.isHidden = false
    }

    // MARK: - Search

    private func performSearch() {
        guard let keyword = searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !keyword.isEmpty
        else { return }
        guard !isLoading else { return }
        guard SessionStore.shared.state.isLoggedIn else {
            placeholder.state = .empty(icon: "person.crop.circle", title: "请先登录", message: "搜索需要登录后使用")
            placeholder.isHidden = false
            return
        }
        isLoading = true
        forumResults = []
        renderedBodies = [:]
        userResults = []
        currentPage = 1
        maxPage = 1
        nextPageTemplate = nil
        placeholder.isHidden = false
        placeholder.state = .loading("搜索中")

        Task { [weak self] in
            guard let self else { return }
            do {
                if self.mode == .forum {
                    let page = try await DiscuzAPI.shared.searchForum(keyword: keyword, pageHrefTemplate: nil, page: 1)
                    self.forumResults = page.results.uniqued(by: \.id)
                    self.searchCount = page.count
                    self.currentPage = page.page
                    self.maxPage = page.maxPage
                    self.nextPageTemplate = page.nextPageHref
                    self.renderAttributedBodies()
                } else {
                    let (results, error) = try await DiscuzAPI.shared.searchUser(keyword: keyword)
                    self.userResults = results
                    self.userError = error
                }
                self.isLoading = false
                self.renderResults()
            } catch {
                self.isLoading = false
                self.placeholder.state = .error(
                    icon: "wifi.exclamationmark",
                    title: "搜索失败",
                    message: (error as? LocalizedError)?.errorDescription ?? "请稍后重试",
                    retry: { [weak self] in self?.performSearch() }
                )
                self.placeholder.isHidden = false
            }
        }
    }

    private func loadNextForumPage() {
        guard !isLoading, mode == .forum,
              let template = nextPageTemplate, currentPage < maxPage
        else { return }
        isLoading = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await DiscuzAPI.shared.searchForum(
                    keyword: self.searchBar.text ?? "",
                    pageHrefTemplate: template,
                    page: self.currentPage + 1
                )
                self.forumResults.appendUniqued(contentsOf: page.results, by: \.id)
                self.currentPage = page.page
                self.maxPage = page.maxPage
                self.renderAttributedBodies()
                self.isLoading = false
                self.tableView.reloadData()
            } catch {
                self.isLoading = false
                Toast.show((error as? LocalizedError)?.errorDescription ?? "加载失败", in: self.view)
            }
        }
    }

    /// li.pbw HTML → 归因文本(后台渲染)
    private func renderAttributedBodies() {
        let inputs = forumResults.filter { renderedBodies[$0.id] == nil }
        guard !inputs.isEmpty else { return }
        let baseURL = S1APIClient.shared.baseURL
        Task.detached(priority: .userInitiated) { [weak self] in
            var output: [Int: NSAttributedString] = [:]
            for item in inputs {
                let blocks = BlockSplitter.split(html: item.html, baseURL: baseURL)
                let text = blocks.compactMap { block -> NSAttributedString? in
                    switch block {
                    case let .text(attributed), let .fallback(attributed), let .quote(_, attributed):
                        return attributed.value
                    default: return nil
                    }
                }.joined(separator: "\n")
                output[item.id] = text
            }
            await MainActor.run { [weak self] in
                self?.renderedBodies.merge(output) { _, new in new }
                self?.tableView.reloadData()
            }
        }
    }

    private func renderResults() {
        tableView.isHidden = false
        switch mode {
        case .forum:
            renderAttributedBodies()
            if forumResults.isEmpty {
                placeholder.state = .empty(icon: "magnifyingglass", title: "没有找到相关主题", message: "换个关键词试试")
                placeholder.isHidden = false
            } else {
                placeholder.isHidden = true
            }
        case .user:
            if let userError, userResults.isEmpty {
                placeholder.state = .error(icon: "person.crop.circle.badge.questionmark", title: "搜索失败", message: userError, retry: { [weak self] in self?.performSearch() })
                placeholder.isHidden = false
            } else if userResults.isEmpty {
                placeholder.state = .empty(icon: "person.crop.circle.badge.questionmark", title: "没有找到相关用户", message: "换个关键词试试")
                placeholder.isHidden = false
            } else {
                placeholder.isHidden = true
            }
        }
        tableView.reloadData()
    }
}

extension SearchViewController: UISearchBarDelegate {

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        performSearch()
    }
}

extension SearchViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        mode == .forum ? forumResults.count : userResults.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "search", for: indexPath)
        cell.applyFlatListBackground()
        if mode == .forum {
            let result = forumResults[indexPath.row]
            let attributed = renderedBodies[result.id] ?? NSAttributedString(string: "渲染中…")
            var config = SearchTextContentConfiguration(attributed: attributed)
            config.onLinkTap = { [weak self] url in
                guard let self else { return }
                LinkRouter.handle(url, from: self)
            }
            cell.contentConfiguration = config
            cell.selectionStyle = .default
        } else {
            let result = userResults[indexPath.row]
            var config = cell.appDefaultContentConfiguration()
            config.text = result.name ?? "UID \(result.uid)"
            config.secondaryText = "UID \(result.uid)"
            config.secondaryTextProperties.color = Theme.secondaryLabel
            config.image = UIImage(systemName: "person.crop.circle")
            config.imageProperties.tintColor = Theme.accent
            cell.contentConfiguration = config
            cell.accessoryType = .disclosureIndicator
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if mode == .user {
            let result = userResults[indexPath.row]
            navigationController?.pushViewController(UserHomeViewController(uid: result.uid), animated: true)
        }
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if mode == .forum, indexPath.row >= forumResults.count - 3 {
            loadNextForumPage()
        }
    }
}

// MARK: - 主题结果归因文本内容配置

struct SearchTextContentConfiguration: UIContentConfiguration {
    let attributed: NSAttributedString
    var onLinkTap: ((URL) -> Void)?

    func makeContentView() -> UIView & UIContentView {
        SearchTextContentView(configuration: self)
    }

    func updated(for state: any UIConfigurationState) -> SearchTextContentConfiguration {
        self
    }
}

@MainActor
final class SearchTextContentView: UIView, UIContentView, UITextViewDelegate {

    var configuration: UIContentConfiguration {
        didSet { render() }
    }

    private let textView = UITextView()

    init(configuration: UIContentConfiguration) {
        self.configuration = configuration
        super.init(frame: .zero)
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = Theme.cardCornerRadius
        textView.isScrollEnabled = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        textView.textContainer.lineFragmentPadding = 0
        textView.linkTextAttributes = [.foregroundColor: Theme.accent]
        textView.delegate = self
        addSubview(textView)
        textView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        render()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func render() {
        guard let config = configuration as? SearchTextContentConfiguration else { return }
        textView.attributedText = config.attributed
    }

    func textView(
        _ textView: UITextView,
        shouldInteractWith URL: URL,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        guard interaction == .invokeDefaultAction else { return true }
        (configuration as? SearchTextContentConfiguration)?.onLinkTap?(URL)
        return false
    }
}

private extension Array where Element == NSAttributedString {
    func joined(separator: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, item) in enumerated() {
            if index > 0 { result.append(NSAttributedString(string: separator)) }
            result.append(item)
        }
        return result
    }
}
