// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QuotaGuard",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "QuotaGuard",
            targets: ["QuotaGuard"]
        ),
    ],
    dependencies: [
        // Add external dependencies here if needed
    ],
    targets: [
        .target(
            name: "QuotaGuard",
            dependencies: [],
            path: "QuotaGuard",
            exclude: ["Widget"]
        ),
        .testTarget(
            name: "QuotaGuardTests",
            dependencies: ["QuotaGuard"],
            path: "QuotaGuardTests"
        ),
    ]
)
