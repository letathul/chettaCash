// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Data",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "Data", targets: ["Data"])
    ],
    dependencies: [
        .package(path: "../Domain")
    ],
    targets: [
        .target(
            name: "Data",
            dependencies: [.product(name: "Domain", package: "Domain")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DataTests",
            dependencies: ["Data", .product(name: "Domain", package: "Domain")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
