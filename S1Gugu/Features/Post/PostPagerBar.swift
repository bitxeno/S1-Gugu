import UIKit
import SnapKit

/// 帖子详情底部功能栏:前一页 · 下一页 · 当前页进度 · 回复 · 分享。
///
/// 视觉对齐 mockup:与页面同色无分隔线,图标用黄绿(postToolbarTint),
/// 中间为橄榄黄绿胶囊显示当前页码。仅负责展示与回调,不持有业务状态。
@MainActor
final class PostPagerBar: UIView {

    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    var onProgress: (() -> Void)?
    var onReply: (() -> Void)?
    var onShare: (() -> Void)?

    private let stack = UIStackView()
    private let prevButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let progressButton = UIButton(type: .custom)
    /// 胶囊进度填充(叠在 progressButton 背景轨道之上,宽度随阅读进度变化)
    private let progressFill = UIView()
    private let replyButton = UIButton(type: .system)
    private let shareButton = UIButton(type: .system)

    private var progressFillWidth: Constraint?
    private var state = PostPagerState(currentPage: 0, pageCount: 1)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setup() {
        backgroundColor = Theme.contentBackground

        configureIconButton(prevButton, systemName: "chevron.up", accessibility: "上一页")
        configureIconButton(nextButton, systemName: "chevron.down", accessibility: "下一页")
        configureIconButton(replyButton, systemName: "arrowshape.turn.up.left", accessibility: "回复")
        configureIconButton(shareButton, systemName: "square.and.arrow.up", accessibility: "分享")
        configureProgressButton()

        prevButton.addTarget(self, action: #selector(handlePrevious), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(handleNext), for: .touchUpInside)
        progressButton.addTarget(self, action: #selector(handleProgress), for: .touchUpInside)
        replyButton.addTarget(self, action: #selector(handleReply), for: .touchUpInside)
        shareButton.addTarget(self, action: #selector(handleShare), for: .touchUpInside)

        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .equalSpacing
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        [prevButton, nextButton, progressButton, replyButton, shareButton].forEach(stack.addArrangedSubview)
        addSubview(stack)

        stack.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.leading.equalToSuperview()
            make.trailing.equalToSuperview()
            make.height.equalTo(48)
            make.bottom.equalTo(safeAreaLayoutGuide.snp.bottom)
        }

        // 固定宽度:图标按钮 44×44 触控,胶囊约 100pt 宽
        [prevButton, nextButton, replyButton, shareButton].forEach { button in
            button.snp.makeConstraints { make in
                make.width.height.equalTo(44)
            }
        }
        progressButton.snp.makeConstraints { make in
            make.width.equalTo(108)
            make.height.equalTo(32)
        }

        // 进度填充:贴胶囊左侧,宽度按比例,铺满高度;叠在按钮背景之上、文字之下
        progressButton.insertSubview(progressFill, at: 0)
        progressFill.isUserInteractionEnabled = false
        progressFill.backgroundColor = Theme.postPagerPillFill
        progressFill.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            progressFillWidth = make.width.equalTo(0).constraint
        }

        applyState()
    }

    private func configureIconButton(_ button: UIButton, systemName: String, accessibility: String) {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: systemName)
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold)
        config.contentInsets = .zero
        button.configuration = config
        button.accessibilityLabel = accessibility
        button.configurationUpdateHandler = { button in
            var updated = button.configuration
            updated?.baseForegroundColor = button.isEnabled ? Theme.postToolbarTint : Theme.postToolbarDisabled
            button.configuration = updated
        }
    }

    private func configureProgressButton() {
        progressButton.backgroundColor = Theme.postPagerPill
        progressButton.layer.cornerRadius = 16
        progressButton.layer.masksToBounds = true
        progressButton.setTitle("–", for: .normal)
        progressButton.setTitleColor(.white, for: .normal)
        progressButton.titleLabel?.font = .monospacedDigitSystemFont(ofSize: 16, weight: .medium)
        progressButton.accessibilityLabel = "当前页进度"
        progressButton.accessibilityHint = "点击选择页面"
    }

    // MARK: - Public

    /// 更新翻页状态与胶囊文案
    func update(currentPage: Int, pageCount: Int) {
        state = PostPagerState(currentPage: currentPage, pageCount: pageCount)
        applyState()
    }

    private func applyState() {
        prevButton.isEnabled = state.canPrevious
        nextButton.isEnabled = state.canNext
        progressButton.setTitle(state.progressText, for: .normal)
        progressButton.accessibilityLabel = "当前第 \(max(state.currentPage, 1)) 页,共 \(state.pageCount) 页"

        // 进度填充宽度 = 当前页/总页数 × 胶囊宽度
        let ratio = min(max(Double(state.currentPage) / Double(max(state.pageCount, 1)), 0), 1)
        progressFillWidth?.update(offset: 0)
        progressFillWidth?.update(offset: 108 * CGFloat(ratio))
    }

    // MARK: - Actions

    @objc private func handlePrevious() { if state.canPrevious { onPrevious?() } }
    @objc private func handleNext() { if state.canNext { onNext?() } }
    @objc private func handleProgress() { onProgress?() }
    @objc private func handleReply() { onReply?() }
    @objc private func handleShare() { onShare?() }
}
