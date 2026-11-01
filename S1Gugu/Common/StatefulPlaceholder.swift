import UIKit
import SnapKit

/// 统一的整页状态视图:loading / error(可重试) / empty。覆盖在内容之上。
@MainActor
final class StatefulPlaceholderView: UIView {

    enum State {
        case loading(String)
        case error(icon: String?, title: String, message: String?, retry: (() -> Void)?)
        case empty(icon: String?, title: String, message: String?)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case let (.loading(a), .loading(b)): return a == b
            case let (.error(a1, a2, a3, _), .error(b1, b2, b3, _)):
                return a1 == b1 && a2 == b2 && a3 == b3
            case let (.empty(a1, a2, a3), .empty(b1, b2, b3)):
                return a1 == b1 && a2 == b2 && a3 == b3
            default: return false
            }
        }
    }

    private let spinner = UIActivityIndicatorView(style: .medium)
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private var retryAction: (() -> Void)?

    var state: State = .loading("加载中") {
        didSet { render(state) }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.contentBackground

        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = Theme.tertiaryLabel

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = Theme.label
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = true

        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.textColor = Theme.secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.adjustsFontForContentSizeCategory = true

        retryButton.configuration = {
            var config = UIButton.Configuration.gray()
            config.title = "重试"
            config.cornerStyle = .capsule
            return config
        }()
        retryButton.addAction(UIAction { [weak self] _ in self?.retryAction?() }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [spinner, iconView, titleLabel, messageLabel, retryButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.setCustomSpacing(20, after: messageLabel)
        addSubview(stack)
        stack.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview().offset(-44)
            make.leading.greaterThanOrEqualToSuperview().inset(32)
            make.trailing.lessThanOrEqualToSuperview().inset(32)
        }

        iconView.snp.makeConstraints { make in
            make.size.equalTo(CGSize(width: 56, height: 56))
        }
        render(state)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func render(_ state: State) {
        switch state {
        case let .loading(text):
            isHidden = false
            spinner.startAnimating()
            spinner.isHidden = false
            iconView.isHidden = true
            retryButton.isHidden = true
            titleLabel.text = text
            messageLabel.text = nil
        case let .error(icon, title, message, retry):
            isHidden = false
            spinner.stopAnimating()
            spinner.isHidden = true
            iconView.isHidden = false
            iconView.image = UIImage(systemName: icon ?? "wifi.exclamationmark")
            retryAction = retry
            retryButton.isHidden = (retry == nil)
            titleLabel.text = title
            messageLabel.text = message
        case let .empty(icon, title, message):
            isHidden = false
            spinner.stopAnimating()
            spinner.isHidden = true
            iconView.isHidden = false
            iconView.image = UIImage(systemName: icon ?? "tray")
            retryAction = nil
            retryButton.isHidden = true
            titleLabel.text = title
            messageLabel.text = message
        }
    }
}

/// 轻提示(已复制/已收藏等),自动消失。
@MainActor
enum Toast {
    private static var currentLabel: UILabel?

    static func show(_ text: String, in view: UIView) {
        currentLabel?.removeFromSuperview()
        let label = PaddingLabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        currentLabel = label
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -48),
            label.widthAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.widthAnchor, constant: -24),
        ])
        label.alpha = 0
        UIView.animate(withDuration: 0.2) { label.alpha = 1 }
        UIView.animate(withDuration: 0.25, delay: 1.4, options: [.beginFromCurrentState]) {
            label.alpha = 0
        } completion: { _ in
            label.removeFromSuperview()
            if currentLabel === label { currentLabel = nil }
        }
    }
}

final class PaddingLabel: UILabel {
    var padding = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + padding.left + padding.right,
            height: size.height + padding.top + padding.bottom
        )
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: padding))
    }
}
