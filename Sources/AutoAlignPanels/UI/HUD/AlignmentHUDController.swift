import AppKit
import SwiftUI

/// Volume-HUD-style transient overlay: non-activating, click-through, shown
/// on the screen that was just aligned, auto-dismissing. Visual counterpart
/// to the sound cues and VoiceOver announcements.
@MainActor
final class AlignmentHUDController {
    static let shared = AlignmentHUDController()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<AlignmentHUDView>?
    private var dismissTimer: Timer?
    /// Bumped on every show; stale dismiss timers and fade-out completions
    /// compare against it so an in-flight fade-out can't hide fresh content.
    private var generation = 0

    func install() {
        AlignmentFeedbackCenter.shared.hudPresenter = { [weak self] content in
            self?.show(content)
        }
    }

    private func makePanelIfNeeded() -> (NSPanel, NSHostingView<AlignmentHUDView>) {
        if let panel, let hostingView {
            return (panel, hostingView)
        }
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false

        let hosting = NSHostingView(rootView: AlignmentHUDView(content: nil))
        panel.contentView = hosting

        self.panel = panel
        self.hostingView = hosting
        return (panel, hosting)
    }

    private func show(_ content: AlignmentFeedbackCenter.HUDContent) {
        let (panel, hosting) = makePanelIfNeeded()
        hosting.rootView = AlignmentHUDView(content: content)
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize

        guard let screen = content.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 140)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)

        generation += 1
        let currentGeneration = generation
        dismissTimer?.invalidate()

        // Always retarget through the animator: a new animation on the same
        // property replaces any in-flight fade-out, where a direct property
        // set would be clobbered by its remaining ticks.
        let alreadyVisible = panel.isVisible && panel.alphaValue > 0.01
        if !alreadyVisible {
            panel.alphaValue = 0
        }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = (AccessibilityHelper.shouldReduceMotion || alreadyVisible) ? 0 : 0.15
            panel.animator().alphaValue = 1
        }

        // .common mode so the auto-dismiss still fires during menu tracking
        // and slider drags (nested event-tracking run loops).
        let timer = Timer(timeInterval: 1.4, repeats: false) { _ in
            Task { @MainActor in
                AlignmentHUDController.shared.dismiss(ifGeneration: currentGeneration)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        dismissTimer = timer
    }

    private func dismiss(ifGeneration expected: Int) {
        guard expected == generation, let panel else { return }
        if AccessibilityHelper.shouldReduceMotion {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.35
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                // Only hide if no newer HUD was shown while fading out.
                let controller = AlignmentHUDController.shared
                if expected == controller.generation, let panel = controller.panel {
                    panel.orderOut(nil)
                }
            }
        })
    }
}
