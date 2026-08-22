// swift-tools-version:6.1

import PackageDescription

let package = Package(
    name: "BeltpackKit",
    platforms: [
        // iOS too: the app shares PairingLink and the token plumbing rather
        // than keeping a second copy that can drift.
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        // Shared by the headless bridge and the Mac app, so the two can never
        // drift apart on how a device is picked or a room is joined.
        .library(name: "BeltpackKit", targets: ["BeltpackKit"]),
        .executable(name: "BeltpackBridge", targets: ["BeltpackBridge"]),
    ],
    dependencies: [
        .package(url: "https://github.com/livekit/client-sdk-swift.git", from: "2.16.0"),
    ],
    targets: [
        .target(
            name: "BeltpackKit",
            dependencies: [
                .product(name: "LiveKit", package: "client-sdk-swift"),
            ],
        ),
        .executableTarget(
            name: "BeltpackBridge",
            dependencies: ["BeltpackKit"],
        ),
        .testTarget(
            name: "BeltpackKitTests",
            dependencies: ["BeltpackKit"],
        ),
    ],
)
