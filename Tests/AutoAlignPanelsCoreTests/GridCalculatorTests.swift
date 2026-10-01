import XCTest
import AutoAlignPanelsCore

final class GridCalculatorTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 25, width: 1000, height: 600)

    // MARK: - Empty / single

    func testZeroWindowsReturnsEmptyLayout() {
        let layout = GridCalculator.calculate(windowCount: 0, screenFrame: screen, gap: 8, mode: .grid)
        XCTAssertEqual(layout.rows, 0)
        XCTAssertEqual(layout.cols, 0)
        XCTAssertTrue(layout.cells.isEmpty)
    }

    func testSingleWindowFillsScreenInAllModes() {
        for mode in AlignmentMode.allCases {
            let layout = GridCalculator.calculate(windowCount: 1, screenFrame: screen, gap: 8, mode: mode)
            XCTAssertEqual(layout.cells.count, 1, "\(mode)")
            let cell = layout.cells[0]
            XCTAssertEqual(cell.x, screen.origin.x, "\(mode)")
            XCTAssertEqual(cell.y, screen.origin.y, "\(mode)")
            XCTAssertEqual(cell.width, screen.width, "\(mode)")
            XCTAssertEqual(cell.height, screen.height, "\(mode)")
        }
    }

    // MARK: - Grid shapes

    func testGridShapes() {
        // (windowCount, expectedCols, expectedRows)
        let cases: [(Int, Int, Int)] = [
            (2, 2, 1), (3, 2, 2), (4, 2, 2), (5, 3, 2), (6, 3, 2), (7, 3, 3), (9, 3, 3), (10, 4, 3),
        ]
        for (count, cols, rows) in cases {
            let layout = GridCalculator.calculate(windowCount: count, screenFrame: screen, gap: 8, mode: .grid)
            XCTAssertEqual(layout.cols, cols, "count \(count)")
            XCTAssertEqual(layout.rows, rows, "count \(count)")
            XCTAssertEqual(layout.cells.count, count, "count \(count)")
        }
    }

    func testGridFourWindowsCellGeometry() {
        let layout = GridCalculator.calculate(windowCount: 4, screenFrame: screen, gap: 8, mode: .grid)
        let cellWidth = (1000.0 - 8) / 2
        let cellHeight = (600.0 - 8) / 2
        XCTAssertEqual(layout.cells[0].x, 0)
        XCTAssertEqual(layout.cells[0].y, 25)
        XCTAssertEqual(layout.cells[1].x, cellWidth + 8)
        XCTAssertEqual(layout.cells[1].y, 25)
        XCTAssertEqual(layout.cells[2].x, 0)
        XCTAssertEqual(layout.cells[2].y, 25 + cellHeight + 8)
        XCTAssertEqual(layout.cells[3].x, cellWidth + 8)
        for cell in layout.cells {
            XCTAssertEqual(cell.width, cellWidth)
            XCTAssertEqual(cell.height, cellHeight)
        }
        // Right edge of last column lands exactly on the screen edge.
        XCTAssertEqual(layout.cells[1].x + layout.cells[1].width, screen.maxX)
        XCTAssertEqual(layout.cells[2].y + layout.cells[2].height, screen.maxY)
    }

    func testGridRowColAssignmentsAreRowMajor() {
        let layout = GridCalculator.calculate(windowCount: 5, screenFrame: screen, gap: 8, mode: .grid)
        let expected = [(0, 0), (0, 1), (0, 2), (1, 0), (1, 1)]
        for (i, (row, col)) in expected.enumerated() {
            XCTAssertEqual(layout.cells[i].row, row, "cell \(i)")
            XCTAssertEqual(layout.cells[i].col, col, "cell \(i)")
        }
    }

    // MARK: - Horizontal / vertical

    func testHorizontalLaysAllWindowsInOneRow() {
        let layout = GridCalculator.calculate(windowCount: 3, screenFrame: screen, gap: 10, mode: .horizontal)
        XCTAssertEqual(layout.rows, 1)
        XCTAssertEqual(layout.cols, 3)
        let cellWidth = (1000.0 - 10 * 2) / 3
        for (i, cell) in layout.cells.enumerated() {
            XCTAssertEqual(cell.row, 0)
            XCTAssertEqual(cell.col, i)
            XCTAssertEqual(cell.width, cellWidth, accuracy: 0.001)
            XCTAssertEqual(cell.height, screen.height)
            XCTAssertEqual(cell.y, screen.origin.y)
        }
        XCTAssertEqual(layout.cells[2].x + layout.cells[2].width, screen.maxX, accuracy: 0.001)
    }

    func testVerticalStacksAllWindowsInOneColumn() {
        let layout = GridCalculator.calculate(windowCount: 4, screenFrame: screen, gap: 6, mode: .vertical)
        XCTAssertEqual(layout.rows, 4)
        XCTAssertEqual(layout.cols, 1)
        let cellHeight = (600.0 - 6 * 3) / 4
        for (i, cell) in layout.cells.enumerated() {
            XCTAssertEqual(cell.row, i)
            XCTAssertEqual(cell.col, 0)
            XCTAssertEqual(cell.height, cellHeight, accuracy: 0.001)
            XCTAssertEqual(cell.width, screen.width)
            XCTAssertEqual(cell.x, screen.origin.x)
        }
        XCTAssertEqual(layout.cells[3].y + layout.cells[3].height, screen.maxY, accuracy: 0.001)
    }

    // MARK: - Gap arithmetic

    func testZeroGapTilesEdgeToEdge() {
        let layout = GridCalculator.calculate(windowCount: 4, screenFrame: screen, gap: 0, mode: .grid)
        XCTAssertEqual(layout.cells[0].width, 500)
        XCTAssertEqual(layout.cells[1].x, 500)
    }

    // MARK: - Persistence round-trip

    func testAlignmentModePersistedValueRoundTrips() {
        for mode in AlignmentMode.allCases {
            XCTAssertEqual(AlignmentMode(persistedValue: mode.persistedValue), mode)
        }
        XCTAssertNil(AlignmentMode(persistedValue: "bogus"))
    }
}
