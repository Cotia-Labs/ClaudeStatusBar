// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeStatusBar",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0")
    ],
    targets: [
        .executableTarget(
            name: "ClaudeStatusBar",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/ClaudeStatusBar",
            linkerSettings: [
                // Sparkle.framework is copied into Contents/Frameworks by
                // build-app.sh; SPM otherwise bakes in the artifact path from
                // ~/.build, which does not exist on the user's machine.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        )
    ]
)
