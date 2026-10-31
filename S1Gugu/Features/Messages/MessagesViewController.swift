import UIKit
import SnapKit

/// Tab 3「消息」:私信 + 通知(Segmented 切换)。
@MainActor
final class MessagesViewController: UIViewController {

    private let segmented = UISegmentedControl(items: ["私信", "通知"])
    private let container = UIView()
    private var pmList: PMListViewController?
    private var noticeList: NoticeViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.title = "消息"

        segmented.selectedSegmentIndex = 0
        segmented.addAction(UIAction { [weak self] action in
            guard let control = action.sender as? UISegmentedControl else { return }
            self?.showSegment(control.selectedSegmentIndex)
        }, for: .valueChanged)

        let stack = UIStackView(arrangedSubviews: [segmented, container])
        stack.axis = .vertical
        stack.spacing = 8
        view.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }
        segmented.snp.makeConstraints { make in
            make.height.equalTo(32)
        }
        showSegment(0)
    }

    private func showSegment(_ index: Int) {
        pmList?.view.removeFromSuperview()
        pmList?.removeFromParent()
        noticeList?.view.removeFromSuperview()
        noticeList?.removeFromParent()

        let child: UIViewController
        if index == 0 {
            let controller = PMListViewController()
            pmList = controller
            child = controller
        } else {
            let controller = NoticeViewController()
            noticeList = controller
            child = controller
        }
        addChild(child)
        container.addSubview(child.view)
        child.view.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        child.didMove(toParent: self)
    }
}

// MARK: - 私信列表

@MainActor
final class PMListViewController: UIViewController {

    private var tableView: UITableView!
    private var groups: [PmGroup] = []
    private var page = 0
    private var canLoadMore = true
    private var isLoading = false
    private let placeholder = StatefulPlaceholderView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground

        tableView = UITableView(frame: view.bounds, style: .insetGrouped)
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "pmgroup")
        view.addSubview(tableView)

        navigationItem.rightBarButtonItem = UIBarButtonItem(primaryAction: UIAction(
            title: "发私信",
            image: UIImage(systemName: "plus.square.on.square")
        ) { [weak self] _ in
            self?.showNewPM()
        })

        placeholder.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.topAnchor.constraint(equalTo: view.topAnchor),
            placeholder.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            placeholder.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            placeholder.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        NotificationCenter.default.addObserver(
            self, selector: #selector(sessionChanged),
            name: SessionStore.didChangeNotification, object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if groups.isEmpty { reloadFirstPage() }
    }

    @objc private func sessionChanged() {
        groups = []
        page = 0
        canLoadMore = true
        tableView.reloadData()
        reloadFirstPage()
    }

    private func reloadFirstPage() {
        guard !isLoading else { return }
        guard SessionStore.shared.state.isLoggedIn else {
            placeholder.state = .empty(icon: "envelope", title: "请先登录", message: "登录后即可收发私信")
            placeholder.isHidden = false
            return
        }
        isLoading = true
        placeholder.isHidden = groups.isEmpty ? false : true
        placeholder.state = .loading("正在加载私信")
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await DiscuzAPI.shared.pmGroups(page: 1)
                self.groups = result.items
                self.page = 1
                self.canLoadMore = result.hasMore
                self.isLoading = false
                self.placeholder.isHidden = !self.groups.isEmpty
                if self.groups.isEmpty {
                    self.placeholder.state = .empty(icon: "envelope.open", title: "暂无私信", message: "给吧友发的私信会出现在这里")
                }
                self.tableView.reloadData()
            } catch {
                self.isLoading = false
                self.renderError(error)
            }
        }
    }

    private func renderError(_ error: Error) {
        placeholder.isHidden = false
        placeholder.state = .error(
            icon: "wifi.exclamationmark",
            title: "私信加载失败",
            message: (error as? LocalizedError)?.errorDescription ?? "请稍后重试",
            retry: { [weak self] in self?.reloadFirstPage() }
        )
    }

    private func showNewPM() {
        let alert = UIAlertController(title: "发新私信", message: "输入对方 UID 与内容", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "对方 UID"; $0.keyboardType = .numberPad }
        alert.addTextField { $0.placeholder = "内容" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "发送", style: .default) { [weak self] _ in
            guard let uid = alert.textFields?[0].text, Int(uid) != nil,
                  let message = alert.textFields?[1].text, !message.isEmpty
            else { return }
            Task {
                do {
                    try await DiscuzAPI.shared.sendPm(touid: uid, message: message)
                    Toast.show("已发送", in: self?.view ?? UIView())
                    self?.reloadFirstPage()
                } catch {
                    Toast.show((error as? LocalizedError)?.errorDescription ?? "发送失败", in: self?.view ?? UIView())
                }
            }
        })
        present(alert, animated: true)
    }
}

