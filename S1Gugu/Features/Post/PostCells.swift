import UIKit
import Kingfisher
import SnapKit

// MARK: - 楼层头

struct PostHeaderModel: Hashable, Sendable {
    let pid: Int
    let author: String
    let authorId: Int
    let avatarURL: URL?
    let dateTimeText: String
    let floor: Int?
    let isOp: Bool
}

final class PostHeaderCell: UICollectionViewCell {

    private let avatarView = UIImageView()
    private let authorLabel = UILabel()
    private let opBadge = UILabel()
    private let metaLabel = UILabel()

    var onAvatarTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        avatarView.contentMode = .scaleAspectFill
        avatarView.layer.cornerRadius = 20
        avatarView.layer.masksToBounds = true
        avatarView.image = UIImage(systemName: "person.crop.circle.fill")
        avatarView.tintColor = Theme.tertiaryLabel
        avatarView.isUserInteractionEnabled = true
        avatarView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(avatarTapped)))

        authorLabel.font = .preferredFont(forTextStyle: .subheadline).bold()
        authorLabel.textColor = Theme.label
        authorLabel.adjustsFontForContentSizeCategory = true

        opBadge.text = "楼主"
        opBadge.font = .preferredFont(forTextStyle: .caption2)
        opBadge.textColor = Theme.accent
        opBadge.textAlignment = .center
        opBadge.layer.cornerRadius = 4
        opBadge.layer.borderWidth = 1
        opBadge.layer.borderColor = Theme.accent.cgColor
        opBadge.adjustsFontForContentSizeCategory = true

        metaLabel.font = .preferredFont(forTextStyle: .caption1)
        metaLabel.textColor = Theme.tertiaryLabel
        metaLabel.adjustsFontForContentSizeCategory = true

        let nameRow = UIStackView(arrangedSubviews: [authorLabel, opBadge])
        nameRow.axis = .horizontal
        nameRow.spacing = 6
        nameRow.alignment = .center

        let textStack = UIStackView(arrangedSubviews: [nameRow, metaLabel])
        textStack.axis = .vertical
        textStack.spacing = 3

        contentView.addSubview(avatarView)
        contentView.addSubview(textStack)
        avatarView.snp.makeConstraints { make in
            make.leading.equalTo(contentView.layoutMarginsGuide.snp.leading)
            make.top.equalToSuperview().inset(12)
            make.size.equalTo(CGSize(width: 40, height: 40))
            make.bottom.lessThanOrEqualToSuperview().inset(10)
        }
        textStack.snp.makeConstraints { make in
            make.leading.equalTo(avatarView.snp.trailing).offset(10)
            make.centerY.equalTo(avatarView)
            make.trailing.lessThanOrEqualTo(contentView.layoutMarginsGuide.snp.trailing)
        }
        opBadge.snp.makeConstraints { make in
            make.height.equalTo(16)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func avatarTapped() {
        onAvatarTap?()
    }

    func configure(_ model: PostHeaderModel) {
        authorLabel.text = model.author
        opBadge.isHidden = !model.isOp
        var meta: [String] = []
        if !model.dateTimeText.isEmpty { meta.append(model.dateTimeText) }
        if let floor = model.floor { meta.append("\(floor) 楼") }
        metaLabel.text = meta.joined(separator: " · ")

        if let url = model.avatarURL {
            avatarView.kf.setImage(
                with: url,
                placeholder: UIImage(systemName: "person.crop.circle.fill"),
                options: [.transition(.fade(0.15))]
            )
        } else {
            avatarView.image = UIImage(systemName: "person.crop.circle.fill")
        }
    }
}

// MARK: - 文本块

final class TextBlockCell: UICollectionViewCell, UITextViewDelegate {

    private let textView = UITextView()

    var onLinkTap: ((URL) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        textView.isScrollEnabled = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.linkTextAttributes = [.foregroundColor: Theme.accent]
        textView.delegate = self
        textView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            textView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),
            textView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ attributed: NSAttributedString) {
        textView.attributedText = attributed
    }

    // MARK: UITextViewDelegate

    func textView(
        _ textView: UITextView,
        shouldInteractWith URL: URL,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        guard interaction == .invokeDefaultAction else { return true }
        onLinkTap?(URL)
        return false
    }
}

// MARK: - 图片块

final class ImageBlockCell: UICollectionViewCell {

    private let imageView = UIImageView()
    private let overlayLabel = UILabel()

    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?
    private var postImage: PostImage?
    private var isPendingUserLoad = false

