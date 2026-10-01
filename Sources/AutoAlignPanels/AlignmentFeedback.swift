import AppKit
import AutoAlignPanelsCore

/// Single sink for user feedback: every outcome flows through here and fans
/// out to the visual HUD, the sound cue, and the VoiceOver announcement, so
/// sighted, low-vision, and blind users all get consistent confirmation.
@MainActor
final class AlignmentFeedbackCenter {
    static let shared = AlignmentFeedbackCenter()

    struct HUDContent {
        enum Style {
            case success(symbolName: String)
            case warning(symbolName: String)
            case error
            case info(symbolName: String)
        }

        let style: Style
        let primary: String
        let secondary: String?
        /// Screen the HUD should appear on; nil = screen with mouse/default.
        let screen: NSScreen?
    }

    /// Registered by the HUD controller at startup; nil (early in launch, or
    /// in tests) simply skips visual feedback.
    var hudPresenter: ((HUDContent) -> Void)?

    func alignment(_ report: AlignmentReport, screen: NSScreen?) {
        let verbose = UserDefaults.standard.object(forKey: AccessibilityPrefs.voiceOverVerboseKey) as? Bool ?? false
        AccessibilityHelper.playFeedback(tone: report.tone, mode: report.mode)
        AccessibilityHelper.announce(report.summaryMessage(verbose: verbose))
        hudPresenter?(hudContent(for: report, screen: screen))
    }

    func failure(_ message: String, screen: NSScreen? = nil) {
        AccessibilityHelper.playErrorSound()
        AccessibilityHelper.announce(message)
        hudPresenter?(HUDContent(style: .error, primary: message, secondary: nil, screen: screen))
    }

    /// Informational outcome — announced and shown, but not an error and not
    /// a completed action, so no sound.
    func notice(_ message: String, symbolName: String = "info.circle", screen: NSScreen? = nil) {
        AccessibilityHelper.announce(message)
        hudPresenter?(HUDContent(style: .info(symbolName: symbolName), primary: message, secondary: nil, screen: screen))
    }

    func restored(count: Int) {
        AccessibilityHelper.playRestoreSound()
        let announcement = count == 1
            ? String(localized: "Restored previous arrangement, 1 window")
            : String(localized: "Restored previous arrangement, \(count) windows")
        AccessibilityHelper.announce(announcement)
        hudPresenter?(HUDContent(style: .success(symbolName: "arrow.uturn.backward"),
                                 primary: String(localized: "Restored"),
                                 secondary: windowCountPhrase(count),
                                 screen: nil))
    }

    func read(message: String, count: Int, appName: String) {
        AccessibilityHelper.announce(message)
        hudPresenter?(HUDContent(style: .info(symbolName: "waveform"),
                                 primary: windowCountPhrase(count),
                                 secondary: appName,
                                 screen: nil))
    }

    /// Focus changes are frequent and self-evident on screen; they speak but
    /// never flash the HUD.
    func announceOnly(_ message: String) {
        AccessibilityHelper.announce(message)
    }

    private func windowCountPhrase(_ count: Int) -> String {
        count == 1 ? String(localized: "1 window") : String(localized: "\(count) windows")
    }

    private func hudContent(for report: AlignmentReport, screen: NSScreen?) -> HUDContent {
        let symbol: String
        if case .stackedByApp = report.scope {
            symbol = "square.stack.3d.up"
        } else {
            symbol = report.mode.symbolName
        }

        var secondary: String
        switch report.mode {
        case .grid: secondary = String(localized: "\(report.cols)×\(report.rows) grid")
        case .horizontal: secondary = String(localized: "Side by side")
        case .vertical: secondary = String(localized: "Stacked vertically")
        case .maximize: secondary = String(localized: "Maximized")
        }
        switch report.scope {
        case .singleApp:
            if let appName = report.appName {
                secondary += " · \(appName)"
            }
        case .allApps(let apps):
            secondary += " · " + String(localized: "\(apps) apps")
        case .stackedByApp(let apps):
            secondary = String(localized: "Stacked by app") + " · " + String(localized: "\(apps) apps")
        }

        switch report.tone {
        case .success:
            return HUDContent(style: .success(symbolName: symbol),
                              primary: windowCountPhrase(report.alignedCount),
                              secondary: secondary, screen: screen)
        case .partial:
            return HUDContent(style: .warning(symbolName: symbol),
                              primary: String(localized: "Aligned \(report.alignedCount) of \(report.items.count)"),
                              secondary: secondary, screen: screen)
        case .failure:
            return HUDContent(style: .error,
                              primary: String(localized: "Could not align windows"),
                              secondary: report.appName, screen: screen)
        }
    }
}

extension AlignmentMode {
    var symbolName: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .horizontal: return "rectangle.split.3x1"
        case .vertical: return "rectangle.split.1x2"
        case .maximize: return "square.stack"
        }
    }
}
