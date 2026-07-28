// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NightcapCompanionUI",
    platforms: [.iOS(.v17), .watchOS(.v10)],
    products: [
        .library(name: "NightcapCompanionUI", targets: ["NightcapCompanionUI"])
    ],
    dependencies: [
        .package(path: "../NightcapDomain"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "NightcapCompanionUI",
            dependencies: [
                .product(name: "NightcapDomain", package: "NightcapDomain"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ]
        )
    ]
)
