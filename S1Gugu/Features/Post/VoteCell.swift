import UIKit
import SnapKit

/// 主楼投票卡:展示选项/票数/百分比,可投票(单选/多选)并提交。
@MainActor
final class VoteCell: UICollectionViewCell {

    private let titleLabel = UILabel()
    private let optionStack = UIStackView()
    private let submitButton = UIButton(type: .system)
    private var options: [VoteOptionInfo] = []
    private var multiple = false
    private var canVote = false
    private var selectedIds: Set<Int> = []
    var onVote: (([Int]) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        titleLabel.font = .preferredFont(forTextStyle: .subheadline).bold()
        titleLabel.textColor = Theme.label
        titleLabel.adjustsFontForContentSizeCategory = true

        optionStack.axis = .vertical
        optionStack.spacing = 8

        var config = UIButton.Configuration.filled()
        config.title = "投票"
        config.cornerStyle = .capsule
        config.baseBackgroundColor = Theme.accent
        config.baseForegroundColor = .white
        submitButton.configuration = config
        submitButton.addAction(UIAction { [weak self] _ in self?.submitTapped() }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, optionStack, submitButton])
        stack.axis = .vertical
        stack.spacing = 12

        let container = UIView()
        container.backgroundColor = .secondarySystemBackground
        container.layer.cornerRadius = Theme.cardCornerRadius
        container.addSubview(stack)
        contentView.addSubview(container)
        container.snp.makeConstraints { make in
            make.leading.trailing.equalTo(contentView.layoutMarginsGuide)
            make.top.equalToSuperview().inset(6)
            make.bottom.equalToSuperview().inset(6)
        }
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(14)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ vote: VoteInfo, onVote: @escaping ([Int]) -> Void) {
        self.onVote = onVote
        options = vote.options
        multiple = vote.multiple
        canVote = vote.allowVote
        selectedIds = []
        titleLabel.text = "投票 · \(vote.votersCount) 人参与 · \(multiple ? "多选" : "单选")"
        submitButton.isHidden = !canVote
        rebuildOptionRows()
    }

    private func rebuildOptionRows() {
        optionStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for option in options {
            let row = UIButton(type: .system)
            row.contentHorizontalAlignment = .leading
            row.titleLabel?.numberOfLines = 0
            if canVote {
                row.addAction(UIAction { [weak self] _ in
                    self?.toggle(option.id)
                }, for: .touchUpInside)
            } else {
                // 不可投时给出去原因:游客提示登录,已登录则是已参与/已截止
                row.addAction(UIAction { [weak self] _ in
                    let loggedIn = SessionStore.shared.state.isLoggedIn
                    Toast.show(
                        loggedIn ? "您已参与过投票或投票已截止" : "请先登录后参与投票",
                        in: self?.contentView ?? UIView()
                    )
                }, for: .touchUpInside)
            }
            styleRow(row, option: option)
            optionStack.addArrangedSubview(row)
        }
    }

    private func styleRow(_ row: UIButton, option: VoteOptionInfo) {
        var config = UIButton.Configuration.plain()
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
        config.titleLineBreakMode = .byWordWrapping
        if canVote {
            // 投票前不展示票数(与论坛一致:投完才可见),仅高亮已选
            let selected = selectedIds.contains(option.id)
            let mark = selected ? "☑︎ " : "○  "
            config.attributedTitle = AttributedString("\(mark)\(option.option)")
            config.baseForegroundColor = selected ? Theme.accent : Theme.label
            config.background.cornerRadius = 8
            if selected {
                config.background.strokeColor = Theme.accent
                config.background.strokeWidth = 1.5
            } else {
                config.background.strokeColor = .separator
                config.background.strokeWidth = 0.5
            }
        } else {
            // 只读结果:文字 + 右侧票数,底部票数占比条(Discuz 主题色,截断取整对齐网页)
            let percentText = option.percent.flatMap { Double($0).map { String(Int($0.rounded())) + "%" } } ?? ""
            config.attributedTitle = AttributedString("\(option.option)  \(percentText) (\(option.votes))")
            config.baseForegroundColor = Theme.secondaryLabel
            config.background.cornerRadius = 8
            config.background.customView = resultBar(for: option)
        }
        row.configuration = config
    }

    /// 结果条:铺在按钮底部的票数占比填充(不拦截点击)
    private func resultBar(for option: VoteOptionInfo) -> UIView {
        let colors: [(UIColor, Double)] = [
            (UIColor(red: 0xE9 / 255, green: 0x27 / 255, blue: 0x25 / 255, alpha: 1), 1),
            (UIColor(red: 0xF2 / 255, green: 0x7B / 255, blue: 0x21 / 255, alpha: 1), 0.9),
            (UIColor(red: 0xF2 / 255, green: 0xA6 / 255, blue: 0x1F / 255, alpha: 1), 0.85),
            (UIColor(red: 0x5A / 255, green: 0xAF / 255, blue: 0x4A / 255, alpha: 1), 0.8),
            (UIColor(red: 0x42 / 255, green: 0xC4 / 255, blue: 0xF5 / 255, alpha: 1), 0.85),
            (UIColor(red: 0x00 / 255, green: 0x99 / 255, blue: 0xCC / 255, alpha: 1), 0.9),
            (UIColor(red: 0x33 / 255, green: 0x65 / 255, blue: 0xAE / 255, alpha: 1), 0.9),
            (UIColor(red: 0x2A / 255, green: 0x35 / 255, blue: 0x91 / 255, alpha: 1), 0.9),
            (UIColor(red: 0x59 / 255, green: 0x2D / 255, blue: 0x8E / 255, alpha: 1), 0.9),
            (UIColor(red: 0xDB / 255, green: 0x31 / 255, blue: 0x91 / 255, alpha: 1), 0.9),
        ]
        let index = options.firstIndex(where: { $0.id == option.id }) ?? 0
        let fraction = min(max(((option.percent.flatMap { Double($0) } ?? 0) / 100), 0.02), 1)
        let bar = ResultBarView(fraction: fraction)
        bar.isUserInteractionEnabled = false
        bar.fillColor = colors[index % colors.count].0.withAlphaComponent(0.18)
        return bar
    }

    private func toggle(_ id: Int) {
        guard canVote else { return }
        if multiple {
            if selectedIds.contains(id) {
                selectedIds.remove(id)
            } else {
                selectedIds.insert(id)
            }
        } else {
            selectedIds = [id]
        }
        rebuildOptionRows()
    }

    private func submitTapped() {
        guard !selectedIds.isEmpty else {
            Toast.show("请先选择选项", in: contentView)
            return
        }
        onVote?(Array(selectedIds).sorted())
    }
}

/// 按钮背景 customView: UIButton 装配时还没有 superview,约束方案会崩,
/// 改为在 layoutSubviews 里手动按占比布局填充条。
private final class ResultBarView: UIView {

    let fraction: CGFloat
    let fill = UIView()

    init(fraction: Double) {
        self.fraction = CGFloat(min(max(fraction, 0.02), 1))
        super.init(frame: .zero)
        fill.backgroundColor = .white
        addSubview(fill)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var fillColor: UIColor? {
        get { fill.backgroundColor }
        set { fill.backgroundColor = newValue }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        fill.frame = CGRect(x: 0, y: 0, width: bounds.width * fraction, height: bounds.height)
    }
}
