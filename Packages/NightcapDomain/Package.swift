// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NightcapDomain",
    platforms: [.macOS(.v14), .iOS(.v17), .watchOS(.v10)],
    products: [
        .library(name: "NightcapDomain", targets: ["NightcapDomain"])
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.12.0"),
        .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.8.0"),
    ],
    targets: [
        // Pure: no AppKit, IOKit, ServiceManagement or StoreKit, so this builds
        // for iOS and watchOS as well as macOS.
        .target(
            name: "NightcapDomain",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
                .product(name: "Sharing", package: "swift-sharing"),
            ]
        )
    ]
)
