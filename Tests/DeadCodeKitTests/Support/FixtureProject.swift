import DeadCodeKit
import Foundation

/// A fixture project copied into a temporary git repository, so tests never touch the
/// fixtures themselves and git sees the files as tracked.
struct FixtureProject {
  static let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures")

  let root: URL

  /// Copies `Tests/Fixtures/<name>` and stages every file.
  static func copy(_ name: String) throws -> FixtureProject {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("swift-dead-code-tests-\(UUID().uuidString)")
      .appendingPathComponent(name)
    try FileManager.default.createDirectory(
      at: root.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.copyItem(at: fixtures.appendingPathComponent(name), to: root)
    let project = FixtureProject(root: root)
    _ = try project.git(["init", "--quiet"])
    _ = try project.git(["add", "--all"])
    return project
  }

  /// A scratch directory next to the project, for scan and prune output.
  var scratch: URL {
    root.deletingLastPathComponent().appendingPathComponent("work")
  }

  func git(_ arguments: [String]) throws -> String {
    try ProcessRunner().output(of: Command("git", arguments, in: root))
  }

  /// Everything git sees, ignored files included: a command that writes into the project
  /// changes it.
  func status() throws -> String {
    try git(["status", "--porcelain", "--ignored", "--untracked-files=all"])
  }

  func write(_ text: String, to path: String) throws {
    try TextFiles.write(text, to: root.appendingPathComponent(path))
  }

  func read(_ path: String) -> String? {
    TextFiles.read(root.appendingPathComponent(path))
  }

  /// Regenerates the Xcode project from `project.yml` and stages every file.
  func generateXcodeProject() throws {
    _ = try ProcessRunner().output(of: Command("xcodegen", ["generate", "--quiet"], in: root))
    _ = try git(["add", "--all"])
  }

  func load(_ configuration: Configuration = Configuration()) throws -> ProjectModel {
    try ProjectLoader().load(root: root, configuration: configuration)
  }

  func remove() {
    try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
  }

  /// Writes a package at `directory` with one library, named after the directory, whose
  /// target has `source`. `dependencies` are `.package(path:)` paths; the target uses the
  /// library `products` name, each from the package of the same name.
  static func writePackage(
    at directory: URL,
    source: String = "public let value = 1\n",
    dependencies: [String] = [],
    products: [String] = []
  ) throws {
    let name = directory.lastPathComponent
    let packages = dependencies.map { #".package(path: "\#($0)")"# }.joined(separator: ", ")
    let uses = products.map { #".product(name: "\#($0)", package: "\#($0)")"# }
      .joined(separator: ", ")
    try TextFiles.write(
      """
      // swift-tools-version: 6.0
      import PackageDescription

      let package = Package(
        name: "\(name)",
        products: [.library(name: "\(name)", targets: ["\(name)"])],
        dependencies: [\(packages)],
        targets: [.target(name: "\(name)", dependencies: [\(uses)])]
      )

      """,
      to: directory.appendingPathComponent("Package.swift")
    )
    try TextFiles.write(
      source,
      to: directory.appendingPathComponent("Sources/\(name)/\(name).swift")
    )
  }
}

/// External tools some tests need.
enum Tools {
  static let hasPeriphery: Bool = {
    let result = try? ProcessRunner().run(
      Command("periphery", ["version"], in: FileManager.default.temporaryDirectory)
    )
    return result?.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
      == PeripherySettings().version
  }()

  static let hasXcodeGen: Bool = {
    let result = try? ProcessRunner().run(
      Command("xcodegen", ["--version"], in: FileManager.default.temporaryDirectory)
    )
    return result?.succeeded == true
  }()
}
