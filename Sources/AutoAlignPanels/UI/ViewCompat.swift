import SwiftUI

extension View {
    /// The single-parameter `onChange(of:perform:)` is deprecated in the
    /// macOS 14 SDK, but the two-parameter form doesn't exist on macOS 13 —
    /// deployment target 13.0 needs this shim.
    @ViewBuilder
    func onChangeCompat<V: Equatable>(of value: V, perform: @escaping (V) -> Void) -> some View {
        if #available(macOS 14.0, *) {
            onChange(of: value) { _, newValue in perform(newValue) }
        } else {
            onChange(of: value, perform: perform)
        }
    }
}

/// nil (no animation) when the user prefers reduced motion.
func appAnimation(_ base: Animation = .easeOut(duration: 0.2)) -> Animation? {
    AccessibilityHelper.shouldReduceMotion ? nil : base
}
