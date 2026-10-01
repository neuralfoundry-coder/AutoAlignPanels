import Foundation
import CoreGraphics

public struct GridCell: Equatable, Sendable {
    public let row: Int
    public let col: Int
    public let x: CGFloat
    public let y: CGFloat
    public let width: CGFloat
    public let height: CGFloat

    public init(row: Int, col: Int, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.row = row
        self.col = col
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct GridLayout: Equatable, Sendable {
    public let rows: Int
    public let cols: Int
    public let cells: [GridCell]

    public init(rows: Int, cols: Int, cells: [GridCell]) {
        self.rows = rows
        self.cols = cols
        self.cells = cells
    }
}

public enum GridCalculator {
    /// Cells narrower or shorter than this are considered unusable; gap and
    /// margin are dropped before letting a cell shrink below it.
    public static let minUsableCellEdge: CGFloat = 50

    public static func calculate(
        windowCount: Int,
        screenFrame: CGRect,
        gap: CGFloat,
        margin: CGFloat = 0,
        mode: AlignmentMode = .grid,
        balanceLastRow: Bool = true
    ) -> GridLayout {
        guard windowCount > 0 else {
            return GridLayout(rows: 0, cols: 0, cells: [])
        }

        let gap = max(0, gap)
        let margin = max(0, margin)

        var frame = screenFrame.insetBy(dx: margin, dy: margin)
        if frame.width <= 0 || frame.height <= 0 {
            frame = screenFrame
        }

        if mode == .maximize {
            let cell = GridCell(row: 0, col: 0,
                                x: frame.origin.x, y: frame.origin.y,
                                width: max(1, frame.width), height: max(1, frame.height))
            return GridLayout(rows: 1, cols: 1, cells: Array(repeating: cell, count: windowCount))
        }

        let cols: Int
        let rows: Int
        switch mode {
        case .grid:
            cols = Int(ceil(sqrt(Double(windowCount))))
            rows = Int(ceil(Double(windowCount) / Double(cols)))
        case .horizontal:
            cols = windowCount
            rows = 1
        case .vertical:
            cols = 1
            rows = windowCount
        case .maximize:
            cols = 1
            rows = 1
        }

        var effectiveFrame = frame
        var effectiveGap = gap
        var cellWidth = (effectiveFrame.width - effectiveGap * CGFloat(cols - 1)) / CGFloat(cols)
        var cellHeight = (effectiveFrame.height - effectiveGap * CGFloat(rows - 1)) / CGFloat(rows)

        // Degrade gracefully on tiny screens / large counts: drop gap and margin
        // before producing unusable (or negative) cells.
        if cellWidth < Self.minUsableCellEdge || cellHeight < Self.minUsableCellEdge {
            effectiveFrame = screenFrame
            effectiveGap = 0
            cellWidth = effectiveFrame.width / CGFloat(cols)
            cellHeight = effectiveFrame.height / CGFloat(rows)
        }
        cellWidth = max(1, cellWidth)
        cellHeight = max(1, cellHeight)

        // In grid mode a short final row divides the full width among the
        // windows that actually remain, instead of leaving a dead empty cell.
        let lastRowCount = windowCount - (rows - 1) * cols
        let balancesLastRow = balanceLastRow && mode == .grid && lastRowCount > 0 && lastRowCount < cols
        let lastRowCellWidth = balancesLastRow
            ? max(1, (effectiveFrame.width - effectiveGap * CGFloat(lastRowCount - 1)) / CGFloat(lastRowCount))
            : cellWidth

        var cells: [GridCell] = []
        for i in 0..<windowCount {
            let row = i / cols
            let col = i % cols
            let width = (balancesLastRow && row == rows - 1) ? lastRowCellWidth : cellWidth
            let x = effectiveFrame.origin.x + CGFloat(col) * (width + effectiveGap)
            let y = effectiveFrame.origin.y + CGFloat(row) * (cellHeight + effectiveGap)
            cells.append(GridCell(row: row, col: col, x: x, y: y, width: width, height: cellHeight))
        }

        return GridLayout(rows: rows, cols: cols, cells: cells)
    }
}
