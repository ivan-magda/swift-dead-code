import Foundation
import PathKit
import XcodeProj

/// A copy of the project where imports are removed and the result is built.
///
/// The working tree is never written: sources, manifests and project files change only in
/// `work/copy`, and the result leaves as `work/prune.patch`.
final class PruneWorkspace {
  static let compilerError = try? NSRegularExpression(
    pattern: #"^(/[^:\n]+\.swift):(\d+):\d+: error: (.*)$"#,
    options: [.anchorsMatchLines]
  )
  /// A target in the dependency graph xcodebuild prints before it builds.
  static let graphTarget = try? NSRegularExpression(
    pattern: #"^ {4}Target '([^']+)' in project '"#,
    options: [.anchorsMatchLines]
  )

  let model: ProjectModel
  let configuration: Configuration
  let work: URL
  let copy: URL
  let runner: any CommandRunning
  /// The checked files' original lines, with their line endings, by path.
  let originalLines: [String: [String]]
  /// The latest build's log.
  private(set) var log: URL
  /// The targets the latest Xcode build covered, from its target dependency graph.
  private var builtTargets: Set<String> = []
  private var originalProjectFiles: [String: String] = [:]

  init(
    model: ProjectModel,
    configuration: Configuration,
    work: URL,
    files: [String],
    runner: any CommandRunning
  ) throws {
    self.model = model
    self.configuration = configuration
    self.work = work
    self.copy = work.appendingPathComponent("copy")
    self.runner = runner
    self.log = work.appendingPathComponent("build.log")
    var lines: [String: [String]] = [:]
    for path in files {
      guard let text = TextFiles.read(model.root.appendingPathComponent(path)) else {
        throw DeadCodeError.usage("cannot read \(path)")
      }
      lines[path] = Self.linesKeepingEndings(text)
    }
    originalLines = lines
    try WorkingCopy(source: model.root, copy: copy, runner: runner).refresh()
  }

  /// Writes every checked file into the copy without the removed import lines.
  func writeSources(removing removed: Set<ImportLine>) throws {
    for (path, lines) in originalLines {
      let text = linesWithout(removed, in: path, lines: lines).joined()
      try TextFiles.write(text, to: copy.appendingPathComponent(path))
    }
  }

  /// Restores the copy's manifests and project files, then makes `strictTargets` build with
  /// MemberImportVisibility.
  func writeStrictness(for strictTargets: Set<String>) throws {
    for (path, text) in originalProjectFiles {
      try TextFiles.write(text, to: copy.appendingPathComponent(path))
    }
    var packageTargets: [String: [String]] = [:]
    for name in strictTargets.sorted() {
      guard let target = model.target(named: name) else {
        continue
      }
      if target.manifestPath.hasSuffix("Package.swift") {
        packageTargets[target.manifestPath, default: []].append(name)
      } else {
        try setStrictBuildSetting(project: target.manifestPath, target: name)
      }
    }
    for (manifest, names) in packageTargets {
      try appendStrictSuffix(manifest: manifest, targets: names)
    }
  }

  /// The unified diff that removes the import lines from the project.
  func patch(removing removed: Set<ImportLine>) -> String {
    originalLines.keys.sorted()
      .map { path in
        let numbers = Set(removed.filter { $0.path == path }.map(\.line))
        return UnifiedDiff.removing(numbers, from: originalLines[path] ?? [], path: path)
      }
      .joined()
  }

  /// Builds the copy: the whole project with tests, or one target. Returns whether it
  /// succeeded and the compiler errors by file. A failure without any file error stops the
  /// run, because the pruner could not tell which import caused it.
  func build(target: String? = nil) throws -> (succeeded: Bool, errors: [String: Set<String>]) {
    let result: CommandResult
    switch model.kind {
    case .swiftPackage:
      result = try buildPackage(target: target)
    case .xcode(let container):
      result = try buildXcode(container: container, target: target)
    }
    let output = TextFiles.strippingTerminalEscapes(result.standardOutput + result.standardError)
    try TextFiles.write(output, to: log)
    if case .xcode = model.kind {
      builtTargets = Self.targetsInDependencyGraph(output)
    }
    let errors = errorsByFile(output)
    if !result.succeeded && errors.isEmpty {
      throw DeadCodeError.failure("build failed without file-level errors; see \(log.path)")
    }
    return (result.succeeded, errors)
  }

  /// Whether the latest build compiled `target`: a package's build compiles every target, a
  /// scheme only its own and their dependencies.
  func built(_ target: String) -> Bool {
    model.kind == .swiftPackage || builtTargets.contains(target)
  }

  /// Whether the latest build compiled `path` in every target that compiles it.
  func compiledEverywhere(_ path: String) -> Bool {
    model.owningTargets(of: path).allSatisfy(built)
  }

  /// The targets an xcodebuild log lists in its target dependency graph.
  static func targetsInDependencyGraph(_ output: String) -> Set<String> {
    guard let expression = graphTarget else {
      return []
    }
    let matches = expression.matches(in: output, range: NSRange(output.startIndex..., in: output))
    return Set(
      matches.compactMap { match in
        Range(match.range(at: 1), in: output).map { String(output[$0]) }
      }
    )
  }
}

