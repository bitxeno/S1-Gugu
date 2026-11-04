import UIKit
import Kingfisher
import SnapKit

/// 用户个人空间:资料卡 + 签名 + 好友 + 拉黑入口。
@MainActor
final class UserHomeViewController: UIViewController {

    private let uid: String

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private var friendsSection: [Friend] = []
    private var profile: Profile?

    /// 是否在浏览自己的个人空间(自己的空间不显示「加入黑名单」)
    private var isSelf: Bool {
        guard let current = SessionStore.shared.state.uid else { return false }
        return Int(uid) == current
    }

    init(uid: String) {
        self.uid = uid
        super.init(nibName: nil, bundle: nil)
        title = "个人空间"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        // 参考 S1-Next:个人空间右上角只有一个「塞抹布」入口(已拉黑时为「取抹布」)。
        // 浏览自己的空间不显示拉黑入口。
        if !isSelf {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                image: UIImage(systemName: "nosign"),
                menu: blackListMenu()
            )
        }

        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }

        contentStack.axis = .vertical
        contentStack.spacing = 12
        scrollView.addSubview(contentStack)
        contentStack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 16, left: 16, bottom: 32, right: 16))
            make.width.equalTo(scrollView.frameLayoutGuide).offset(-32)
        }

        Task { await load() }
    }

    private func blackListMenu() -> UIMenu {
        let uidValue = Int(uid) ?? 0
        let name = profile?.username
        // 对齐 S1-Next:已拉黑时为「取抹布」,否则为「塞抹布」
        if BlacklistService.shared.existingBlacklist(uid: uidValue, name: name) != nil {
            return UIMenu(children: [
                UIAction(title: "取抹布", attributes: .destructive) { [weak self] _ in
                    self?.removeFromBlacklist()
                },
            ])
        }
        return UIMenu(children: [
            UIAction(title: "塞抹布", attributes: .destructive) { [weak self] _ in
                self?.promptBlacklistRemark()
            },
        ])
    }

    /// 「塞抹布」前可填写备注(对齐 S1-Next 的备注弹窗),默认隐藏该用户的主题与回复。
    private func promptBlacklistRemark() {
        let alert = UIAlertController(title: "塞抹布", message: "可填写备注(可选)", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "备注" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "塞抹布", style: .destructive) { [weak self] _ in
            guard let self else { return }
            let remark = alert.textFields?.first?.text
            self.addToBlacklist(postLevel: 1, forumLevel: 3,
                                remark: (remark?.isEmpty ?? true) ? nil : remark)
        })
        present(alert, animated: true)
    }

    private func addToBlacklist(postLevel: Int, forumLevel: Int, remark: String?) {
        let uidValue = Int(uid) ?? 0
        let name = profile?.username
        Task { [weak self] in
            await BlacklistService.shared.addBlackList(uid: uidValue, name: name, postLevel: postLevel, forumLevel: forumLevel, remark: remark)
            self?.refreshBlacklistMenu()
            if let view = self?.view { Toast.show("塞抹布成功", in: view) }
        }
    }

    private func removeFromBlacklist() {
        let uidValue = Int(uid) ?? 0
        let name = profile?.username
        Task { [weak self] in
            await BlacklistService.shared.removeBlackList(uid: uidValue, name: name)
            self?.refreshBlacklistMenu()
            if let view = self?.view { Toast.show("取抹布成功", in: view) }
        }
    }

    /// 黑名单状态变化后刷新右上角菜单
    private func refreshBlacklistMenu() {
        guard !isSelf else { return }
        navigationItem.rightBarButtonItem?.menu = blackListMenu()
    }

    private func load() async {
        let loading = makeCard(title: "加载中…")
        contentStack.addArrangedSubview(loading)
        do {
            // 先确保黑名单快照就绪,右上角菜单才能正确显示「加入/移出」
            await BlacklistService.shared.reloadIfNeeded()
            async let profileTask = DiscuzAPI.shared.profile(uid: uid)
            async let friendsTask = DiscuzAPI.shared.friends(uid: uid)
            let (fetchedProfile, friends) = try await (profileTask, friendsTask)
            self.profile = fetchedProfile
            self.friendsSection = friends
            render(fetchedProfile, friends: friends)
            refreshBlacklistMenu()
        } catch {
            loading.removeFromSuperview()
            let errorCard = makeCard(title: "加载失败", detail: (error as? LocalizedError)?.errorDescription)
            contentStack.addArrangedSubview(errorCard)
        }
    }

    private func render(_ profile: Profile, friends: [Friend]) {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // 资料卡
        let avatar = UIImageView()
        avatar.layer.cornerRadius = 28
        avatar.layer.masksToBounds = true
        avatar.contentMode = .scaleAspectFill
        avatar.kf.setImage(with: profile.avatarURL ?? AvatarURL.url(uid: Int(uid) ?? 0),
                           placeholder: DefaultAvatar.image,
                           options: [.onFailureImage(DefaultAvatar.image)])
        avatar.snp.makeConstraints { $0.size.equalTo(CGSize(width: 56, height: 56)) }

        let nameLabel = UILabel()
        nameLabel.font = .preferredFont(forTextStyle: .title3).bold()
        nameLabel.text = profile.username ?? "UID \(uid)"
        nameLabel.adjustsFontForContentSizeCategory = true

        let groupLabel = UILabel()
        groupLabel.font = .preferredFont(forTextStyle: .footnote)
        groupLabel.textColor = Theme.secondaryLabel
        let regText = profile.regDate.flatMap { Thread.formatDate($0) } ?? "-"
        groupLabel.text = [profile.groupTitle, "注册:\(regText)"].compactMap { $0 }.joined(separator: " · ")
        groupLabel.adjustsFontForContentSizeCategory = true

        let nameStack = UIStackView(arrangedSubviews: [nameLabel, groupLabel])
        nameStack.axis = .vertical
        nameStack.spacing = Theme.Spacing.titleToSecondary

        let header = UIStackView(arrangedSubviews: [avatar, nameStack])
        header.axis = .horizontal
        header.spacing = 14
        header.alignment = .center

        let statsLabel = UILabel()
        statsLabel.numberOfLines = 0
        statsLabel.font = .preferredFont(forTextStyle: .footnote)
        statsLabel.textColor = Theme.secondaryLabel
        let visitText = profile.lastVisitDate.flatMap { Thread.formatDate($0) } ?? "-"
        statsLabel.text = "好友 \(profile.friendsCount) · 主题 \(profile.threadsCount) · 回复 \(profile.repliesCount)\n最后访问:\(visitText)"
        statsLabel.adjustsFontForContentSizeCategory = true

        let card = UIStackView(arrangedSubviews: [header, statsLabel])
        card.axis = .vertical
        card.spacing = 12
        wrapInCard(card)

        // 签名(渲染管线降级为归因文本)
        if let signatureHTML = profile.signatureHTML, !signatureHTML.isEmpty {
            let blocks = BlockSplitter.split(html: signatureHTML, baseURL: S1APIClient.shared.baseURL)
            let text = blocks.compactMap { block -> String? in
                switch block {
                case let .text(attributed), let .fallback(attributed), let .quote(_, attributed):
                    return attributed.value.string
                default: return nil
                }
            }.joined(separator: "\n")
            if !text.isEmpty {
                let signLabel = UILabel()
                signLabel.numberOfLines = 0
                signLabel.font = .preferredFont(forTextStyle: .subheadline)
                signLabel.textColor = Theme.secondaryLabel
                signLabel.text = "签名:\(text)"
                signLabel.adjustsFontForContentSizeCategory = true
                wrapInCard(makeStack([signLabel]))
            }
        }

        // TA 的主题 / TA 的回复
        let threadsButton = UIButton(type: .system)
        threadsButton.setTitle("TA 的主题", for: .normal)
        threadsButton.addAction(UIAction { [weak self] _ in
            self?.openUserThreads(mode: .threads)
        }, for: .touchUpInside)
        let repliesButton = UIButton(type: .system)
        repliesButton.setTitle("TA 的回复", for: .normal)
        repliesButton.addAction(UIAction { [weak self] _ in
            self?.openUserThreads(mode: .replies)
        }, for: .touchUpInside)
        let actionsRow = UIStackView(arrangedSubviews: [threadsButton, repliesButton])
        actionsRow.axis = .horizontal
        actionsRow.distribution = .fillEqually
        actionsRow.spacing = 12
        wrapInCard(makeStack([actionsRow]))

        // 好友
        if !friends.isEmpty {
            let title = UILabel()
            title.text = "好友(\(friends.count))"
            title.font = .preferredFont(forTextStyle: .headline)
            title.adjustsFontForContentSizeCategory = true
            let stack = makeStack([title])
            let friendNames = UILabel()
            friendNames.numberOfLines = 0
            friendNames.font = .preferredFont(forTextStyle: .subheadline)
            friendNames.textColor = Theme.accent
            friendNames.text = friends.prefix(20).map(\.displayName).joined(separator: "、")
            friendNames.adjustsFontForContentSizeCategory = true
            stack.addArrangedSubview(friendNames)
            wrapInCard(stack)
        }
    }

    private func openUserThreads(mode: UserThreadsViewController.Mode) {
        navigationController?.pushViewController(
            UserThreadsViewController(uid: uid, userName: profile?.username, mode: mode),
            animated: true
        )
    }

    private func makeStack(_ subviews: [UIView]) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: subviews)
        stack.axis = .vertical
        stack.spacing = 10
        return stack
    }

    private func makeCard(title: String, detail: String? = nil) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        let stack = makeStack([label])
        if let detail {
            let detailLabel = UILabel()
            detailLabel.text = detail
            detailLabel.font = .preferredFont(forTextStyle: .footnote)
            detailLabel.textColor = Theme.secondaryLabel
            detailLabel.numberOfLines = 0
            stack.addArrangedSubview(detailLabel)
        }
        return wrapInCard(stack)
    }

    @discardableResult
    private func wrapInCard(_ stack: UIStackView) -> UIView {
        let card = UIView()
        // 卡片底色跟随主题(奶黄 = 与页面同色,靠下方阴影分层,对齐 S1-Next 的 CardView),
        // 不再固定用白色 secondarySystemGroupedBackground。
        card.backgroundColor = Theme.cardBackground
        card.layer.cornerRadius = Theme.cardCornerRadius
        card.layer.shadowColor = Theme.cardShadowColor.cgColor
        card.layer.shadowOpacity = 0.12
        card.layer.shadowRadius = 6
        card.layer.shadowOffset = CGSize(width: 0, height: 2)
        card.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(14)
        }
        contentStack.addArrangedSubview(card)
        return card
    }
}

