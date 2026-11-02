import XCTest
import UIKit
@testable import S1Gugu

@MainActor
final class ImageBlockCellSizingTests: XCTestCase {

    private let store = ImageDimensionStore.shared

    override func tearDown() {
        store.clear()
        super.tearDown()
    }

    /// 测量 cell 在给定宽度下的自适应高度
    private func fittingHeight(of cell: ImageBlockCell, width: CGFloat) -> CGFloat {
        let target = CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
        return cell.contentView.systemLayoutSizeFitting(
            target,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: UILayoutPriority(50)
        ).height
    }

    func testPlaceholderHeightIsStableAcrossReconfigures() {
        let url = URL(string: "https://img.stage1st.com/forum/202605/28/tall.jpg")!
        // 记录一张 3:4 的竖图真实像素
        store.store(size: CGSize(width: 1200, height: 1600), for: url)
        let image = PostImage(url: url, displayWidth: nil, displayHeight: nil)
        let width = UIScreen.main.bounds.width

        let cellA = ImageBlockCell()
        cellA.configure(image, index: 0) { _ in }
        let heightA = fittingHeight(of: cellA, width: width)

        let cellB = ImageBlockCell()
        cellB.configure(image, index: 0) { _ in }
        let heightB = fittingHeight(of: cellB, width: width)

        // 同一张图两次复用占位高度必须一致,否则滚动时会抖动
        XCTAssertEqual(heightA, heightB, accuracy: 0.5)
        // 占位应按真实 3:4 比例(可用宽 / 0.75),明显高于 160 的兜底高度
        let available = width - 32
        XCTAssertEqual(heightA, available / 0.75 + 8, accuracy: 2)
    }

    func testUnknownDimensionFallsBackToCompactHeight() {
        let url = URL(string: "https://img.stage1st.com/forum/202605/28/unknown.jpg")!
        let image = PostImage(url: url, displayWidth: nil, displayHeight: nil)
        let cell = ImageBlockCell()
        cell.configure(image, index: 0) { _ in }
        let height = fittingHeight(of: cell, width: UIScreen.main.bounds.width)
        // 无任何尺寸信息时用 160 兜底(+上下各 4pt 内边距)
        XCTAssertEqual(height, 160 + 8, accuracy: 2)
    }
}
