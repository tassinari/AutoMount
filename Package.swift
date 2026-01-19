// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Mounter",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Mounter",
            targets: ["Mounter"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "Mounter"
        ),

        .testTarget(
            name: "MounterTests",
            dependencies: ["Mounter"]
        ),
    ]
)
