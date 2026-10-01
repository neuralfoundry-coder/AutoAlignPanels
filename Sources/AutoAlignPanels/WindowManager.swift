import Cocoa
import ApplicationServices
import AutoAlignPanelsCore

@MainActor
final class WindowManager {
    static let shared = WindowManager()

    /// Most recent alignment: which window landed in which cell, used by the
    /// slot shortcuts (Ctrl+Opt+1..4) and the arrow-key focus navigation so
    /// motor-impaired users can switch focus without a pointing device.
    private struct SlotEntry {
        let window: AXUIElement
        let pid: pid_t
        let cell: GridCell
        let title: String?
    }

    private struct SlotMapping {
        var entries: [SlotEntry]
        let rows: Int
        let cols: Int
        let mode: AlignmentMode
        let scope: AlignmentReport.Scope

        var pids: Set<pid_t> { Set(entries.map(\.pid)) }

        /// Entry index behind each slot number. Stacked-by-app passes put
        /// several windows in one cell, so a slot is a stack (its front
        /// window), not a window.
        var slotIndices: [Int] {
            guard case .stackedByApp = scope else { return Array(entries.indices) }
            var seen: [(Int, Int)] = []
            var result: [Int] = []
            for (index, entry) in entries.enumerated()
            where !seen.contains(where: { $0 == (entry.cell.row, entry.cell.col) }) {
                seen.append((entry.cell.row, entry.cell.col))
                result.append(index)
            }
            return result
        }
    }

    private var slotMapping: SlotMapping?
    private var currentFocusIndex = 0

    /// Pre-alignment snapshot for ⌃⇧Z: restore swaps with the current frames,
    /// so pressing it twice toggles between the two arrangements.
    private struct ArrangementSnapshot {
        var entries: [(window: AXUIElement, pid: pid_t, frame: CGRect)]
    }

    private var previousArrangement: ArrangementSnapshot?

    private var lastUsedMode: AlignmentMode = .grid
    private var terminationObserver: NSObjectProtocol?

    private var feedback: AlignmentFeedbackCenter { .shared }

