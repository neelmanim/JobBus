// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "JobBus",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", .upToNextMajor(from: "0.9.0")),
    ],
    targets: [
        .executableTarget(
            name: "JobBus",
            dependencies: ["ZIPFoundation"],
            path: "Sources",
            resources: [
                .process("Resources")
            ]
        ),
    ]
)
