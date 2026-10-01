import Foundation

public enum AlignmentMode: Sendable, Equatable, CaseIterable {
    case grid
    case horizontal
    case vertical
    /// Every window full size, stacked — legibility for low-vision users who
    /// switch between windows with the slot/arrow shortcuts.
    case maximize
}

public extension AlignmentMode {
    var persistedValue: String {
        switch self {
        case .grid: return "grid"
        case .horizontal: return "horizontal"
        case .vertical: return "vertical"
        case .maximize: return "maximize"
        }
    }

    init?(persistedValue: String) {
        switch persistedValue {
        case "grid": self = .grid
        case "horizontal": self = .horizontal
        case "vertical": self = .vertical
        case "maximize": self = .maximize
        default: return nil
        }
    }
}

/// Direction for moving keyboard focus between aligned windows.
public enum FocusDirection: Sendable, Equatable, CaseIterable {
    case left, right, up, down
}
