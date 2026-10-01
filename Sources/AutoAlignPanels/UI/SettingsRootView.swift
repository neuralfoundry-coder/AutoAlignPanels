import SwiftUI
import KeyboardShortcuts
import ServiceManagement
import AutoAlignPanelsCore

struct SettingsRootView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            ShortcutsSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "command") }
            AccessibilitySettingsView()
                .tabItem { Label("Accessibility", systemImage: "figure.roll") }
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 560)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @AppStorage("windowGap") private var windowGap: Double = 8
    @AppStorage("windowMargin") private var windowMargin: Double = 0
    @AppStorage("maxWindowsToAlign") private var maxWindowsToAlign: Int = 9
    @AppStorage("hideMenuBar") private var hideMenuBar: Bool = false
    @AppStorage("statusItemLeftClickAligns") private var leftClickAligns: Bool = false

    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?
    @State private var isRevertingLaunchAtLogin = false
    @State private var confirmHideIcon = false

    var body: some View {
        Form {
            Section("Layout") {
                sliderRow("Window gap", value: $windowGap,
                          accessibilityLabel: "Window gap in points")
                sliderRow("Screen edge margin", value: $windowMargin,
                          accessibilityLabel: "Screen edge margin in points")
                VStack(alignment: .leading, spacing: 4) {
                    Stepper(value: $maxWindowsToAlign, in: 0...30) {
                        Text(maxWindowsToAlign == 0
                             ? "Align at most: no limit"
                             : "Align at most: \(maxWindowsToAlign) windows")
                    }
                    .accessibilityLabel("Maximum windows to align")
                    Text("Extra windows stay where they are, and the announcement says so. 0 means no limit.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Menu bar") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Left click aligns immediately", isOn: $leftClickAligns)
                    Text("One click on the menu bar icon applies the app's last layout — no chord needed. Right-click still opens the menu.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    // The persisted value is written only in the alert's Hide
                    // action — flipping the toggle must not hide the icon on
                    // the next launch when the user never confirmed (or quit
                    // with the alert still open).
                    Toggle("Hide menu bar icon", isOn: Binding(
                        get: { hideMenuBar },
                        set: { newValue in
                            if newValue {
                                confirmHideIcon = true
                            } else {
                                hideMenuBar = false
                                statusBarController?.setupStatusItem()
                            }
                        }
                    ))
                    if hideMenuBar {
                        Text("To show the icon again, open AutoAlignPanels from Launchpad or Finder while it's running.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .alert("Hide the menu bar icon?", isPresented: $confirmHideIcon) {
                    Button("Hide") {
                        hideMenuBar = true
                        statusBarController?.removeStatusItem()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("The keyboard shortcuts keep working. To bring the icon back, open AutoAlignPanels from Launchpad or Finder while it's running.")
                }
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChangeCompat(of: launchAtLogin) { newValue in
                        // The failure path reverts this same @State, which
                        // re-fires onChange — the guard keeps the revert from
                        // issuing a second, opposite SMAppService call that
                        // would overwrite the original error message.
                        guard !isRevertingLaunchAtLogin else {
                            isRevertingLaunchAtLogin = false
                            return
                        }
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                            launchAtLoginError = nil
                        } catch {
                            launchAtLoginError = error.localizedDescription
                            let actual = SMAppService.mainApp.status == .enabled
                            if actual != newValue {
                                isRevertingLaunchAtLogin = true
                                launchAtLogin = actual
                            }
                        }
                    }
                if let launchAtLoginError {
                    Label(launchAtLoginError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
    }

    private var statusBarController: StatusBarController? {
        (NSApp.delegate as? AppDelegate)?.statusBarController
    }

    private func sliderRow(_ title: LocalizedStringKey, value: Binding<Double>, accessibilityLabel: LocalizedStringKey) -> some View {
        HStack(spacing: 8) {
            Text(title)
            Slider(value: value, in: 0...64, step: 1)
                .accessibilityLabel(Text(accessibilityLabel))
            Text("\(Int(value.wrappedValue)) pt")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }
}

// MARK: - Shortcuts

struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            Section("Layout") {
                shortcutRow("Grid layout", name: .alignWindows,
                            hint: "Arranges windows of the frontmost app into a grid.")
                shortcutRow("Horizontal layout", name: .alignHorizontal,
                            hint: "Lines windows side by side in a single row.")
                shortcutRow("Vertical layout", name: .alignVertical,
                            hint: "Stacks windows in a single column.")
                shortcutRow("Maximize stacked", name: .alignMaximize,
                            hint: "Makes every window of the frontmost app full size, stacked. Use the slot shortcuts to switch between them.")
                shortcutRow("Align with last layout", name: .alignLastLayout,
                            hint: "Repeats whichever layout was last used for the frontmost app. Falls back to grid.")
                shortcutRow("Restore previous arrangement", name: .restoreArrangement,
                            hint: "Moves windows back to where they were before the last alignment. Press again to reapply.")
                shortcutRow("Move to next display", name: .moveToNextDisplay,
                            hint: "Moves the frontmost app's windows to the next display.")
            }
            Section("All visible apps") {
                shortcutRow("All apps: grid", name: .alignAllAppsGrid,
                            hint: "Arranges the windows of every visible app on the current screen into a grid.")
                shortcutRow("All apps: side by side", name: .alignAllAppsHorizontal,
                            hint: "Lines up the windows of every visible app on the current screen in a single row.")
                shortcutRow("All apps: stacked vertically", name: .alignAllAppsVertical,
                            hint: "Stacks the windows of every visible app on the current screen in a single column.")
                shortcutRow("Stack by app", name: .alignStackedByApp,
                            hint: "Stacks each app's windows on top of each other, then tiles one stack per app. Press a slot shortcut again to cycle through a stack.")
            }
            Section {
                ForEach(SnapPosition.allCases, id: \.self) { position in
                    shortcutRow(position.title(), name: position.shortcutName,
                                hint: "Moves the focused window to this part of its screen.")
                }
                shortcutRow(String(localized: "Restore"), name: .snapRestore,
                            hint: "Returns the focused window to where it was before it was first snapped.")
                shortcutRow(String(localized: "Next Display"), name: .snapNextDisplay,
                            hint: "Moves the focused window to the next display.")
                shortcutRow(String(localized: "Previous Display"), name: .snapPreviousDisplay,
                            hint: "Moves the focused window to the previous display.")
            } header: {
                Text("Snap focused window")
            } footer: {
                Text("Defaults match Magnet. On a portrait display, thirds run top to bottom.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Accessibility") {
                shortcutRow("Read open windows", name: .readOpenWindows,
                            hint: "Speaks every visible window of the frontmost app for VoiceOver users.")
                shortcutRow("Announce window position", name: .announcePosition,
                            hint: "Speaks the focused window's row and column in the current layout.")
                shortcutRow("Focus slot 1", name: .focusSlot1,
                            hint: "Brings the window in slot 1 of the last alignment to focus, for keyboard-only users.")
                shortcutRow("Focus slot 2", name: .focusSlot2,
                            hint: "Brings the window in slot 2 of the last alignment to focus.")
                shortcutRow("Focus slot 3", name: .focusSlot3,
                            hint: "Brings the window in slot 3 of the last alignment to focus.")
                shortcutRow("Focus slot 4", name: .focusSlot4,
                            hint: "Brings the window in slot 4 of the last alignment to focus.")
                shortcutRow("Focus window left", name: .focusLeft,
                            hint: "Moves focus to the window in the cell to the left.")
                shortcutRow("Focus window right", name: .focusRight,
                            hint: "Moves focus to the window in the cell to the right.")
                shortcutRow("Focus window above", name: .focusUp,
                            hint: "Moves focus to the window in the cell above.")
                shortcutRow("Focus window below", name: .focusDown,
                            hint: "Moves focus to the window in the cell below.")
            }
        }
        .formStyle(.grouped)
    }

    private func shortcutRow(_ label: LocalizedStringKey, name: KeyboardShortcuts.Name, hint: LocalizedStringKey) -> some View {
        shortcutRow(text: Text(label), name: name, hint: hint)
    }

    /// For labels that are already localized (e.g. snap position titles).
    private func shortcutRow(_ label: String, name: KeyboardShortcuts.Name, hint: LocalizedStringKey) -> some View {
        shortcutRow(text: Text(verbatim: label), name: name, hint: hint)
    }

    private func shortcutRow(text label: Text, name: KeyboardShortcuts.Name, hint: LocalizedStringKey) -> some View {
        // No .combine here: it would flatten the row into one static element
        // and hide the recorder control from VoiceOver entirely. Label the
        // interactive recorder itself so it stays reachable and operable.
        HStack {
            label
            Spacer()
            KeyboardShortcuts.Recorder("", name: name)
                .accessibilityLabel(label)
                .accessibilityHint(Text(hint))
        }
    }
}

// MARK: - Accessibility

struct AccessibilitySettingsView: View {
    @AppStorage(AccessibilityPrefs.voiceOverEnabledKey) private var voiceOverEnabled: Bool = true
    @AppStorage(AccessibilityPrefs.voiceOverVerboseKey) private var voiceOverVerbose: Bool = false
    @AppStorage(AccessibilityPrefs.speakAloudKey) private var speakAloud: Bool = false
    @AppStorage(AccessibilityPrefs.soundCuesEnabledKey) private var soundCuesEnabled: Bool = true
    @AppStorage(AccessibilityPrefs.rememberPerAppLayoutKey) private var rememberPerAppLayout: Bool = true

    @StateObject private var sysA11y = SystemAccessibilityObserver()

    var body: some View {
        Form {
            Section("Spoken feedback") {
                Toggle("Speak alignment results (VoiceOver)", isOn: $voiceOverEnabled)
                    .accessibilityHint("When enabled, VoiceOver announces the layout and window count after each alignment.")
                Toggle("Verbose announcements", isOn: $voiceOverVerbose)
                    .disabled(!voiceOverEnabled)
                    .accessibilityHint("Include the application name and grid dimensions in spoken announcements.")
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Speak results aloud (without VoiceOver)", isOn: $speakAloud)
                    Text("Uses the system speech synthesizer, so results are spoken even when VoiceOver is off.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Other feedback") {
                Toggle("Play sound cue per layout", isOn: $soundCuesEnabled)
                    .accessibilityHint("Plays a distinct system sound for each layout, and different sounds for partial or failed alignments.")
                Toggle("Remember last layout per app", isOn: $rememberPerAppLayout)
                    .accessibilityHint("Provides predictable, repeatable behavior for users with cognitive accessibility needs.")
            }
            Section {
                systemFlagRow("Reduce Motion", on: sysA11y.reduceMotion)
                systemFlagRow("Increase Contrast", on: sysA11y.increaseContrast)
                systemFlagRow("Differentiate Without Color", on: sysA11y.differentiateWithoutColor)
            } header: {
                Text("System accessibility")
            } footer: {
                Text("These reflect your System Settings. AutoAlignPanels adapts its animations and colors to them automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
    }

    private func systemFlagRow(_ title: LocalizedStringKey, on: Bool) -> some View {
        // State is carried by symbol shape, wording, AND badge shape (filled
        // capsule vs outlined) — never color alone, honoring Differentiate
        // Without Color; the green fill degrades to primary under it.
        let fillColor: Color = sysA11y.differentiateWithoutColor ? .primary : .green
        return HStack {
            Image(systemName: on ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(on ? fillColor : Color.secondary)
            Text(title)
            Spacer()
            Text(on ? "On" : "Off")
                .font(.caption.weight(.semibold))
                // White stays readable on green in both appearances; under
                // Differentiate Without Color the fill is .primary, so the
                // window background color gives the proper inverse.
                .foregroundStyle(on ? (sysA11y.differentiateWithoutColor ? Color(nsColor: .windowBackgroundColor) : .white) : Color.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(on ? AnyShapeStyle(fillColor) : AnyShapeStyle(Color.primary.opacity(0.06)))
                )
                .overlay(
                    Capsule().strokeBorder(on ? Color.clear : Color.secondary.opacity(0.5))
                )
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - About

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            Text("AutoAlignPanels")
                .font(.title3.weight(.semibold))
            Text("Version \(Bundle.main.appVersionString)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("An accessibility tool that arranges, announces, and focuses the front app's windows from the keyboard — for users with vision, motor, or cognitive needs.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Link("Send Feedback", destination: URL(string: "https://github.com/neuralfoundry-coder/AutoAlignPanels/issues")!)
                .font(.callout)
            Spacer()
            if let copyright = Bundle.main.humanReadableCopyright {
                Text(copyright)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
