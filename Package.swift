// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PRPulse",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PRPulseCore", targets: ["PRPulseCore"]),
        .executable(name: "PRPulse", targets: ["PRPulse"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),
    ],
    targets: [
        .target(name: "PRPulseCore"),
        .executableTarget(
            name: "PRPulse",
            dependencies: [
                "PRPulseCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "PRPulseCoreTests",
            dependencies: ["PRPulseCore"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
