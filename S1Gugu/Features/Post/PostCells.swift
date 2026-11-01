import UIKit
import Kingfisher
import OSLog
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
    private let opBadge = UIView()
    private let opBadgeLabel = UILabel()
    private let floorLabel = UILabel()
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

        // 楼主徽标:方框样式(同主题列表「置顶」),容器 + 内边距 label
        opBadgeLabel.text = "楼主"
        opBadgeLabel.font = .preferredFont(forTextStyle: .caption2)
        opBadgeLabel.adjustsFontForContentSizeCategory = true
        opBadge.clipsToBounds = true
        opBadge.addSubview(opBadgeLabel)
        opBadgeLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(5)
            make.top.bottom.equalToSuperview().inset(2)
        }

        // 楼层号固定右上角,展示为 "#1" 样式
        floorLabel.font = .preferredFont(forTextStyle: .footnote)
        floorLabel.textColor = Theme.secondaryLabel
        floorLabel.adjustsFontForContentSizeCategory = true

        metaLabel.font = .preferredFont(forTextStyle: .caption1)
        metaLabel.textColor = Theme.tertiaryLabel
        metaLabel.adjustsFontForContentSizeCategory = true

        let nameRow = UIStackView(arrangedSubviews: [authorLabel, opBadge])
        nameRow.axis = .horizontal
        nameRow.spacing = 6
        nameRow.alignment = .center
        // 徽标是普通 UIView 无固有尺寸,行内余量会被它吸收;名字行只在
        // 日期行宽度内排布,内部视图一律 required 拥抱,方框才只包住文字
        authorLabel.setContentHuggingPriority(.required, for: .horizontal)
        authorLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        opBadge.setContentCompressionResistancePriority(.required, for: .horizontal)
        opBadgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        opBadgeLabel.setContentHuggingPriority(.required, for: .horizontal)

        let textStack = UIStackView(arrangedSubviews: [nameRow, metaLabel])
        textStack.axis = .vertical
        textStack.spacing = 3
        // .fill 会把名字行拉宽到日期行宽度,徽标随之被拉伸成大方框
        textStack.alignment = .leading

        contentView.addSubview(avatarView)
        contentView.addSubview(textStack)
        contentView.addSubview(floorLabel)
        avatarView.snp.makeConstraints { make in
            make.leading.equalTo(contentView.layoutMarginsGuide.snp.leading)
            make.top.equalToSuperview().inset(12)
            make.size.equalTo(CGSize(width: 40, height: 40))
            make.bottom.lessThanOrEqualToSuperview().inset(10)
        }
        textStack.snp.makeConstraints { make in
            make.leading.equalTo(avatarView.snp.trailing).offset(10)
            make.centerY.equalTo(avatarView)
            make.trailing.lessThanOrEqualTo(floorLabel.snp.leading).offset(-8)
        }
        floorLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(12)
            make.trailing.equalTo(contentView.layoutMarginsGuide.snp.trailing)
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

        // 徽标在 configure 里着色:主题切换/深浅模式时注册 cell 会重走配置
        opBadge.layer.borderColor = Theme.accent.withAlphaComponent(0.45).cgColor
        opBadge.layer.borderWidth = 1
        opBadge.layer.cornerRadius = 3
        opBadgeLabel.textColor = Theme.accent
        opBadge.isHidden = !model.isOp

        if let floor = model.floor {
            floorLabel.text = "#\(floor)"
            floorLabel.isHidden = false
        } else {
            floorLabel.isHidden = true
        }
        metaLabel.text = model.dateTimeText

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
        loadInlineImages(in: attributed)
    }

    /// 行内表情:占位附件经 InlineImageStore 异步回填图片
    private func loadInlineImages(in attributed: NSAttributedString) {
        let full = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttribute(.attachment, in: full) { value, _, _ in
            guard let attachment = value as? InlineImageAttachment, attachment.image == nil else { return }
            InlineImageStore.shared.image(for: attachment.url) { [weak self] image in
                guard let self, let image else { return }
                attachment.image = image
                self.refreshAttachment(attachment)
            }
        }
    }

    /// 通知 TextKit 附件属性变化,重排当前文本(高度已被占位 bounds 预留,无需重建布局)
    private func refreshAttachment(_ attachment: InlineImageAttachment) {
        let storage = textView.textStorage
        let full = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.attachment, in: full) { value, range, stop in
            guard (value as? InlineImageAttachment) === attachment else { return }
            storage.edited(.editedAttributes, range: range, changeInLength: 0)
            stop.pointee = true
        }
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

    private static let imageLogger = Logger(subsystem: "app.bitxeno.s1gugu", category: "image")

    private let imageView = UIImageView()
    private let progressIndicator = UIActivityIndicatorView(style: .medium)
    private let statusView = UIView()
    private let statusIcon = UIImageView()
    private let statusLabel = UILabel()

    private enum LoadPhase { case idle, loading, loaded, failed, pendingUserLoad }
    private var phase: LoadPhase = .idle

    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?
    private var postImage: PostImage?
    /// configure 计算的占位尺寸(HTML 宽高或估算),重试时恢复
    private var preferredSize: CGSize = CGSize(width: 300, height: 160)

    var onTap: ((PostImage) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8
        imageView.isUserInteractionEnabled = true
        imageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(imageTapped)))

        statusView.backgroundColor = .secondarySystemFill
        statusView.layer.cornerRadius = 8
        statusView.isHidden = true
        statusIcon.contentMode = .scaleAspectFit
        statusIcon.tintColor = Theme.secondaryLabel
        statusIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .title3)
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = Theme.secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        statusLabel.adjustsFontForContentSizeCategory = true

        let statusStack = UIStackView(arrangedSubviews: [statusIcon, statusLabel])
        statusStack.axis = .vertical
        statusStack.alignment = .center
        statusStack.spacing = 6
        statusView.addSubview(statusStack)

        contentView.addSubview(imageView)
        contentView.addSubview(statusView)
        contentView.addSubview(progressIndicator)
        imageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().inset(4)
            make.bottom.equalToSuperview().inset(4)
        }
        statusView.snp.makeConstraints { make in
            make.edges.equalTo(imageView)
        }
        statusStack.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().inset(12)
            make.trailing.lessThanOrEqualToSuperview().inset(12)
        }
        progressIndicator.snp.makeConstraints { make in
            make.center.equalTo(imageView)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func imageTapped() {
        guard let postImage else { return }
        switch phase {
        case .pendingUserLoad, .failed:
            // 蜂窝网络待加载 / 加载失败:点击重新加载
            startLoad()
        case .loaded:
            onTap?(postImage)
        case .idle, .loading:
            break
        }
    }

    func configure(_ postImage: PostImage, index: Int, onTap: @escaping (PostImage) -> Void) {
        self.postImage = postImage
        self.onTap = onTap
        phase = .idle
        progressIndicator.stopAnimating()
        imageView.image = nil
        statusView.isHidden = true

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
        preferredSize = CGSize(width: targetWidth, height: targetHeight)
        updateSize(width: targetWidth, height: targetHeight)

        let blocked = AppSettings.wifiOnlyImages && NetworkMonitor.shared.isExpensive
        if blocked {
            phase = .pendingUserLoad
            showStatus(icon: "icloud.and.arrow.down", text: "蜂窝网络已暂停加载\n点击加载")
            return
        }
        startLoad()
    }

    /// 失败/蜂窝占位:图标 + 说明,压成紧凑卡片高度,避免大图占位留下一片空白
    private func showStatus(icon name: String, text: String) {
        statusIcon.image = UIImage(systemName: name)
        statusLabel.text = text
        statusView.isHidden = false
        progressIndicator.stopAnimating()
        updateSize(width: preferredSize.width, height: 96)
        invalidateCellHeight()
    }

    private func startLoad() {
        guard let postImage else { return }
        phase = .loading
        statusView.isHidden = true
        progressIndicator.startAnimating()
        updateSize(width: preferredSize.width, height: preferredSize.height)
        invalidateCellHeight()
        let maxWidth = UIScreen.main.bounds.width
        let processor = DownsamplingImageProcessor(size: CGSize(width: maxWidth * UIScreen.main.scale, height: 2400))
        imageView.kf.setImage(
            with: postImage.url,
            options: [
                .processor(processor),
                .transition(.fade(0.2)),
                .cacheOriginalImage,
                // 大图边下边显示(渐进式 JPEG),弱网下不用等完整文件
                .progressiveJPEG(ImageProgressive()),
            ],
            completionHandler: { [weak self] result in
                guard let self, self.postImage?.url == postImage.url, self.phase == .loading else { return }
                self.progressIndicator.stopAnimating()
                switch result {
                case .success(let value):
                    self.phase = .loaded
                    self.applySize(ofNativeImage: value.image)
                case .failure(let error):
                    // 复用/刷新取消的请求不算失败
                    guard error.isTaskCancelled == false else { return }
                    Self.imageLogger.error("图片加载失败 \(self.postImage?.url.absoluteString ?? "-", privacy: .public): \(String(describing: error), privacy: .public)")
                    self.phase = .failed
                    self.showStatus(icon: "photo.badge.exclamationmark", text: "图片加载失败\n点击重试")
                }
            }
        )
    }

    private func invalidateCellHeight() {
        (superview as? UICollectionView)?.collectionViewLayout.invalidateLayout()
    }

    private func applySize(ofNativeImage image: UIImage) {
        let available = UIScreen.main.bounds.width - 32
        // 原始像素宽 = 显示宽上限,小图(表情)不放大
        let nativeWidth = image.size.width * image.scale
        let nativeHeight = image.size.height * image.scale
        let width = min(available, nativeWidth)
        let height = min(width * nativeHeight / max(nativeWidth, 1), available * 2.5)
        updateSize(width: width, height: height)
        invalidateCellHeight()
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
