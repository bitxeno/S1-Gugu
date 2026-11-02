import UIKit
import SnapKit

/// 「选择页面」弹窗:滚轮选页码 + 右侧上/下双箭头(跳首/末页) + 绿色「确定」。
///
/// 形态为底部 sheet(medium/large 两档、可上拉),视觉对齐 mockup:
/// 奶黄底、标题与选中页码为深藏青、当前页居中高亮、双箭头黄绿、确定按钮橄榄黄绿。
@MainActor
final class PageJumpSheetViewController: UIViewController {

    private let total: Int
    private let initialPage: Int
    /// 点击「确定」后回调目标页码
    private let onConfirm: (Int) -> Void

    private let titleLabel = UILabel()
    private let picker = UIPickerView()
    private let upButton = UIButton(type: .system)
    private let downButton = UIButton(type: .system)
    private let confirmButton = UIButton(type: .system)

    /// 滚轮当前选中的页码(1-based)
    private var selectedPage: Int

    /// 每行高度:布局后按「滚轮实际高度 / 可视行数」动态计算,保证恰好铺满 9 行
    private var rowHeight: CGFloat = 30
    /// 滚轮可视行数
    private let visibleRows = 9

    init(total: Int, current: Int, onConfirm: @escaping (Int) -> Void) {
        self.total = max(total, 1)
        self.initialPage = min(max(current, 1), max(total, 1))
        self.selectedPage = self.initialPage
        self.onConfirm = onConfirm
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.contentBackground
        configureSheet()
        setupUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        picker.selectRow(initialPage - 1, inComponent: 0, animated: false)
    }

    private func configureSheet() {
        guard let sheet = sheetPresentationController else { return }
        // medium 档位;内容铺满整页:标题在上、确定贴底、滚轮占据中间全部高度。
        // 行高按滚轮真实高度动态计算,恰好显示 9 行且确定下方无空白。
        sheet.detents = [.medium()]
        sheet.prefersGrabberVisible = true
        sheet.preferredCornerRadius = 16
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let h = picker.bounds.height
        guard h > 0 else { return }
        let target = (h / CGFloat(visibleRows)).rounded()
        if abs(target - rowHeight) > 0.5 {
            rowHeight = target
            picker.reloadAllComponents()
            picker.selectRow(selectedPage - 1, inComponent: 0, animated: false)
        }
    }

    // MARK: - UI

    private func setupUI() {
        titleLabel.text = "选择页面"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = Theme.postPickerText
        titleLabel.textAlignment = .center

        picker.dataSource = self
        picker.delegate = self

        configureArrow(upButton, systemName: "chevron.up.2", accessibility: "跳到第一页")
        configureArrow(downButton, systemName: "chevron.down.2", accessibility: "跳到最后一页")
        upButton.addTarget(self, action: #selector(jumpToFirst), for: .touchUpInside)
        downButton.addTarget(self, action: #selector(jumpToLast), for: .touchUpInside)

        var confirmConfig = UIButton.Configuration.filled()
        confirmConfig.title = "确定"
        confirmConfig.baseBackgroundColor = Theme.postPagerPill
        confirmConfig.baseForegroundColor = .white
        confirmConfig.cornerStyle = .medium
        confirmConfig.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 22, bottom: 8, trailing: 22)
        confirmButton.configuration = confirmConfig
        confirmButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        confirmButton.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)

        let arrowStack = UIStackView(arrangedSubviews: [upButton, downButton])
        arrowStack.axis = .vertical
        arrowStack.alignment = .center
        arrowStack.distribution = .equalSpacing
        arrowStack.spacing = 8

        [titleLabel, picker, arrowStack, confirmButton].forEach(view.addSubview)

        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(16)
            make.centerX.equalToSuperview()
        }

        picker.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(24)
            make.top.equalTo(titleLabel.snp.bottom).offset(4)
            make.bottom.equalTo(confirmButton.snp.top).offset(-6)
            make.width.equalTo(200)
        }

        arrowStack.snp.makeConstraints { make in
            make.leading.greaterThanOrEqualTo(picker.snp.trailing).offset(16)
            make.trailing.equalToSuperview().offset(-40)
            make.centerY.equalTo(picker)
            make.width.equalTo(56)
            make.height.equalTo(120)
        }

        confirmButton.snp.makeConstraints { make in
            make.bottom.equalTo(view.safeAreaLayoutGuide).offset(-12)
            make.centerX.equalToSuperview()
            make.height.equalTo(38)
        }
    }

    private func configureArrow(_ button: UIButton, systemName: String, accessibility: String) {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: systemName)
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        config.baseForegroundColor = Theme.postToolbarTint
        button.configuration = config
        button.accessibilityLabel = accessibility
    }

    // MARK: - Actions

    @objc private func jumpToFirst() { select(page: 1) }
    @objc private func jumpToLast() { select(page: total) }

    private func select(page: Int) {
        selectedPage = min(max(page, 1), total)
        picker.selectRow(selectedPage - 1, inComponent: 0, animated: true)
    }

    @objc private func confirmTapped() {
        let page = selectedPage
        dismiss(animated: true) { [onConfirm] in onConfirm(page) }
    }
}

// MARK: - UIPickerViewDataSource / Delegate

extension PageJumpSheetViewController: UIPickerViewDataSource, UIPickerViewDelegate {

    func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int { total }

    func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat { rowHeight }

    func pickerView(_ pickerView: UIPickerView, attributedTitleForRow row: Int, forComponent component: Int) -> NSAttributedString? {
        let isSelected = (row + 1) == selectedPage
        let color: UIColor = isSelected ? Theme.postPickerText : Theme.tertiaryLabel
        return NSAttributedString(
            string: "\(row + 1)",
            attributes: [
                .foregroundColor: color,
                .font: UIFont.monospacedDigitSystemFont(ofSize: isSelected ? 21 : 16, weight: isSelected ? .semibold : .regular),
            ]
        )
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        selectedPage = row + 1
        // 刷新高亮:重载以更新字号/颜色
        pickerView.reloadComponent(component)
        pickerView.selectRow(row, inComponent: component, animated: false)
    }

    func pickerView(_ pickerView: UIPickerView, accessibilityLabelForComponent component: Int) -> String? {
        "页码"
    }
}
