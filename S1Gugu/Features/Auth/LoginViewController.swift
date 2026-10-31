import UIKit
import SnapKit

/// 表单登录:用户名/密码/安全提问。凭据成功后存 Keychain。
@MainActor
final class LoginViewController: UIViewController {

    static let securityQuestions = [
        "无安全提问",
        "母亲的名字",
        "爷爷的名字",
        "父亲出生的城市",
        "您其中一位老师的名字",
        "您个人计算机的型号",
        "您最喜欢的餐馆名称",
        "驾驶执照的最后四位数字",
    ]

    private let usernameField = UITextField()
    private let passwordField = UITextField()
    private let questionButton = UIButton(type: .system)
    private let answerField = UITextField()
    private let submitButton = UIButton(type: .system)
    private let activity = UIActivityIndicatorView(style: .medium)

    private var selectedQuestionIndex = 0
    private var isSubmitting = false {
        didSet { renderSubmitting() }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.title = "登录"

        // 预填上次凭据
        if let credentials = KeychainStore.load() {
            usernameField.text = credentials.name
            passwordField.text = credentials.password
            selectedQuestionIndex = credentials.questionId
            answerField.text = credentials.answer
        }

        buildForm()
        renderSubmitting()
    }

    private func buildForm() {
        let spacing: CGFloat = 14

        func styledField(_ placeholder: String) -> UITextField {
            let field = UITextField()
            field.placeholder = placeholder
            field.borderStyle = .roundedRect
            field.font = .preferredFont(forTextStyle: .body)
            field.adjustsFontForContentSizeCategory = true
            field.autocorrectionType = .no
            field.autocapitalizationType = .none
            return field
        }

        usernameField.placeholder = "用户名 / UID / Email"
        usernameField.borderStyle = .roundedRect
        usernameField.font = .preferredFont(forTextStyle: .body)
        usernameField.autocorrectionType = .no
        usernameField.autocapitalizationType = .none

        passwordField.placeholder = "密码"
        passwordField.borderStyle = .roundedRect
        passwordField.font = .preferredFont(forTextStyle: .body)
        passwordField.isSecureTextEntry = true

        questionButton.configuration = {
            var config = UIButton.Configuration.gray()
            config.title = Self.securityQuestions[selectedQuestionIndex]
            config.image = UIImage(systemName: "chevron.up.chevron.down")
            config.imagePlacement = .trailing
            config.cornerStyle = .capsule
            config.titleAlignment = .leading
            return config
        }()
        questionButton.showsMenuAsPrimaryAction = true
        questionButton.menu = makeQuestionMenu()

        answerField.placeholder = "安全提问答案"
        answerField.borderStyle = .roundedRect
        answerField.font = .preferredFont(forTextStyle: .body)

        var submitConfig = UIButton.Configuration.filled()
        submitConfig.title = "登录"
        submitConfig.cornerStyle = .capsule
        submitConfig.baseBackgroundColor = Theme.accent
        submitConfig.baseForegroundColor = .white
        submitButton.configuration = submitConfig
        submitButton.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)

        let note = UILabel()
        note.text = "登录后将维持论坛 Cookie 会话;密码仅保存在本机钥匙串。"
        note.font = .preferredFont(forTextStyle: .footnote)
        note.textColor = .secondaryLabel
        note.numberOfLines = 0
        note.adjustsFontForContentSizeCategory = true

        let stack = UIStackView(arrangedSubviews: [
            usernameField, passwordField, questionButton, answerField, submitButton, note,
        ])
        stack.axis = .vertical
        stack.spacing = spacing
        stack.setCustomSpacing(24, after: answerField)

        view.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(24)
            make.centerY.equalToSuperview().offset(-40)
        }
        submitButton.snp.makeConstraints { make in
            make.height.equalTo(44)
        }
        activity.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activity)
        NSLayoutConstraint.activate([
            activity.centerXAnchor.constraint(equalTo: submitButton.centerXAnchor),
            activity.centerYAnchor.constraint(equalTo: submitButton.centerYAnchor),
        ])
    }

    private func makeQuestionMenu() -> UIMenu {
        UIMenu(children: Self.securityQuestions.enumerated().map { index, title in
            UIAction(title: title, state: index == selectedQuestionIndex ? .on : .off) { [weak self] _ in
                self?.selectedQuestionIndex = index
                self?.questionButton.configuration?.title = title
            }
        })
    }

    private func renderSubmitting() {
        submitButton.isEnabled = !isSubmitting
        submitButton.configuration?.title = isSubmitting ? "登录中…" : "登录"
        submitButton.alpha = isSubmitting ? 0.4 : 1
        if isSubmitting { activity.startAnimating() } else { activity.stopAnimating() }
    }

    @objc private func submitTapped() {
        guard let username = usernameField.text, !username.isEmpty,
              let password = passwordField.text, !password.isEmpty
        else {
            let alert = UIAlertController(title: "请填写用户名与密码", message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default))
            present(alert, animated: true)
            return
        }
        isSubmitting = true
        Task { [weak self] in
            guard let self else { return }
            do {
                try await SessionStore.shared.login(
                    username: username,
                    password: password,
                    questionId: self.selectedQuestionIndex,
                    answer: self.answerField.text ?? ""
                )
                self.isSubmitting = false
                let name = SessionStore.shared.state.name ?? username
                Toast.show("登录成功,欢迎 \(name)", in: self.view ?? UIView())
                self.closeAfterSuccess()
            } catch {
                self.isSubmitting = false
                let alert = UIAlertController(
                    title: "登录失败",
                    message: (error as? LocalizedError)?.errorDescription ?? "请稍后重试",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "好", style: .default))
                self.present(alert, animated: true)
            }
        }
    }

    /// 登录页可能被 push(「我的」Tab)或 present(帖子页收藏/回复),按呈现方式关闭
    private func closeAfterSuccess() {
        if presentingViewController != nil {
            dismiss(animated: true)
        } else if let navigationController, navigationController.viewControllers.count > 1 {
            navigationController.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }
}
