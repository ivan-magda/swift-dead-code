import Foundation

/// Runs Periphery twice on an indexed build: with tests, and without test code.
///
/// Without tests, a production declaration that only tests use shows up as unused, which is
/// the point of the second scan; its redundant-public notes are noise and are turned off.
public struct PeripheryScanner: Sendable {
  /// Sends Periphery's plan request (it reports the project's line count) to a closed port.
  public static let environment = ["PERIPHERY_API_BASE_URL": "http://127.0.0.1:9/v1"]

  let model: ProjectModel
  let configuration: Configuration
  let runner: any CommandRunning

  public init(
    model: ProjectModel,
    configuration: Configuration,
    runner: any CommandRunning = ProcessRunner()
  ) {
    self.model = model
    self.configuration = configuration
    self.runner = runner
  }

  /// Fails unless `periphery version` is the configured one: triage notes were checked
  /// against it.
  public func checkVersion(in directory: URL) throws {
    let result: CommandResult
    do {
      result = try runner.run(Command("periphery", ["version"], in: directory))
    } catch {
      throw DeadCodeError.usage(
        "periphery not found; install \(configuration.periphery.version) (brew install periphery)"
      )
    }
    let installed = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard result.succeeded, installed == configuration.periphery.version else {
      throw DeadCodeError.usage(
        """
        periphery \(installed.isEmpty ? "(unknown)" : installed) found; the configuration \
        expects \(configuration.periphery.version) (periphery.version in \
        \(configuration.sourcePath)).
        If it came from the old peripheryapp/periphery tap (it stops at 2.21.2), run in this \
        order: brew untap peripheryapp/periphery; brew uninstall --cask periphery; brew \
        install periphery. Uninstalling first fails because the tap's cask no longer loads.
        """
      )
    }
  }

  /// The arguments of both scans, without the scan-specific test exclusion.
  public func commonArguments(build: IndexedBuild, configFile: URL) -> [String] {
    var arguments = ["scan", "--config", configFile.path, "--skip-build"]
    for store in build.indexStores {
      arguments += ["--index-store-path", store.path]
    }
    arguments += ["--disable-update-check", "--quiet", "--relative-results", "--format", "json"]
    arguments += build.projectArguments
    for glob in build.dependencyExcludes {
      arguments += ["--index-exclude", glob]
    }
    for glob in build.generatedExcludes + configuration.exclude.map(\.pattern) {
      arguments += ["--report-exclude", glob]
    }
    if configuration.periphery.retainCodableProperties {
      arguments.append("--retain-codable-properties")
    }
    if configuration.periphery.retainEquatableProperties {
      arguments.append("--retain-equatable-properties")
    }
    if configuration.periphery.retainHashableProperties {
      arguments.append("--retain-hashable-properties")
    }
    if hasObjectiveCSources {
      // Objective-C callers of Swift declarations are invisible to the index.
      arguments.append("--retain-objc-accessible")
    }
    return arguments + configuration.periphery.arguments
  }

  /// The `prod` scan's extra arguments: test code out of the index, no redundant-public notes.
  public func productionArguments() -> [String] {
    var arguments: [String] = []
    for glob in TestCodeExcludes(model: model, configuration: configuration).globs() {
      arguments += ["--index-exclude", glob]
    }
    return arguments + ["--disable-redundant-public-analysis"]
  }

  /// Runs one scan in `directory` and writes its JSON to `output`; errors go to `errors`.
  public func scan(arguments: [String], in directory: URL, output: URL, errors: URL) throws {
    let result = try runner.run(
      Command("periphery", arguments, in: directory, environment: Self.environment)
    )
    try TextFiles.write(result.standardError, to: errors)
    guard result.succeeded else {
      let tail = result.standardError.split(separator: "\n").suffix(20).joined(separator: "\n")
      throw DeadCodeError.failure("Periphery failed, see \(errors.path)\n\(tail)")
    }
    try TextFiles.write(result.standardOutput, to: output)
  }

  /// A configuration file for Periphery, so that a project's own `.periphery.yml` cannot
  /// change the scan (it may set `strict`, `baseline` or `retain_public`).
  public static func writeConfiguration(to url: URL) throws {
    try TextFiles.write(
      "# Written by swift-dead-code; options come from the command line in environment.txt.\n",
      to: url
    )
  }

  var hasObjectiveCSources: Bool {
    model.targets.contains { target in
      target.otherSourceFiles.contains { path in
        SourceLanguages.objectiveCExtensions.contains((path as NSString).pathExtension)
      }
    }
  }
}

/// The smallest set of directory globs that covers test code and no product code: the
/// directories the scan without tests leaves out of the index.
struct TestCodeExcludes {
  let model: ProjectModel
  let configuration: Configuration

  func globs() -> [String] {
    let testTargets = model.targets.filter { $0.role != .product }
    let productTargets = model.targets.filter { $0.role == .product }
    let productFiles = productTargets.flatMap { $0.sourceFiles + $0.otherSourceFiles }
    let productDirectories = Set(productFiles.flatMap(Self.ancestors))
    var globs: Set<String> = []
    for target in testTargets {
      for file in target.sourceFiles + target.otherSourceFiles {
        // The topmost ancestor that holds no product file.
        if let directory = Self.ancestors(of: file).first(where: {
          !productDirectories.contains($0)
        }) {
          globs.insert(directory + "/**")
        } else {
          globs.insert(file)
        }
      }
    }
    globs.formUnion(configuration.testSupportGlobs.map(\.pattern))
    // A glob below another glob adds nothing.
    let sorted = globs.sorted()
    return sorted.filter { glob in
      !sorted.contains { other in
        other != glob && other.hasSuffix("/**") && glob.hasPrefix(String(other.dropLast(2)))
      }
    }
  }

  /// `a/b/c.swift` has the ancestors `a` and `a/b`, outermost first.
  static func ancestors(of path: String) -> [String] {
    let components = path.split(separator: "/").dropLast()
    return components.indices.map { index in
      components[...index].joined(separator: "/")
    }
  }
}