extension PMListViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { groups.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "pmgroup", for: indexPath)
        let group = groups[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = group.displayName
        config.secondaryText = group.lastSummary ?? ""
        config.textProperties.font = .preferredFont(forTextStyle: .body)
        config.secondaryTextProperties.font = .preferredFont(forTextStyle: .footnote)
        config.secondaryTextProperties.color = .secondaryLabel
        config.secondaryTextProperties.numberOfLines = 1
        config.image = UIImage(systemName: group.isNew ? "envelope.badge" : "envelope")
        config.imageProperties.tintColor = group.isNew ? Theme.accent : .tertiaryLabel
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let group = groups[indexPath.row]
        navigationController?.pushViewController(
            PMThreadViewController(touid: group.toUid, title: group.displayName),
            animated: true
        )
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {}
}

extension PMListViewController {
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard indexPath.row >= groups.count - 5, !isLoading, canLoadMore, page > 0 else { return }
        isLoading = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await DiscuzAPI.shared.pmGroups(page: self.page + 1)
                let known = Set(self.groups.map(\.id))
                self.groups += result.items.filter { !known.contains($0.id) }
                self.page += 1
                self.canLoadMore = result.hasMore
            } catch {
                self.canLoadMore = false
            }
            self.isLoading = false
            self.tableView.reloadData()
        }
    }
}

// MARK: - 私信会话

@MainActor
final class PMThreadViewController: UIViewController {

    private let touid: String
    private var tableView: UITableView!
    private var inputField = UITextField()
    private var messages: [PrivateMessage] = []
    private var page = 1
    private var canLoadMore = true
    private var isLoading = false

    init(touid: String, title: String?) {
        self.touid = touid
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        inputField.placeholder = "输入消息…"
        inputField.borderStyle = .roundedRect
        inputField.font = .preferredFont(forTextStyle: .body)
        inputField.delegate = self

        let sendButton = UIButton(type: .system)
        sendButton.setTitle("发送", for: .normal)
        sendButton.addAction(UIAction { [weak self] _ in self?.sendTapped() }, for: .touchUpInside)

        let inputBar = UIStackView(arrangedSubviews: [inputField, sendButton])
        inputBar.axis = .horizontal
        inputBar.spacing = 12
        inputBar.layoutMargins = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        inputBar.isLayoutMarginsRelativeArrangement = true

        tableView = UITableView(frame: .zero, style: .plain)
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "pm")
        tableView.allowsSelection = false

        view.addSubview(tableView)
        view.addSubview(inputBar)
        inputBar.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.keyboardLayoutGuide)
            make.height.greaterThanOrEqualTo(52)
        }
        tableView.snp.makeConstraints { make in
            make.leading.trailing.top.equalTo(view.safeAreaLayoutGuide)
            make.bottom.equalTo(inputBar.snp.top)
        }

        reloadFirstPage()
    }

    private func reloadFirstPage() {
        isLoading = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await DiscuzAPI.shared.pmMessages(touid: self.touid, page: 1)
                self.messages = result.items
                self.page = 1
                self.canLoadMore = result.hasMore
                self.isLoading = false
                self.tableView.reloadData()
                if !self.messages.isEmpty {
                    self.scrollToBottom()
                }
            } catch {
                self.isLoading = false
                Toast.show((error as? LocalizedError)?.errorDescription ?? "加载失败", in: self.view)
            }
        }
    }

    private func scrollToBottom() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.messages.isEmpty else { return }
            let last = IndexPath(row: self.messages.count - 1, section: 0)
            self.tableView.scrollToRow(at: last, at: .bottom, animated: false)
        }
    }

    private func sendTapped() {
        guard let text = inputField.text, !text.isEmpty else { return }
        inputField.text = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                try await DiscuzAPI.shared.sendPm(touid: self.touid, message: text)
                // 发送后重拉最新页
                let result = try await DiscuzAPI.shared.pmMessages(touid: self.touid, page: 1)
                self.messages = result.items
                self.tableView.reloadData()
                self.scrollToBottom()
            } catch {
                Toast.show((error as? LocalizedError)?.errorDescription ?? "发送失败", in: self.view)
                self.inputField.text = text
            }
        }
    }
}

extension PMThreadViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { messages.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "pm", for: indexPath)
        let message = messages[indexPath.row]
        let isMine = message.authorId == String(SessionStore.shared.state.uid ?? -1)
        cell.contentConfiguration = PMBubbleContentConfiguration(message: message, isMine: isMine)
        return cell
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        // 顶部上滑加载更早消息(服务端按时间倒序时翻页取更早)
        guard indexPath.row == 0, !isLoading, canLoadMore else { return }
        isLoading = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let nextPage = self.page + 1
                let result = try await DiscuzAPI.shared.pmMessages(touid: self.touid, page: nextPage)
                let known = Set(self.messages.map(\.id))
                let older = result.items.filter { !known.contains($0.id) }
                if older.isEmpty { self.canLoadMore = false }
                self.messages.insert(contentsOf: older, at: 0)
                self.page = nextPage
            } catch {
                self.canLoadMore = false
            }
            self.isLoading = false
            self.tableView.reloadData()
        }
    }
}

extension PMThreadViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        sendTapped()
        return true
    }
}

/// 私信气泡(自定义内容配置,轻量实现聊天气泡)
struct PMBubbleContentConfiguration: UIContentConfiguration {

    let message: PrivateMessage
    let isMine: Bool

    func makeContentView() -> UIView & UIContentView {
        PMBubbleContentView(configuration: self)
    }

