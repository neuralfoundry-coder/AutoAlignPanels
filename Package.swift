// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AutoAlignPanels",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "AutoAlignPanelsCore",
            path: "Sources/AutoAlignPanelsCore"
        ),
        .executableTarget(
            name: "AutoAlignPanels",
            dependencies: ["KeyboardShortcuts", "AutoAlignPanelsCore"],
            path: "Sources/AutoAlignPanels"
        ),
        .testTarget(
            name: "AutoAlignPanelsCoreTests",
            dependencies: ["AutoAlignPanelsCore"],
            path: "Tests/AutoAlignPanelsCoreTests"
        ),
    ]
)
