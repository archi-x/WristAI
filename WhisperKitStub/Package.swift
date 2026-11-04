// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WhisperKitStub",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .watchOS(.v10),
    ],
    products: [
        .library(name: "WhisperKit", targets: ["WhisperKit"]),
    ],
    targets: [
        .target(name: "WhisperKit", path: "Sources/WhisperKit"),
    ]
)
