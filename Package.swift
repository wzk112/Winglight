// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Winglight",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "WinglightCore", targets: ["WinglightCore"]), .executable(name: "Winglight", targets: ["Winglight"])],
    targets: [
        .target(name: "WinglightCore", resources: [.copy("Resources/Aircraft.json")]),
        .executableTarget(name: "Winglight", dependencies: ["WinglightCore"], resources: [.copy("Resources/Lights.metal"), .copy("Resources/Lights.metallib"), .copy("Resources/Models"), .copy("Resources/Textures"), .copy("Resources/Liveries")]),
        .testTarget(name: "WinglightCoreTests", dependencies: ["WinglightCore"]),
        .testTarget(name: "WinglightAppTests", dependencies: ["Winglight"])
    ],
    swiftLanguageModes: [.v5]
)
