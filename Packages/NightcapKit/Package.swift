// swift-tools-version: 5.9
import PackageDescription

// One package, three targets. The boundary that matters is the module boundary:
// NightcapDomain cannot import AppKit/IOKit/SwiftUI, and the compiler enforces it.
// Separate packages would add a manifest each and duplicate package identity in
// the generated Xcode project for no extra isolation.
let package = Package(
    name: "NightcapKit",
    platforms: [.macOS(.v14), .iOS(.v17), .watchOS(.v10)],
    products: [
        .library(name: "NightcapDomain", targets: ["NightcapDomain"]),
        .library(name: "NightcapClients", targets: ["NightcapClients"]),
        .library(name: "NightcapUI", targets: ["NightcapUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.12.0"),
        .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.8.0"),
    ],
    targets: [
        // Pure. No platform frameworks, so it builds for watchOS too.
        .target(
            name: "NightcapDomain",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
                .product(name: "Sharing", package: "swift-sharing"),
            ]
        ),
        // The only target allowed to touch AppKit, IOKit, ServiceManagement, StoreKit.
        .target(
            name: "NightcapClients",
            dependencies: [
                "NightcapDomain",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .target(
            name: "NightcapUI",
            dependencies: [
                "NightcapDomain",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ]
        ),
    ]
)
