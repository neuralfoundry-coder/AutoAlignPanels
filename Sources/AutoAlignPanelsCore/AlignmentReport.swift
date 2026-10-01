import Foundation
import CoreGraphics

/// The truthful result of one alignment pass: what actually happened to each
/// window, verified by reading frames back. Feedback (VoiceOver, sound, HUD)
/// is built from this so the app never announces a layout that didn't happen.
public struct AlignmentReport: Sendable {
    public enum Failure: Equatable, Sendable {
        /// The target app did not answer within the messaging timeout.
        case timeout
        /// The window's position attribute is not settable.
        case notSettable
        /// The window server / app rejected the position even after a retry.
        case positionRejected
        /// The window disappeared before its frame could be verified.
        case windowVanished
        case apiError(Int)
    }

    public enum WindowOutcome: Equatable, Sendable {
        /// Frame verified within tolerance.
        case aligned
        /// Position correct, but the app kept a different size (e.g. a minimum size).
        case clamped(actualSize: CGSize)
        /// Window is not resizable; only its position was set.
        case movedOnly
        case failed(Failure)

        public var isFailure: Bool {
            if case .failed = self { return true }
            return false
        }
    }

    public struct Item: Sendable {
        public let title: String?
        public let outcome: WindowOutcome

        public init(title: String?, outcome: WindowOutcome) {
            self.title = title
            self.outcome = outcome
        }
    }

    /// Which windows the pass covered: the front app only, or every visible
    /// app on the screen (tiled per window, or stacked per app).
    public enum Scope: Equatable, Sendable {
        case singleApp
        case allApps(appCount: Int)
        case stackedByApp(appCount: Int)
    }

    public let appName: String?
    public let mode: AlignmentMode
    public let scope: Scope
    public let rows: Int
    public let cols: Int
    public let items: [Item]
    /// Eligible windows before the max-window cap was applied.
    public let totalWindowCount: Int

    public init(appName: String?, mode: AlignmentMode, rows: Int, cols: Int,
                items: [Item], totalWindowCount: Int? = nil, scope: Scope = .singleApp) {
        self.appName = appName
        self.mode = mode
        self.scope = scope
        self.rows = rows
        self.cols = cols
        self.items = items
        self.totalWindowCount = max(totalWindowCount ?? items.count, items.count)
    }

    public var alignedCount: Int { items.filter { !$0.outcome.isFailure }.count }
    public var failedCount: Int { items.count - alignedCount }
    public var isCapped: Bool { totalWindowCount > items.count }
    public var isFullSuccess: Bool { failedCount == 0 }

    public enum Tone: Sendable {
        case success, partial, failure
    }

    public var tone: Tone {
        if alignedCount == 0 { return .failure }
        return failedCount == 0 ? .success : .partial
    }

    /// Spoken/displayed summary. Every branch is a
    /// full-sentence localization key — never composed fragments — so word
    /// order can differ per language.
    public func summaryMessage(verbose: Bool) -> String {
        var message: String
        switch tone {
        case .failure:
            message = appName.map { String(localized: "Could not align windows of \($0)") }
                ?? String(localized: "Could not align windows")
        case .partial:
            message = appName.map { String(localized: "Aligned \(alignedCount) of \(items.count) windows of \($0)") }
                ?? String(localized: "Aligned \(alignedCount) of \(items.count) windows")
        case .success:
            message = verbose ? verboseSuccessMessage() : briefSuccessMessage()
            if verbose && isCapped {
                message += ". " + String(localized: "\(totalWindowCount - items.count) windows were not moved")
            }
        }

        for note in constraintNotes() {
            message += "; " + note
        }
        return message
    }

