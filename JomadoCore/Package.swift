// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "JomadoCore",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "JomadoCore", targets: ["JomadoCore"])
    ],
    targets: [
        .target(name: "JomadoCore"),
        .testTarget(name: "JomadoCoreTests", dependencies: ["JomadoCore"])
    ]
)
