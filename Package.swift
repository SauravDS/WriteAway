// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WriteAway",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "WriteAway",
            path: "Sources/WriteAway"
        )
    ]
)
