import KeyboardShortcuts
import AutoAlignPanelsCore

extension KeyboardShortcuts.Name {
    // Layout shortcuts
    static let alignWindows = Self(
        "alignWindows",
        default: .init(.p, modifiers: [.shift, .control])
    )
    static let alignHorizontal = Self(
        "alignHorizontal",
        default: .init(.h, modifiers: [.shift, .control])
    )
    static let alignVertical = Self(
        "alignVertical",
        default: .init(.v, modifiers: [.shift, .control])
    )
    static let alignMaximize = Self(
        "alignMaximize",
        default: .init(.f, modifiers: [.shift, .control])
    )
    static let alignLastLayout = Self(
        "alignLastLayout",
        default: .init(.l, modifiers: [.shift, .control])
    )
    static let restoreArrangement = Self(
        "restoreArrangement",
        default: .init(.z, modifiers: [.shift, .control])
    )
    static let moveToNextDisplay = Self(
        "moveToNextDisplay",
        default: .init(.d, modifiers: [.shift, .control])
    )

    // All-apps shortcuts: windows of every visible app on the working
    // screen, not just the frontmost app. ⌃⌥ is avoided on purpose — it is
    // the VoiceOver modifier.
    static let alignAllAppsGrid = Self(
        "alignAllAppsGrid",
        default: .init(.p, modifiers: [.shift, .control, .command])
    )
    static let alignAllAppsHorizontal = Self(
        "alignAllAppsHorizontal",
        default: .init(.h, modifiers: [.shift, .control, .command])
    )
    static let alignAllAppsVertical = Self(
        "alignAllAppsVertical",
        default: .init(.v, modifiers: [.shift, .control, .command])
    )
    static let alignStackedByApp = Self(
        "alignStackedByApp",
        default: .init(.s, modifiers: [.shift, .control])
    )

    // Accessibility shortcuts
    static let readOpenWindows = Self(
        "readOpenWindows",
        default: .init(.r, modifiers: [.shift, .control])
    )
    static let announcePosition = Self(
        "announcePosition",
        default: .init(.w, modifiers: [.shift, .control])
    )
    static let focusSlot1 = Self(
        "focusSlot1",
        default: .init(.one, modifiers: [.option, .control])
    )
    static let focusSlot2 = Self(
        "focusSlot2",
        default: .init(.two, modifiers: [.option, .control])
    )
    static let focusSlot3 = Self(
        "focusSlot3",
        default: .init(.three, modifiers: [.option, .control])
    )
    static let focusSlot4 = Self(
        "focusSlot4",
        default: .init(.four, modifiers: [.option, .control])
    )
    static let focusLeft = Self(
        "focusLeft",
        default: .init(.leftArrow, modifiers: [.shift, .control])
    )
    static let focusRight = Self(
        "focusRight",
        default: .init(.rightArrow, modifiers: [.shift, .control])
    )
    static let focusUp = Self(
        "focusUp",
        default: .init(.upArrow, modifiers: [.shift, .control])
    )
    static let focusDown = Self(
        "focusDown",
        default: .init(.downArrow, modifiers: [.shift, .control])
    )

