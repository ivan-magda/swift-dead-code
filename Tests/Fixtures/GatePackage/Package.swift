// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "GatePackage",
  targets: [
    .target(name: "Kit"),
    .target(name: "Spare"),
    .target(name: "App", dependencies: ["Kit", "Spare"], resources: [.process("Media.xcassets")]),
    .testTarget(name: "AppTests", dependencies: ["App"]),
  ]
)
