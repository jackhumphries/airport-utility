// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "AirPortUtility",
  defaultLocalization: "en",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(name: "AirPort Utility", targets: ["AirPortUtilityApp"]),
    // Exposed as a product so AirPortUtility.xcodeproj can depend on it as a
    // local package product. Xcode can only link products, not bare targets,
    // and this keeps the app target from having to duplicate the source list.
    .library(name: "AirPortUtilityCore", targets: ["AirPortUtilityCore"]),
  ],
  targets: [
    .target(
      name: "AirPortUtilityCore",
      path: "Sources/AirPortUtilityCore",
      resources: [
        .process("Resources")
      ]
    ),
    .executableTarget(
      name: "AirPortUtilityApp",
      dependencies: ["AirPortUtilityCore"],
      path: "Sources/AirPortUtilityApp"
    ),
    .testTarget(
      name: "AirPortUtilityAppTests",
      dependencies: ["AirPortUtilityCore"],
      path: "Tests/AirPortUtilityAppTests"
    ),
  ]
)
