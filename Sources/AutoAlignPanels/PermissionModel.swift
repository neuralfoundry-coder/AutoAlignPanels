import AppKit
import Combine

/// Reactive Accessibility-trust state. `AXIsProcessTrusted()` has no direct
/// change callback, so while any of our UI is visible we poll once a second
/// (and listen for the public distributed notification as a fast path), and
/// the permission banner disappears the moment the user grants access.
@MainActor
final class PermissionModel: ObservableObject {
    static let shared = PermissionModel()

    @Published private(set) var isTrusted = AccessibilityHelper.isTrusted

    /// Fired once when trust flips from false to true while running — the
    /// moment to relaunch so the grant actually takes effect in-process.
    var onTrustGranted: (() -> Void)?

    private var timer: Timer?
    private var visibleUICount = 0
    private var monitorUntilTrustedActive = false
    private var notificationObserver: NSObjectProtocol?

    private init() {
        notificationObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { _ in
            // The notification fires slightly before AXIsProcessTrusted flips.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                PermissionModel.shared.refresh()
            }
        }
    }

    /// Call when a popover/window that shows permission state appears.
    func uiDidAppear() {
        visibleUICount += 1
        refresh()
        startTimerIfNeeded()
    }

    /// Call when that UI disappears; polling stops when nothing is visible.
    func uiDidDisappear() {
        visibleUICount = max(0, visibleUICount - 1)
        if visibleUICount == 0 && !monitorUntilTrustedActive {
            timer?.invalidate()
            timer = nil
        }
    }

    /// Keeps polling until trust is granted, independent of UI visibility —
    /// used when the app launched untrusted, so the grant is noticed even if
    /// the user goes straight to System Settings without our windows open.
    func monitorUntilTrusted() {
        guard !isTrusted else { return }
        monitorUntilTrustedActive = true
        startTimerIfNeeded()
    }

    func refresh() {
        let now = AccessibilityHelper.isTrusted
        if now != isTrusted {
            isTrusted = now
            if now {
                monitorUntilTrustedActive = false
                if visibleUICount == 0 {
                    timer?.invalidate()
                    timer = nil
                }
                onTrustGranted?()
            }
        }
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        // .common mode so the poll keeps firing during slider drags and menu
        // tracking, which run nested event-tracking run loops.
        let pollTimer = Timer(timeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                PermissionModel.shared.refresh()
            }
        }
        RunLoop.main.add(pollTimer, forMode: .common)
        timer = pollTimer
    }
}

/// Observes system-level accessibility preferences (Reduce Motion, Increase
/// Contrast, etc.) so the UI can adapt at runtime — the user does not need to
/// quit and relaunch the app after changing System Settings.
final class SystemAccessibilityObserver: ObservableObject {
    @Published var increaseContrast: Bool = AccessibilityHelper.shouldIncreaseContrast
    @Published var reduceMotion: Bool = AccessibilityHelper.shouldReduceMotion
    @Published var differentiateWithoutColor: Bool = AccessibilityHelper.shouldDifferentiateWithoutColor

    private var observers: [NSObjectProtocol] = []

    init() {
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.increaseContrast = AccessibilityHelper.shouldIncreaseContrast
            self.reduceMotion = AccessibilityHelper.shouldReduceMotion
            self.differentiateWithoutColor = AccessibilityHelper.shouldDifferentiateWithoutColor
        })
    }

    deinit {
        let nc = NSWorkspace.shared.notificationCenter
        for o in observers { nc.removeObserver(o) }
    }
}
