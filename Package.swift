// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SSHDeck",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SSHDeck", targets: ["SSHDeck"])
    ],
    targets: [
        .target(
            name: "SSHDeckCore"
        ),
        .executableTarget(
            name: "SSHDeck",
            dependencies: ["SSHDeckCore"]
        ),
        .testTarget(
            name: "SSHDeckCoreTests",
            dependencies: ["SSHDeckCore"]
        )
    ],
    swiftLanguageModes: [.v5]
)
