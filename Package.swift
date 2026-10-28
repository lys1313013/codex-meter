// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexMeter",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "CodexMeter", targets: ["CodexMeter"])],
    targets: [
        .target(name: "MeterCore"),
        .executableTarget(name: "CodexMeter", dependencies: ["MeterCore"]),
        .executableTarget(name: "MeterChecks", dependencies: ["MeterCore"], path: "Tests")
    ],
    swiftLanguageModes: [.v5]
)
