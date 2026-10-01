import XCTest
@testable import AutoAlignPanelsCore

final class SnapLayoutTests: XCTestCase {
    // 1440×900 landscape visible frame below a 25pt menu bar.
    private let landscape = CGRect(x: 0, y: 25, width: 1440, height: 900)
    private let portrait = CGRect(x: 1440, y: 0, width: 1080, height: 1920)
    private let window = CGSize(width: 800, height: 600)

    private func frame(_ p: SnapPosition, _ area: CGRect? = nil, gap: CGFloat = 0, margin: CGFloat = 0) -> CGRect {
        SnapLayout.frame(for: p, windowSize: window, in: area ?? landscape, gap: gap, margin: margin)
    }

    func testHalves() {
        XCTAssertEqual(frame(.leftHalf), CGRect(x: 0, y: 25, width: 720, height: 900))
        XCTAssertEqual(frame(.rightHalf), CGRect(x: 720, y: 25, width: 720, height: 900))
        XCTAssertEqual(frame(.topHalf), CGRect(x: 0, y: 25, width: 1440, height: 450))
        XCTAssertEqual(frame(.bottomHalf), CGRect(x: 0, y: 475, width: 1440, height: 450))
    }

    func testQuartersTileTheScreen() {
        let quarters: [SnapPosition] = [.topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter]
        let union = quarters.map { frame($0) }.reduce(CGRect.null) { $0.union($1) }
        XCTAssertEqual(union, landscape)
        XCTAssertEqual(frame(.bottomRightQuarter), CGRect(x: 720, y: 475, width: 720, height: 450))
    }

    func testThirdsAndTwoThirdsLandscape() {
        XCTAssertEqual(frame(.firstThird), CGRect(x: 0, y: 25, width: 480, height: 900))
        XCTAssertEqual(frame(.centerThird), CGRect(x: 480, y: 25, width: 480, height: 900))
        XCTAssertEqual(frame(.lastThird), CGRect(x: 960, y: 25, width: 480, height: 900))
        XCTAssertEqual(frame(.firstTwoThirds), CGRect(x: 0, y: 25, width: 960, height: 900))
        XCTAssertEqual(frame(.centerTwoThirds), CGRect(x: 240, y: 25, width: 960, height: 900))
        XCTAssertEqual(frame(.lastTwoThirds), CGRect(x: 480, y: 25, width: 960, height: 900))
    }

    func testThirdsRunVerticallyOnPortraitDisplay() {
        XCTAssertEqual(frame(.firstThird, portrait), CGRect(x: 1440, y: 0, width: 1080, height: 640))
        XCTAssertEqual(frame(.lastTwoThirds, portrait), CGRect(x: 1440, y: 640, width: 1080, height: 1280))
        // Halves are unaffected by orientation.
        XCTAssertEqual(frame(.leftHalf, portrait), CGRect(x: 1440, y: 0, width: 540, height: 1920))
    }

    func testSixthsAndRows() {
        XCTAssertEqual(frame(.topCenterSixth), CGRect(x: 480, y: 25, width: 480, height: 450))
        XCTAssertEqual(frame(.bottomRightSixth), CGRect(x: 960, y: 475, width: 480, height: 450))
        XCTAssertEqual(frame(.row1Of4), CGRect(x: 0, y: 25, width: 1440, height: 225))
        XCTAssertEqual(frame(.row4Of4), CGRect(x: 0, y: 700, width: 1440, height: 225))
    }

    func testMaximizeAndCenter() {
        XCTAssertEqual(frame(.maximize), landscape)
        XCTAssertEqual(frame(.center), CGRect(x: 320, y: 175, width: 800, height: 600))
        let huge = SnapLayout.frame(for: .center, windowSize: CGSize(width: 3000, height: 2000), in: landscape)
        XCTAssertEqual(huge, landscape)
    }

    func testGapSplitsOnlyInteriorEdges() {
        let left = frame(.leftHalf, gap: 10)
        let right = frame(.rightHalf, gap: 10)
        XCTAssertEqual(left, CGRect(x: 0, y: 25, width: 715, height: 900))
        XCTAssertEqual(right.minX - left.maxX, 10)
        XCTAssertEqual(right.maxX, 1440)
        XCTAssertEqual(frame(.maximize, gap: 10), landscape)
    }

    func testMarginInsetsScreenEdges() {
        XCTAssertEqual(frame(.maximize, margin: 20), landscape.insetBy(dx: 20, dy: 20))
        XCTAssertEqual(frame(.leftHalf, margin: 20).minX, 20)
    }

    func testTranslateKeepsRelativePositionAndScales() {
        let left = CGRect(x: 0, y: 25, width: 720, height: 900)
        let moved = SnapLayout.translate(left, from: landscape, to: portrait)
        XCTAssertEqual(moved, CGRect(x: 1440, y: 0, width: 540, height: 1920))
    }

    func testTranslateClampsIntoDestination() {
        let offRight = CGRect(x: 1300, y: 25, width: 400, height: 300)
        let moved = SnapLayout.translate(offRight, from: landscape, to: portrait)
        XCTAssertLessThanOrEqual(moved.maxX, portrait.maxX)
        XCTAssertGreaterThanOrEqual(moved.minX, portrait.minX)
    }
}