    private func verboseSuccessMessage() -> String {
        let count = items.count
        let total = totalWindowCount
        switch scope {
        case .singleApp:
            break
        case .allApps(let apps):
            // The cap note ("N windows were not moved") is appended by the caller.
            switch mode {
            case .grid:
                return String(localized: "Aligned \(count) windows from \(apps) apps into a \(cols) by \(rows) grid")
            case .horizontal:
                return String(localized: "Aligned \(count) windows from \(apps) apps horizontally side by side")
            case .vertical:
                return String(localized: "Stacked \(count) windows from \(apps) apps vertically")
            case .maximize:
                return String(localized: "Maximized \(count) windows from \(apps) apps, stacked full screen")
            }
        case .stackedByApp(let apps):
            return String(localized: "Stacked \(count) windows of \(apps) apps into a \(cols) by \(rows) grid, one stack per app")
        }
        switch (mode, isCapped, appName) {
        case (.grid, false, .some(let app)):
            return String(localized: "Aligned \(count) windows of \(app) into a \(cols) by \(rows) grid")
        case (.grid, false, .none):
            return String(localized: "Aligned \(count) windows into a \(cols) by \(rows) grid")
        case (.grid, true, .some(let app)):
            return String(localized: "Aligned the first \(count) of \(total) windows of \(app) into a \(cols) by \(rows) grid")
        case (.grid, true, .none):
            return String(localized: "Aligned the first \(count) of \(total) windows into a \(cols) by \(rows) grid")
        case (.horizontal, false, .some(let app)):
            return String(localized: "Aligned \(count) windows of \(app) horizontally side by side")
        case (.horizontal, false, .none):
            return String(localized: "Aligned \(count) windows horizontally side by side")
        case (.horizontal, true, .some(let app)):
            return String(localized: "Aligned the first \(count) of \(total) windows of \(app) horizontally side by side")
        case (.horizontal, true, .none):
            return String(localized: "Aligned the first \(count) of \(total) windows horizontally side by side")
        case (.vertical, false, .some(let app)):
            return String(localized: "Stacked \(count) windows of \(app) vertically")
        case (.vertical, false, .none):
            return String(localized: "Stacked \(count) windows vertically")
        case (.vertical, true, .some(let app)):
            return String(localized: "Stacked the first \(count) of \(total) windows of \(app) vertically")
        case (.vertical, true, .none):
            return String(localized: "Stacked the first \(count) of \(total) windows vertically")
        case (.maximize, false, .some(let app)):
            return String(localized: "Maximized \(count) windows of \(app), stacked full screen")
        case (.maximize, false, .none):
            return String(localized: "Maximized \(count) windows, stacked full screen")
        case (.maximize, true, .some(let app)):
            return String(localized: "Maximized the first \(count) of \(total) windows of \(app), stacked full screen")
        case (.maximize, true, .none):
            return String(localized: "Maximized the first \(count) of \(total) windows, stacked full screen")
        }
    }

    private func briefSuccessMessage() -> String {
        let count = items.count
        let total = totalWindowCount
        if case .stackedByApp(let apps) = scope {
            return String(localized: "Stacked by app, \(apps) apps, \(count) windows")
        }
        switch (mode, isCapped) {
        case (.grid, false): return String(localized: "Grid layout, \(count) windows")
        case (.grid, true): return String(localized: "Grid layout, first \(count) of \(total) windows")
        case (.horizontal, false): return String(localized: "Horizontal layout, \(count) windows")
        case (.horizontal, true): return String(localized: "Horizontal layout, first \(count) of \(total) windows")
        case (.vertical, false): return String(localized: "Vertical layout, \(count) windows")
        case (.vertical, true): return String(localized: "Vertical layout, first \(count) of \(total) windows")
        case (.maximize, false): return String(localized: "Maximized, \(count) windows")
        case (.maximize, true): return String(localized: "Maximized, first \(count) of \(total) windows")
        }
    }

    private func constraintNotes() -> [String] {
        var notes: [String] = []

        let clamped = items.filter {
            if case .clamped = $0.outcome { return true }
            return false
        }
        if clamped.count == 1 {
            let title = clamped[0].title ?? String(localized: "One window")
            notes.append(String(localized: "\(title) kept its minimum size"))
        } else if clamped.count > 1 {
            notes.append(String(localized: "\(clamped.count) windows kept their minimum size"))
        }

        let movedOnly = items.filter { $0.outcome == .movedOnly }
        if movedOnly.count == 1 {
            let title = movedOnly[0].title ?? String(localized: "One window")
            notes.append(String(localized: "\(title) is not resizable"))
        } else if movedOnly.count > 1 {
            notes.append(String(localized: "\(movedOnly.count) windows are not resizable"))
        }

        return notes
    }
}
