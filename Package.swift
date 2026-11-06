// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CodexQuotaBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CodexQuotaBar", targets: ["CodexQuotaBar"])
    ],
    targets: [
        .executableTarget(
            name: "CodexQuotaBar",
            path: "Sources/CodexQuotaBar",
            resources: [.copy("Resources/CodexProvider.png"), .copy("Resources/GrokProvider.icns")]
        ),
        .testTarget(
            name: "CodexQuotaBarTests",
            dependencies: ["CodexQuotaBar"]
        )
    ]
)
