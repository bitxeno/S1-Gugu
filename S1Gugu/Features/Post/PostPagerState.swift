import Foundation

/// 帖子底部翻页栏的纯状态逻辑(不依赖 UIKit),便于单元测试。
struct PostPagerState: Equatable {

    /// 当前页码;加载中尚未确定时为 0
    let currentPage: Int
    /// 总页数,至少为 1
    let pageCount: Int

    init(currentPage: Int, pageCount: Int) {
        self.currentPage = currentPage
        self.pageCount = max(pageCount, 1)
    }

    /// 是否可翻到上一页(首页/单页/未加载时禁用)
    var canPrevious: Bool {
        currentPage > 1 && pageCount > 1
    }

    /// 是否可翻到下一页(末页/单页/未加载时禁用)
    var canNext: Bool {
        currentPage >= 1 && currentPage < pageCount
    }

    /// 胶囊展示文案:未加载完(0)显示占位破折号,否则显示当前页码
    var progressText: String {
        currentPage > 0 ? "\(currentPage)" : "–"
    }

    /// 上一页目标页;不可用时为 nil
    var previousTarget: Int? {
        canPrevious ? currentPage - 1 : nil
    }

    /// 下一页目标页;不可用时为 nil
    var nextTarget: Int? {
        canNext ? currentPage + 1 : nil
    }
}
