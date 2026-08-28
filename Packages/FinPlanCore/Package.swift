// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FinPlanCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "FinPlanCore", targets: ["FinPlanCore"])
    ],
    targets: [
        .target(name: "FinPlanCore"),
        .testTarget(name: "FinPlanCoreTests", dependencies: ["FinPlanCore"])
    ]
)
