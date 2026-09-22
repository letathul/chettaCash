// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Features",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "Features", targets: ["Features"])
    ],
    dependencies: [
        .package(path: "../Domain")
    ],
    targets: [
        .target(
            name: "Features",
            dependencies: [.product(name: "Domain", package: "Domain")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FeaturesTests",
            dependencies: ["Features", .product(name: "Domain", package: "Domain")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
