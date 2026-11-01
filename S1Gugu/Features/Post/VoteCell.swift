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
            row.addAction(UIAction { [weak self] _ in
                self?.toggle(option.id)
            }, for: .touchUpInside)
            styleRow(row, option: option)
            optionStack.addArrangedSubview(row)
        }
    }

    private func styleRow(_ row: UIButton, option: VoteOptionInfo) {
        var config = UIButton.Configuration.plain()
        if canVote {
            let selected = selectedIds.contains(option.id)
            let mark = selected ? "☑︎ " : "○  "
            config.attributedTitle = AttributedString("\(mark)\(option.option)")
            config.baseForegroundColor = selected ? Theme.accent : Theme.label
        } else {
            let percent = option.percent ?? ""
            config.attributedTitle = AttributedString("\(option.option)  \(percent) (\(option.votes))")
            config.baseForegroundColor = Theme.secondaryLabel
        }
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
        config.background.cornerRadius = 8
        if canVote, selectedIds.contains(option.id) {
            config.background.strokeColor = Theme.accent
            config.background.strokeWidth = 1.5
        } else {
            config.background.strokeColor = .separator
            config.background.strokeWidth = 0.5
        }
        row.configuration = config
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
