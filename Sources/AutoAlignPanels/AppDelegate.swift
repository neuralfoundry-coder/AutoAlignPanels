import Cocoa
import KeyboardShortcuts
import AutoAlignPanelsCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Latest launched copy wins: an older version still running after a
        // reinstall would hold the same hotkeys.
        InstallManager.terminateOtherInstances()
        Diag.log.info("launch: trusted=\(AccessibilityHelper.isTrusted, privacy: .public) axHealthy=\(AccessibilityHelper.axSessionHealthy(), privacy: .public) path=\(Bundle.main.bundlePath, privacy: .public)")

        statusBarController = StatusBarController()
        AlignmentHUDController.shared.install()

        migrateFocusArrowShortcutsIfNeeded()

        // Layout shortcuts
        KeyboardShortcuts.onKeyUp(for: .alignWindows) {
            WindowManager.shared.alignFrontmostAppWindows(mode: .grid)
        }
        KeyboardShortcuts.onKeyUp(for: .alignHorizontal) {
            WindowManager.shared.alignFrontmostAppWindows(mode: .horizontal)
        }
        KeyboardShortcuts.onKeyUp(for: .alignVertical) {
            WindowManager.shared.alignFrontmostAppWindows(mode: .vertical)
        }
        KeyboardShortcuts.onKeyUp(for: .alignMaximize) {
            WindowManager.shared.alignFrontmostAppWindows(mode: .maximize)
        }
        KeyboardShortcuts.onKeyUp(for: .alignLastLayout) {
            WindowManager.shared.alignWithLastLayoutForFrontmostApp()
        }
        KeyboardShortcuts.onKeyUp(for: .restoreArrangement) {
            WindowManager.shared.restorePreviousArrangement()
        }
        KeyboardShortcuts.onKeyUp(for: .moveToNextDisplay) {
            WindowManager.shared.moveFrontmostAppToNextDisplay()
        }

        // All-apps shortcuts (mixed apps on the working screen)
        KeyboardShortcuts.onKeyUp(for: .alignAllAppsGrid) {
            WindowManager.shared.alignAllAppsWindows(mode: .grid)
        }
        KeyboardShortcuts.onKeyUp(for: .alignAllAppsHorizontal) {
            WindowManager.shared.alignAllAppsWindows(mode: .horizontal)
        }
        KeyboardShortcuts.onKeyUp(for: .alignAllAppsVertical) {
            WindowManager.shared.alignAllAppsWindows(mode: .vertical)
        }
        KeyboardShortcuts.onKeyUp(for: .alignStackedByApp) {
            WindowManager.shared.alignStackedByApp()
        }

        // Snap the focused window (Magnet-style)
        for position in SnapPosition.allCases {
            KeyboardShortcuts.onKeyUp(for: position.shortcutName) {
                WindowManager.shared.snapFocusedWindow(position)
            }
        }
        KeyboardShortcuts.onKeyUp(for: .snapRestore) {
            WindowManager.shared.restoreFocusedWindow()
        }
        KeyboardShortcuts.onKeyUp(for: .snapNextDisplay) {
            WindowManager.shared.moveFocusedWindowToDisplay(offset: 1)
        }
        KeyboardShortcuts.onKeyUp(for: .snapPreviousDisplay) {
            WindowManager.shared.moveFocusedWindowToDisplay(offset: -1)
        }

        // Accessibility shortcuts — for users with vision, motor, or
        // cognitive needs, as described in the accessibility usage description.
        KeyboardShortcuts.onKeyUp(for: .readOpenWindows) {
            WindowManager.shared.readOpenWindows()
        }
        KeyboardShortcuts.onKeyUp(for: .announcePosition) {
            WindowManager.shared.announceFocusedWindowPosition()
        }
        KeyboardShortcuts.onKeyUp(for: .focusSlot1) {
            WindowManager.shared.focusSlot(1)
        }
        KeyboardShortcuts.onKeyUp(for: .focusSlot2) {
            WindowManager.shared.focusSlot(2)
        }
        KeyboardShortcuts.onKeyUp(for: .focusSlot3) {
            WindowManager.shared.focusSlot(3)
        }
        KeyboardShortcuts.onKeyUp(for: .focusSlot4) {
            WindowManager.shared.focusSlot(4)
        }
        KeyboardShortcuts.onKeyUp(for: .focusLeft) {
            WindowManager.shared.focusAdjacentWindow(.left)
        }
        KeyboardShortcuts.onKeyUp(for: .focusRight) {
            WindowManager.shared.focusAdjacentWindow(.right)
        }
        KeyboardShortcuts.onKeyUp(for: .focusUp) {
            WindowManager.shared.focusAdjacentWindow(.up)
        }
        KeyboardShortcuts.onKeyUp(for: .focusDown) {
            WindowManager.shared.focusAdjacentWindow(.down)
        }

        let safeLocation = offerInstallIfRunningFromDiskImage()
        if safeLocation {
            // A reinstalled build can inherit a dead permission entry from
            // the previous one; reset it so the prompt below starts clean.
            InstallManager.resetStalePermissionIfNeeded()
            registerInAccessibilityListIfNeeded()
        }
        if !AccessibilityHelper.isTrusted {
            // A grant only takes effect in a fresh process: watch for it and
            // relaunch the moment the user flips the toggle in System Settings.
            PermissionModel.shared.onTrustGranted = {
                AccessibilityHelper.relaunchToApplyPermission()
            }
            PermissionModel.shared.monitorUntilTrusted()
        }
        maybeShowOnboarding()
    }

    /// macOS only adds an app to System Settings → Privacy & Security →
    /// Accessibility when the AX API is called with the prompt option, so
    /// fire it on EVERY untrusted launch — that guarantees the app is in the
    /// list whenever the user goes looking (even after a TCC reset). This
    /// does not nag: the system dialog only appears while NO TCC entry
    /// exists; once the entry is there (granted or not), the call is silent.
    private func registerInAccessibilityListIfNeeded() {
        guard !AccessibilityHelper.isTrusted else { return }
        AccessibilityHelper.checkAndPrompt()
    }

    /// Running from the mounted DMG (or Gatekeeper's app-translocation copy)
    /// binds the TCC accessibility entry to a throwaway path, so the grant
    /// silently fails to stick. Offer to install into /Applications —
    /// replacing any older copy — and relaunch from there before any
    /// permission is requested. Returns false when the app keeps running
    /// from such a location.
    private func offerInstallIfRunningFromDiskImage() -> Bool {
        guard InstallManager.isRunningFromDiskImage else { return true }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = String(localized: "Install AutoAlignPanels before granting permissions")
        alert.informativeText = String(localized: "AutoAlignPanels will be copied to the Applications folder, replacing any previous version, and reopened from there. macOS cannot remember Accessibility permission for an app running from a disk image.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Install and Reopen"))
        alert.addButton(withTitle: String(localized: "Quit"))
        alert.addButton(withTitle: String(localized: "Continue Anyway"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if InstallManager.installToApplicationsAndRelaunch() { return false }
            let failure = NSAlert()
            failure.messageText = String(localized: "Could not install automatically")
            failure.informativeText = String(localized: "Drag AutoAlignPanels to the Applications folder and open it from there. macOS cannot remember Accessibility permission for an app running from a disk image or a translocated location.")
            failure.addButton(withTitle: String(localized: "Quit"))
            failure.runModal()
            NSApp.terminate(nil)
        case .alertSecondButtonReturn:
            NSApp.terminate(nil)
        default:
            break
        }
        return false
    }

    /// 0.1.0 put focus navigation on ⌃⌥+arrows; since 0.1.1 those keys snap
    /// the window to a half (Magnet's layout) and focus moved to ⌃⇧+arrows.
    /// KeyboardShortcuts persists defaults on first registration, so an
    /// upgraded install would keep the old keys and collide with the snaps.
    /// Move them only if they still hold the untouched 0.1.0 default.
    private func migrateFocusArrowShortcutsIfNeeded() {
        let marker = "didMigrateFocusArrowsToControlShift"
        guard !UserDefaults.standard.bool(forKey: marker) else { return }
        UserDefaults.standard.set(true, forKey: marker)
        let legacy: [(KeyboardShortcuts.Name, KeyboardShortcuts.Key)] = [
            (.focusLeft, .leftArrow), (.focusRight, .rightArrow), (.focusUp, .upArrow), (.focusDown, .downArrow),
        ]
        for (name, key) in legacy
        where KeyboardShortcuts.getShortcut(for: name) == KeyboardShortcuts.Shortcut(key, modifiers: [.control, .option]) {
            KeyboardShortcuts.reset(name)
        }
    }

    /// The app is an LSUIElement and launches invisibly, and it is useless
    /// without Accessibility permission — so EVERY untrusted launch offers
    /// the registration walkthrough, not just the first.
    private func maybeShowOnboarding() {
        if AccessibilityHelper.isTrusted {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            return
        }
        OnboardingWindowController.shared.show()
    }

    /// Recovery path for hidden-menu-bar-icon mode: opening the app from
    /// Launchpad/Finder while it runs restores the icon. Without this, hiding
    /// the icon was a permanent lockout for an accessory app.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if UserDefaults.standard.bool(forKey: "hideMenuBar") {
            UserDefaults.standard.set(false, forKey: "hideMenuBar")
            statusBarController?.setupStatusItem()
            SettingsWindowController.shared.show()
        }
        return true
    }
}
