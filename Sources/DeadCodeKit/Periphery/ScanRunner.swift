import Foundation

/// `scan`: copy the project, build it with an index store, run Periphery with and without
/// tests, and write the triage report.
///
/// Everything goes under the output directory: `source/` (the copy), `build/` or
/// `DerivedData/`, `all.json`, `prod.json`, their `.err` logs, `report.md` and
/// `environment.txt`. The working tree is only read.
public struct ScanRunner: Sendable {
  public static let lockName = "swift-dead-code-build.lock"

  let model: ProjectModel
  let configuration: Configuration
  let runner: any CommandRunning
  let lockName: String

  /// `lockName` names the machine-wide build lock; tests pass their own.
  public init(
    model: ProjectModel,
    configuration: Configuration,
    runner: any CommandRunning = ProcessRunner(),
    lockName: String = ScanRunner.lockName
  ) {
    self.model = model
    self.configuration = configuration
    self.runner = runner
    self.lockName = lockName
  }

  /// Runs the scan into `output` and returns the report's path.
  @discardableResult
  public func run(output: URL, skipBuild: Bool, progress: (String) -> Void) throws -> URL {
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let report = output.appendingPathComponent("report.md")
    // The directory is reused across runs, so a failed run must not leave an old report.
    try? FileManager.default.removeItem(at: report)

    let scanner = PeripheryScanner(model: model, configuration: configuration, runner: runner)
    try scanner.checkVersion(in: model.root)
    let lock = try FileLock(name: lockName) {
      progress("another swift-dead-code build is running; waiting for it")
    }
    defer {
      withExtendedLifetime(lock) {}
    }

    let copy = output.appendingPathComponent("source")
    if !skipBuild {
      progress("copying the project into \(copy.path)")
      try WorkingCopy(source: model.root, copy: copy, runner: runner).refresh()
    }
    let build = try ProjectBuilder(model: model, configuration: configuration, runner: runner)
      .build(copy: copy, work: output, skipBuild: skipBuild, progress: progress)

    let configFile = output.appendingPathComponent("periphery.yml")
    try PeripheryScanner.writeConfiguration(to: configFile)
    if FileManager.default.fileExists(
      atPath: model.root.appendingPathComponent(".periphery.yml").path
    ) {
      progress(
        ".periphery.yml is ignored: put its options in periphery.arguments in "
          + configuration.sourcePath
      )
    }
    let common = scanner.commonArguments(build: build, configFile: configFile)
    progress("Periphery, tests included")
    try scanner.scan(
      arguments: common,
      in: copy,
      output: output.appendingPathComponent("all.json"),
      errors: output.appendingPathComponent("all.err")
    )
    progress("Periphery, test code excluded")
    try scanner.scan(
      arguments: common + scanner.productionArguments(),
      in: copy,
      output: output.appendingPathComponent("prod.json"),
      errors: output.appendingPathComponent("prod.err")
    )
    try TextFiles.write(environment(), to: output.appendingPathComponent("environment.txt"))

    let triage = TriageReport(
      all: try PeripheryFinding.read(output.appendingPathComponent("all.json")),
      production: try PeripheryFinding.read(output.appendingPathComponent("prod.json")),
      model: model,
      configuration: configuration,
      sourceRoot: copy
    )
    try TextFiles.write(triage.render(), to: report)
    return report
  }
}

// MARK: - Environment

private extension ScanRunner {
  /// The tool versions the scan depends on: results hold only for these.
  func environment() -> String {
    let commands: [(String, [String])] = [
      ("swift", ["--version"]),
      ("periphery", ["version"]),
      ("xcodebuild", ["-version"]),
    ]
    return commands.map { executable, arguments in
      let result = try? runner.run(Command(executable, arguments, in: model.root))
      let text = (result?.standardOutput ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      return "$ \(executable) \(arguments.joined(separator: " "))\n\(text)"
    }
    .joined(separator: "\n") + "\n"
  }
}
