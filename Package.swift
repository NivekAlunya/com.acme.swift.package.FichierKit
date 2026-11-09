// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FichierKit",
    platforms: [
        .iOS(.v18),
        .tvOS(.v18)
    ],
    products: [
        .library(
            name: "FichierKit",
            targets: ["FichierKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/amosavian/AMSMB2.git", from: "4.0.3"),
        .package(url: "https://github.com/videolan/vlckit.git", exact: "4.0.0-a25")
    ],
    targets: [
        .target(
            name: "FichierKit",
            dependencies: [
                .product(name: "AMSMB2", package: "AMSMB2"),
                .product(name: "VLCKit", package: "vlckit")
            ]
        ),
        .testTarget(
            name: "FichierKitTests",
            dependencies: ["FichierKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
