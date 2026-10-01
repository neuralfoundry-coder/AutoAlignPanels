import XCTest
import AutoAlignPanelsCore

final class AlignmentReportTests: XCTestCase {
    private func makeReport(
        mode: AlignmentMode = .grid,
        rows: Int = 2, cols: Int = 2,
        outcomes: [AlignmentReport.WindowOutcome],
        titles: [String?]? = nil,
        appName: String? = "Safari",
        total: Int? = nil
    ) -> AlignmentReport {
        let items = outcomes.enumerated().map { index, outcome in
            AlignmentReport.Item(title: titles?[index] ?? "Window \(index + 1)", outcome: outcome)
        }
        return AlignmentReport(appName: appName, mode: mode, rows: rows, cols: cols, items: items, totalWindowCount: total)
    }

    // MARK: - Legacy message compatibility (regression requirement)

    func testFullSuccessGridMessagesMatchLegacyStrings() {
        let report = makeReport(outcomes: [.aligned, .aligned, .aligned, .aligned])
        XCTAssertEqual(report.summaryMessage(verbose: true), "Aligned 4 windows of Safari into a 2 by 2 grid")
        XCTAssertEqual(report.summaryMessage(verbose: false), "Grid layout, 4 windows")
    }

    func testFullSuccessHorizontalMessagesMatchLegacyStrings() {
        let report = makeReport(mode: .horizontal, rows: 1, cols: 3, outcomes: [.aligned, .aligned, .aligned])
        XCTAssertEqual(report.summaryMessage(verbose: true), "Aligned 3 windows of Safari horizontally side by side")
        XCTAssertEqual(report.summaryMessage(verbose: false), "Horizontal layout, 3 windows")
    }

    func testFullSuccessVerticalMessagesMatchLegacyStrings() {
        let report = makeReport(mode: .vertical, rows: 2, cols: 1, outcomes: [.aligned, .aligned])
        XCTAssertEqual(report.summaryMessage(verbose: true), "Stacked 2 windows of Safari vertically")
        XCTAssertEqual(report.summaryMessage(verbose: false), "Vertical layout, 2 windows")
    }

    func testNilAppNameOmitsAppPart() {
        let report = makeReport(outcomes: [.aligned], appName: nil)
        XCTAssertEqual(report.summaryMessage(verbose: true), "Aligned 1 windows into a 2 by 2 grid")
    }

    // MARK: - Tone

    func testToneClassification() {
        XCTAssertEqual(makeReport(outcomes: [.aligned, .aligned]).tone, .success)
        XCTAssertEqual(makeReport(outcomes: [.aligned, .clamped(actualSize: .init(width: 500, height: 400))]).tone, .success)
        XCTAssertEqual(makeReport(outcomes: [.aligned, .movedOnly]).tone, .success)
        XCTAssertEqual(makeReport(outcomes: [.aligned, .failed(.timeout)]).tone, .partial)
        XCTAssertEqual(makeReport(outcomes: [.failed(.timeout), .failed(.notSettable)]).tone, .failure)
    }

    // MARK: - Partial / failure messages

    func testPartialMessageCountsHonestly() {
        let report = makeReport(outcomes: [.aligned, .aligned, .aligned, .failed(.timeout)])
        XCTAssertEqual(report.summaryMessage(verbose: false), "Aligned 3 of 4 windows of Safari")
    }

    func testTotalFailureMessage() {
        let report = makeReport(outcomes: [.failed(.notSettable), .failed(.apiError(-25204))])
        XCTAssertEqual(report.summaryMessage(verbose: false), "Could not align windows of Safari")
    }

    // MARK: - Constraint notes

    func testSingleClampedWindowIsNamed() {
        let report = makeReport(outcomes: [.aligned, .clamped(actualSize: .init(width: 700, height: 500))],
                                titles: ["Safari", "Terminal"])
        XCTAssertEqual(report.summaryMessage(verbose: false),
                       "Grid layout, 2 windows; Terminal kept its minimum size")
    }

    func testMultipleClampedWindowsAreCounted() {
        let clamp = AlignmentReport.WindowOutcome.clamped(actualSize: .init(width: 700, height: 500))
        let report = makeReport(outcomes: [.aligned, clamp, clamp])
        XCTAssertTrue(report.summaryMessage(verbose: false).hasSuffix("; 2 windows kept their minimum size"))
    }

    func testMovedOnlyNote() {
        let report = makeReport(outcomes: [.aligned, .movedOnly], titles: ["Main", "Inspector"])
        XCTAssertEqual(report.summaryMessage(verbose: false),
                       "Grid layout, 2 windows; Inspector is not resizable")
    }

    // MARK: - Cap

    func testCappedSuccessMessages() {
        let report = makeReport(rows: 3, cols: 3, outcomes: Array(repeating: .aligned, count: 9), total: 30)
        XCTAssertEqual(report.summaryMessage(verbose: true),
                       "Aligned the first 9 of 30 windows of Safari into a 3 by 3 grid. 21 windows were not moved")
        XCTAssertEqual(report.summaryMessage(verbose: false), "Grid layout, first 9 of 30 windows")
        XCTAssertTrue(report.isCapped)
    }

    func testUncappedReportDefaultsTotalToItemCount() {
        let report = makeReport(outcomes: [.aligned, .aligned])
        XCTAssertEqual(report.totalWindowCount, 2)
        XCTAssertFalse(report.isCapped)
    }

    // MARK: - Counts

    func testCounts() {
        let report = makeReport(outcomes: [.aligned, .movedOnly, .failed(.windowVanished)])
        XCTAssertEqual(report.alignedCount, 2)
        XCTAssertEqual(report.failedCount, 1)
        XCTAssertFalse(report.isFullSuccess)
    }
}

final class AlignmentReportScopeTests: XCTestCase {
    private func items(_ n: Int) -> [AlignmentReport.Item] {
        (0..<n).map { _ in .init(title: nil, outcome: .aligned) }
    }

    func testAllAppsVerboseMentionsAppCount() {
        let report = AlignmentReport(appName: nil, mode: .grid, rows: 2, cols: 2,
                                     items: items(4), scope: .allApps(appCount: 3))
        XCTAssertEqual(report.summaryMessage(verbose: true), "Aligned 4 windows from 3 apps into a 2 by 2 grid")
    }

    func testStackedByAppMessages() {
        let report = AlignmentReport(appName: nil, mode: .grid, rows: 1, cols: 2,
                                     items: items(5), scope: .stackedByApp(appCount: 2))
        XCTAssertEqual(report.summaryMessage(verbose: true),
                       "Stacked 5 windows of 2 apps into a 2 by 1 grid, one stack per app")
        XCTAssertEqual(report.summaryMessage(verbose: false), "Stacked by app, 2 apps, 5 windows")
    }

    func testSingleAppDefaultScopeUnchanged() {
        let report = AlignmentReport(appName: "Safari", mode: .grid, rows: 2, cols: 2, items: items(4))
        XCTAssertEqual(report.scope, .singleApp)
        XCTAssertEqual(report.summaryMessage(verbose: true), "Aligned 4 windows of Safari into a 2 by 2 grid")
    }
}
