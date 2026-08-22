// swift-tools-version:6.1

import PackageDescription

let package = Package(
    name: "BeltpackBridge",
    platforms: [
        .macOS(.v13),
    ],
    dependencies: [
        .package(url: "https://github.com/livekit/client-sdk-swift.git", from: "2.16.0"),
    ],
    targets: [
        .executableTarget(
            name: "BeltpackBridge",
            dependencies: [
                .product(name: "LiveKit", package: "client-sdk-swift"),
            ],
        ),
    ],
)
