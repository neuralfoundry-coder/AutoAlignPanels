import Cocoa
import ApplicationServices
import AVFoundation
import AutoAlignPanelsCore

enum AccessibilityHelper {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func checkAndPrompt() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Self-probe: reads our own process's AX windows attribute. When the
    /// permission was granted AFTER this process launched, AXIsProcessTrusted
    /// flips to true but the process's AX session stays dead — even reads
    /// against ourselves fail. Distinguishes "our session is stale" from
    /// "the target app is hung".
    static func axSessionHealthy() -> Bool {
        let selfElement = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        AXUIElementSetMessagingTimeout(selfElement, 1.0)
        var ref: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(selfElement, kAXWindowsAttribute as CFString, &ref)
        return error == .success
    }

    private static let relaunchMarkerKey = "lastAXRelaunchAt"

    private static var recentlyRelaunchedForPermission: Bool {
        Date().timeIntervalSince1970 - UserDefaults.standard.double(forKey: relaunchMarkerKey) < 120
    }

    /// A freshly granted Accessibility permission only takes effect in a new
    /// process. Announce, then relaunch. Guarded so a broken state can never
    /// relaunch-loop: within 2 minutes of a relaunch it falls back to a
    /// spoken manual instruction instead.
    @MainActor
    static func relaunchToApplyPermission() {
        guard !recentlyRelaunchedForPermission else {
            playErrorSound()
            announce(String(localized: "Accessibility permission isn't active yet. Quit and reopen AutoAlignPanels."))
            return
        }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: relaunchMarkerKey)
        announce(String(localized: "Restarting AutoAlignPanels to apply the accessibility permission."))
        // Give VoiceOver a moment to speak before the process goes away.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
                Task { @MainActor in
                    NSApp.terminate(nil)
                }
            }
        }
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"),
           NSWorkspace.shared.open(url) {
            return
        }
        // The legacy pane URL can fail on newer macOS — open System Settings itself.
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    // MARK: - System accessibility settings

    static var shouldReduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static var shouldIncreaseContrast: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    static var shouldDifferentiateWithoutColor: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldDifferentiateWithoutColor
    }

    // MARK: - Spoken feedback

    /// Must be retained for the lifetime of the app or speech cuts off mid-utterance.
    private static let speechSynthesizer = AVSpeechSynthesizer()

    /// Posts a VoiceOver announcement so blind / low-vision users get spoken
    /// confirmation of window-management actions performed by the app, and —
    /// when the opt-in "speak aloud" preference is set — speaks the same text
    /// through the speech synthesizer for users who don't run VoiceOver.
    static func announce(_ text: String, priority: NSAccessibilityPriorityLevel = .high) {
        guard !text.isEmpty else { return }

        let voiceOverEnabled = UserDefaults.standard.object(forKey: AccessibilityPrefs.voiceOverEnabledKey) as? Bool ?? true
        if voiceOverEnabled {
            DispatchQueue.main.async {
                NSAccessibility.post(
                    element: NSApp as Any,
                    notification: .announcementRequested,
                    userInfo: [
                        .announcement: text,
                        .priority: NSNumber(value: priority.rawValue)
                    ]
                )
            }
        }

        // Off by default: VoiceOver users would otherwise hear everything twice.
        let speakAloud = UserDefaults.standard.object(forKey: AccessibilityPrefs.speakAloudKey) as? Bool ?? false
        if speakAloud {
            speechSynthesizer.stopSpeaking(at: .immediate)
            speechSynthesizer.speak(AVSpeechUtterance(string: text))
        }
    }

    // MARK: - Sound cues

    private static var soundCuesEnabled: Bool {
        UserDefaults.standard.object(forKey: AccessibilityPrefs.soundCuesEnabledKey) as? Bool ?? true
    }

    /// Plays a short, distinct system sound to confirm the alignment action
    /// without requiring the user to look at the screen.
    static func playSoundCue(for mode: AlignmentMode) {
        guard soundCuesEnabled else { return }
        let soundName: String
        switch mode {
        case .grid:       soundName = "Tink"
        case .horizontal: soundName = "Pop"
        case .vertical:   soundName = "Morse"
        case .maximize:   soundName = "Glass"
        }
        NSSound(named: soundName)?.play()
    }

    /// Distinct sounds per outcome so partial and failed alignments are never
    /// mistaken for success by ear.
    static func playFeedback(tone: AlignmentReport.Tone, mode: AlignmentMode) {
        switch tone {
        case .success:
            playSoundCue(for: mode)
        case .partial:
            guard soundCuesEnabled else { return }
            NSSound(named: "Funk")?.play()
        case .failure:
            playErrorSound()
        }
    }

    static func playErrorSound() {
        guard soundCuesEnabled else { return }
        NSSound(named: "Basso")?.play()
    }

    static func playRestoreSound() {
        guard soundCuesEnabled else { return }
        NSSound(named: "Bottle")?.play()
    }
}

enum AccessibilityPrefs {
    static let voiceOverEnabledKey = "a11yVoiceOverEnabled"
    static let voiceOverVerboseKey = "a11yVoiceOverVerbose"
    static let soundCuesEnabledKey = "a11ySoundCuesEnabled"
    static let rememberPerAppLayoutKey = "a11yRememberPerAppLayout"
    static let speakAloudKey = "a11ySpeakAloud"
}
