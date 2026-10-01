import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var hasShownOnce = false

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "AutoAlignPanels Settings")
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: SettingsRootView().environmentObject(PermissionModel.shared)
        )
        self.init(window: window)
        window.delegate = self
    }

    func show() {
        guard let window else { return }
        let wasVisible = window.isVisible
        NSApp.activate(ignoringOtherApps: true)
        if !hasShownOnce {
            window.center()
            hasShownOnce = true
        }
        window.makeKeyAndOrderFront(nil)
        if !wasVisible {
            PermissionModel.shared.uiDidAppear()
        }
    }

    func windowWillClose(_ notification: Notification) {
        PermissionModel.shared.uiDidDisappear()
    }
}
