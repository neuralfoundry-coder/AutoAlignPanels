import SwiftUI
import AutoAlignPanelsCore

/// Compact quick-actions popover shown from the status item. Settings moved
/// to their own window (SettingsRootView); this surface is for acting fast.
struct PopoverView: View {
    @EnvironmentObject private var permission: PermissionModel
    @AppStorage("windowGap") private var windowGap: Double = 8

    var closePopover: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !permission.isTrusted {
                permissionBanner
                    .transition(.opacity)
            }
            quickActions
            allAppsActions
            readWindowsButton
            Divider()
            gapRow
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 320)
        .animation(appAnimation(), value: permission.isTrusted)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.gradient)
                    .frame(width: 28, height: 28)
                Image(systemName: "rectangle.grid.2x2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("AutoAlignPanels")
                    .font(.headline)
                Text("Keyboard-driven window accessibility")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("AutoAlignPanels, keyboard-driven window accessibility tool")
            Spacer()
            Button {
                closePopover()
                SettingsWindowController.shared.show()
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open settings")
        }
    }

    // MARK: - Permission banner

    private var permissionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility access required")
                    .font(.caption.weight(.semibold))
                Text("Needed to move and read windows.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Grant") {
                AccessibilityHelper.checkAndPrompt()
                AccessibilityHelper.openAccessibilitySettings()
            }
            .controlSize(.small)
            .accessibilityHint("Opens System Settings to grant Accessibility permission")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.orange.opacity(0.15)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.orange.opacity(0.35)))
    }

    // MARK: - Quick actions

    private var quickActions: some View {
        HStack(spacing: 8) {
            // Return aligns to grid — the popover's default action.
            layoutButton("Grid", mode: .grid, hint: "Arranges windows of the front app into a grid.")
                .keyboardShortcut(.defaultAction)
            layoutButton("Side by side", mode: .horizontal, hint: "Lines windows side by side in a single row.")
            layoutButton("Stacked", mode: .vertical, hint: "Stacks windows in a single column.")
        }
    }

    private func layoutButton(_ title: LocalizedStringKey, mode: AlignmentMode, hint: LocalizedStringKey) -> some View {
        Button {
            let target = PopoverContext.shared.targetApp
            closePopover()
            WindowManager.shared.alignWindows(of: target, mode: mode)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: mode.symbolName)
                    .font(.system(size: 20, weight: .medium))
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(QuickActionButtonStyle())
        .disabled(!permission.isTrusted)
        .accessibilityHint(Text(hint))
    }

    // MARK: - All apps

    private var allAppsActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("All visible apps")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 8) {
                allAppsButton("Grid", symbol: AlignmentMode.grid.symbolName,
                              hint: "Arranges the windows of every visible app on this screen into a grid.") {
                    WindowManager.shared.alignAllAppsWindows(mode: .grid)
                }
                allAppsButton("Side by side", symbol: AlignmentMode.horizontal.symbolName,
                              hint: "Lines up the windows of every visible app in a single row.") {
                    WindowManager.shared.alignAllAppsWindows(mode: .horizontal)
                }
                allAppsButton("Stacked", symbol: AlignmentMode.vertical.symbolName,
                              hint: "Stacks the windows of every visible app in a single column.") {
                    WindowManager.shared.alignAllAppsWindows(mode: .vertical)
                }
                allAppsButton("By app", symbol: "square.stack.3d.up",
                              hint: "Stacks each app's windows on top of each other, then tiles the stacks.") {
                    WindowManager.shared.alignStackedByApp()
                }
            }
        }
    }

    private func allAppsButton(_ title: LocalizedStringKey, symbol: String, hint: LocalizedStringKey,
                               action: @escaping () -> Void) -> some View {
        Button {
            closePopover()
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(QuickActionButtonStyle())
        .disabled(!permission.isTrusted)
        .accessibilityLabel(Text("All apps: \(Text(title))"))
        .accessibilityHint(Text(hint))
    }

    private var readWindowsButton: some View {
        Button {
            closePopover()
            WindowManager.shared.readOpenWindows()
        } label: {
            Label("Read Open Windows", systemImage: "waveform")
        }
        .controlSize(.small)
        .buttonStyle(.bordered)
        .disabled(!permission.isTrusted)
        .accessibilityHint("Speaks every visible window of the front app.")
    }

    // MARK: - Gap

    private var gapRow: some View {
        HStack(spacing: 8) {
            Text("Window gap")
                .font(.callout)
            Slider(value: $windowGap, in: 0...64, step: 1)
                .controlSize(.small)
                .accessibilityLabel("Window gap in points")
            Text("\(Int(windowGap)) pt")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text(verbatim: "v\(Bundle.main.appVersionString)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Settings…") {
                closePopover()
                SettingsWindowController.shared.show()
            }
            .controlSize(.small)
            Button("Quit") {
                NSApp.terminate(nil)
            }
            .controlSize(.small)
            .accessibilityHint("Quits AutoAlignPanels.")
        }
    }
}

private struct QuickActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.16 : 0.07))
            )
    }
}