// MARK: - 评分

/// 给楼层评分(分数 1–10 + 理由),走 web 表单通道。
@MainActor
final class RateViewController: UIViewController {

    private let threadId: Int
    private let postId: Int
    private let authorName: String

    private let scoreLabel = UILabel()
    private var score = 1
    private let reasonField = UITextField()
    private let submitButton = UIButton(type: .system)

    init(threadId: Int, postId: Int, authorName: String) {
        self.threadId = threadId
        self.postId = postId
        self.authorName = authorName
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .formSheet
        title = "评分"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.contentBackground

        let info = UILabel()
        info.text = "给 \(authorName) 的楼层评分"
        info.font = .preferredFont(forTextStyle: .subheadline)
        info.textColor = Theme.secondaryLabel
        info.adjustsFontForContentSizeCategory = true

        updateScoreLabel()
        let stepper = UIStepper()
        stepper.minimumValue = 1
        stepper.maximumValue = 10
        stepper.value = 1
        stepper.addAction(UIAction { [weak self] action in
            guard let control = action.sender as? UIStepper else { return }
            self?.score = Int(control.value)
            self?.updateScoreLabel()
        }, for: .valueChanged)

        let scoreRow = UIStackView(arrangedSubviews: [scoreLabel, UIView(), stepper])
        scoreRow.axis = .horizontal
        scoreRow.alignment = .center

        reasonField.placeholder = "评分理由(必填)"
        reasonField.borderStyle = .roundedRect
        reasonField.font = .preferredFont(forTextStyle: .body)

        var config = UIButton.Configuration.filled()
        config.title = "提交评分"
        config.cornerStyle = .capsule
        config.baseBackgroundColor = Theme.accent
        config.baseForegroundColor = .white
        submitButton.configuration = config
        submitButton.addAction(UIAction { [weak self] _ in self?.submit() }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [info, scoreRow, reasonField, submitButton])
        stack.axis = .vertical
        stack.spacing = 16
        view.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(24)
            make.centerY.equalToSuperview()
        }
        submitButton.snp.makeConstraints { $0.height.equalTo(44) }
    }

    private func updateScoreLabel() {
        scoreLabel.text = "积分:\(score)"
        scoreLabel.font = .preferredFont(forTextStyle: .body)
    }

    private func submit() {
        guard let reason = reasonField.text, !reason.isEmpty else {
            Toast.show("请填写评分理由", in: view)
            return
        }
        submitButton.isEnabled = false
        Task { [weak self] in
            guard let self else { return }
            do {
                let formhash = try await SessionStore.shared.requireFormhash()
                _ = try await WebChannel.submitForm(
                    action: URL(string: "forum.php?mod=misc&action=rate&ratesubmit=yes&infloat=yes&inajax=1", relativeTo: S1APIClient.shared.baseURL)!.absoluteURL,
                    fields: [
                        "formhash": formhash,
                        "tid": String(self.threadId),
                        "pid": String(self.postId),
                        "handlekey": "rate",
                        "score1": String(self.score),
                        "reason": reason,
                        "referer": LinkRouter.threadURL(tid: self.threadId, page: 1).absoluteString,
                    ]
                )
                Toast.show("评分成功", in: self.view ?? UIView())
                self.dismiss(animated: true)
            } catch {
                self.submitButton.isEnabled = true
                let alert = UIAlertController(title: "评分失败", message: (error as? LocalizedError)?.errorDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "好", style: .default))
                self.present(alert, animated: true)
            }
        }
    }
}

// MARK: - 举报

@MainActor
enum ReportFlow {

    static func present(from viewController: UIViewController, threadId: Int, postId: Int) {
        let alert = UIAlertController(title: "举报该楼层", message: "请填写举报理由", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "理由" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "提交", style: .default) { _ in
            guard let message = alert.textFields?.first?.text, !message.isEmpty else { return }
            Task {
                do {
                    let formhash = try await SessionStore.shared.requireFormhash()
                    _ = try await WebChannel.submitForm(
                        action: URL(string: "forum.php?mod=misc&action=report&inajax=1", relativeTo: S1APIClient.shared.baseURL)!.absoluteURL,
                        fields: [
                            "formhash": formhash,
                            "tid": String(threadId),
                            "pid": String(postId),
                            "rid": String(postId),
                            "message": message,
                        ]
                    )
                    Toast.show("已提交举报", in: viewController.view ?? UIView())
                } catch {
                    Toast.show((error as? LocalizedError)?.errorDescription ?? "举报失败", in: viewController.view ?? UIView())
                }
            }
        })
        viewController.present(alert, animated: true)
    }
}