    // Snap the focused window (Magnet-compatible defaults, so switching
    // from Magnet needs no relearning). ⌃⌥ is also the VoiceOver modifier;
    // VoiceOver users can remap these in Settings → Shortcuts.
    static let snapLeftHalf = Self(
        "snapLeftHalf",
        default: .init(.leftArrow, modifiers: [.control, .option])
    )
    static let snapRightHalf = Self(
        "snapRightHalf",
        default: .init(.rightArrow, modifiers: [.control, .option])
    )
    static let snapTopHalf = Self(
        "snapTopHalf",
        default: .init(.upArrow, modifiers: [.control, .option])
    )
    static let snapBottomHalf = Self(
        "snapBottomHalf",
        default: .init(.downArrow, modifiers: [.control, .option])
    )
    static let snapTopLeftQuarter = Self(
        "snapTopLeftQuarter",
        default: .init(.u, modifiers: [.control, .option])
    )
    static let snapTopRightQuarter = Self(
        "snapTopRightQuarter",
        default: .init(.i, modifiers: [.control, .option])
    )
    static let snapBottomLeftQuarter = Self(
        "snapBottomLeftQuarter",
        default: .init(.j, modifiers: [.control, .option])
    )
    static let snapBottomRightQuarter = Self(
        "snapBottomRightQuarter",
        default: .init(.k, modifiers: [.control, .option])
    )
    static let snapFirstThird = Self(
        "snapFirstThird",
        default: .init(.d, modifiers: [.control, .option])
    )
    static let snapCenterThird = Self(
        "snapCenterThird",
        default: .init(.f, modifiers: [.control, .option])
    )
    static let snapLastThird = Self(
        "snapLastThird",
        default: .init(.g, modifiers: [.control, .option])
    )
    static let snapFirstTwoThirds = Self(
        "snapFirstTwoThirds",
        default: .init(.e, modifiers: [.control, .option])
    )
    static let snapCenterTwoThirds = Self(
        "snapCenterTwoThirds",
        default: .init(.r, modifiers: [.control, .option])
    )
    static let snapLastTwoThirds = Self(
        "snapLastTwoThirds",
        default: .init(.t, modifiers: [.control, .option])
    )
    static let snapTopLeftSixth = Self(
        "snapTopLeftSixth",
        default: .init(.u, modifiers: [.control, .option, .command])
    )
    static let snapTopCenterSixth = Self(
        "snapTopCenterSixth",
        default: .init(.i, modifiers: [.control, .option, .command])
    )
    static let snapTopRightSixth = Self(
        "snapTopRightSixth",
        default: .init(.o, modifiers: [.control, .option, .command])
    )
    static let snapBottomLeftSixth = Self(
        "snapBottomLeftSixth",
        default: .init(.j, modifiers: [.control, .option, .command])
    )
    static let snapBottomCenterSixth = Self(
        "snapBottomCenterSixth",
        default: .init(.k, modifiers: [.control, .option, .command])
    )
    static let snapBottomRightSixth = Self(
        "snapBottomRightSixth",
        default: .init(.l, modifiers: [.control, .option, .command])
    )
    static let snapRow1Of4 = Self(
        "snapRow1Of4",
        default: .init(.one, modifiers: [.control, .option, .command])
    )
    static let snapRow2Of4 = Self(
        "snapRow2Of4",
        default: .init(.two, modifiers: [.control, .option, .command])
    )
    static let snapRow3Of4 = Self(
        "snapRow3Of4",
        default: .init(.three, modifiers: [.control, .option, .command])
    )
    static let snapRow4Of4 = Self(
        "snapRow4Of4",
        default: .init(.four, modifiers: [.control, .option, .command])
    )
    static let snapMaximize = Self(
        "snapMaximize",
        default: .init(.return, modifiers: [.control, .option])
    )
    static let snapCenter = Self(
        "snapCenter",
        default: .init(.c, modifiers: [.control, .option])
    )
    static let snapRestore = Self(
        "snapRestore",
        default: .init(.delete, modifiers: [.control, .option])
    )
    static let snapNextDisplay = Self(
        "snapNextDisplay",
        default: .init(.rightArrow, modifiers: [.control, .option, .command])
    )
    static let snapPreviousDisplay = Self(
        "snapPreviousDisplay",
        default: .init(.leftArrow, modifiers: [.control, .option, .command])
    )
}

extension SnapPosition {
    var shortcutName: KeyboardShortcuts.Name {
        switch self {
        case .leftHalf: return .snapLeftHalf
        case .rightHalf: return .snapRightHalf
        case .topHalf: return .snapTopHalf
        case .bottomHalf: return .snapBottomHalf
        case .topLeftQuarter: return .snapTopLeftQuarter
        case .topRightQuarter: return .snapTopRightQuarter
        case .bottomLeftQuarter: return .snapBottomLeftQuarter
        case .bottomRightQuarter: return .snapBottomRightQuarter
        case .firstThird: return .snapFirstThird
        case .centerThird: return .snapCenterThird
        case .lastThird: return .snapLastThird
        case .firstTwoThirds: return .snapFirstTwoThirds
        case .centerTwoThirds: return .snapCenterTwoThirds
        case .lastTwoThirds: return .snapLastTwoThirds
        case .topLeftSixth: return .snapTopLeftSixth
        case .topCenterSixth: return .snapTopCenterSixth
        case .topRightSixth: return .snapTopRightSixth
        case .bottomLeftSixth: return .snapBottomLeftSixth
        case .bottomCenterSixth: return .snapBottomCenterSixth
        case .bottomRightSixth: return .snapBottomRightSixth
        case .row1Of4: return .snapRow1Of4
        case .row2Of4: return .snapRow2Of4
        case .row3Of4: return .snapRow3Of4
        case .row4Of4: return .snapRow4Of4
        case .maximize: return .snapMaximize
        case .center: return .snapCenter
        }
    }
}
