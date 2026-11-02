import XCTest
@testable import S1Gugu

final class PostPagerStateTests: XCTestCase {

    func testFirstPageCannotGoPrevious() {
        let state = PostPagerState(currentPage: 1, pageCount: 5)
        XCTAssertFalse(state.canPrevious)
        XCTAssertTrue(state.canNext)
        XCTAssertNil(state.previousTarget)
        XCTAssertEqual(state.nextTarget, 2)
        XCTAssertEqual(state.progressText, "1")
    }

    func testLastPageCannotGoNext() {
        let state = PostPagerState(currentPage: 5, pageCount: 5)
        XCTAssertTrue(state.canPrevious)
        XCTAssertFalse(state.canNext)
        XCTAssertEqual(state.previousTarget, 4)
        XCTAssertNil(state.nextTarget)
        XCTAssertEqual(state.progressText, "5")
    }

    func testMiddlePageBothDirections() {
        let state = PostPagerState(currentPage: 3, pageCount: 5)
        XCTAssertTrue(state.canPrevious)
        XCTAssertTrue(state.canNext)
        XCTAssertEqual(state.previousTarget, 2)
        XCTAssertEqual(state.nextTarget, 4)
    }

    func testSinglePageDisablesBoth() {
        let state = PostPagerState(currentPage: 1, pageCount: 1)
        XCTAssertFalse(state.canPrevious)
        XCTAssertFalse(state.canNext)
        XCTAssertNil(state.previousTarget)
        XCTAssertNil(state.nextTarget)
    }

    func testLoadingStateShowsPlaceholder() {
        let state = PostPagerState(currentPage: 0, pageCount: 3)
        XCTAssertFalse(state.canPrevious)
        XCTAssertFalse(state.canNext)
        XCTAssertEqual(state.progressText, "–")
    }

    func testPageCountClampedToAtLeastOne() {
        let state = PostPagerState(currentPage: 0, pageCount: 0)
        XCTAssertEqual(state.pageCount, 1)
    }

    func testNormalizedPageClampsToFirstPage() {
        // 深链/进度恢复传入 0 或负数时,请求页码必须收敛到 1
        XCTAssertEqual(PostPagerState.normalizedPage(0), 1)
        XCTAssertEqual(PostPagerState.normalizedPage(-5), 1)
        XCTAssertEqual(PostPagerState.normalizedPage(1), 1)
        XCTAssertEqual(PostPagerState.normalizedPage(7), 7)
    }
}
