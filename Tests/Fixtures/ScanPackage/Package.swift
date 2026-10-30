// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ScanPackage",
  platforms: [.macOS(.v14)],
  targets: [
    .target(name: "Helper"),
    .target(name: "Lib", dependencies: ["Helper"]),
    .testTarget(name: "LibTests", dependencies: ["Lib"]),
  ]
)
