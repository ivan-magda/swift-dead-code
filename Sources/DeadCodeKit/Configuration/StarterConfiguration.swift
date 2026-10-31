import Foundation

/// The `.deadcode.yml` that `init` prints: the detected project, schemes, likely test-support
/// targets and contract documents, with every other field at its default.
public struct StarterConfiguration: Sendable {
  /// Target names that usually hold shared test helpers rather than product code.
  static let testSupportMarkers = [
    "TestSupport", "TestUtilities", "TestHelpers", "TestKit", "Mocks",
  ]
  static let contractDocuments = [
    "AGENTS.md", "CLAUDE.md", "docs/ARCHITECTURE.md", "ARCHITECTURE.md", "docs/TESTING.md",
  ]

  let model: ProjectModel

  public init(model: ProjectModel) {
    self.model = model
  }

  public func text() -> String {
    var lines = [
      "# swift-dead-code configuration. Every field is optional; the tool's README lists them."
    ]
    switch model.kind {
    case .swiftPackage:
      lines += ["project:", "  kind: swiftpm"]
    case .xcode(let container):
      let schemes = Self.sharedSchemes(in: model.root.appendingPathComponent(container))
      lines += [
        "project:",
        "  kind: xcode",
        "  path: \(container)",
        "  # Shared schemes: \(schemes.isEmpty ? "none found" : schemes.joined(separator: ", "))",
        "  schemes: [\(schemes.prefix(1).joined())]",
        "  destination: \"\(ProjectBuilder.defaultDestination)\"",
      ]
    }
    let support = model.targets.filter { target in
      target.role != .test
        && Self.testSupportMarkers.contains { target.name.contains($0) }
    }
    lines += [
      "",
      "# Targets that hold shared test code besides the test targets.",
      "test_support: [\(support.map(\.name).joined(separator: ", "))]",
      "",
      "# Generated or vendored code no check reports on.",
      "exclude: []",
      "",
      "# Findings kept on purpose, each with a reason:",
      "#   - file: docs/diagram.png",
      "#     reason: linked from the wiki",
      "allowlist: []",
      "",
      "periphery:",
      "  version: \(PeripherySettings().version)",
      "  baseline: \(PeripherySettings().baseline)",
    ]
    if model.kind == .swiftPackage, model.targets.contains(where: { $0.productType == .library }) {
      lines += [
        "  # A library whose public API others use: public declarations count as used.",
        "  # arguments: [--retain-public]",
      ]
    }
    let documents = Self.contractDocuments.filter { path in
      FileManager.default.fileExists(atPath: model.root.appendingPathComponent(path).path)
    }
    lines += [
      "",
      "# Documents that describe the project's contracts, for the triage.",
      "docs:",
      "  contracts: [\(documents.joined(separator: ", "))]",
    ]
    return lines.joined(separator: "\n") + "\n"
  }

  static func sharedSchemes(in container: URL) -> [String] {
    var directories = [container.appendingPathComponent("xcshareddata/xcschemes")]
    if container.pathExtension == "xcworkspace" {
      let parent = container.deletingLastPathComponent()
      let entries = (try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []
      directories += entries.filter { $0.hasSuffix(".xcodeproj") }
        .map { parent.appendingPathComponent($0).appendingPathComponent("xcshareddata/xcschemes") }
    }
    return directories.flatMap { directory in
      ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
        .filter { $0.hasSuffix(".xcscheme") }
        .map { ($0 as NSString).deletingPathExtension }
    }
    .sorted()
  }
}
