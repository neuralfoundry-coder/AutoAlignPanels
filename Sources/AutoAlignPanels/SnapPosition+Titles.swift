import Foundation
import AutoAlignPanelsCore

extension SnapPosition {
    /// Shown in Settings and the menu, and spoken after a snap. Thirds are
    /// named for the display's orientation ("Left Third" vs "Top Third").
    func title(portrait: Bool = false) -> String {
        switch self {
        case .leftHalf: return String(localized: "Left Half")
        case .rightHalf: return String(localized: "Right Half")
        case .topHalf: return String(localized: "Top Half")
        case .bottomHalf: return String(localized: "Bottom Half")
        case .topLeftQuarter: return String(localized: "Top Left Quarter")
        case .topRightQuarter: return String(localized: "Top Right Quarter")
        case .bottomLeftQuarter: return String(localized: "Bottom Left Quarter")
        case .bottomRightQuarter: return String(localized: "Bottom Right Quarter")
        case .firstThird: return portrait ? String(localized: "Top Third") : String(localized: "Left Third")
        case .centerThird: return String(localized: "Center Third")
        case .lastThird: return portrait ? String(localized: "Bottom Third") : String(localized: "Right Third")
        case .firstTwoThirds: return portrait ? String(localized: "Top Two Thirds") : String(localized: "Left Two Thirds")
        case .centerTwoThirds: return String(localized: "Center Two Thirds")
        case .lastTwoThirds: return portrait ? String(localized: "Bottom Two Thirds") : String(localized: "Right Two Thirds")
        case .topLeftSixth: return String(localized: "Top Left Sixth")
        case .topCenterSixth: return String(localized: "Top Center Sixth")
        case .topRightSixth: return String(localized: "Top Right Sixth")
        case .bottomLeftSixth: return String(localized: "Bottom Left Sixth")
        case .bottomCenterSixth: return String(localized: "Bottom Center Sixth")
        case .bottomRightSixth: return String(localized: "Bottom Right Sixth")
        case .row1Of4: return String(localized: "Row 1 of 4")
        case .row2Of4: return String(localized: "Row 2 of 4")
        case .row3Of4: return String(localized: "Row 3 of 4")
        case .row4Of4: return String(localized: "Row 4 of 4")
        case .maximize: return String(localized: "Maximize")
        case .center: return String(localized: "Center")
        }
    }
}
