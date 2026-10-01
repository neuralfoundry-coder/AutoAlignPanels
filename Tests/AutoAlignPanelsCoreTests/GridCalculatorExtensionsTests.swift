import XCTest
import AutoAlignPanelsCore

final class GridCalculatorExtensionsTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 25, width: 1000, height: 600)

    // MARK: - Margin

    func testMarginInsetsAllSides() {
        let layout = GridCalculator.calculate(windowCount: 1, screenFrame: screen, gap: 8, margin: 20, mode: .grid)
        let cell = layout.cells[0]
        XCTAssertEqual(cell.x, 20)
        XCTAssertEqual(cell.y, 45)
        XCTAssertEqual(cell.width, 960)
        XCTAssertEqual(cell.height, 560)
    }

    func testNegativeGapAndMarginAreClampedToZero() {
        let layout = GridCalculator.calculate(windowCount: 2, screenFrame: screen, gap: -10, margin: -5, mode: .horizontal)
        XCTAssertEqual(layout.cells[0].width, 500)
        XCTAssertEqual(layout.cells[1].x, 500)
        XCTAssertEqual(layout.cells[0].x, 0)
    }

    // MARK: - Balanced last row

    func testThreeWindowGridBalancesLastRow() {
        let layout = GridCalculator.calculate(windowCount: 3, screenFrame: screen, gap: 8, mode: .grid)
        XCTAssertEqual(layout.rows, 2)
        XCTAssertEqual(layout.cols, 2)
        // Top row: two half-width cells.
        XCTAssertEqual(layout.cells[0].width, (1000 - 8) / 2)
        XCTAssertEqual(layout.cells[1].width, (1000 - 8) / 2)
        // Bottom row: one full-width cell, no dead empty cell.
        XCTAssertEqual(layout.cells[2].width, 1000)
        XCTAssertEqual(layout.cells[2].x, 0)
        XCTAssertEqual(layout.cells[2].row, 1)
        XCTAssertEqual(layout.cells[2].col, 0)
    }

    func testFiveWindowGridBalancesTwoCellLastRow() {
        let layout = GridCalculator.calculate(windowCount: 5, screenFrame: screen, gap: 8, mode: .grid)
        XCTAssertEqual(layout.cols, 3)
        let balancedWidth = (1000.0 - 8) / 2
        XCTAssertEqual(layout.cells[3].width, balancedWidth)
        XCTAssertEqual(layout.cells[4].width, balancedWidth)
        XCTAssertEqual(layout.cells[4].x, balancedWidth + 8)
        XCTAssertEqual(layout.cells[4].x + layout.cells[4].width, screen.maxX, accuracy: 0.001)
    }

    func testLegacyUnbalancedLastRowStillAvailable() {
        let layout = GridCalculator.calculate(windowCount: 3, screenFrame: screen, gap: 8, mode: .grid, balanceLastRow: false)
        let cellWidth = (1000.0 - 8) / 2
        XCTAssertEqual(layout.cells[2].width, cellWidth)
        XCTAssertEqual(layout.cells[2].x, 0)
    }

    func testFullLastRowIsNotRebalanced() {
        let layout = GridCalculator.calculate(windowCount: 4, screenFrame: screen, gap: 8, mode: .grid)
        let cellWidth = (1000.0 - 8) / 2
        for cell in layout.cells {
            XCTAssertEqual(cell.width, cellWidth)
        }
    }

    // MARK: - Maximize

    func testMaximizeStacksIdenticalFullFrameCells() {
        let layout = GridCalculator.calculate(windowCount: 3, screenFrame: screen, gap: 8, margin: 10, mode: .maximize)
        XCTAssertEqual(layout.rows, 1)
        XCTAssertEqual(layout.cols, 1)
        XCTAssertEqual(layout.cells.count, 3)
        for cell in layout.cells {
            XCTAssertEqual(cell.row, 0)
            XCTAssertEqual(cell.col, 0)
            XCTAssertEqual(cell.x, 10)
            XCTAssertEqual(cell.y, 35)
            XCTAssertEqual(cell.width, 980)
            XCTAssertEqual(cell.height, 580)
        }
    }

    // MARK: - Degradation guards

    func testTinyScreenDropsGapAndMarginBeforeProducingUnusableCells() {
        let tiny = CGRect(x: 0, y: 0, width: 300, height: 200)
        // 6 windows horizontally with gap 40: with gap, cells would be 6.6pt wide.
        let layout = GridCalculator.calculate(windowCount: 6, screenFrame: tiny, gap: 40, margin: 30, mode: .horizontal)
        XCTAssertEqual(layout.cells[0].width, 50)
        XCTAssertEqual(layout.cells[0].x, 0)
        XCTAssertEqual(layout.cells[1].x, 50)
        XCTAssertGreaterThan(layout.cells[0].height, 0)
    }

    func testCellsNeverGoNegativeEvenOnAbsurdInput() {
        let tiny = CGRect(x: 0, y: 0, width: 10, height: 10)
        let layout = GridCalculator.calculate(windowCount: 20, screenFrame: tiny, gap: 64, margin: 64, mode: .horizontal)
        for cell in layout.cells {
            XCTAssertGreaterThanOrEqual(cell.width, 1)
            XCTAssertGreaterThanOrEqual(cell.height, 1)
        }
    }

    func testOversizedMarginFallsBackToFullFrame() {
        let layout = GridCalculator.calculate(windowCount: 1, screenFrame: screen, gap: 0, margin: 400, mode: .grid)
        // Inset by 400 on a 600pt-tall frame is degenerate — full frame wins.
        XCTAssertEqual(layout.cells[0].width, screen.width)
        XCTAssertEqual(layout.cells[0].height, screen.height)
    }
}
