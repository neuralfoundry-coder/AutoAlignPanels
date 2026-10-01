import XCTest
@testable import AutoAlignPanelsCore

final class MultiAppLayoutTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 25, width: 1200, height: 800)

    func testStackedCellsGiveEveryGroupMemberTheGroupCell() {
        let (layout, cells) = MultiAppLayout.stackedCells(groupSizes: [3, 1, 2], screenFrame: screen, gap: 0)
        XCTAssertEqual(layout.cells.count, 3)
        XCTAssertEqual(cells.count, 6)
        XCTAssertEqual(Array(cells[0..<3]), Array(repeating: layout.cells[0], count: 3))
        XCTAssertEqual(cells[3], layout.cells[1])
        XCTAssertEqual(Array(cells[4..<6]), Array(repeating: layout.cells[2], count: 2))
    }

    func testStackedCellsTwoAppsSplitScreenInHalf() {
        let (layout, cells) = MultiAppLayout.stackedCells(groupSizes: [2, 4], screenFrame: screen, gap: 0)
        XCTAssertEqual(layout.cols, 2)
        XCTAssertEqual(layout.rows, 1)
        XCTAssertEqual(cells.first?.width, 600)
        XCTAssertEqual(cells.last?.x, 600)
    }

    func testStackedCellsSkipEmptyGroups() {
        let (layout, cells) = MultiAppLayout.stackedCells(groupSizes: [0, 2], screenFrame: screen, gap: 0)
        XCTAssertEqual(layout.cells.count, 1)
        XCTAssertEqual(cells.count, 2)
    }

    func testIndicesCenteredInScreen() {
        let frames = [
            CGRect(x: 100, y: 100, width: 200, height: 200),   // on
            CGRect(x: 1100, y: 100, width: 400, height: 200),  // center x=1300, off
            CGRect(x: -150, y: 100, width: 400, height: 200),  // center x=50, on
        ]
        XCTAssertEqual(MultiAppLayout.indices(of: frames, centeredIn: screen), [0, 2])
    }

    func testRecentFirstGroupedOrderGroupsByAppAfterPickingMostRecent() {
        // windows: z      0  1  2  3  4
        //          group  A  B  A  C  B
        let order = MultiAppLayout.recentFirstGroupedOrder(
            zOrders: [0, 1, 2, 3, 4], groupIDs: [1, 2, 1, 3, 2], limit: 0)
        XCTAssertEqual(order, [0, 2, 1, 4, 3])
    }

    func testRecentFirstGroupedOrderCapKeepsMostRecentWindows() {
        // App A owns the two BACKMOST windows; the cap must drop them, not
        // the front windows of other apps.
        let order = MultiAppLayout.recentFirstGroupedOrder(
            zOrders: [3, 0, 4, 1], groupIDs: [1, 2, 1, 3], limit: 3)
        XCTAssertEqual(Set(order), [0, 1, 3])
        XCTAssertEqual(order, [1, 3, 0])
    }
}
