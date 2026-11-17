import UIKit
import SnapKit

/// 导航栏正下方的列表加载指示:在标题栏与列表相接处显示一条 accent 色细进度条
/// 左右往复滑动;加载完成后淡出隐藏。浮在列表顶部且只占 2pt,不遮挡内容。
@MainActor
final class LoadingBar: UIView {

    private let bar = UIView()
    private var isRunning = false
    /// 上一次开始动画时的自身宽度,用于布局变化(旋转/分屏)后按新宽度重启动画
    private var animationWidth: CGFloat = 0

    /// 细条高度
    private static let barHeight: CGFloat = 2
    /// 指示器整体高度(与细条等高,避免遮住下方内容)
    static let preferredHeight: CGFloat = barHeight

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isHidden = true
        isUserInteractionEnabled = false
        alpha = 0

        bar.backgroundColor = Theme.accent
        bar.layer.cornerRadius = Self.barHeight / 2
        addSubview(bar)

        bar.snp.makeConstraints { make in
            make.bottom.equalToSuperview()
            make.height.equalTo(Self.barHeight)
            make.width.equalToSuperview().multipliedBy(0.35)
            make.leading.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 首次开始动画时可能还没完成布局(宽度为 0),或布局宽度变了,这里兜底(重)启动
        if isRunning, bounds.width > 0, bounds.width != animationWidth {
            startBarAnimation()
        }
    }

    func startAnimating() {
        guard !isRunning else { return }
        isRunning = true
        isHidden = false
        alpha = 1
        // 主动触发布局,尽量当帧就开始滑动
        setNeedsLayout()
        layoutIfNeeded()
        startBarAnimation()
    }

    private func startBarAnimation() {
        let width = bounds.width
        guard width > 0 else { return }
        animationWidth = width

        bar.layer.removeAllAnimations()
        let barWidth = bar.bounds.width > 0 ? bar.bounds.width : max(width * 0.35, 24)
        // 从左侧屏幕外滑到右侧屏幕外,往复循环
        bar.transform = CGAffineTransform(translationX: -barWidth, y: 0)
        UIView.animate(
            withDuration: 1.1,
            delay: 0,
            options: [.curveEaseInOut, .repeat, .autoreverse]
        ) {
            self.bar.transform = CGAffineTransform(translationX: width, y: 0)
        }
    }

    func stopAnimating() {
        guard isRunning else { return }
        isRunning = false
        animationWidth = 0
        bar.layer.removeAllAnimations()
        UIView.animate(withDuration: 0.2, animations: {
            self.alpha = 0
        }, completion: { _ in
            // 淡出期间若又开始了新一轮加载,保持可见
            if !self.isRunning {
                self.isHidden = true
                self.alpha = 0
            }
        })
    }
}
