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
        // The directories are named Mounter/MounterTests while the targets are
        // libMounter/libMounterTests, so both paths are explicit.
        .target(
            name: "libMounter",
            path: "Sources/Mounter"
        ),

        .testTarget(
            name: "libMounterTests",
            dependencies: ["libMounter"],
            path: "Tests/MounterTests",
            // Documentation, not a resource; excluding it silences an
            // "unhandled file" warning on every build.
            exclude: ["ACCEPTANCE_TESTS.md"]
        ),
    ]
)
