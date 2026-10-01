import Foundation
import CoreGraphics

/// Layout math for passes that span several apps at once.
public enum MultiAppLayout {
    /// One grid cell per group (app); every window of a group gets its
    /// group's cell, so same-app windows stack on top of each other and the
    /// stacks are tiled.
    ///
    /// - Parameter groupSizes: window count per group, in display order.
    /// - Returns: the stack grid, plus one cell per window in group order
    ///   (all of group 0's windows first, then group 1's, …).
    public static func stackedCells(
        groupSizes: [Int],
        screenFrame: CGRect,
        gap: CGFloat,
        margin: CGFloat = 0
    ) -> (layout: GridLayout, cells: [GridCell]) {
        let groups = groupSizes.filter { $0 > 0 }
        let layout = GridCalculator.calculate(
            windowCount: groups.count,
            screenFrame: screenFrame,
            gap: gap,
            margin: margin,
            mode: .grid
        )
        var cells: [GridCell] = []
        for (groupIndex, size) in groups.enumerated() {
            cells.append(contentsOf: Array(repeating: layout.cells[groupIndex], count: size))
        }
        return (layout, cells)
    }

    /// Indices of the frames whose center lies inside `screenFrame` (all in
    /// the same coordinate space). Windows straddling two displays belong to
    /// the one holding their center.
    public static func indices(of frames: [CGRect], centeredIn screenFrame: CGRect) -> [Int] {
        frames.indices.filter { screenFrame.contains(CGPoint(x: frames[$0].midX, y: frames[$0].midY)) }
    }

    /// Picks `limit` items by recency (lower `z` = closer to the front),
    /// then orders the survivors so each group's items sit next to each
    /// other — groups ordered by their frontmost item, items within a group
    /// front to back. `limit <= 0` keeps everything.
    public static func recentFirstGroupedOrder(
        zOrders: [Int],
        groupIDs: [Int],
        limit: Int
    ) -> [Int] {
        precondition(zOrders.count == groupIDs.count)
        var chosen = zOrders.indices.sorted { zOrders[$0] < zOrders[$1] }
        if limit > 0 && chosen.count > limit {
            chosen = Array(chosen.prefix(limit))
        }
        var groupFront: [Int: Int] = [:]
        for index in chosen {
            groupFront[groupIDs[index]] = min(groupFront[groupIDs[index]] ?? .max, zOrders[index])
        }
        return chosen.sorted { a, b in
            let ga = groupFront[groupIDs[a]]!, gb = groupFront[groupIDs[b]]!
            return ga != gb ? ga < gb : zOrders[a] < zOrders[b]
        }
    }
}
