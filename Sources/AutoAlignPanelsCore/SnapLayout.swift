import Foundation
import CoreGraphics

/// Magnet-style positions for snapping the single focused window.
public enum SnapPosition: String, CaseIterable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeftQuarter, topRightQuarter, bottomLeftQuarter, bottomRightQuarter
    /// On a portrait display thirds and two-thirds run top to bottom.
    case firstThird, centerThird, lastThird
    case firstTwoThirds, centerTwoThirds, lastTwoThirds
    case topLeftSixth, topCenterSixth, topRightSixth
    case bottomLeftSixth, bottomCenterSixth, bottomRightSixth
    /// Full-width horizontal bands, a quarter of the height each.
    case row1Of4, row2Of4, row3Of4, row4Of4
    case maximize
    /// Keeps the window's size (clamped to the screen) and centers it.
    case center
}

public enum SnapLayout {
    /// The position as fractions of the usable area (origin top-left, y down).
    /// Nil for `.center`, which depends on the window's own size.
    public static func unitRect(for position: SnapPosition, portrait: Bool) -> CGRect? {
        let third: CGFloat = 1.0 / 3.0
        func split(_ start: CGFloat, _ length: CGFloat) -> CGRect {
            portrait
                ? CGRect(x: 0, y: start, width: 1, height: length)
                : CGRect(x: start, y: 0, width: length, height: 1)
        }
        switch position {
        case .leftHalf: return CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .rightHalf: return CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .topHalf: return CGRect(x: 0, y: 0, width: 1, height: 0.5)
        case .bottomHalf: return CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        case .topLeftQuarter: return CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .topRightQuarter: return CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .bottomLeftQuarter: return CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .bottomRightQuarter: return CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .firstThird: return split(0, third)
        case .centerThird: return split(third, third)
        case .lastThird: return split(2 * third, third)
        case .firstTwoThirds: return split(0, 2 * third)
        case .centerTwoThirds: return split(third / 2, 2 * third)
        case .lastTwoThirds: return split(third, 2 * third)
        case .topLeftSixth: return CGRect(x: 0, y: 0, width: third, height: 0.5)
        case .topCenterSixth: return CGRect(x: third, y: 0, width: third, height: 0.5)
        case .topRightSixth: return CGRect(x: 2 * third, y: 0, width: third, height: 0.5)
        case .bottomLeftSixth: return CGRect(x: 0, y: 0.5, width: third, height: 0.5)
        case .bottomCenterSixth: return CGRect(x: third, y: 0.5, width: third, height: 0.5)
        case .bottomRightSixth: return CGRect(x: 2 * third, y: 0.5, width: third, height: 0.5)
        case .row1Of4: return CGRect(x: 0, y: 0, width: 1, height: 0.25)
        case .row2Of4: return CGRect(x: 0, y: 0.25, width: 1, height: 0.25)
        case .row3Of4: return CGRect(x: 0, y: 0.5, width: 1, height: 0.25)
        case .row4Of4: return CGRect(x: 0, y: 0.75, width: 1, height: 0.25)
        case .maximize: return CGRect(x: 0, y: 0, width: 1, height: 1)
        case .center: return nil
        }
    }

    /// Target frame in the same top-left coordinate space as `area` (the
    /// screen's visible frame). `margin` insets the screen edges; `gap` is
    /// split across interior edges so two adjacent snaps leave exactly `gap`
    /// between them. Results are rounded to whole points.
    public static func frame(
        for position: SnapPosition,
        windowSize: CGSize,
        in area: CGRect,
        gap: CGFloat = 0,
        margin: CGFloat = 0
    ) -> CGRect {
        var usable = area.insetBy(dx: max(0, margin), dy: max(0, margin))
        if usable.width <= 0 || usable.height <= 0 { usable = area }
        let portrait = area.height > area.width

        guard let unit = unitRect(for: position, portrait: portrait) else {
            let width = min(windowSize.width, usable.width)
            let height = min(windowSize.height, usable.height)
            return CGRect(x: (usable.midX - width / 2).rounded(),
                          y: (usable.midY - height / 2).rounded(),
                          width: width.rounded(), height: height.rounded())
        }

        let half = max(0, gap) / 2
        let epsilon: CGFloat = 0.0001
        var minX = usable.minX + unit.minX * usable.width
        var maxX = usable.minX + unit.maxX * usable.width
        var minY = usable.minY + unit.minY * usable.height
        var maxY = usable.minY + unit.maxY * usable.height
        if unit.minX > epsilon { minX += half }
        if unit.maxX < 1 - epsilon { maxX -= half }
        if unit.minY > epsilon { minY += half }
        if unit.maxY < 1 - epsilon { maxY -= half }

        let x = minX.rounded(), y = minY.rounded()
        return CGRect(x: x, y: y,
                      width: max(1, maxX.rounded() - x),
                      height: max(1, maxY.rounded() - y))
    }

    /// Carries a frame to another screen at the same relative position and
    /// proportional size, clamped to fit — "next display" for one window.
    public static func translate(_ frame: CGRect, from source: CGRect, to destination: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0 else { return frame }
        let sx = destination.width / source.width
        let sy = destination.height / source.height
        let width = min(destination.width, frame.width * sx)
        let height = min(destination.height, frame.height * sy)
        var x = destination.minX + (frame.minX - source.minX) * sx
        var y = destination.minY + (frame.minY - source.minY) * sy
        x = min(max(x, destination.minX), destination.maxX - width)
        y = min(max(y, destination.minY), destination.maxY - height)
        return CGRect(x: x.rounded(), y: y.rounded(), width: width.rounded(), height: height.rounded())
    }
}
