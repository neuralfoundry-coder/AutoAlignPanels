import SwiftUI

/// First-run walkthrough. The app is an LSUIElement — it launches invisibly —
/// so this window is the only signal a new user gets. It explains the
/// accessibility purpose and walks through granting permission, with a live
/// status row that flips the moment access is granted. On first launch the
/// system permission prompt also fires automatically (AppDelegate) so the app
/// is already listed in System Settings; the button re-triggers it on demand.
struct OnboardingView: View {
    @EnvironmentObject private var permission: PermissionModel

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.gradient)
                    .frame(width: 56, height: 56)
                Image(systemName: "rectangle.grid.2x2.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
            .padding(.top, 8)

            Text("Welcome to AutoAlignPanels")
                .font(.title2.weight(.semibold))

            Text("An accessibility tool for arranging, announcing, and focusing the front app's windows — entirely from the keyboard.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 10) {
                benefitRow(symbol: "waveform",
                           title: "Hear your windows",
                           detail: "Speaks the layout and titles of open windows for VoiceOver users.")
                benefitRow(symbol: "keyboard",
                           title: "Focus without a pointer",
                           detail: "Move keyboard focus between aligned windows with slots or arrow keys.")
                benefitRow(symbol: "square.grid.2x2",
                           title: "One-keystroke layouts",
                           detail: "Predictable, repeatable window arrangements that replace drag-and-resize.")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 4)

            Divider()
                .padding(.horizontal, 24)

            HStack(spacing: 8) {
                Image(systemName: permission.isTrusted ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(permission.isTrusted ? .green : .secondary)
                Text(permission.isTrusted ? "Accessibility access granted" : "Accessibility access not granted")
                    .font(.callout.weight(.medium))
            }
            .accessibilityElement(children: .combine)
            .animation(appAnimation(), value: permission.isTrusted)

            if permission.isTrusted {
                Button("Done") {
                    OnboardingWindowController.shared.dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            } else {
                VStack(spacing: 8) {
                    Button("Open System Settings") {
                        AccessibilityHelper.checkAndPrompt()
                        AccessibilityHelper.openAccessibilitySettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Opens the Accessibility privacy pane where you can allow AutoAlignPanels.")
                    Text("macOS will ask you to allow AutoAlignPanels under Privacy & Security → Accessibility.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }

            Spacer(minLength: 4)

            Label("AutoAlignPanels lives in your menu bar — look for the grid icon.",
                  systemImage: "menubar.rectangle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)
        }
        .padding(20)
        .frame(width: 480)
    }

    private func benefitRow(symbol: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
