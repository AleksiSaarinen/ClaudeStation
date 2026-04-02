// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeStation",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeStation",
            path: "Sources",
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals")
            ]
        )
    ]
)

