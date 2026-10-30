// swift-tools-version:5.10
import PackageDescription

// Built into ZnKeyboard.app by scripts/build_app.sh (needs only the Command Line Tools, no Xcode).
let package = Package(
    name: "ZnKeyboardMac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ZnKeyboardMac",
            path: "Sources/ZnKeyboardMac",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
    ]
)
