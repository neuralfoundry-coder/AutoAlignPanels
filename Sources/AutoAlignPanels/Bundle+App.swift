import Foundation

extension Bundle {
    /// "1.1.0 (9)" — from Info.plist; "dev" in bare SPM builds with no bundle.
    var appVersionString: String {
        guard let version = infoDictionary?["CFBundleShortVersionString"] as? String else { return "dev" }
        if let build = infoDictionary?["CFBundleVersion"] as? String {
            return "\(version) (\(build))"
        }
        return version
    }

    var humanReadableCopyright: String? {
        infoDictionary?["NSHumanReadableCopyright"] as? String
    }
}
