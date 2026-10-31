import UIKit
import Kingfisher

// MARK: - Sendable 包装

/// NSAttributedString 官方未标注 Sendable,渲染管线跨线程传递时用此不可变包装。
struct AttributedText: Hashable, @unchecked Sendable {
    let value: NSAttributedString

    init(_ value: NSAttributedString) {
        self.value = value
    }
}

// MARK: - 渲染块模型(后台线程产出,主线程消费)

enum PostBlock: Hashable, Sendable {
    /// 普通文本段(可含内联表情附件、链接)
    case text(AttributedText)
    /// 独立成段的帖子图片
    case image(PostImage)
    /// 引用块(一层展示,内部归因文本)
    case quote(author: String?, attributed: AttributedText)
    /// 代码块
    case code(String)
    /// 文件附件
    case fileAttachment(PostFileAttachment)
    /// 复杂结构(表格等)降级归因文本
    case fallback(AttributedText)
}

struct PostImage: Hashable, Sendable {
    let url: URL
    /// 来自 HTML width/height 属性的显示宽高(用于比例占位);可能缺失
    let displayWidth: Int?
    let displayHeight: Int?

    var aspectRatio: CGFloat? {
        guard let w = displayWidth, let h = displayHeight, w > 0, h > 0 else { return nil }
        return CGFloat(w) / CGFloat(h)
    }
}

struct PostFileAttachment: Hashable, Sendable {
    let name: String
    let url: URL
    let sizeText: String?
}

// MARK: - 内联图片(表情/小图)异步填充

/// NSTextAttachment 的占位实现:BlockSplitter 先塞进归因文本,图片到位后回填。
final class InlineImageAttachment: NSTextAttachment, @unchecked Sendable {
    let url: URL
    let pointSize: CGFloat

    init(url: URL, pointSize: CGFloat) {
        self.url = url
        self.pointSize = pointSize
        super.init(data: nil, ofType: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        CGRect(x: 0, y: -2, width: pointSize, height: pointSize)
    }
}

/// 表情/内联小图的下载缓存;回调统一回主线程。
final class InlineImageStore: @unchecked Sendable {

    static let shared = InlineImageStore()

    private let cache = NSCache<NSURL, UIImage>()
    private let lock = NSLock()
    private var pending: [URL: [(UIImage?) -> Void]] = [:]

    private init() {
        cache.countLimit = 600
    }

    func image(for url: URL, completion: @escaping (UIImage?) -> Void) {
        if let image = cache.object(forKey: url as NSURL) {
            completion(image)
            return
        }
        lock.lock()
        pending[url, default: []].append(completion)
        lock.unlock()

        KingfisherManager.shared.retrieveImage(with: url) { [weak self] result in
            guard let self else { return }
            let image = try? result.get().image
            if let image {
                self.cache.setObject(image, forKey: url as NSURL)
            }
            self.lock.lock()
            let callbacks = self.pending[url] ?? []
            self.pending[url] = nil
            self.lock.unlock()
            DispatchQueue.main.async {
                callbacks.forEach { $0(image) }
            }
        }
    }
}
