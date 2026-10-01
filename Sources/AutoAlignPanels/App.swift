import Cocoa

@main
enum AutoAlignPanelsMain {
    // NSApplication.delegate does not retain its delegate.
    @MainActor private static var delegate: AppDelegate?

    @MainActor static func main() {
        let app = NSApplication.shared
        let appDelegate = AppDelegate()
        delegate = appDelegate
        app.delegate = appDelegate
        app.run()
    }
}
