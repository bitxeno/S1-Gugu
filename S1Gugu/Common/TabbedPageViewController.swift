import UIKit
import SnapKit

/// 顶部文字 Tab 容器(选中加粗 + 下划线),页面可左右滑动切换。
///
/// 头部与系统导航栏同色同高;本容器在 `viewWillAppear` 隐藏导航栏,
/// push 进入其它页面时在 `viewWillDisappear` 恢复。
/// 消息页(私信/通知)、收藏页(收藏/浏览历史)共用此容器。
@MainActor
class TabbedPageViewController: UIViewController {

    /// 每个 Tab 的标题与内容控制器
    struct Tab {
        let title: String
        let controller: UIViewController
    }

    private let tabs: [Tab]
    private let header = UIView()
    private let tabStack = UIStackView()
    private let underline = UIView()
    private let container = UIView()
    private let pageController: UIPageViewController
    private lazy var pages: [UIViewController] = tabs.map(\.controller)

    private var tabButtons: [UIButton] = []
    private(set) var selectedIndex = 0
    private var toolViews: [UIView] = []
    private var trailingAnchors: [UIView] = []

    init(tabs: [Tab]) {
        precondition(!tabs.isEmpty, "TabbedPageViewController 至少需要一个 Tab")
        self.tabs = tabs
        self.pageController = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal
        )
        super.init(nibName: nil, bundle: nil)
        pageController.dataSource = self
        pageController.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        // 字号随 Dynamic Type 变化时重算 Tab 字体与下划线
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: TabbedPageViewController, _) in
            self.renderTabs()
            self.view.setNeedsLayout()
        }
        setupHeader()
        setupContainer()
        setupPages()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    /// 子类可覆盖:向头部右侧添加常驻操作按钮(如发私信)
    func headerTrailingViews() -> [UIView] { [] }

    /// 子类可覆盖:追加右侧「页相关工具」按钮,随选中 Tab 显隐
    func headerToolViews(for index: Int) -> [UIView] { [] }

    /// 子类可覆盖:切换后更新自定义头部按钮的状态
    func tabSelectionDidChange(to index: Int) {}

    /// 供子类切换 Tab
    func selectTab(_ index: Int) {
        guard index != selectedIndex, pages.indices.contains(index) else { return }
        let direction: UIPageViewController.NavigationDirection = index > selectedIndex ? .forward : .reverse
        selectedIndex = index
        pageController.setViewControllers([pages[index]], direction: direction, animated: true)
        applyTabState()
    }

    /// 供子类刷新右侧工具按钮(如数据加载完成后切换可用状态)
    func reloadHeaderTools() {
        updateToolViews()
    }

    private func setupHeader() {
        // 与其它页面导航栏同色(奶黄主题为奶茶色 #D8D8A8)
        header.backgroundColor = Theme.navigationBarBackground
        view.addSubview(header)
        header.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            // 与其它页面导航栏同高(安全区下 54pt)
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.top).offset(54)
        }

        tabStack.axis = .horizontal
        tabStack.spacing = 20
        tabStack.alignment = .center
        header.addSubview(tabStack)
        tabStack.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            // 54pt 栏中心,对应系统导航标题的垂直位置
            make.centerY.equalTo(view.safeAreaLayoutGuide.snp.top).offset(27)
        }

        // 下划线先加入 header,renderTabs 里再用约束对齐选中 Tab
        underline.backgroundColor = Theme.barForeground
        underline.layer.cornerRadius = 1.5
        underline.isUserInteractionEnabled = false
        header.addSubview(underline)

        for (index, tab) in tabs.enumerated() {
            let button = UIButton(type: .system)
            button.tag = index
            var config = UIButton.Configuration.plain()
            config.title = tab.title
            // 扩大点击热区,不影响下划线宽度计算(按文字实际宽度定位)
            config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 6)
            button.configuration = config
            button.addAction(UIAction { [weak self] action in
                guard let sender = action.sender as? UIButton else { return }
                self?.selectTab(sender.tag)
            }, for: .touchUpInside)
            tabButtons.append(button)
            tabStack.addArrangedSubview(button)
        }
        renderTabs()

        // 子类提供的头部右侧按钮,依次贴右排列(常驻)
        var previous: UIView?
        for subview in headerTrailingViews() {
            header.addSubview(subview)
            subview.snp.makeConstraints { make in
                if let previous {
                    make.trailing.equalTo(previous.snp.leading).offset(-8)
                } else {
                    make.trailing.equalToSuperview().inset(16)
                }
                make.centerY.equalTo(tabStack)
                make.size.equalTo(43)
            }
            previous = subview
            trailingAnchors.append(subview)
        }
    }

    /// 按当前选中 Tab 重建右侧工具按钮
    private func updateToolViews() {
        for view in toolViews {
            view.removeFromSuperview()
        }
        toolViews = headerToolViews(for: selectedIndex)
        guard let firstTrailing = trailingAnchors.first else {
            // 没有常驻按钮时,工具按钮贴右
            var previous: UIView?
            for subview in toolViews {
                header.addSubview(subview)
                subview.snp.remakeConstraints { make in
                    if let previous {
                        make.trailing.equalTo(previous.snp.leading).offset(-8)
                    } else {
                        make.trailing.equalToSuperview().inset(16)
                    }
                    make.centerY.equalTo(tabStack)
                    make.size.equalTo(43)
                }
                subview.alpha = 0
                previous = subview
            }
            UIView.animate(withDuration: 0.2) {
                self.toolViews.forEach { $0.alpha = 1 }
            }
            return
        }
        var previous: UIView = firstTrailing
        for subview in toolViews {
            header.addSubview(subview)
            subview.snp.remakeConstraints { make in
                make.trailing.equalTo(previous.snp.leading).offset(-8)
                make.centerY.equalTo(tabStack)
                make.size.equalTo(43)
            }
            subview.alpha = 0
            previous = subview
        }
        UIView.animate(withDuration: 0.2) {
            self.toolViews.forEach { $0.alpha = 1 }
        }
    }

    private func setupContainer() {
        view.addSubview(container)
        container.snp.makeConstraints { make in
            make.top.equalTo(header.snp.bottom)
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

    private func setupPages() {
        addChild(pageController)
        container.addSubview(pageController.view)
        pageController.view.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        pageController.didMove(toParent: self)
        pageController.setViewControllers([pages[0]], direction: .forward, animated: false)
        applyTabState()
    }

    /// 同步 Tab 高亮/下划线,并通知子类更新自定义按钮
    private func applyTabState() {
        renderTabs()
        updateToolViews()
        tabSelectionDidChange(to: selectedIndex)
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut) {
            self.view.layoutIfNeeded()
        }
    }

    /// 与系统导航标题同款字体:17pt,选中 semibold、未选中 regular,随 Dynamic Type 缩放
    private func tabFont(selected: Bool) -> UIFont {
        let base = UIFont.systemFont(ofSize: 17, weight: selected ? .semibold : .regular)
        return UIFontMetrics(forTextStyle: .headline).scaledFont(for: base)
    }

    /// 选中加粗主色、未选中常规次级色
    private func renderTabs() {
        for (index, button) in tabButtons.enumerated() {
            let selected = index == selectedIndex
            var attributed = AttributedString(tabs[index].title)
            attributed.font = tabFont(selected: selected)
            attributed.foregroundColor = selected ? Theme.barForeground : Theme.secondaryLabel
            var config = button.configuration ?? UIButton.Configuration.plain()
            config.attributedTitle = attributed
            button.configuration = config
            button.accessibilityTraits = selected ? [.button, .selected] : .button
        }
        updateUnderlineConstraints()
    }

    /// 下划线用约束对齐选中 Tab(跨视图约束由 Auto Layout 换算坐标),
    /// 切换时结合 layoutIfNeeded 产生滑动动画
    private func updateUnderlineConstraints() {
        guard tabButtons.indices.contains(selectedIndex) else { return }
        let button = tabButtons[selectedIndex]
        let font = tabFont(selected: true)
        let textWidth = (tabs[selectedIndex].title as NSString).size(withAttributes: [.font: font]).width
        underline.snp.remakeConstraints { make in
            make.centerX.equalTo(button)
            // 按钮底部留有 8pt 点击热区内边距,上移抵消后让下划线贴近文字
            make.top.equalTo(button.snp.bottom).offset(-5)
            make.width.equalTo(textWidth + 4)
            make.height.equalTo(3)
        }
    }
}

// MARK: - 左右滑动切换

extension TabbedPageViewController: UIPageViewControllerDataSource, UIPageViewControllerDelegate {

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let index = pages.firstIndex(of: viewController), index > 0 else { return nil }
        return pages[index - 1]
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let index = pages.firstIndex(of: viewController), index < pages.count - 1 else { return nil }
        return pages[index + 1]
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard completed,
              let current = pageViewController.viewControllers?.first,
              let index = pages.firstIndex(of: current) else { return }
        selectedIndex = index
        applyTabState()
    }
}
