import XCTest
@testable import S1Gugu

final class FavoriteReorderTests: XCTestCase {

    private let items = ["A", "B", "C", "D"]

    func testDragDownUsesFinalIndexSemantics() {
        // UITableView destination 是移动后的最终行号:B 从 1 拖到 2 → [A, C, B, D]
        XCTAssertEqual(FavoriteReorder.reordering(items, moving: 1, to: 2), ["A", "C", "B", "D"])
        // A 从 0 拖到 2 → [B, C, A, D]
        XCTAssertEqual(FavoriteReorder.reordering(items, moving: 0, to: 2), ["B", "C", "A", "D"])
        // A 拖到末尾 3 → [B, C, D, A]
        XCTAssertEqual(FavoriteReorder.reordering(items, moving: 0, to: 3), ["B", "C", "D", "A"])
    }

    func testDragUpUsesFinalIndexSemantics() {
        XCTAssertEqual(FavoriteReorder.reordering(items, moving: 2, to: 1), ["A", "C", "B", "D"])
        XCTAssertEqual(FavoriteReorder.reordering(items, moving: 3, to: 0), ["D", "A", "B", "C"])
    }

    func testSameIndexIsNoOp() {
        XCTAssertEqual(FavoriteReorder.reordering(items, moving: 2, to: 2), items)
    }

    func testInvalidIndexesReturnUnchanged() {
        XCTAssertEqual(FavoriteReorder.reordering(items, moving: -1, to: 2), items)
        XCTAssertEqual(FavoriteReorder.reordering(items, moving: 1, to: 9), items)
    }

    /// 关键回归:向下拖一格绝不能退化成 no-op(否则会触发快照与表视图不一致)
    func testAdjacentDownwardDragIsNotNoOp() {
        XCTAssertNotEqual(FavoriteReorder.reordering(items, moving: 1, to: 2), items)
    }

    /// 端到端验证:按 handleMoveRow 的锚点 moveItem 逻辑更新真实 diffable 快照后,
    /// 快照顺序必须与目标顺序一致(这是名称/点击对不上的根因所在)。
    @MainActor
    func testSnapshotMoveItemProducesTargetOrder() {
        let tableView = UITableView(frame: CGRect(x: 0, y: 0, width: 320, height: 600), style: .plain)
        let dataSource = UITableViewDiffableDataSource<String, String>(tableView: tableView) { _, _, item in
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = item
            return cell
        }
        var snapshot = NSDiffableDataSourceSnapshot<String, String>()
        snapshot.appendSections(["fav"])
        snapshot.appendItems(items, toSection: "fav")
        dataSource.apply(snapshot, animatingDifferences: false)

        for (source, destination) in [(1, 2), (0, 2), (0, 3), (2, 1), (3, 0)] {
            let current = dataSource.snapshot().itemIdentifiers(inSection: "fav")
            let target = FavoriteReorder.reordering(current, moving: source, to: destination)
            guard target != current else { continue }
            let moved = current[source]
            var updated = dataSource.snapshot()
            let movedIndex = target.firstIndex(of: moved) ?? 0
            if movedIndex + 1 < target.count {
                updated.moveItem(moved, beforeItem: target[movedIndex + 1])
            } else if movedIndex >= 1 {
                updated.moveItem(moved, afterItem: target[movedIndex - 1])
            }
            dataSource.apply(updated, animatingDifferences: false)
            XCTAssertEqual(dataSource.snapshot().itemIdentifiers(inSection: "fav"), target,
                           "move \(source)->\(destination) 快照未对齐")
        }
    }
}
