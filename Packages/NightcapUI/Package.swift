// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NightcapUI",
    platforms: [.macOS(.v14), .iOS(.v17), .watchOS(.v10)],
    products: [
        .library(name: "NightcapUI", targets: ["NightcapUI"])
    ],
    dependencies: [
        .package(path: "../NightcapDomain"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
    ],
    targets: [
        .testTarget(
            name: "NightcapUITests",
            dependencies: [
                "NightcapUI",
                .product(name: "NightcapDomain", package: "NightcapDomain"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ]
        ),
        .target(
            name: "NightcapUI",
            dependencies: [
                .product(name: "NightcapDomain", package: "NightcapDomain"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ]
        )
    ]
)
