import AppKit
import Security

/// Keeps reinstalls clean for the direct (DMG) build: the most recently
/// launched copy wins, a copy run from the disk image installs itself into
/// /Applications, and an Accessibility entry left over from a previous build
/// is reset so macOS asks again for THIS build.
///
/// Every step is a no-op under the App Sandbox, where none of it is
/// permitted.
@MainActor
enum InstallManager {
    static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    private static var bundleID: String? { Bundle.main.bundleIdentifier }

    // MARK: - Single instance

    /// Quits any other running copy (typically the previous version still
    /// running after the user installed a new one). Two copies would both
    /// grab the same global hotkeys and fight over windows.
    static func terminateOtherInstances() {
        guard let bundleID else { return }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ownPID }
        guard !others.isEmpty else { return }
        Diag.log.info("install: terminating \(others.count, privacy: .public) older instance(s)")
        others.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(3)
        while others.contains(where: { !$0.isTerminated }) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        others.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
    }

    // MARK: - Install location

    /// True when running from somewhere macOS can't bind a permission to: a
    /// read-only volume (the mounted DMG) or Gatekeeper's translocation copy.
    /// A writable external drive is a legitimate install location.
    static var isRunningFromDiskImage: Bool {
        let path = Bundle.main.bundlePath
        if path.contains("/AppTranslocation/") { return true }
        guard path.hasPrefix("/Volumes/") else { return false }
        let values = try? Bundle.main.bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey])
        return values?.volumeIsReadOnly ?? false
    }

    static let applicationsURL = URL(fileURLWithPath: "/Applications/AutoAlignPanels.app")

    /// Copies this bundle over /Applications/AutoAlignPanels.app (the old
    /// copy goes to the Trash), clears the quarantine flag, and launches the
    /// installed copy. Returns false if the copy failed; on success this
    /// process terminates.
    static func installToApplicationsAndRelaunch() -> Bool {
        let fm = FileManager.default
        let destination = applicationsURL
        terminateOtherInstances()
        do {
            if fm.fileExists(atPath: destination.path) {
                do {
                    try fm.trashItem(at: destination, resultingItemURL: nil)
                } catch {
                    try fm.removeItem(at: destination)
                }
            }
            try fm.copyItem(at: Bundle.main.bundleURL, to: destination)
        } catch {
            Diag.log.error("install: copy to /Applications failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        // The copy is notarized and stapled; dropping quarantine just skips a
        // second "downloaded from the Internet" dialog for the same build.
        run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", destination.path])

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
        return true
    }

    // MARK: - Accessibility entry

    private static let fingerprintKey = "installFingerprint"

    /// macOS binds the Accessibility grant to the code signature. After a
    /// reinstall with a different signature the old entry goes stale: the
    /// switch still shows ON in System Settings, AXIsProcessTrusted() says
    /// false, and the system prompt never appears again — the user is stuck
    /// toggling a switch that does nothing. When this build differs from the
    /// one that ran last and is not trusted, reset our own entry so the
    /// prompt that follows registers THIS build from scratch.
    static func resetStalePermissionIfNeeded() {
        guard !isSandboxed, let bundleID else { return }
        let current = installFingerprint()
        let previous = UserDefaults.standard.string(forKey: fingerprintKey)
        UserDefaults.standard.set(current, forKey: fingerprintKey)
        guard current != previous, !AccessibilityHelper.isTrusted else { return }
        let status = run("/usr/bin/tccutil", ["reset", "Accessibility", bundleID])
        Diag.log.info("install: new build untrusted -> tccutil reset exit=\(status, privacy: .public)")
    }

    /// Path + version + code-directory hash: changes on every reinstall of a
    /// different build or a move to a different location.
    private static func installFingerprint() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(Bundle.main.bundlePath)|\(version)|\(codeDirectoryHash() ?? "unsigned")"
    }

    private static func codeDirectoryHash() -> String? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode
        else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any],
              let hash = dict[kSecCodeInfoUnique as String] as? Data
        else { return nil }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
