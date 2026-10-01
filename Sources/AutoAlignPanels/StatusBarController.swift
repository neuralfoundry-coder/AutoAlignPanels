import Cocoa
import SwiftUI
import KeyboardShortcuts
import AutoAlignPanelsCore

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private let popover: NSPopover

    override init() {
        popover = NSPopover()
        popover.behavior = .transient
        super.init()

        let root = PopoverView(closePopover: { [weak self] in
            self?.popover.performClose(nil)
        })
        .environmentObject(PermissionModel.shared)
        let host = NSHostingController(rootView: root)
        // Content-driven popover height — no hardcoded size to keep in sync.
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.delegate = self

        setupStatusItem()
    }

    func setupStatusItem() {
        let hideMenuBar = UserDefaults.standard.bool(forKey: "hideMenuBar")
        if hideMenuBar {
            removeStatusItem()
            return
        }

        if statusItem != nil { return }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "rectangle.grid.2x2", accessibilityDescription: "AutoAlignPanels")
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = String(localized: "AutoAlignPanels — align the front app's windows")
        }
    }

    func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        // Capture the user's app BEFORE any of our UI can become frontmost.
        PopoverContext.shared.captureTargetApp()

        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            Diag.log.info("statusItem: right-click menu")
            showMenu()
        } else if UserDefaults.standard.bool(forKey: "statusItemLeftClickAligns") {
            // Opt-in single-click alignment for users who find chords hard.
            Diag.log.info("statusItem: left-click align, target=\(PopoverContext.shared.targetApp?.bundleIdentifier ?? "nil", privacy: .public)")
            WindowManager.shared.alignWithLastLayoutForFrontmostApp()
        } else {
            Diag.log.info("statusItem: popover")
            togglePopover()
        }
    }

    func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Right-click menu

    private func showMenu() {
        // Attach → click → detach: the supported way to give one status item
        // both a popover (left click) and a menu (right click).
        statusItem?.menu = buildMenu()
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(menuItem(String(localized: "Align Grid"), action: #selector(menuAlignGrid), shortcut: .alignWindows))
        menu.addItem(menuItem(String(localized: "Align Horizontally"), action: #selector(menuAlignHorizontal), shortcut: .alignHorizontal))
        menu.addItem(menuItem(String(localized: "Align Vertically"), action: #selector(menuAlignVertical), shortcut: .alignVertical))
        menu.addItem(menuItem(String(localized: "Maximize Stacked"), action: #selector(menuAlignMaximize), shortcut: .alignMaximize))
        menu.addItem(.separator())
        menu.addItem(menuItem(String(localized: "All Apps: Grid"), action: #selector(menuAllAppsGrid), shortcut: .alignAllAppsGrid))
        menu.addItem(menuItem(String(localized: "All Apps: Side by Side"), action: #selector(menuAllAppsHorizontal), shortcut: .alignAllAppsHorizontal))
        menu.addItem(menuItem(String(localized: "All Apps: Stacked Vertically"), action: #selector(menuAllAppsVertical), shortcut: .alignAllAppsVertical))
        menu.addItem(menuItem(String(localized: "All Apps: Stack by App"), action: #selector(menuStackByApp), shortcut: .alignStackedByApp))
        menu.addItem(.separator())
        let snapItem = NSMenuItem(title: String(localized: "Snap Window"), action: nil, keyEquivalent: "")
        snapItem.submenu = buildSnapMenu()
        menu.addItem(snapItem)
        menu.addItem(.separator())
        menu.addItem(menuItem(String(localized: "Restore Previous Arrangement"), action: #selector(menuRestore), shortcut: .restoreArrangement))
        menu.addItem(menuItem(String(localized: "Read Open Windows"), action: #selector(menuReadWindows), shortcut: .readOpenWindows))
        menu.addItem(.separator())
        let settings = menuItem(String(localized: "Settings…"), action: #selector(menuOpenSettings))
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(menuItem(String(localized: "Welcome Guide"), action: #selector(menuOpenWelcome)))
        menu.addItem(.separator())
        let quit = menuItem(String(localized: "Quit AutoAlignPanels"), action: #selector(menuQuit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)

        return menu
    }

    private func buildSnapMenu() -> NSMenu {
        let menu = NSMenu()
        // Blank lines between Magnet's groups: halves, quarters, thirds,
        // two-thirds, sixths, rows, then whole-screen actions.
        let groupStarts: Set<SnapPosition> = [.topLeftQuarter, .firstThird, .firstTwoThirds, .topLeftSixth, .row1Of4, .maximize]
        for position in SnapPosition.allCases {
            if groupStarts.contains(position) { menu.addItem(.separator()) }
            let item = menuItem(position.title(), action: #selector(menuSnap(_:)), shortcut: position.shortcutName)
            item.representedObject = position.rawValue
            menu.addItem(item)
        }
        menu.addItem(menuItem(String(localized: "Restore"), action: #selector(menuSnapRestore), shortcut: .snapRestore))
        menu.addItem(.separator())
        menu.addItem(menuItem(String(localized: "Next Display"), action: #selector(menuSnapNextDisplay), shortcut: .snapNextDisplay))
        menu.addItem(menuItem(String(localized: "Previous Display"), action: #selector(menuSnapPreviousDisplay), shortcut: .snapPreviousDisplay))
        return menu
    }

    private func menuItem(_ title: String, action: Selector, shortcut: KeyboardShortcuts.Name? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let shortcut {
            item.setShortcut(for: shortcut)
        }
        return item
    }

    @objc private func menuAlignGrid() { WindowManager.shared.alignWindows(of: nil, mode: .grid) }
    @objc private func menuAlignHorizontal() { WindowManager.shared.alignWindows(of: nil, mode: .horizontal) }
    @objc private func menuAlignVertical() { WindowManager.shared.alignWindows(of: nil, mode: .vertical) }
    @objc private func menuAlignMaximize() { WindowManager.shared.alignWindows(of: nil, mode: .maximize) }
    @objc private func menuAllAppsGrid() { WindowManager.shared.alignAllAppsWindows(mode: .grid) }
    @objc private func menuAllAppsHorizontal() { WindowManager.shared.alignAllAppsWindows(mode: .horizontal) }
    @objc private func menuAllAppsVertical() { WindowManager.shared.alignAllAppsWindows(mode: .vertical) }
    @objc private func menuStackByApp() { WindowManager.shared.alignStackedByApp() }
    @objc private func menuSnap(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let position = SnapPosition(rawValue: raw) else { return }
        WindowManager.shared.snapFocusedWindow(position)
    }
    @objc private func menuSnapRestore() { WindowManager.shared.restoreFocusedWindow() }
    @objc private func menuSnapNextDisplay() { WindowManager.shared.moveFocusedWindowToDisplay(offset: 1) }
    @objc private func menuSnapPreviousDisplay() { WindowManager.shared.moveFocusedWindowToDisplay(offset: -1) }
    @objc private func menuRestore() { WindowManager.shared.restorePreviousArrangement() }
    @objc private func menuReadWindows() { WindowManager.shared.readOpenWindows() }
    @objc private func menuOpenSettings() { SettingsWindowController.shared.show() }
    @objc private func menuOpenWelcome() { OnboardingWindowController.shared.show() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    // MARK: - NSPopoverDelegate

    func popoverWillShow(_ notification: Notification) {
        PermissionModel.shared.uiDidAppear()
    }

    func popoverDidClose(_ notification: Notification) {
        PermissionModel.shared.uiDidDisappear()
    }
}
