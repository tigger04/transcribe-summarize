// swift-tools-version: 5.9
// ABOUTME: Swift package manifest for transcribe-summarize CLI tool.
// ABOUTME: Defines executable target with ArgumentParser and Yams dependencies.

import PackageDescription

let package = Package(
    name: "transcribe-summarize",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "transcribe-summarize", targets: ["TranscribeSummarize"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "TranscribeSummarize",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Yams", package: "Yams"),
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .testTarget(
            name: "TranscribeSummarizeTests",
            dependencies: ["TranscribeSummarize"],
            resources: [
                .copy("Resources/sample.mp3")
            ]
        ),
    ]
)