    func updated(for state: UIConfigurationState) -> PMBubbleContentConfiguration {
        self
    }
}

@MainActor
final class PMBubbleContentView: UIView, UIContentView {

    var configuration: UIContentConfiguration {
        didSet { render() }
    }

    private let bubble = UIView()
    private let label = UILabel()
    private let metaLabel = UILabel()

    init(configuration: UIContentConfiguration) {
        self.configuration = configuration
        super.init(frame: .zero)

        label.font = .preferredFont(forTextStyle: .body)
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true

        metaLabel.font = .preferredFont(forTextStyle: .caption2)
        metaLabel.textColor = .tertiaryLabel
        metaLabel.adjustsFontForContentSizeCategory = true

        bubble.layer.cornerRadius = 14
        bubble.addSubview(label)
        addSubview(bubble)
        addSubview(metaLabel)

        label.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12))
        }
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        bubble.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(6)
            make.width.lessThanOrEqualToSuperview().multipliedBy(0.78)
        }
        metaLabel.snp.makeConstraints { make in
            make.top.equalTo(bubble.snp.bottom).offset(2)
            make.bottom.equalToSuperview().inset(6)
        }
        render()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func render() {
        guard let config = configuration as? PMBubbleContentConfiguration else { return }
        label.text = config.message.message
        metaLabel.text = config.message.timeText
        if config.isMine {
            bubble.backgroundColor = Theme.accent
            label.textColor = .white
            bubble.snp.remakeConstraints { make in
                make.trailing.equalToSuperview().inset(16)
                make.width.lessThanOrEqualToSuperview().multipliedBy(0.78)
                make.top.equalToSuperview().inset(6)
            }
            metaLabel.snp.remakeConstraints { make in
                make.trailing.equalToSuperview().inset(20)
                make.top.equalTo(bubble.snp.bottom).offset(2)
                make.bottom.equalToSuperview().inset(6)
            }
        } else {
            bubble.backgroundColor = .secondarySystemBackground
            label.textColor = .label
            bubble.snp.remakeConstraints { make in
                make.leading.equalToSuperview().inset(16)
                make.width.lessThanOrEqualToSuperview().multipliedBy(0.78)
                make.top.equalToSuperview().inset(6)
            }
            metaLabel.snp.remakeConstraints { make in
                make.leading.equalToSuperview().inset(20)
                make.top.equalTo(bubble.snp.bottom).offset(2)
                make.bottom.equalToSuperview().inset(6)
            }
        }
    }
}

// MARK: - 通知列表

@MainActor
final class NoticeViewController: UIViewController {

    private var tableView: UITableView!
    private var notes: [Note] = []
    private var page = 0
    private var canLoadMore = true
    private var isLoading = false
    private let placeholder = StatefulPlaceholderView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        tableView = UITableView(frame: view.bounds, style: .insetGrouped)
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "note")
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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if notes.isEmpty { reloadFirstPage() }
    }

    private func reloadFirstPage() {
        guard !isLoading else { return }
        guard SessionStore.shared.state.isLoggedIn else {
            placeholder.state = .empty(icon: "bell", title: "请先登录", message: "登录后即可查看消息通知")
            placeholder.isHidden = false
            return
        }
        isLoading = true
        placeholder.isHidden = false
        placeholder.state = .loading("正在加载通知")
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await DiscuzAPI.shared.notices(page: 1)
                self.notes = result.items
                self.page = 1
                self.canLoadMore = result.hasMore
                self.isLoading = false
                self.placeholder.isHidden = !self.notes.isEmpty
                if self.notes.isEmpty {
                    self.placeholder.state = .empty(icon: "bell.slash", title: "暂无通知", message: "帖子被回复、评分时会在这里提醒你")
                }
                self.tableView.reloadData()
            } catch {
                self.isLoading = false
                self.placeholder.isHidden = false
                self.placeholder.state = .error(
                    icon: "wifi.exclamationmark",
                    title: "通知加载失败",
                    message: (error as? LocalizedError)?.errorDescription ?? "请稍后重试",
                    retry: { [weak self] in self?.reloadFirstPage() }
                )
            }
        }
    }
}

extension NoticeViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { notes.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "note", for: indexPath)
        let note = notes[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = HTMLTextCleaner.plain(note.note)
        config.secondaryText = note.timeText
        config.textProperties.font = .preferredFont(forTextStyle: .subheadline)
        config.textProperties.numberOfLines = 3
        config.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1)
        config.secondaryTextProperties.color = .tertiaryLabel
        config.image = UIImage(systemName: "bell")
        config.imageProperties.tintColor = Theme.accent
        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard indexPath.row >= notes.count - 5, !isLoading, canLoadMore, page > 0 else { return }
        isLoading = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await DiscuzAPI.shared.notices(page: self.page + 1)
                let known = Set(self.notes.map(\.id))
                self.notes += result.items.filter { !known.contains($0.id) }
                self.page += 1
                self.canLoadMore = result.hasMore
            } catch {
                self.canLoadMore = false
            }
            self.isLoading = false
            self.tableView.reloadData()
        }
    }
}
