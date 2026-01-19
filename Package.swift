// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "libMounter",
    
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "libMounter",
            targets: ["libMounter"]),
    ],
    targets: [
        .target(
            name: "libMounter"
        ),

        .testTarget(
            name: "libMounterTests",
            dependencies: ["libMounter"]
        ),
    ]
)
