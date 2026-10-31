import UIKit

/// 楼层快速侧边条(对齐 S1-Next QuickSideBar):A–Z 字母条,滑动跳转对应楼层。
final class QuickSideBarView: UIView {

    static let letters: [Character] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(\.self)

    /// 滑动经过字母时回调(0–25)
    var onIndexChange: ((Int) -> Void)?
    /// 手指抬起(跳转结束)
    var onTouchEnd: (() -> Void)?

    private let stack = UIStackView()
    private var letterLabels: [UILabel] = []
    private var currentIndex: Int?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = true

        stack.axis = .vertical
        stack.distribution = .fillEqually
        stack.alignment = .center
        addSubview(stack)
        stack.frame = bounds
        stack.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        for letter in Self.letters {
            let label = UILabel()
            label.text = String(letter)
            label.font = .systemFont(ofSize: 9, weight: .semibold)
            label.textColor = Theme.accent
            label.textAlignment = .center
            label.isUserInteractionEnabled = false
            stack.addArrangedSubview(label)
            letterLabels.append(label)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        stack.frame = bounds
    }

    // MARK: - Touch tracking

    private func index(at location: CGPoint) -> Int? {
        guard bounds.height > 0 else { return nil }
        let ratio = min(max(location.y / bounds.height, 0), 0.999)
        return Int(ratio * CGFloat(Self.letters.count))
    }

    private func highlight(_ index: Int?) {
        guard currentIndex != index else { return }
        if let old = currentIndex, letterLabels.indices.contains(old) {
            letterLabels[old].textColor = Theme.accent
            letterLabels[old].font = .systemFont(ofSize: 9, weight: .semibold)
        }
        currentIndex = index
        if let index, letterLabels.indices.contains(index) {
            letterLabels[index].textColor = .label
            letterLabels[index].font = .systemFont(ofSize: 12, weight: .bold)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let index = index(at: touch.location(in: self))
        highlight(index)
        if let index { onIndexChange?(index) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let index = index(at: touch.location(in: self))
        highlight(index)
        if let index { onIndexChange?(index) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        highlight(nil)
        onTouchEnd?()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        highlight(nil)
        onTouchEnd?()
    }
}
