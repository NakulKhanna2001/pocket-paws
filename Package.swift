// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PocketPaws",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "PocketPaws", targets: ["PocketPaws"])],
    targets: [
        .target(name: "PawsCore", resources: [.copy("Animals")]),
        .executableTarget(name: "PocketPaws", dependencies: ["PawsCore"]),
        .executableTarget(name: "PawsChecks", dependencies: ["PawsCore"], path: "Tests/PawsChecks"),
    ],
    swiftLanguageModes: [.v5]
)
