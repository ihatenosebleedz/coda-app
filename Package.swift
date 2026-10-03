// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NaviCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "NaviCore", targets: ["NaviCore"])
    ],
    targets: [
        .target(
            name: "NaviCore",
            path: "Sources/NaviCore"
        ),
        .testTarget(
            name: "NaviCoreTests",
            dependencies: ["NaviCore"],
            path: "Tests/NaviCoreTests"
        ),
        .testTarget(
            name: "NaviIntegrationTests",
            dependencies: ["NaviCore"],
            path: "Tests/NaviIntegrationTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
