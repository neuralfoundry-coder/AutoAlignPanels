# CLAUDE.md

## Project Overview

AutoAlignPanels is a macOS menu bar utility that aligns windows of the frontmost application — or of every visible app on the working screen (tiled per window, or stacked per app) — into grid, horizontal, or vertical layouts using the Accessibility API.

**Distribution: Developer ID–signed, notarized DMG via GitHub Releases.**

## Tech Stack

- **Language**: Swift 5.9
- **Platform**: macOS 13.0+
- **UI**: SwiftUI (settings popover) + AppKit (NSStatusItem, NSPopover)
- **Window Control**: AXUIElement (ApplicationServices), CGWindowList
- **Dependencies**: [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) v2.x (via SPM)
- **Build**: Swift Package Manager + XcodeGen (`project.yml`)

## Build & Run

```bash
# SPM build (no sandbox, good for local testing) + unit tests.
# xcode-select points at CommandLineTools, which lacks the #Preview macro
# plugin KeyboardShortcuts needs — use the Xcode toolchain:
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift build
swift test
.build/debug/AutoAlignPanels

# Xcode project (regenerate after changing project.yml; set your team)
DEVELOPMENT_TEAM=<team-id> xcodegen generate
# Then open AutoAlignPanels.xcodeproj and Cmd+R
```

Note: `swift build` produces an **unsandboxed** binary. Accessibility/entitlement
behavior must be verified with the Xcode-built (sandboxed, signed) app.

## Project Structure

```
Sources/AutoAlignPanelsCore/  # Pure logic, no AppKit/AX — unit-testable via `swift test`
  AlignmentMode.swift     # grid/horizontal/vertical/maximize + FocusDirection
  GridCalculator.swift    # Layout math (gap, margin, balanced last row)
  ScreenSelection.swift   # Target-screen pick by window-center majority
  AlignmentReport.swift   # Per-window outcomes + honest summary messages (scope: single/all apps/stacked)
  MultiAppLayout.swift    # Stack-per-app cells, recency-capped grouped ordering
  SnapLayout.swift        # Magnet-style single-window regions, display translate
Sources/AutoAlignPanels/
  App.swift               # @main entry point
  AppDelegate.swift       # Lifecycle, hotkey registration, onboarding trigger
  InstallManager.swift    # Latest copy wins, DMG→/Applications install, stale TCC reset
  WindowManager.swift     # @MainActor align pipeline (collect→filter→apply→verify→report)
  AXWindowKit.swift       # Safe AX wrappers: typed decode, batch reads, timeouts
  AccessibilityHelper.swift  # Permission checks, announcements, sound cues
  AlignmentFeedback.swift # Feedback sink: HUD + sound + VoiceOver per outcome
  PermissionModel.swift   # Reactive AX-trust state (polls while UI visible)
  PopoverContext.swift    # Captures target app before our UI steals frontmost
  StatusBarController.swift  # Menu bar icon: left-click popover, right-click menu
  ShortcutNames.swift     # KeyboardShortcuts.Name definitions
  UI/PopoverView.swift    # Quick-actions popover
  UI/SettingsRootView.swift + SettingsWindowController.swift  # Tabbed settings window
  UI/HUD/                 # Non-activating alignment feedback panel
  UI/Onboarding/          # First-run permission walkthrough
Tests/AutoAlignPanelsCoreTests/  # GridCalculator/ScreenSelection/AlignmentReport tests
Resources/Localizable.xcstrings  # EN (source) + KO translations, incl. announcements
Resources/InfoPlist.xcstrings    # Localized NSAccessibilityUsageDescription
```

## Key Architecture Decisions

- **Coordinate system**: NSScreen uses bottom-left origin, AX/CG APIs use top-left. Conversion happens in `WindowManager.alignFrontmostAppWindows()`.
- **Window matching**: AX windows are fuzzy-matched (10px tolerance) against CGWindowList on-screen bounds to filter current-space windows.
- **App Sandbox**: Off for the release build (see Distribution).
- **No Dock icon**: `LSUIElement = true` in Info.plist + `.accessory` activation policy.