// MARK: - Sources

private extension PruneWorkspace {
  static func linesKeepingEndings(_ text: String) -> [String] {
    var lines: [String] = []
    var current = ""
    for character in text {
      current.append(character)
      if character == "\n" || character == "\r\n" {
        lines.append(current)
        current = ""
      }
    }
    if !current.isEmpty {
      lines.append(current)
    }
    return lines
  }

  func linesWithout(_ removed: Set<ImportLine>, in path: String, lines: [String]) -> [String] {
    let dropped = Set(removed.filter { $0.path == path }.map(\.line))
    return lines.enumerated()
      .filter { !dropped.contains($0.offset + 1) }
      .map(\.element)
  }

  func errorsByFile(_ output: String) -> [String: Set<String>] {
    guard let expression = Self.compilerError else {
      return [:]
    }
    var errors: [String: Set<String>] = [:]
    let range = NSRange(output.startIndex..., in: output)
    for match in expression.matches(in: output, range: range) {
      guard let pathRange = Range(match.range(at: 1), in: output),
        let messageRange = Range(match.range(at: 3), in: output)
      else {
        continue
      }
      let absolute = URL(fileURLWithPath: String(output[pathRange]))
      let path =
        TextFiles.relativePath(of: absolute, under: copy)
        ?? TextFiles.relativePath(of: absolute, under: model.root)
        ?? absolute.path
      errors[path, default: []].insert(String(output[messageRange]))
    }
    return errors
  }
}

// MARK: - Strictness

private extension PruneWorkspace {
  /// Appended to the copy's manifest to build some targets with MemberImportVisibility.
  func appendStrictSuffix(manifest: String, targets: [String]) throws {
    let url = copy.appendingPathComponent(manifest)
    let original = try rememberOriginal(manifest)
    let names = targets.sorted().map { "\"\($0)\"" }.joined(separator: ", ")
    let suffix = """

      for target in package.targets where [\(names)].contains(target.name) {
        target.swiftSettings =
          (target.swiftSettings ?? []) + [.enableUpcomingFeature("MemberImportVisibility")]
      }

      """
    try TextFiles.write(original + suffix, to: url)
  }

  func setStrictBuildSetting(project manifest: String, target name: String) throws {
    let projectDirectory = (manifest as NSString).deletingLastPathComponent
    _ = try rememberOriginal(manifest)
    let path = Path(copy.appendingPathComponent(projectDirectory).path)
    let project = try XcodeProj(path: path)
    for target in project.pbxproj.nativeTargets where target.name == name {
      for configuration in target.buildConfigurationList?.buildConfigurations ?? [] {
        configuration.buildSettings["SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY"] =
          .string("YES")
      }
    }
    try project.pbxproj.write(path: path + "project.pbxproj", override: true)
  }

  func rememberOriginal(_ path: String) throws -> String {
    if let text = originalProjectFiles[path] {
      return text
    }
    guard let text = TextFiles.read(model.root.appendingPathComponent(path)) else {
      throw DeadCodeError.usage("cannot read \(path)")
    }
    originalProjectFiles[path] = text
    return text
  }
}

// MARK: - Builds

private extension PruneWorkspace {
  /// Builds every configured build; an import one of them needs stays.
  func buildPackage(target: String?) throws -> CommandResult {
    var arguments: [String]
    if let target {
      // The native build system with -continue-building-after-errors reports every failing
      // file; the default backend cancels a target's remaining batches after the first one.
      arguments = ["build", "--build-system", "native", "--target", target]
      arguments += ["--scratch-path", work.appendingPathComponent("build-native").path]
      arguments += ["-Xswiftc", "-continue-building-after-errors"]
      log = work.appendingPathComponent("build-\(target).log")
    } else {
      arguments = ["build", "--build-tests"]
      arguments += ["--scratch-path", work.appendingPathComponent("build").path]
      log = work.appendingPathComponent("build.log")
    }
    var combined = CommandResult(status: 0, standardOutput: "", standardError: "")
    let builder = ProjectBuilder(model: model, configuration: configuration, runner: runner)
    for variant in builder.variants {
      let variantArguments = configuration.project.buildArguments + variant.buildArguments
      combined.append(try runner.run(Command("swift", arguments + variantArguments, in: copy)))
    }
    return combined
  }

  /// Builds every configured scheme; an import a scheme needs stays.
  func buildXcode(container: String, target: String?) throws -> CommandResult {
    let builder = ProjectBuilder(model: model, configuration: configuration, runner: runner)
    log = work.appendingPathComponent(target.map { "build-\($0).log" } ?? "build.log")
    var combined = CommandResult(status: 0, standardOutput: "", standardError: "")
    for variant in builder.variants {
      for scheme in try builder.schemes(of: variant, container: container) {
        let arguments =
          builder.xcodebuildArguments(
            scheme: scheme,
            variant: variant,
            container: container,
            derivedData: work.appendingPathComponent("DerivedData")
          )
          + ["OTHER_SWIFT_FLAGS=$(inherited) -continue-building-after-errors"]
        combined.append(
          try builder.runScheme(arguments: arguments, forTesting: variant.forTesting, in: copy)
        )
      }
    }
    return combined
  }
}
