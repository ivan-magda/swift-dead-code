// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "swift-dead-code",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "swift-dead-code", targets: ["swift-dead-code"]),
    .library(name: "DeadCodeKit", targets: ["DeadCodeKit"]),
    .plugin(name: "DeadCodeCommand", targets: ["DeadCodeCommand"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.0"),
    .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "604.0.0"),
    .package(url: "https://github.com/tuist/XcodeProj.git", from: "9.17.0"),
    .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.0"),
  ],
  targets: [
    .target(
      name: "DeadCodeKit",
      dependencies: [
        .product(name: "SwiftParser", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "XcodeProj", package: "XcodeProj"),
        .product(name: "Yams", package: "Yams"),
      ]
    ),
    .executableTarget(
      name: "swift-dead-code",
      dependencies: [
        "DeadCodeKit",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),
    .plugin(
      name: "DeadCodeCommand",
      capability: .command(
        intent: .custom(
          verb: "dead-code",
          description: "Find dead code: check, scan, triage, baseline, prune-imports"
        )
      ),
      dependencies: ["swift-dead-code"]
    ),
    .testTarget(
      name: "DeadCodeKitTests",
      dependencies: ["DeadCodeKit"]
    ),
  ]
)

for target in package.targets where target.type != .plugin {
  target.swiftSettings =
    (target.swiftSettings ?? []) + [.enableUpcomingFeature("MemberImportVisibility")]
}
