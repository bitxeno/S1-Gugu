import UIKit
import SnapKit

/// Tab 3「消息」:私信 + 通知。顶部文字 Tab(选中加粗 + 下划线)替代导航标题,
/// 本页隐藏导航栏,push 会话页时恢复;原导航栏「发私信」入口移到头部右侧。
@MainActor
final class MessagesViewController: UIViewController {

    private let tabTitles = ["私信", "通知"]
    private let header = UIView()
    private let tabStack = UIStackView()
    private let underline = UIView()
    private let composeButton = UIButton(type: .system)
    private let container = UIView()
    private var pmList: PMListViewController?
    private var noticeList: NoticeViewController?

    private var tabButtons: [UIButton] = []
    private var selectedIndex = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        // 字号随 Dynamic Type 变化时重算 Tab 字体与下划线
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: MessagesViewController, _) in
            self.renderTabs()
            self.view.setNeedsLayout()
        }
        setupHeader()
        setupContainer()
        showSegment(0)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        positionUnderline()
    }

    private func setupHeader() {
        // 与其它页面导航栏同色(奶黄主题为奶茶色 #D8D8A8)
        header.backgroundColor = Theme.navigationBarBackground
        view.addSubview(header)
        header.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
        }

        tabStack.axis = .horizontal
        tabStack.spacing = 20
        tabStack.alignment = .center
        header.addSubview(tabStack)
        tabStack.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide).offset(6)
            make.bottom.equalToSuperview().inset(12)
        }

        for (index, title) in tabTitles.enumerated() {
            let button = UIButton(type: .system)
            button.tag = index
            var config = UIButton.Configuration.plain()
            config.title = title
            // 扩大点击热区,不影响下划线宽度计算(按文字实际宽度定位)
            config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 6)
            button.configuration = config
            button.addAction(UIAction { [weak self] action in
                guard let sender = action.sender as? UIButton else { return }
                self?.selectTab(sender.tag)
            }, for: .touchUpInside)
            tabButtons.append(button)
            tabStack.addArrangedSubview(button)
        }
        renderTabs()

        underline.backgroundColor = Theme.barForeground
        underline.layer.cornerRadius = 1.5
        underline.isUserInteractionEnabled = false
        header.addSubview(underline)

        composeButton.setImage(UIImage(systemName: "square.and.pencil"), for: .normal)
        composeButton.tintColor = Theme.barForeground
        composeButton.accessibilityLabel = "发私信"
        composeButton.addAction(UIAction { [weak self] _ in
            self?.pmList?.showNewPM()
        }, for: .touchUpInside)
        header.addSubview(composeButton)
        composeButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(4)
            make.centerY.equalTo(tabStack)
            make.size.equalTo(44)
        }
    }

    private func setupContainer() {
        view.addSubview(container)
        container.snp.makeConstraints { make in
            make.top.equalTo(header.snp.bottom)
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

    private func selectTab(_ index: Int) {
        guard index != selectedIndex else { return }
        selectedIndex = index
        renderTabs()
        showSegment(index)
        composeButton.isEnabled = index == 0
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut) {
            self.composeButton.alpha = index == 0 ? 1 : 0
            self.view.layoutIfNeeded()
        }
    }

    /// 选中加粗主色、未选中常规次级色,对齐 S1-Next 顶部 Tab
    private func renderTabs() {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title3)
        for (index, button) in tabButtons.enumerated() {
            let selected = index == selectedIndex
            let styled = descriptor.withSymbolicTraits(selected ? .traitBold : []) ?? descriptor
            var attributed = AttributedString(tabTitles[index])
            attributed.font = UIFont(descriptor: styled, size: 0)
            attributed.foregroundColor = selected ? Theme.barForeground : Theme.secondaryLabel
            var config = button.configuration ?? UIButton.Configuration.plain()
            config.attributedTitle = attributed
            button.configuration = config
            button.accessibilityTraits = selected ? [.button, .selected] : .button
        }
    }

    /// 下划线对齐选中 Tab 的文字宽度,随布局刷新(切换时经 layoutIfNeeded 产生滑动动画)
    private func positionUnderline() {
        guard tabButtons.indices.contains(selectedIndex) else { return }
        let button = tabButtons[selectedIndex]
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title3)
        let bold = descriptor.withSymbolicTraits(.traitBold) ?? descriptor
        let font = UIFont(descriptor: bold, size: 0)
        let textSize = (tabTitles[selectedIndex] as NSString).size(withAttributes: [.font: font])
        let buttonFrame = header.convert(button.bounds, from: button)
        let textFrame = CGRect(
            x: buttonFrame.midX - textSize.width / 2,
            y: buttonFrame.midY - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        underline.frame = CGRect(x: textFrame.minX - 2, y: textFrame.maxY + 5, width: textSize.width + 4, height: 3)
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
        view.backgroundColor = Theme.background

        tableView = UITableView(frame: view.bounds, style: .insetGrouped)
        tableView.backgroundColor = Theme.background
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "pmgroup")
        view.addSubview(tableView)

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

    func showNewPM() {
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
        cell.applyFlatListBackground()
        let group = groups[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = group.displayName
        config.secondaryText = group.lastSummary ?? ""
        config.textProperties.font = .preferredFont(forTextStyle: .body)
        config.secondaryTextProperties.font = .preferredFont(forTextStyle: .footnote)
        config.secondaryTextProperties.color = Theme.secondaryLabel
        config.secondaryTextProperties.numberOfLines = 1
        config.image = UIImage(systemName: group.isNew ? "envelope.badge" : "envelope")
        config.imageProperties.tintColor = group.isNew ? Theme.accent : Theme.tertiaryLabel
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
                self.groups.appendUniqued(contentsOf: result.items, by: \.id)
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
        view.backgroundColor = Theme.contentBackground

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
        // plain 表格缺省白底,与页面米白对齐
        tableView.backgroundColor = Theme.contentBackground
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
        // 会话页底色是 contentBackground,气泡 cell 同色铺底
        cell.applyFlatListBackground(color: Theme.contentBackground)
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
                let older = result.items.uniqued(by: \.id, excluding: self.messages)
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
        metaLabel.textColor = Theme.tertiaryLabel
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
            label.textColor = Theme.label
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
        view.backgroundColor = Theme.background
        tableView = UITableView(frame: view.bounds, style: .insetGrouped)
        tableView.backgroundColor = Theme.background
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
        cell.applyFlatListBackground()
        let note = notes[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = HTMLTextCleaner.plain(note.note)
        config.secondaryText = note.timeText
        config.textProperties.font = .preferredFont(forTextStyle: .subheadline)
        config.textProperties.numberOfLines = 3
        config.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1)
        config.secondaryTextProperties.color = Theme.tertiaryLabel
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
                self.notes.appendUniqued(contentsOf: result.items, by: \.id)
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
