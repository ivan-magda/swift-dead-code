import Foundation

/// The project model in a form people and tools read: what `describe` prints.
public struct ProjectDescription: Sendable {
  let model: ProjectModel
  let configuration: Configuration

  public init(model: ProjectModel, configuration: Configuration) {
    self.model = model
    self.configuration = configuration
  }

  public func text() -> String {
    var lines: [String] = []
    switch model.kind {
    case .swiftPackage:
      lines.append("project: swiftpm (Package.swift)")
    case .xcode(let container):
      lines.append("project: xcode (\(container))")
    }
    let tests = model.targets.filter { $0.role == .test }.count
    let support = model.targets.filter { $0.role == .testSupport }.count
    lines.append(
      "targets: \(model.targets.count) (\(tests) test, \(support) test support)"
    )
    for target in model.targets {
      var summary =
        "  \(target.name) [\(target.role.rawValue), \(target.productType.rawValue)]"
        + " module \(target.moduleName), \(target.sourceFiles.count) Swift files"
      if !target.otherSourceFiles.isEmpty {
        summary += ", \(target.otherSourceFiles.count) other sources"
      }
      lines.append(summary)
      if !target.dependencies.isEmpty {
        let dependencies = target.dependencies.map { "\($0.name) (\($0.kind.rawValue))" }
          .sorted()
          .joined(separator: ", ")
        lines.append("    depends on: \(dependencies)")
      }
    }
    let external = model.externalModules.sorted().joined(separator: ", ")
    lines.append("external modules: \(external.isEmpty ? "none" : external)")
    let mixed = model.targets.filter { target in
      target.otherSourceFiles.contains { path in
        SourceLanguages.objectiveCExtensions.contains((path as NSString).pathExtension)
      }
    }
    if !mixed.isEmpty {
      lines.append(
        "Objective-C sources in: \(mixed.map(\.name).joined(separator: ", ")); "
          + "scans retain @objc declarations there"
      )
    }
    return lines.joined(separator: "\n")
  }

  public func json() throws -> String {
    struct Target: Encodable {
      var name: String
      var module: String
      var role: String
      var productType: String
      var swiftFiles: Int
      var otherSourceFiles: Int
      var dependencies: [String]
    }
    struct Description: Encodable {
      var kind: String
      var container: String?
      var targets: [Target]
      var externalModules: [String]
    }
    let kind: String
    let container: String?
    switch model.kind {
    case .swiftPackage:
      kind = "swiftpm"
      container = nil
    case .xcode(let path):
      kind = "xcode"
      container = path
    }
    let description = Description(
      kind: kind,
      container: container,
      targets: model.targets.map { target in
        Target(
          name: target.name,
          module: target.moduleName,
          role: target.role.rawValue,
          productType: target.productType.rawValue,
          swiftFiles: target.sourceFiles.count,
          otherSourceFiles: target.otherSourceFiles.count,
          dependencies: target.dependencies.map(\.name).sorted()
        )
      },
      externalModules: model.externalModules.sorted()
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return String(bytes: try encoder.encode(description), encoding: .utf8) ?? "{}"
  }
}