    var onTap: ((PostImage) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8
        imageView.isUserInteractionEnabled = true
        imageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(imageTapped)))

        overlayLabel.font = .preferredFont(forTextStyle: .footnote)
        overlayLabel.textColor = .white
        overlayLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        overlayLabel.textAlignment = .center
        overlayLabel.layer.cornerRadius = 6
        overlayLabel.clipsToBounds = true
        overlayLabel.isHidden = true

        contentView.addSubview(imageView)
        contentView.addSubview(overlayLabel)
        imageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().inset(4)
            make.bottom.equalToSuperview().inset(4)
        }
        overlayLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.height.greaterThanOrEqualTo(28)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func imageTapped() {
        guard let postImage else { return }
        if isPendingUserLoad {
            isPendingUserLoad = false
            overlayLabel.isHidden = true
            loadImage(postImage)
            return
        }
        onTap?(postImage)
    }

    func configure(_ postImage: PostImage, index: Int, onTap: @escaping (PostImage) -> Void) {
        self.postImage = postImage
        self.onTap = onTap

        // 显示尺寸上限 = 原始宽(HTML 属性/加载后像素),不放大,居中(对齐 S1-Next)
        let available = UIScreen.main.bounds.width - 32
        let originalWidth = postImage.displayWidth.map(CGFloat.init)
        let targetWidth = min(available, originalWidth ?? available)
        let targetHeight: CGFloat
        if let ratio = postImage.aspectRatio, ratio > 0 {
            targetHeight = targetWidth / ratio
        } else if let originalWidth {
            targetHeight = originalWidth * 0.75
        } else {
            targetHeight = 160
        }
        updateSize(width: targetWidth, height: targetHeight)

        let blocked = AppSettings.wifiOnlyImages && NetworkMonitor.shared.isExpensive
        if blocked {
            isPendingUserLoad = true
            overlayLabel.isHidden = false
            overlayLabel.text = "当前为蜂窝网络\n点击加载图片"
            overlayLabel.numberOfLines = 2
            return
        }
        loadImage(postImage)
    }

    private func updateSize(width: CGFloat, height: CGFloat) {
        widthConstraint?.isActive = false
        heightConstraint?.isActive = false
        let w = imageView.widthAnchor.constraint(equalToConstant: max(width, 40))
        let h = imageView.heightAnchor.constraint(equalToConstant: max(height, 40))
        w.priority = .defaultHigh
        h.priority = .defaultHigh
        w.isActive = true
        h.isActive = true
        widthConstraint = w
        heightConstraint = h
    }

    private func loadImage(_ postImage: PostImage) {
        let maxWidth = UIScreen.main.bounds.width
        let processor = DownsamplingImageProcessor(size: CGSize(width: maxWidth * UIScreen.main.scale, height: 2400))
        imageView.kf.setImage(
            with: postImage.url,
            options: [.processor(processor), .transition(.fade(0.2)), .cacheOriginalImage],
            completionHandler: { [weak self] result in
                guard let self, let image = try? result.get().image else { return }
                let available = UIScreen.main.bounds.width - 32
                // 原始像素宽 = 显示宽上限,小图(表情)不放大
                let nativeWidth = image.size.width * image.scale
                let nativeHeight = image.size.height * image.scale
                let width = min(available, nativeWidth)
                let height = min(width * nativeHeight / max(nativeWidth, 1), available * 2.5)
                self.updateSize(width: width, height: height)
                (self.superview as? UICollectionView)?.collectionViewLayout.invalidateLayout()
            }
        )
    }
}

// MARK: - 引用块

final class QuoteBlockCell: UICollectionViewCell, UITextViewDelegate {

    private let authorLabel = UILabel()
    private let textView = UITextView()
    private let barView = UIView()