    init() {
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor [weak self] in
                self?.handleAppTermination(app)
            }
        }
    }

    // MARK: - Settings

    var gap: CGFloat {
        let raw = UserDefaults.standard.object(forKey: "windowGap") as? Double ?? 8
        return CGFloat(min(max(raw, 0), 64))
    }

    var margin: CGFloat {
        let raw = UserDefaults.standard.object(forKey: "windowMargin") as? Double ?? 0
        return CGFloat(min(max(raw, 0), 64))
    }

    /// 0 = no limit. Aligning 30 windows produces unreadable cells, so only
    /// the frontmost N are aligned and the announcement says so.
    private var maxWindowsToAlign: Int {
        let raw = UserDefaults.standard.object(forKey: "maxWindowsToAlign") as? Int ?? 9
        return max(0, raw)
    }

    // MARK: - Public entry points

    func alignFrontmostAppWindows(mode: AlignmentMode = .grid) {
        alignWindows(of: nil, mode: mode)
    }

    func alignWindows(of explicitApp: NSRunningApplication?, mode: AlignmentMode) {
        guard requireTrust() else { return }
        guard let app = resolveTargetApp(explicitApp) else { return }
        performAlignment(app: app, mode: mode)
    }

    /// Tiles the windows of EVERY visible app on the working screen — mixed
    /// apps side by side, one cell per window.
    func alignAllAppsWindows(mode: AlignmentMode) {
        guard requireTrust() else { return }
        performMultiAppAlignment(mode: mode, stackByApp: false)
    }

    /// Mixed apps, one cell per APP: each app's windows are stacked on top
    /// of each other in that app's cell, and the stacks are tiled in a grid.
    func alignStackedByApp() {
        guard requireTrust() else { return }
        performMultiAppAlignment(mode: .grid, stackByApp: true)
    }

    private func logCollection(_ label: String, app: NSRunningApplication) {
        Diag.log.info("collect: \(app.bundleIdentifier ?? "?", privacy: .public) -> \(label, privacy: .public)")
    }

    /// Aligns using whichever layout was last used for the app — one memorable
    /// shortcut with predictable, repeatable behavior (cognitive accessibility).
    func alignWithLastLayoutForFrontmostApp() {
        guard requireTrust() else { return }
        guard let app = resolveTargetApp(nil) else { return }
        let mode = app.bundleIdentifier.flatMap { lastLayout(for: $0) } ?? .grid
        performAlignment(app: app, mode: mode)
    }

    /// Moves the frontmost app's windows to the next display, re-applying the
    /// app's last layout there — no dragging across screens.
    func moveFrontmostAppToNextDisplay() {
        guard requireTrust() else { return }
        guard let app = resolveTargetApp(nil) else { return }
        guard NSScreen.screens.count > 1 else {
            feedback.notice(String(localized: "Only one display connected"), symbolName: "display")
            return
        }
        let mode = app.bundleIdentifier.flatMap { lastLayout(for: $0) } ?? lastUsedMode
        if let (report, screen) = performAlignment(app: app, mode: mode, screenTransform: { index, screens in
            (index + 1) % screens.count
        }), report.alignedCount > 0 {
            feedback.announceOnly(String(localized: "Moved to \(screen.localizedName)"))
        }
    }

    /// Restores every window to where it was before the last alignment —
    /// mistake recovery without pointer-precision window dragging.
    func restorePreviousArrangement() {
        guard requireTrust() else { return }
        guard let snapshot = previousArrangement, !snapshot.entries.isEmpty else {
            feedback.notice(String(localized: "Nothing to restore"), symbolName: "arrow.uturn.backward")
            return
        }
        let redo = snapshot.entries.compactMap { entry in
            AXWindowKit.frame(of: entry.window).map { (window: entry.window, pid: entry.pid, frame: $0) }
        }
        var restored = 0
        for (window, _, frame) in snapshot.entries where AXWindowKit.setFrame(window, to: frame) == .success {
            restored += 1
        }
        guard restored > 0 else {
            // Every window is gone or rejected the set — success-toned
            // feedback here would lie to the ears of blind users.
            previousArrangement = nil
            feedback.failure(String(localized: "Could not restore previous arrangement"))
            return
        }
        previousArrangement = ArrangementSnapshot(entries: redo)
        feedback.restored(count: restored)
    }

    /// Speaks the title of every visible window of the frontmost app, letting
    /// blind / low-vision users enumerate what's open without scanning the
    /// screen or the App Switcher.
    func readOpenWindows() {
        guard requireTrust() else { return }
        guard let app = resolveTargetApp(nil) else { return }
        let appName = app.localizedName ?? String(localized: "the frontmost app")

        switch collectAlignableWindows(for: app) {
        case .ok(let windows, _):
            let heading = windows.count == 1
                ? String(localized: "\(appName) has 1 window")
                : String(localized: "\(appName) has \(windows.count) windows")
            var parts = [heading]
            for (index, window) in windows.enumerated() {
                parts.append("\(index + 1): \(window.title ?? String(localized: "Untitled window"))")
            }
            feedback.read(message: parts.joined(separator: ". "), count: windows.count, appName: appName)
        case .appHidden:
            feedback.notice(String(localized: "\(appName) is hidden"))
        case .noWindows:
            feedback.notice(String(localized: "\(appName) has no open windows"))
        case .noneOnThisSpace:
            feedback.notice(String(localized: "\(appName) has no windows on this Space"))
        case .allFullScreen:
            feedback.notice(String(localized: "All windows of \(appName) are full screen"))
        case .appUnresponsive:
            reportUnresponsive(appName: appName)
        }
    }

    /// Brings the window in the given alignment slot to focus. Slot is 1-based.
    func focusSlot(_ slot: Int) {
        guard requireTrust() else { return }
        guard let mapping = slotMapping, slot >= 1, slot <= mapping.slotIndices.count else {
            feedback.announceOnly(String(localized: "Slot \(slot) is empty"))
            return
        }
        var index = mapping.slotIndices[slot - 1]
        let entry = mapping.entries[index]
        guard let app = NSRunningApplication(processIdentifier: entry.pid), !app.isTerminated,
              AXWindowKit.isAlive(entry.window)
        else {
            feedback.announceOnly(String(localized: "Slot \(slot) is no longer available"))
            return
        }
        // Pressing a stack's slot again cycles through the stacked windows.
        if case .stackedByApp = mapping.scope,
           let focused = currentFocusedWindowIndex(in: mapping),
           mapping.entries[focused].cell == entry.cell {
            let stack = mapping.entries.indices.filter { mapping.entries[$0].cell == entry.cell }
            if let position = stack.firstIndex(of: focused) {
                index = stack[(position + 1) % stack.count]
            }
        }
        if let title = focusWindow(at: index, in: mapping) {
            feedback.announceOnly(String(localized: "Focused slot \(slot): \(title)"))
        } else {
            feedback.announceOnly(String(localized: "Could not focus slot \(slot)"))
        }
    }

    /// Moves focus to the window in the adjacent grid cell — spatial "the
    /// window to the left" instead of memorized slot numbers.
    func focusAdjacentWindow(_ direction: FocusDirection) {
        guard requireTrust() else { return }
        guard let mapping = slotMapping, !mapping.entries.isEmpty else {
            feedback.announceOnly(String(localized: "No alignment active. Align windows first."))
            return
        }
        // Resolve the truly focused window on every keypress — the user may
        // have refocused with the mouse or Cmd+` since the last alignment.
        let index = currentFocusedWindowIndex(in: mapping)
            ?? min(currentFocusIndex, mapping.entries.count - 1)

        // Maximize stacks every window in the same cell — arrows step
        // through the stack instead of navigating a grid.
        if mapping.mode == .maximize {
            let delta = (direction == .right || direction == .down) ? 1 : -1
            let target = index + delta
            guard target >= 0, target < mapping.entries.count else {
                feedback.announceOnly(direction.noWindowMessage)
                return
            }
            if let title = focusWindow(at: target, in: mapping) {
                feedback.announceOnly(String(localized: "Focused \(title), window \(target + 1) of \(mapping.entries.count)"))
            } else {
                feedback.announceOnly(String(localized: "Could not focus that window"))
            }
            return
        }

        let cell = mapping.entries[index].cell
        var row = cell.row
        var col = cell.col
        switch direction {
        case .left: col -= 1
        case .right: col += 1
        case .up: row -= 1
        case .down: row += 1
        }
        guard let target = mapping.entries.firstIndex(where: { $0.cell.row == row && $0.cell.col == col }) else {
            feedback.announceOnly(direction.noWindowMessage)
            return
        }
        if let title = focusWindow(at: target, in: mapping) {
            feedback.announceOnly(String(localized: "Focused \(title), row \(row + 1), column \(col + 1)"))
        } else {
            feedback.announceOnly(String(localized: "Could not focus that window"))
        }
    }

    /// "Where am I?" — speaks the focused window's position in the layout.
    func announceFocusedWindowPosition() {
        guard requireTrust() else { return }
        guard let app = resolveTargetApp(nil) else { return }
        let appName = app.localizedName ?? String(localized: "The frontmost app")

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXWindowKit.applyTimeout(axApp)
        let (ref, _) = AXWindowKit.copyValue(axApp, kAXFocusedWindowAttribute as String)
        guard let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else {
            feedback.announceOnly(String(localized: "\(appName) has no focused window"))
            return
        }
        let focused = ref as! AXUIElement
        let title = AXWindowKit.title(of: focused) ?? String(localized: "Untitled window")

        if let mapping = slotMapping, mapping.pids.contains(app.processIdentifier),
           let index = mapping.entries.firstIndex(where: { CFEqual($0.window, focused) }) {
            if mapping.mode == .maximize {
                feedback.announceOnly(String(localized: "\(title), window \(index + 1) of \(mapping.entries.count), stacked"))
            } else {
                // Columns before rows, matching the alignment announcement
                // ("into a 2 by 2 grid") and the HUD.
                let cell = mapping.entries[index].cell
                feedback.announceOnly(String(localized: "\(title), row \(cell.row + 1), column \(cell.col + 1), of \(mapping.cols) by \(mapping.rows) grid"))
            }
        } else {
            feedback.announceOnly(String(localized: "\(appName), \(title), not in the current alignment"))
        }
    }

    // MARK: - Single-window snapping (Magnet-style)

    /// Frames each window had before its first snap, for ⌃⌥⌫ restore.
    private var preSnapFrames: [(window: AXUIElement, frame: CGRect)] = []

    /// Moves the focused window of the front app into a screen region.
    func snapFocusedWindow(_ position: SnapPosition) {
        guard requireTrust() else { return }
        guard let (window, _) = focusedWindowForSnap() else { return }
        guard let screen = screenContaining(window.frame) else { return }
        let area = cgRect(fromCocoa: screen.visibleFrame)
        let target = SnapLayout.frame(for: position, windowSize: window.frame.size,
                                      in: area, gap: gap, margin: margin)
        rememberPreSnapFrame(of: window)
        let title = position.title(portrait: area.height > area.width)
        applySnap(window, to: target, title: title)
    }

    /// Puts the focused window back where it was before it was first snapped.
    func restoreFocusedWindow() {
        guard requireTrust() else { return }
        guard let (window, _) = focusedWindowForSnap() else { return }
        guard let index = preSnapFrames.firstIndex(where: { CFEqual($0.window, window.element) }) else {
            feedback.announceOnly(String(localized: "Nothing to restore"))
            return
        }
        let frame = preSnapFrames.remove(at: index).frame
        applySnap(window, to: frame, title: String(localized: "Restored"))
    }

    /// Moves the focused window to the next (+1) or previous (-1) display,
    /// keeping its relative position and proportional size.
    func moveFocusedWindowToDisplay(offset: Int) {
        guard requireTrust() else { return }
        let screens = NSScreen.screens
        guard screens.count > 1 else {
            feedback.notice(String(localized: "Only one display connected"), symbolName: "display")
            return
        }
        guard let (window, _) = focusedWindowForSnap(),
              let current = screenContaining(window.frame),
              let index = screens.firstIndex(of: current)
        else { return }
        let destination = screens[(index + offset + screens.count) % screens.count]
        let target = SnapLayout.translate(window.frame,
                                          from: cgRect(fromCocoa: current.visibleFrame),
                                          to: cgRect(fromCocoa: destination.visibleFrame))
        rememberPreSnapFrame(of: window)
        applySnap(window, to: target, title: String(localized: "Moved to \(destination.localizedName)"))
    }

    private func applySnap(_ window: ManagedWindow, to target: CGRect, title: String) {
        let outcome = alignOne(window, to: target)
        Diag.log.info("snap: \(title, privacy: .public) -> \(String(describing: outcome), privacy: .public)")
        switch outcome {
        case .aligned, .movedOnly:
            // Snaps are frequent and visible on screen: speak, no HUD.
            feedback.announceOnly(title)
        case .clamped:
            let name = window.title ?? String(localized: "One window")
            feedback.announceOnly(title + "; " + String(localized: "\(name) kept its minimum size"))
        case .failed(.timeout):
            reportUnresponsive(appName: NSWorkspace.shared.frontmostApplication?.localizedName)
        case .failed:
            feedback.failure(String(localized: "Could not move the window"))
        }
    }

    private func rememberPreSnapFrame(of window: ManagedWindow) {
        guard !preSnapFrames.contains(where: { CFEqual($0.window, window.element) }) else { return }
        preSnapFrames.append((window.element, window.frame))
        if preSnapFrames.count > 50 { preSnapFrames.removeFirst() }
    }

    /// The front app's focused window, read fresh. Reports and returns nil
    /// when there is nothing movable (hidden app, no window, full screen).
    private func focusedWindowForSnap() -> (ManagedWindow, NSRunningApplication)? {
        guard let app = resolveTargetApp(nil) else { return nil }
        let appName = app.localizedName ?? String(localized: "The frontmost app")
        if app.isHidden {
            feedback.failure(String(localized: "\(appName) is hidden"))
            return nil
        }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXWindowKit.applyTimeout(axApp)
        var (ref, error) = AXWindowKit.copyValue(axApp, kAXFocusedWindowAttribute as String)
        if error == .cannotComplete {
            (ref, error) = AXWindowKit.copyValue(axApp, kAXFocusedWindowAttribute as String)
        }
        if error == .cannotComplete {
            reportUnresponsive(appName: app.localizedName)
            return nil
        }
        guard let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else {
            feedback.failure(String(localized: "\(appName) has no focused window"))
            return nil
        }
        let element = ref as! AXUIElement
        AXWindowKit.applyTimeout(element)
        let attrs = AXWindowKit.readWindowAttributes(element)
        if attrs.isFullScreen {
            feedback.failure(String(localized: "All windows are full screen"))
            return nil
        }
        guard let position = attrs.position, let size = attrs.size else {
            feedback.failure(String(localized: "Could not move the window"))
            return nil
        }
        return (ManagedWindow(element: element, frame: CGRect(origin: position, size: size), title: attrs.title), app)
    }

    /// Screen holding the center of an AX (top-left) frame; nearest screen
    /// when the center is off every screen.
    private func screenContaining(_ frame: CGRect) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            feedback.failure(String(localized: "No display found"))
            return nil
        }
        let index = ScreenSelection.targetScreenIndex(
            windowFrames: [cgRect(fromCocoa: frame)],   // the flip is its own inverse
            screenFrames: screens.map(\.frame)
        ) ?? 0
        return screens[index]
    }

    /// Flips between Cocoa (bottom-left, primary-anchored) and AX/CG
    /// (top-left) global coordinates. The transform is its own inverse.
    private func cgRect(fromCocoa rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.origin.x, y: primaryHeight - rect.origin.y - rect.height,
                      width: rect.width, height: rect.height)
    }

    // MARK: - Alignment pipeline

    @discardableResult
    private func performAlignment(
        app: NSRunningApplication,
        mode: AlignmentMode,
        screenTransform: ((Int, [NSScreen]) -> Int)? = nil
    ) -> (AlignmentReport, NSScreen)? {
        let appName = app.localizedName

        let windows: [ManagedWindow]
        let skippedUnresponsive: Int
        switch collectAlignableWindows(for: app) {
        case .ok(let collected, let skipped):
            windows = collected
            skippedUnresponsive = skipped
            logCollection("ok windows=\(collected.count) skipped=\(skipped)", app: app)
        case .appHidden:
            logCollection("appHidden", app: app)
            let name = appName ?? String(localized: "The app")
            feedback.failure(String(localized: "\(name) is hidden"))
            return nil
        case .noWindows:
            logCollection("noWindows", app: app)
            feedback.failure(String(localized: "No windows to align"))
            return nil
        case .noneOnThisSpace:
            logCollection("noneOnThisSpace", app: app)
            feedback.failure(String(localized: "No windows on this Space to align"))
            return nil
        case .allFullScreen:
            logCollection("allFullScreen", app: app)
            feedback.failure(String(localized: "All windows are full screen"))
            return nil
        case .appUnresponsive:
            logCollection("appUnresponsive", app: app)
            reportUnresponsive(appName: appName)
            return nil
        }

        let totalCount = windows.count
        let cap = maxWindowsToAlign
        // AX returns windows roughly front-to-back, so "first N" = most recent.
        let toAlign = (cap > 0 && totalCount > cap) ? Array(windows.prefix(cap)) : windows

        let screens = NSScreen.screens
        guard let primary = screens.first else {
            feedback.failure(String(localized: "No display found"))
            return nil
        }

        // Window frames are AX top-left; NSScreen frames are Cocoa bottom-left
        // anchored to the primary screen. Flip to pick the target screen.
        let primaryHeight = primary.frame.height
        let cocoaFrames = toAlign.map { window in
            CGRect(x: window.frame.origin.x,
                   y: primaryHeight - window.frame.origin.y - window.frame.height,
                   width: window.frame.width,
                   height: window.frame.height)
        }
        var screenIndex = ScreenSelection.targetScreenIndex(
            windowFrames: cocoaFrames,
            screenFrames: screens.map(\.frame)
        ) ?? 0
        if let screenTransform {
            screenIndex = screenTransform(screenIndex, screens)
        }
        let screen = screens[screenIndex]

        let visibleFrame = screen.visibleFrame
        let cgVisibleFrame = CGRect(
            x: visibleFrame.origin.x,
            y: primaryHeight - visibleFrame.origin.y - visibleFrame.height,
            width: visibleFrame.width,
            height: visibleFrame.height
        )

        let layout = GridCalculator.calculate(
            windowCount: toAlign.count,
            screenFrame: cgVisibleFrame,
            gap: gap,
            margin: margin,
            mode: mode
        )

        let report = commitAlignment(
            targets: toAlign.map { AlignTarget(window: $0, pid: app.processIdentifier) },
            cells: layout.cells,
            layout: layout,
            mode: mode,
            scope: .singleApp,
            appName: appName,
            totalCount: totalCount,
            skippedUnresponsive: skippedUnresponsive,
            screen: screen
        )
        lastUsedMode = mode
        if let bundleID = app.bundleIdentifier {
            rememberLayout(mode: mode, for: bundleID)
        }
        return (report, screen)
    }

    private struct AlignTarget {
        let window: ManagedWindow
        let pid: pid_t
    }

    /// Apply → verify → report, shared by single- and multi-app passes.
    /// Updates the undo snapshot and slot mapping, then gives feedback.
    @discardableResult
    private func commitAlignment(
        targets: [AlignTarget],
        cells: [GridCell],
        layout: GridLayout,
        mode: AlignmentMode,
        scope: AlignmentReport.Scope,
        appName: String?,
        totalCount: Int,
        skippedUnresponsive: Int,
        screen: NSScreen
    ) -> AlignmentReport {
        // Frames were already read at collection time — the snapshot is free.
        // Committed only after at least one window actually moved, so a fully
        // failed pass doesn't destroy the still-valid undo state.
        let snapshot = ArrangementSnapshot(
            entries: targets.map { ($0.window.element, $0.pid, $0.window.frame) }
        )

        let entries = Array(zip(targets, cells))
        var items = applyLayout(entries.map { ($0.0.window, $0.0.pid, $0.1) })
        // Windows whose reads timed out during collection never got a cell;
        // count them as failures so the summary stays truthful ("Aligned X of
        // Y windows") instead of claiming full success.
        if skippedUnresponsive > 0 {
            items.append(contentsOf: (0..<skippedUnresponsive).map { _ in
                AlignmentReport.Item(title: nil, outcome: .failed(.timeout))
            })
        }

        let report = AlignmentReport(
            appName: appName,
            mode: mode,
            rows: layout.rows,
            cols: layout.cols,
            items: items,
            totalWindowCount: totalCount + skippedUnresponsive,
            scope: scope
        )

        // Slots map only windows that actually moved, in cell order, so slot
        // numbers match what the user sees on screen.
        let slotEntries = zip(entries, items).compactMap { entry, item -> SlotEntry? in
            item.outcome.isFailure ? nil : SlotEntry(window: entry.0.window.element, pid: entry.0.pid,
                                                     cell: entry.1, title: entry.0.window.title)
        }
        slotMapping = SlotMapping(
            entries: slotEntries,
            rows: layout.rows,
            cols: layout.cols,
            mode: mode,
            scope: scope
        )
        currentFocusIndex = 0
        if report.alignedCount > 0 {
            previousArrangement = snapshot
        }

        Diag.log.info("aligned: \(report.summaryMessage(verbose: true), privacy: .public)")
        feedback.alignment(report, screen: screen)
        return report
    }

    // MARK: - Multi-app pipeline

    private func performMultiAppAlignment(mode: AlignmentMode, stackByApp: Bool) {
        guard let primary = NSScreen.screens.first else {
            feedback.failure(String(localized: "No display found"))
            return
        }
        guard let collected = collectAllAppsWindows() else {
            feedback.failure(String(localized: "No windows to align"))
            return
        }
        let screen = collected.screen
        let primaryHeight = primary.frame.height
        let visibleFrame = screen.visibleFrame
        let cgVisibleFrame = CGRect(
            x: visibleFrame.origin.x,
            y: primaryHeight - visibleFrame.origin.y - visibleFrame.height,
            width: visibleFrame.width,
            height: visibleFrame.height
        )

        let all = collected.windows
        let cap = maxWindowsToAlign
        let targets: [AlignTarget]
        let layout: GridLayout
        let cells: [GridCell]
        let appCount: Int

        if stackByApp {
            // The cap limits stacks (apps), not windows: stacked windows
            // share a cell, so they never make cells unreadably small.
            var groupOrder: [pid_t] = []
            for window in all.sorted(by: { $0.z < $1.z }) where !groupOrder.contains(window.pid) {
                groupOrder.append(window.pid)
            }
            if cap > 0 && groupOrder.count > cap {
                groupOrder = Array(groupOrder.prefix(cap))
            }
            let groups = groupOrder.map { pid in
                all.filter { $0.pid == pid }.sorted { $0.z < $1.z }
            }
            (layout, cells) = MultiAppLayout.stackedCells(
                groupSizes: groups.map(\.count),
                screenFrame: cgVisibleFrame,
                gap: gap,
                margin: margin
            )
            targets = groups.flatMap { $0.map { AlignTarget(window: $0.window, pid: $0.pid) } }
            appCount = groups.count
        } else {
            let order = MultiAppLayout.recentFirstGroupedOrder(
                zOrders: all.map(\.z),
                groupIDs: all.map { Int($0.pid) },
                limit: cap
            )
            targets = order.map { AlignTarget(window: all[$0].window, pid: all[$0].pid) }
            layout = GridCalculator.calculate(
                windowCount: targets.count,
                screenFrame: cgVisibleFrame,
                gap: gap,
                margin: margin,
                mode: mode
            )
            cells = layout.cells
            appCount = Set(targets.map(\.pid)).count
        }

        Diag.log.info("collect(all apps): windows=\(all.count, privacy: .public) apps=\(appCount, privacy: .public) stack=\(stackByApp, privacy: .public) skipped=\(collected.skippedUnresponsive, privacy: .public)")
        commitAlignment(
            targets: targets,
            cells: cells,
            layout: layout,
            mode: mode,
            scope: stackByApp ? .stackedByApp(appCount: appCount) : .allApps(appCount: appCount),
            appName: nil,
            totalCount: all.count,
            skippedUnresponsive: collected.skippedUnresponsive,
            screen: screen
        )
    }

    private struct ZOrderedWindow {
        let window: ManagedWindow
        let pid: pid_t
        /// Position in the window server's front-to-back list (0 = frontmost).
        let z: Int
    }

    /// Every alignable window of every regular, visible app on the current
    /// Space whose center sits on the working screen — the screen of the
    /// frontmost window. Nil when there is nothing to align.
    private func collectAllAppsWindows() -> (windows: [ZOrderedWindow], screen: NSScreen, skippedUnresponsive: Int)? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let primary = NSScreen.screens.first
        else { return nil }

        // One CG snapshot for all apps: bounds per pid, in z-order.
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var boundsByPID: [pid_t: [(rect: CGRect, z: Int)]] = [:]
        for (z, info) in windowList.enumerated() {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID != ownPID,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary
            else { continue }
            var rect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict as CFDictionary, &rect),
                  rect.width > 50, rect.height > 50
            else { continue }
            boundsByPID[ownerPID, default: []].append((rect, z))
        }

        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isHidden && !$0.isTerminated
                && boundsByPID[$0.processIdentifier] != nil
        }
        let appPIDs = Set(apps.map(\.processIdentifier))
        let frontmostRect = boundsByPID
            .filter { appPIDs.contains($0.key) }
            .flatMap(\.value)
            .min { $0.z < $1.z }?.rect

        // Screens in AX/CG top-left coordinates.
        let primaryHeight = primary.frame.height
        let screens = NSScreen.screens
        let cgScreenFrames = screens.map { screen in
            CGRect(x: screen.frame.origin.x,
                   y: primaryHeight - screen.frame.origin.y - screen.frame.height,
                   width: screen.frame.width, height: screen.frame.height)
        }
        let anchor: CGPoint
        if let frontmostRect {
            anchor = CGPoint(x: frontmostRect.midX, y: frontmostRect.midY)
        } else {
            let mouse = NSEvent.mouseLocation
            anchor = CGPoint(x: mouse.x, y: primaryHeight - mouse.y)
        }
        let screenIndex = cgScreenFrames.firstIndex { $0.contains(anchor) } ?? 0
        let cgScreen = cgScreenFrames[screenIndex]

        var result: [ZOrderedWindow] = []
        var skippedUnresponsive = 0
        for app in apps {
            let pid = app.processIdentifier
            let bounds = boundsByPID[pid] ?? []
            switch collectAlignableWindows(for: app, prefetchedBounds: .bounds(bounds.map(\.rect))) {
            case .ok(let windows, let skipped):
                skippedUnresponsive += skipped
                for window in windows {
                    guard cgScreen.contains(CGPoint(x: window.frame.midX, y: window.frame.midY)) else { continue }
                    // z of the CG window this AX window matched (same 10pt tolerance).
                    let z = bounds.first { abs($0.rect.minX - window.frame.minX) < 10 && abs($0.rect.minY - window.frame.minY) < 10
                        && abs($0.rect.width - window.frame.width) < 10 && abs($0.rect.height - window.frame.height) < 10 }?.z ?? Int.max
                    result.append(ZOrderedWindow(window: window, pid: pid, z: z))
                }
            case .appUnresponsive:
                // A hung app must not block the others; its on-screen windows
                // count as failures so the summary stays truthful.
                skippedUnresponsive += MultiAppLayout.indices(of: bounds.map(\.rect), centeredIn: cgScreen).count
                Diag.log.info("collect(all apps): \(app.bundleIdentifier ?? "?", privacy: .public) unresponsive")
            case .appHidden, .noWindows, .noneOnThisSpace, .allFullScreen:
                continue
            }
        }
        guard !result.isEmpty else { return nil }
        return (result, screens[screenIndex], skippedUnresponsive)
    }

    private func applyLayout(_ entries: [(ManagedWindow, pid_t, GridCell)]) -> [AlignmentReport.Item] {
        var items: [AlignmentReport.Item] = []
        // Tracked per app: in a multi-app pass one hung app must not abort
        // the windows of every other app.
        var consecutiveTimeouts: [pid_t: Int] = [:]
        var aborted: Set<pid_t> = []

        for (window, pid, cell) in entries {
            if aborted.contains(pid) {
                items.append(.init(title: window.title, outcome: .failed(.timeout)))
                continue
            }
            let target = CGRect(x: cell.x, y: cell.y, width: cell.width, height: cell.height)
            let outcome = alignOne(window, to: target)
            if case .failed(.timeout) = outcome {
                consecutiveTimeouts[pid, default: 0] += 1
                // A hung app times out on every call; stop paying 1.5s per
                // remaining window once it's clearly unresponsive.
                if consecutiveTimeouts[pid, default: 0] >= 2 { aborted.insert(pid) }
            } else {
                consecutiveTimeouts[pid] = 0
            }
            items.append(.init(title: window.title, outcome: outcome))
        }
        return items
    }

    private func alignOne(_ window: ManagedWindow, to target: CGRect) -> AlignmentReport.WindowOutcome {
        // Try the set directly — the common case then needs zero settability
        // round-trips, and a hung app costs at most two timeouts here instead
        // of paying for settability probes first.
        var error = AXWindowKit.setFrame(window.element, to: target)
        if error == .cannotComplete {
            // Busy ≠ hung — retry once before reporting a timeout.
            error = AXWindowKit.setFrame(window.element, to: target)
        }
        if error == .cannotComplete { return .failed(.timeout) }

        if error != .success {
            // The app answered with a refusal (not a timeout) — classify it.
            if AXWindowKit.isSettable(window.element, kAXPositionAttribute as String) == false {
                return .failed(.notSettable)
            }
            // Non-resizable windows (dialogs, fixed panels) still accept position.
            if AXWindowKit.isSettable(window.element, kAXSizeAttribute as String) == false {
                var positionError = AXWindowKit.setPosition(window.element, target.origin)
                if positionError == .cannotComplete {
                    positionError = AXWindowKit.setPosition(window.element, target.origin)
                }
                if positionError == .cannotComplete { return .failed(.timeout) }
                guard positionError == .success else { return .failed(.apiError(Int(positionError.rawValue))) }
                return .movedOnly
            }
            return .failed(.apiError(Int(error.rawValue)))
        }

        // Read back and verify instead of assuming success: apps clamp to
        // minimum sizes, snap to character grids, or ignore the set entirely.
        guard let actual = AXWindowKit.frame(of: window.element) else {
            return .failed(.windowVanished)
        }
        let positionOK = abs(actual.origin.x - target.origin.x) <= 2 && abs(actual.origin.y - target.origin.y) <= 2
        // 10pt absorbs Terminal-style character-grid snapping without
        // reporting a false "kept its minimum size".
        let sizeOK = abs(actual.width - target.width) <= 10 && abs(actual.height - target.height) <= 10

        if positionOK && sizeOK { return .aligned }
        if positionOK { return .clamped(actualSize: actual.size) }

        // Position off — retry once (some apps reposition during the resize).
        _ = AXWindowKit.setPosition(window.element, target.origin)
        if let second = AXWindowKit.frame(of: window.element),
           abs(second.origin.x - target.origin.x) <= 2, abs(second.origin.y - target.origin.y) <= 2 {
            let secondSizeOK = abs(second.width - target.width) <= 10 && abs(second.height - target.height) <= 10
            return secondSizeOK ? .aligned : .clamped(actualSize: second.size)
        }
        return .failed(.positionRejected)
    }

    // MARK: - Window collection

    private enum CollectionResult {
        /// `skippedUnresponsive` counts windows dropped because their reads
        /// timed out — the report includes them as failures so the feedback
        /// never claims full success while windows were silently left behind.
        case ok([ManagedWindow], skippedUnresponsive: Int)
        case appHidden
        case noWindows
        case noneOnThisSpace
        case allFullScreen
        case appUnresponsive
    }

    private func collectAlignableWindows(
        for app: NSRunningApplication,
        prefetchedBounds: OnScreenBounds? = nil
    ) -> CollectionResult {
        if app.isHidden { return .appHidden }

        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)
        AXWindowKit.applyTimeout(axApp)

        var windowsRef: CFTypeRef?
        var result = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
        if result == .cannotComplete {
            // Busy ≠ hung: an app flooding its main thread (a terminal
            // streaming output, say) can miss one 1.5s window and recover.
            // The first call's timeout already gave it breathing room.
            result = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
        }
        if result == .cannotComplete { return .appUnresponsive }
        guard result == .success, let axWindows = windowsRef as? [AXUIElement], !axWindows.isEmpty else {
            return .noWindows
        }

        var kept: [ManagedWindow] = []
        var fullScreenSeen = 0
        var consecutiveTimeouts = 0
        var skippedUnresponsive = 0
        for (index, element) in axWindows.enumerated() {
            AXWindowKit.applyTimeout(element)
            var attrs = AXWindowKit.readWindowAttributes(element)
            if attrs.timedOut {
                // One retry: a momentarily busy app usually answers the
                // second attempt. Only a repeat timeout counts as hung.
                attrs = AXWindowKit.readWindowAttributes(element)
            }

            // A hung app times out on every window; stop paying the timeout
            // per remaining window once it's clearly unresponsive (mirrors
            // the abort rule in applyLayout).
            if attrs.timedOut {
                skippedUnresponsive += 1
                consecutiveTimeouts += 1
                if consecutiveTimeouts >= 2 {
                    skippedUnresponsive += axWindows.count - index - 1
                    break
                }
                continue
            }
            consecutiveTimeouts = 0

            // Palettes, inspectors, and sheets are not tileable. A failed
            // subrole read (some Java apps) keeps the window — the size
            // threshold below still applies.
            if let subrole = attrs.subrole, subrole != kAXStandardWindowSubrole as String {
                continue
            }
            if attrs.isFullScreen {
                fullScreenSeen += 1
                continue
            }
            if let minimized = attrs.minimized {
                if minimized { continue }
            } else if let error = attrs.minimizedError,
                      error != .attributeUnsupported, error != .noValue {
                // An element that cannot answer basic queries is dead or hostile.
                continue
            }
            guard let position = attrs.position, let size = attrs.size,
                  size.width > 50, size.height > 50
            else { continue }

            kept.append(ManagedWindow(element: element,
                                      frame: CGRect(origin: position, size: size),
                                      title: attrs.title))
        }

        if kept.isEmpty {
            if consecutiveTimeouts >= 2 { return .appUnresponsive }
            return fullScreenSeen > 0 ? .allFullScreen : .noWindows
        }

        // Current-Space filter: CGWindowList only reports windows on the
        // active Space, so AX windows without a matching on-screen bound live
        // on another Space and must not be dragged over here.
        switch prefetchedBounds ?? onScreenBounds(for: pid) {
        case .unavailable:
            // The CG API itself failed — no Space information; align what we have.
            return .ok(kept, skippedUnresponsive: skippedUnresponsive)
        case .bounds(let boundsList):
            if boundsList.isEmpty { return .noneOnThisSpace }
            let matched = kept.filter { window in
                boundsList.contains { bounds in
                    abs(window.frame.origin.x - bounds.origin.x) < 10 &&
                    abs(window.frame.origin.y - bounds.origin.y) < 10 &&
                    abs(window.frame.size.width - bounds.size.width) < 10 &&
                    abs(window.frame.size.height - bounds.size.height) < 10
                }
            }
            return matched.isEmpty ? .noneOnThisSpace : .ok(matched, skippedUnresponsive: skippedUnresponsive)
        }
    }

    private enum OnScreenBounds {
        case unavailable
        case bounds([CGRect])
    }

    private func onScreenBounds(for pid: pid_t) -> OnScreenBounds {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return .unavailable
        }

        let rects = windowList.compactMap { info -> CGRect? in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  ownerPID == pid,
                  layer == 0,
                  let boundsAny = info[kCGWindowBounds as String],
                  let boundsDict = boundsAny as? NSDictionary
            else { return nil }

            var rect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict as CFDictionary, &rect),
                  rect.width > 0, rect.height > 0
            else { return nil }
            return rect
        }
        return .bounds(rects)
    }

    // MARK: - Focus helpers

    private func currentFocusedWindowIndex(in mapping: SlotMapping) -> Int? {
        // Multi-app mappings: the focused window belongs to the front app.
        // Single-app mappings keep working while our own UI is frontmost.
        let pids = mapping.pids
        let pid: pid_t
        if let front = NSWorkspace.shared.frontmostApplication?.processIdentifier, pids.contains(front) {
            pid = front
        } else if pids.count == 1, let only = pids.first {
            pid = only
        } else {
            return nil
        }
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return nil }
        let axApp = AXUIElementCreateApplication(pid)
        AXWindowKit.applyTimeout(axApp)
        let (ref, _) = AXWindowKit.copyValue(axApp, kAXFocusedWindowAttribute as String)
        guard let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        let focused = ref as! AXUIElement
        return mapping.entries.firstIndex { CFEqual($0.window, focused) }
    }

    private func focusWindow(at index: Int, in mapping: SlotMapping) -> String? {
        guard index >= 0, index < mapping.entries.count else { return nil }
        let entry = mapping.entries[index]

        // Activate the owning app first so its windows can become key.
        if let app = NSRunningApplication(processIdentifier: entry.pid), !app.isTerminated {
            if #available(macOS 14.0, *) {
                app.activate()
            } else {
                app.activate(options: [.activateIgnoringOtherApps])
            }
        }

        guard AXUIElementPerformAction(entry.window, kAXRaiseAction as CFString) == .success else {
            return nil
        }
        AXUIElementSetAttributeValue(entry.window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(entry.window, kAXFocusedAttribute as CFString, kCFBooleanTrue)

        currentFocusIndex = index
        return AXWindowKit.title(of: entry.window) ?? entry.title ?? String(localized: "Untitled window")
    }

    // MARK: - Target resolution & permission

    private func resolveTargetApp(_ explicit: NSRunningApplication?) -> NSRunningApplication? {
        if let explicit { return explicit }
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            return front
        }
        // Our own UI is frontmost — fall back to the app captured when the
        // status item was clicked.
        if let captured = PopoverContext.shared.targetApp, !captured.isTerminated {
            return captured
        }
        feedback.announceOnly(String(localized: "Switch to the app you want to align, then press the shortcut"))
        return nil
    }

    /// AX timeouts have two very different causes: the target app is hung, or
    /// OUR process's AX session is stale (permission granted after launch —
    /// AXIsProcessTrusted says true but every call fails). Blaming the target
    /// app for the second case sent users chasing ghosts; self-probe first.
    private func reportUnresponsive(appName: String?) {
        guard AccessibilityHelper.axSessionHealthy() else {
            Diag.log.error("unresponsive verdict but OUR AX session is unhealthy -> relaunch flow")
            AccessibilityHelper.relaunchToApplyPermission()
            return
        }
        let name = appName ?? String(localized: "The app")
        feedback.failure(String(localized: "\(name) is not responding"))
    }

    private func requireTrust() -> Bool {
        if AccessibilityHelper.isTrusted { return true }
        Diag.log.error("requireTrust: not trusted")
        // Sounds and announcements from our own process work before AX trust
        // is granted — a blind user must not get silence here. The wording
        // must not promise a system prompt: once a TCC entry exists (denied
        // or unchecked), checkAndPrompt() shows nothing.
        AccessibilityHelper.playErrorSound()
        AccessibilityHelper.announce(String(localized: "Accessibility permission is required. Enable AutoAlignPanels in System Settings, Privacy and Security, Accessibility."))
        AccessibilityHelper.checkAndPrompt()
        // Nothing runs without the permission — bring the walkthrough (live
        // status + "Open System Settings") back in front of the user.
        OnboardingWindowController.shared.show()
        return false
    }

    private func handleAppTermination(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        slotMapping?.entries.removeAll { $0.pid == pid }
        if slotMapping?.entries.isEmpty == true {
            slotMapping = nil
        }
        previousArrangement?.entries.removeAll { $0.pid == pid }
        if previousArrangement?.entries.isEmpty == true {
            previousArrangement = nil
        }
        preSnapFrames.removeAll { entry in
            var owner: pid_t = 0
            return AXUIElementGetPid(entry.window, &owner) != .success || owner == pid
        }
    }

    // MARK: - Per-app layout memory (LRU-capped)

    private static let layoutsKey = "a11yLastLayouts"
    private static let layoutsOrderKey = "a11yLastLayoutsOrder"
    private static let layoutMemoryCap = 50

    func rememberLayout(mode: AlignmentMode, for bundleID: String) {
        let enabled = UserDefaults.standard.object(forKey: AccessibilityPrefs.rememberPerAppLayoutKey) as? Bool ?? true
        guard enabled else { return }

        let defaults = UserDefaults.standard
        var layouts = defaults.dictionary(forKey: Self.layoutsKey) as? [String: String] ?? [:]
        var order = defaults.stringArray(forKey: Self.layoutsOrderKey) ?? []
        layouts[bundleID] = mode.persistedValue
        order.removeAll { $0 == bundleID }
        order.append(bundleID)
        while order.count > Self.layoutMemoryCap {
            layouts.removeValue(forKey: order.removeFirst())
        }
        defaults.set(layouts, forKey: Self.layoutsKey)
        defaults.set(order, forKey: Self.layoutsOrderKey)
    }

    func lastLayout(for bundleID: String) -> AlignmentMode? {
        let layouts = UserDefaults.standard.dictionary(forKey: Self.layoutsKey) as? [String: String]
        guard let raw = layouts?[bundleID] else { return nil }
        return AlignmentMode(persistedValue: raw)
    }
}

private extension FocusDirection {
    var noWindowMessage: String {
        switch self {
        case .left: return String(localized: "No window to the left")
        case .right: return String(localized: "No window to the right")
        case .up: return String(localized: "No window above")
        case .down: return String(localized: "No window below")
        }
    }
}
