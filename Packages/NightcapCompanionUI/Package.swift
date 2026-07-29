// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NightcapCompanionUI",
    // macOS is here only so `swift test` can run this package's tests on the host
    // without a simulator. The app targets ship it to iOS and watchOS only.
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "NightcapCompanionUI", targets: ["NightcapCompanionUI"])
    ],
    dependencies: [
        .package(path: "../NightcapDomain"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
    ],
    targets: [
        .testTarget(
            name: "NightcapCompanionUITests",
            dependencies: [
                "NightcapCompanionUI",
                .product(name: "NightcapDomain", package: "NightcapDomain"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ]
        ),
        .target(
            name: "NightcapCompanionUI",
            dependencies: [
                .product(name: "NightcapDomain", package: "NightcapDomain"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ]
        )
    ]
)
