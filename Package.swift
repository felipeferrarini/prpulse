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
    targets: [
        .target(name: "PRPulseCore"),
        .executableTarget(
            name: "PRPulse",
            dependencies: ["PRPulseCore"],
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
