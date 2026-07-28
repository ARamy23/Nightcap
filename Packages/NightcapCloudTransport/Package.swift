// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NightcapCloudTransport",
    platforms: [.macOS(.v14), .iOS(.v17), .watchOS(.v10)],
    products: [
        .library(name: "NightcapCloudTransport", targets: ["NightcapCloudTransport"])
    ],
    dependencies: [
        .package(path: "../NightcapDomain"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.12.0"),
    ],
    targets: [
        .target(
            name: "NightcapCloudTransport",
            dependencies: [
                .product(name: "NightcapDomain", package: "NightcapDomain"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        )
    ]
)
