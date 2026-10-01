import Foundation
import CoreGraphics

/// Picks the screen the user is actually working on, from pure geometry.
/// An accessory app has no key window, so `NSScreen.main` is unreliable;
/// the majority screen of the target app's windows matches user intent.
public enum ScreenSelection {
    /// - Parameters:
    ///   - windowFrames: window frames in Cocoa (bottom-left origin) global coordinates.
    ///   - screenFrames: `NSScreen.frame` values in the same coordinate space.
    /// - Returns: index into `screenFrames`, or nil when there are no screens.
    ///   Majority of window centers wins; ties break toward the first window's
    ///   screen; if no center is on any screen, the nearest screen to the
    ///   first window's center wins.
    public static func targetScreenIndex(windowFrames: [CGRect], screenFrames: [CGRect]) -> Int? {
        guard !screenFrames.isEmpty else { return nil }
        guard !windowFrames.isEmpty else { return 0 }

        var counts = Array(repeating: 0, count: screenFrames.count)
        var firstWindowScreen: Int?
        for (windowIndex, frame) in windowFrames.enumerated() {
            let center = CGPoint(x: frame.midX, y: frame.midY)
            guard let screenIndex = screenFrames.firstIndex(where: { $0.contains(center) }) else { continue }
            counts[screenIndex] += 1
            if windowIndex == 0 { firstWindowScreen = screenIndex }
        }

        if let maxCount = counts.max(), maxCount > 0 {
            let winners = counts.indices.filter { counts[$0] == maxCount }
            if winners.count > 1, let first = firstWindowScreen, winners.contains(first) {
                return first
            }
            return winners[0]
        }

        // No window center sits on any screen (e.g. mid-drag or stale frame):
        // fall back to the screen nearest the first window's center.
        let center = CGPoint(x: windowFrames[0].midX, y: windowFrames[0].midY)
        var bestIndex = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, screen) in screenFrames.enumerated() {
            let distance = hypot(center.x - screen.midX, center.y - screen.midY)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }
}
