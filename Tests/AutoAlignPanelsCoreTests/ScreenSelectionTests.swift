import XCTest
import AutoAlignPanelsCore

final class ScreenSelectionTests: XCTestCase {
    // Primary 1440×900 at origin; external 1920×1080 to the right.
    private let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let external = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

    private var screens: [CGRect] { [primary, external] }

    func testNoScreensReturnsNil() {
        XCTAssertNil(ScreenSelection.targetScreenIndex(windowFrames: [CGRect(x: 0, y: 0, width: 100, height: 100)], screenFrames: []))
    }

    func testNoWindowsDefaultsToPrimary() {
        XCTAssertEqual(ScreenSelection.targetScreenIndex(windowFrames: [], screenFrames: screens), 0)
    }

    func testMajorityOnExternalWins() {
        let windows = [
            CGRect(x: 1500, y: 100, width: 400, height: 300),
            CGRect(x: 2000, y: 200, width: 400, height: 300),
            CGRect(x: 100, y: 100, width: 400, height: 300),
        ]
        XCTAssertEqual(ScreenSelection.targetScreenIndex(windowFrames: windows, screenFrames: screens), 1)
    }

    func testMajorityOnPrimaryWins() {
        let windows = [
            CGRect(x: 100, y: 100, width: 400, height: 300),
            CGRect(x: 600, y: 100, width: 400, height: 300),
            CGRect(x: 1500, y: 100, width: 400, height: 300),
        ]
        XCTAssertEqual(ScreenSelection.targetScreenIndex(windowFrames: windows, screenFrames: screens), 0)
    }

    func testTieBreaksTowardFirstWindowsScreen() {
        let windows = [
            CGRect(x: 1500, y: 100, width: 400, height: 300),  // external
            CGRect(x: 100, y: 100, width: 400, height: 300),   // primary
        ]
        XCTAssertEqual(ScreenSelection.targetScreenIndex(windowFrames: windows, screenFrames: screens), 1)
    }

    func testWindowOffAllScreensFallsBackToNearest() {
        // Center far to the right of the external display.
        let windows = [CGRect(x: 4000, y: 100, width: 400, height: 300)]
        XCTAssertEqual(ScreenSelection.targetScreenIndex(windowFrames: windows, screenFrames: screens), 1)
    }

    func testSingleScreenAlwaysWins() {
        let windows = [CGRect(x: -5000, y: -5000, width: 100, height: 100)]
        XCTAssertEqual(ScreenSelection.targetScreenIndex(windowFrames: windows, screenFrames: [primary]), 0)
    }
}
