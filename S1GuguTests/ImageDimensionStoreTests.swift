import XCTest
@testable import S1Gugu

final class ImageDimensionStoreTests: XCTestCase {

    private let store = ImageDimensionStore.shared

    override func tearDown() {
        store.clear()
        super.tearDown()
    }

    func testStoreAndRetrieveSize() {
        let url = URL(string: "https://img.stage1st.com/forum/test-a.jpg")!
        XCTAssertNil(store.size(for: url))
        store.store(size: CGSize(width: 800, height: 600), for: url)
        XCTAssertEqual(store.size(for: url), CGSize(width: 800, height: 600))
    }

    func testIgnoresInvalidSize() {
        let url = URL(string: "https://img.stage1st.com/forum/test-b.jpg")!
        store.store(size: CGSize(width: 0, height: 0), for: url)
        XCTAssertNil(store.size(for: url))
    }

    func testClearRemovesEntries() {
        let url = URL(string: "https://img.stage1st.com/forum/test-c.jpg")!
        store.store(size: CGSize(width: 640, height: 480), for: url)
        store.clear()
        XCTAssertNil(store.size(for: url))
    }
}
