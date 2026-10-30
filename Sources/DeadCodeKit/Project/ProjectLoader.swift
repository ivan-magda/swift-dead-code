import Foundation

/// Finds the project at a root and loads it with the matching adapter.
public struct ProjectLoader: Sendable {
  let runner: any CommandRunning

  public init(runner: any CommandRunning = ProcessRunner()) {
    self.runner = runner
  }

  public func load(root: URL, configuration: Configuration) throws -> ProjectModel {
    guard Git(directory: root, runner: runner).isRepository() else {
      throw DeadCodeError.usage("\(root.path) is not inside a git work tree")
    }
    let kind = try Self.detect(root: root, settings: configuration.project)
    let fileManager = FileManager.default
    if case .xcode = kind,
      fileManager.fileExists(atPath: root.appendingPathComponent("Podfile").path),
      !fileManager.fileExists(atPath: root.appendingPathComponent("Pods").path)
    {
      throw DeadCodeError.usage("Podfile without Pods/: run `pod install` first")
    }
    switch kind {
    case .swiftPackage:
      return try SwiftPackageAdapter(runner: runner)
        .load(packageRoot: root, configuration: configuration)
    case .xcode(let container):
      return try XcodeProjectAdapter(runner: runner)
        .load(root: root, containerPath: container, configuration: configuration)
    }
  }

  /// The kind of project at `root`: the configured one, or the only one found there.
  public static func detect(root: URL, settings: ProjectSettings) throws -> ProjectModel.Kind {
    let entries =
      (try? FileManager.default.contentsOfDirectory(atPath: root.path))?.sorted() ?? []
    let workspaces = entries.filter { $0.hasSuffix(".xcworkspace") }
    let projects = entries.filter { $0.hasSuffix(".xcodeproj") }
    let hasManifest = entries.contains("Package.swift")

    if let path = settings.path {
      guard FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path) else {
        throw DeadCodeError.usage("project.path \(path) does not exist")
      }
      return path.hasSuffix("Package.swift") || path == "."
        ? .swiftPackage : .xcode(container: path)
    }
    switch settings.kind {
    case .swiftpm:
      guard hasManifest else {
        throw DeadCodeError.usage("project.kind is swiftpm, but \(root.path) has no Package.swift")
      }
      return .swiftPackage
    case .xcode, .auto:
      if let container = workspaces.count == 1 ? workspaces.first : nil {
        return .xcode(container: container)
      }
      if workspaces.isEmpty, projects.count == 1, let container = projects.first {
        return .xcode(container: container)
      }
      if workspaces.count + projects.count > 1 {
        let found = (workspaces + projects).joined(separator: ", ")
        throw DeadCodeError.usage(
          "several Xcode containers (\(found)); set project.path in \(Configuration.fileName)"
        )
      }
      if settings.kind == .auto, hasManifest {
        return .swiftPackage
      }
      if entries.contains("project.yml") || entries.contains("Project.swift") {
        throw DeadCodeError.usage(
          "no .xcodeproj yet: run `xcodegen generate` (project.yml) or `tuist generate` "
            + "(Project.swift) first; the tool never writes into the working tree"
        )
      }
      throw DeadCodeError.usage("no Package.swift, .xcworkspace or .xcodeproj in \(root.path)")
    }
  }
}
