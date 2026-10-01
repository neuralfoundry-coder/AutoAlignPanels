import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    static let shared = OnboardingWindowController()

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Welcome to AutoAlignPanels")
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: OnboardingView().environmentObject(PermissionModel.shared)
        )
        self.init(window: window)
        window.delegate = self
    }

    func show() {
        guard let window else { return }
        let wasVisible = window.isVisible
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        if !wasVisible {
            PermissionModel.shared.uiDidAppear()
        }
    }

    func dismiss() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        PermissionModel.shared.uiDidDisappear()
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
    }
}
