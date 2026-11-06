import UIKit
import CoreImage.CIFilterBuiltins
import Kingfisher

/// 楼层分享长图:标题 + 楼层头 + 正文块 + 二维码水印,离屏渲染为 UIImage。
@MainActor
enum ShareCardRenderer {

    static func render(
        post: Post,
        blocks: [PostBlock],
        threadTitle: String,
        threadURL: URL
    ) async -> UIImage {
        let width: CGFloat = 640
        let margin: CGFloat = 36
        let contentWidth = width - margin * 2

        let container = UIView()
        container.backgroundColor = .white
        container.frame = CGRect(x: 0, y: 0, width: width, height: 100)
        container.translatesAutoresizingMaskIntoConstraints = true

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 18
        container.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: margin),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -margin),
        ])

        // 标题
        let titleLabel = UILabel()
        titleLabel.numberOfLines = 0
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = .black
        titleLabel.text = threadTitle
        stack.addArrangedSubview(titleLabel)

        // 楼层头
        let metaLabel = UILabel()
        metaLabel.numberOfLines = 0
        metaLabel.font = .systemFont(ofSize: 15)
        metaLabel.textColor = UIColor(white: 0.45, alpha: 1)
        metaLabel.text = [post.author, post.dateTimeText, post.floor.map { "\($0) 楼" }]
            .compactMap { $0 }
            .joined(separator: " · ")
        stack.addArrangedSubview(metaLabel)

        // 头像:优先用加载到的图片,没有则回退到默认头像,保证楼层头始终有头像
        var avatar = DefaultAvatar.image
        if let avatarURL = post.avatarURL, let cached = await cachedImage(avatarURL) {
            avatar = cached
        }
        let avatarView = UIImageView(image: avatar)
        avatarView.layer.cornerRadius = 24
        avatarView.clipsToBounds = true
        avatarView.widthAnchor.constraint(equalToConstant: 48).isActive = true
        avatarView.heightAnchor.constraint(equalToConstant: 48).isActive = true
        avatarView.contentMode = .scaleAspectFill
        let headerRow = UIStackView(arrangedSubviews: [avatarView, metaLabel])
        headerRow.axis = .horizontal
        headerRow.spacing = 14
        headerRow.alignment = .center
        if let index = stack.arrangedSubviews.firstIndex(of: metaLabel) {
            stack.insertArrangedSubview(headerRow, at: index)
        }

        // 正文块
        for block in blocks {
            switch block {
            case let .text(attributed), let .fallback(attributed):
                stack.addArrangedSubview(makeLabel(attributed.value))
            case let .quote(author, dateText, attributed):
                let quoteLabel = makeLabel(attributed.value)
                quoteLabel.textColor = UIColor(white: 0.35, alpha: 1)
                let wrapper = makeQuoteWrapper(quoteLabel, author: author, dateText: dateText)
                stack.addArrangedSubview(wrapper)
            case let .code(code):
                let codeLabel = makeLabel(NSAttributedString(string: code))
                codeLabel.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
                codeLabel.backgroundColor = UIColor(white: 0.94, alpha: 1)
                codeLabel.numberOfLines = 0
                stack.addArrangedSubview(codeLabel)
            case let .image(imageInfo):
                if let image = await cachedImage(imageInfo.url) {
                    let imageView = UIImageView(image: image)
                    imageView.contentMode = .scaleAspectFit
                    imageView.clipsToBounds = true
                    imageView.layer.cornerRadius = 8
                    let ratio = image.size.height / max(image.size.width, 1)
                    imageView.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
                    imageView.heightAnchor.constraint(equalToConstant: contentWidth * min(ratio, 3)).isActive = true
                    stack.addArrangedSubview(imageView)
                }
            case let .fileAttachment(file):
                let label = makeLabel(NSAttributedString(string: "📎 \(file.name)"))
                stack.addArrangedSubview(label)
            }
        }

        // 底部:二维码 + 水印
        let footer = makeFooter(threadURL: threadURL)
        stack.addArrangedSubview(footer)

        // 高度计算 + 渲染(强制浅色,长图分享惯例白底黑字)
        let fittingSize = container.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
        )
        let size = CGSize(width: width, height: max(fittingSize.height, 120) + margin)
        container.bounds = CGRect(origin: .zero, size: size)
        // 长图固定浅色渲染
        container.overrideUserInterfaceStyle = .light
        container.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            container.drawHierarchy(in: container.bounds, afterScreenUpdates: true)
        }
    }

    // MARK: - Pieces

    private static func makeLabel(_ attributed: NSAttributedString) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.attributedText = attributed
        return label
    }

    private static func makeQuoteWrapper(_ label: UILabel, author: String?, dateText: String?) -> UIView {
        let wrapper = UIView()
        wrapper.backgroundColor = UIColor(white: 0.96, alpha: 1)
        wrapper.layer.cornerRadius = 8
        if let author, !author.isEmpty {
            let authorLabel = UILabel()
            authorLabel.text = dateText.map { "\(author) 发表于 \($0)" } ?? author
            authorLabel.font = .systemFont(ofSize: 12)
            authorLabel.textColor = UIColor(white: 0.55, alpha: 1)
            label.text = label.text ?? ""
            let inner = UIStackView(arrangedSubviews: [authorLabel, label])
            inner.axis = .vertical
            inner.spacing = 6
            wrapper.addSubview(inner)
            inner.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                inner.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 10),
                inner.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -10),
                inner.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 14),
                inner.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -14),
            ])
        } else {
            wrapper.addSubview(label)
            label.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 10),
                label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -10),
                label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 14),
                label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -14),
            ])
        }
        return wrapper
    }

    private static func makeFooter(threadURL: URL) -> UIView {
        let footer = UIStackView()
        footer.axis = .horizontal
        footer.spacing = 16
        footer.alignment = .center

        let qr = makeQRCode(threadURL.absoluteString)
        let qrView = UIImageView(image: qr)
        qrView.widthAnchor.constraint(equalToConstant: 88).isActive = true
        qrView.heightAnchor.constraint(equalToConstant: 88).isActive = true
        qrView.contentMode = .scaleAspectFit
        footer.addArrangedSubview(qrView)

        let watermark = UILabel()
        watermark.numberOfLines = 0
        watermark.text = "来自 S1 Gugu\nStage1st 论坛"
        watermark.font = .systemFont(ofSize: 14)
        watermark.textColor = UIColor(white: 0.55, alpha: 1)
        footer.addArrangedSubview(watermark)
        return footer
    }

    static func makeQRCode(_ string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    private static func cachedImage(_ url: URL) async -> UIImage? {
        await withCheckedContinuation { continuation in
            KingfisherManager.shared.retrieveImage(with: url) { result in
                continuation.resume(returning: (try? result.get().image) ?? nil)
            }
        }
    }
}
