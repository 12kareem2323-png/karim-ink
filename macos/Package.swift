// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "EngineeringBoard",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "EngineeringBoard", targets: ["EngineeringBoard"])],
    targets: [
        .executableTarget(name: "EngineeringBoard"),
        .testTarget(name: "EngineeringBoardTests", dependencies: ["EngineeringBoard"])
    ]
)