    var onLinkTap: ((URL) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        barView.backgroundColor = Theme.accent.withAlphaComponent(0.6)
        barView.layer.cornerRadius = 1.5

        authorLabel.font = .preferredFont(forTextStyle: .caption1)
        authorLabel.textColor = Theme.tertiaryLabel
        authorLabel.adjustsFontForContentSizeCategory = true

        textView.isScrollEnabled = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.linkTextAttributes = [.foregroundColor: Theme.accent]
        textView.delegate = self

        let textStack = UIStackView(arrangedSubviews: [authorLabel, textView])
        textStack.axis = .vertical
        textStack.spacing = 4

        let container = UIView()
        container.backgroundColor = .secondarySystemBackground
        container.layer.cornerRadius = Theme.cardCornerRadius
        container.addSubview(barView)
        container.addSubview(textStack)

        contentView.addSubview(container)
        container.snp.makeConstraints { make in
            make.leading.equalTo(contentView.layoutMarginsGuide.snp.leading)
            make.trailing.equalTo(contentView.layoutMarginsGuide.snp.trailing)
            make.top.equalToSuperview().inset(4)
            make.bottom.equalToSuperview().inset(4)
        }
        barView.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview().inset(10)
            make.width.equalTo(3)
        }
        textStack.snp.makeConstraints { make in
            make.leading.equalTo(barView.snp.trailing).offset(10)
            make.top.trailing.bottom.equalToSuperview().inset(10)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(author: String?, attributed: NSAttributedString) {
        authorLabel.text = author.map { "\($0) 的引用" }
        authorLabel.isHidden = (author == nil)
        textView.attributedText = attributed
    }

    func textView(
        _ textView: UITextView,
        shouldInteractWith URL: URL,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        guard interaction == .invokeDefaultAction else { return true }
        onLinkTap?(URL)
        return false
    }
}

// MARK: - 代码块

final class CodeBlockCell: UICollectionViewCell {

    private let textView = UITextView()
    private let copyButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)

        let codeFont: UIFont = {
            let metrics = UIFontMetrics(forTextStyle: .footnote)
            return metrics.scaledFont(for: UIFont(name: "Menlo-Regular", size: 13) ?? .monospacedSystemFont(ofSize: 13, weight: .regular))
        }()

        textView.isScrollEnabled = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        textView.textContainer.lineFragmentPadding = 0
        textView.font = codeFont
        textView.adjustsFontForContentSizeCategory = false

        let container = UIView()
        container.backgroundColor = .secondarySystemBackground
        container.layer.cornerRadius = Theme.cardCornerRadius
        container.addSubview(textView)

        contentView.addSubview(container)
        container.snp.makeConstraints { make in
            make.leading.trailing.equalTo(contentView.layoutMarginsGuide)
            make.top.equalToSuperview().inset(4)
            make.bottom.equalToSuperview().inset(4)
        }
        textView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ code: String) {
        textView.attributedText = NSAttributedString(
            string: code,
            attributes: [
                .font: textView.font ?? .systemFont(ofSize: 13),
                .foregroundColor: Theme.label,
            ]
        )
    }
}

// MARK: - 文件附件

final class FileAttachmentCell: UICollectionViewCell {

    private let iconView = UIImageView()
    private let nameLabel = UILabel()
    private let sizeLabel = UILabel()

    var onTap: ((URL) -> Void)?
    private var url: URL?

    override init(frame: CGRect) {
        super.init(frame: frame)

        iconView.image = UIImage(systemName: "doc")
        iconView.tintColor = Theme.accent
        iconView.contentMode = .scaleAspectFit

        nameLabel.font = .preferredFont(forTextStyle: .subheadline)
        nameLabel.textColor = Theme.label
        nameLabel.adjustsFontForContentSizeCategory = true

        sizeLabel.font = .preferredFont(forTextStyle: .caption1)
        sizeLabel.textColor = Theme.tertiaryLabel
        sizeLabel.adjustsFontForContentSizeCategory = true

        let stack = UIStackView(arrangedSubviews: [iconView, nameLabel, sizeLabel])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center

        let container = UIView()
        container.backgroundColor = .secondarySystemBackground
        container.layer.cornerRadius = Theme.cardCornerRadius
        container.addSubview(stack)
        contentView.addSubview(container)

        container.snp.makeConstraints { make in
            make.leading.trailing.equalTo(contentView.layoutMarginsGuide)
            make.top.equalToSuperview().inset(3)
            make.bottom.equalToSuperview().inset(3)
        }
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(10)
        }
        iconView.snp.makeConstraints { make in
            make.size.equalTo(CGSize(width: 20, height: 22))
        }
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        container.addGestureRecognizer(tap)
        container.isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func tapped() {
        guard let url else { return }
        onTap?(url)
    }

    func configure(_ file: PostFileAttachment, onTap: @escaping (URL) -> Void) {
        self.url = file.url
        self.onTap = onTap
        nameLabel.text = file.name
        sizeLabel.text = file.sizeText
    }
}

// MARK: - 屏蔽楼层占位

final class HiddenPostCell: UICollectionViewCell {

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = Theme.tertiaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        contentView.addSubview(label)
        label.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 14, left: 20, bottom: 14, right: 20))
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(remark: String?) {
        if let remark, !remark.isEmpty {
            label.text = "该楼层已被屏蔽(\(remark))"
        } else {
            label.text = "该楼层已被屏蔽"
        }
    }
}

extension UIFont {
    func bold() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
