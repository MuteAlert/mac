// swift-tools-version: 5.9
import PackageDescription

let package = Package(name: "MuteAlert", platforms: [.macOS(.v13)], products: [
    .executable(name: "MuteAlert", targets: ["MuteAlert"])
], targets: [
    .target(name: "MuteAlertCore"),
    .executableTarget(name: "MuteAlert", dependencies: ["MuteAlertCore"]),
    .testTarget(name: "MuteAlertCoreTests", dependencies: ["MuteAlertCore"])
])
