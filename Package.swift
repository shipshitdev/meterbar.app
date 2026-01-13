// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MeterBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "MeterBar",
            targets: ["MeterBar"]
        ),
    ],
    dependencies: [
        // Add external dependencies here if needed
    ],
    targets: [
        .target(
            name: "MeterBar",
            dependencies: [],
            path: "MeterBar",
            exclude: ["Widget"]
        ),
        .testTarget(
            name: "MeterBarTests",
            dependencies: ["MeterBar"],
            path: "MeterBarTests"
        ),
    ]
)
