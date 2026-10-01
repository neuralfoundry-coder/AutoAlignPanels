import AppKit

/// Remembers which app the user was actually working in before our own UI
/// (popover / status-bar menu) became frontmost, so "Align Now" from the
/// popover aligns that app instead of AutoAlignPanels itself.
@MainActor
final class PopoverContext {
    static let shared = PopoverContext()

    private(set) var targetApp: NSRunningApplication?

    /// Call at status-item click time, before showing any of our UI.
    func captureTargetApp() {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return }
        targetApp = front
    }
}
