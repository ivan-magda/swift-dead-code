// swift-tools-version:5.0
import PackageDescription

// Before tools version 5.4, an executable's target is a regular one, and a dependency's
// product is named like a target.
let package = Package(
    name: "Legacy",
    products: [
        .executable(name: "legacy", targets: ["Tool"]),
    ],
    dependencies: [
        .package(url: "https://example.invalid/Kit.git", from: "1.0.0"),
    ],
    targets: [
        .target(name: "Tool", dependencies: ["Core", "Kit"]),
        .target(name: "Core"),
    ]
)