## Default Hotkeys

| Action | Shortcut |
|--------|----------|
| Grid align | Ctrl+Shift+P |
| Horizontal align | Ctrl+Shift+H |
| Vertical align | Ctrl+Shift+V |
| Maximize stacked | Ctrl+Shift+F |
| Align with last layout | Ctrl+Shift+L |
| Restore previous arrangement | Ctrl+Shift+Z |
| Move to next display | Ctrl+Shift+D |
| All apps: grid | Ctrl+Shift+Cmd+P |
| All apps: side by side | Ctrl+Shift+Cmd+H |
| All apps: stacked vertically | Ctrl+Shift+Cmd+V |
| Stack by app (same-app windows stacked, stacks tiled) | Ctrl+Shift+S |
| Read open windows | Ctrl+Shift+R |
| Announce window position | Ctrl+Shift+W |
| Focus slot 1–4 | Ctrl+Opt+1–4 |
| Focus window left/right/up/down | Ctrl+Shift+arrows (Ctrl+Opt+arrows until 0.1.0; migrated on launch) |
| Snap focused window (Magnet defaults) | Ctrl+Opt+arrows halves · U/I/J/K quarters · D/F/G thirds · E/R/T two-thirds · Return maximize · C center · Delete restore |
| Snap sixths / quarter rows | Ctrl+Opt+Cmd+U/I/O/J/K/L · Ctrl+Opt+Cmd+1–4 |
| Focused window to next/previous display | Ctrl+Opt+Cmd+Right/Left |

Snap shortcuts deliberately mirror Magnet's defaults (users switch from Magnet);
Ctrl+Opt is also the VoiceOver modifier, so all are remappable. All-apps passes
cover regular, unhidden apps on the current Space whose window centers lie on
the screen of the frontmost window. In stack-by-app mode a slot = one stack;
pressing the same slot again cycles through that stack.

## Design Principles

The app is positioned as an **accessibility tool** (vision/motor/cognitive).
Do not remove VoiceOver announcements, sound cues, per-app layout memory, or slot
focus; never move windows without an explicit user command (no auto-align on app
activation). Announcements must reflect verified results (AlignmentReport), never
claim success that didn't happen.

## Distribution (DMG only)

```bash
./scripts/release-dmg.sh
# → dist/AutoAlignPanels-<version>.dmg (Developer ID signed, notarized, stapled)
```

Credentials come from the environment, falling back to the same-named
variables in `~/.zshrc`: `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`,
`APP_STORE_CONNECT_KEY_PATH`, `APP_STORE_TEAMID`. The script exports
`DEVELOPMENT_TEAM` for XcodeGen — the Team ID is never committed (`project.yml`
uses `${DEVELOPMENT_TEAM}`, and the generated `.xcodeproj` is gitignored).
Signing needs a "Developer ID Application" identity in the login keychain; the
DMG is signed by certificate hash when one exists.

- Bundle ID: `io.github.neuralfoundry-coder.AutoAlignPanels`
- Releases: GitHub Releases, tag `v<MARKETING_VERSION>`, DMG attached.

**Clean reinstall (InstallManager, unsandboxed only):** on launch the newest
copy quits any other running instance; a copy launched from the DMG offers
"Install and Reopen" (trashes the old /Applications copy, copies itself,
strips quarantine, relaunches); when the build fingerprint (path + build +
cdhash) changed and AX is not trusted, it runs `tccutil reset Accessibility
<bundle id>` so the system prompt registers the new build instead of leaving
a stale, non-working toggle. Every alignment action is gated on AX trust and
re-opens the permission walkthrough when untrusted.

**The release build is UNSANDBOXED** (`AutoAlignPanelsDirect.entitlements` via a
`CODE_SIGN_ENTITLEMENTS` override in the script): a sandboxed process cannot
self-register in the Accessibility privacy list, replace an older install, or
reset its permission entry. `AutoAlignPanels.entitlements` (sandboxed) remains
the default for plain Xcode builds; InstallManager no-ops there.
