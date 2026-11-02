import XCTest
@testable import S1Gugu

final class DefaultAvatarTests: XCTestCase {

    func testBundledDefaultAvatarIsAvailable() {
        let image = UIImage(named: "DefaultAvatar")
        XCTAssertNotNil(image)
        XCTAssertGreaterThan(image?.size.width ?? 0, 0)
    }

    func testRemoteDefaultAvatarPointsToSiteNoAvatar() {
        XCTAssertEqual(
            DefaultAvatar.remoteURL.absoluteString,
            "https://avatar.stage1st.com/noavatar.svg"
        )
    }
}
