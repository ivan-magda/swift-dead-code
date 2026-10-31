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

    let configFile = try writePeripheryConfiguration(in: output, progress: progress)
    let common = scanner.commonArguments(build: build, configFile: configFile)
    let production = common + scanner.productionArguments()
    progress("Periphery, tests included")
    try scanner.scan(
      arguments: common,
      in: copy,
      output: output.appendingPathComponent("all.json"),
      errors: output.appendingPathComponent("all.err")
    )
    progress("Periphery, test code excluded")
    try scanner.scan(
      arguments: production,
      in: copy,
      output: output.appendingPathComponent("prod.json"),
      errors: output.appendingPathComponent("prod.err")
    )
    var scans = [("tests included", common), ("test code excluded", production)]
    if build.storesByBuild.count > 1 {
      scans += try confirmByBuild(
        build,
        scanner: scanner,
        paths: ScanPaths(output: output, copy: copy, configFile: configFile),
        progress: progress
      )
    }
    try TextFiles.write(
      environment(scans: scans),
      to: output.appendingPathComponent("environment.txt")
    )

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

// MARK: - Builds Scanned One by One

/// Where a scan writes: its output directory, the project's working copy, Periphery's
/// configuration.
private struct ScanPaths {
  var output: URL
  var copy: URL
  var configFile: URL
}

private extension ScanRunner {
  /// Writes Periphery's configuration, so a project's own `.periphery.yml` cannot apply.
  func writePeripheryConfiguration(in output: URL, progress: (String) -> Void) throws -> URL {
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
    return configFile
  }

  /// Scans each build's own index store into `<output>/<build>/`, then keeps in `all.json` and
  /// `prod.json` only the findings the builds confirm; the combined results stay in
  /// `all-combined.json` and `prod-combined.json`. Returns the command lines it ran.
  func confirmByBuild(
    _ build: IndexedBuild,
    scanner: PeripheryScanner,
    paths: ScanPaths,
    progress: (String) -> Void
  ) throws -> [(String, [String])] {
    let (output, copy, configFile) = (paths.output, paths.copy, paths.configFile)
    var commands: [(String, [String])] = []
    var allByBuild: [String: [PeripheryFinding]] = [:]
    var productionByBuild: [String: [PeripheryFinding]] = [:]
    for (name, store) in build.storesByBuild.sorted(by: { $0.key < $1.key }) {
      var single = build
      single.indexStores = [store]
      let directory = output.appendingPathComponent(name)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let common = scanner.commonArguments(build: single, configFile: configFile)
      let production = common + scanner.productionArguments()
      progress("Periphery, build \(name) alone")
      for (file, arguments) in [("all", common), ("prod", production)] {
        try scanner.scan(
          arguments: arguments,
          in: copy,
          output: directory.appendingPathComponent("\(file).json"),
          errors: directory.appendingPathComponent("\(file).err")
        )
      }
      allByBuild[name] = try PeripheryFinding.read(directory.appendingPathComponent("all.json"))
      productionByBuild[name] = try PeripheryFinding.read(
        directory.appendingPathComponent("prod.json")
      )
      commands += [
        ("build \(name), tests included", common),
        ("build \(name), test code excluded", production),
      ]
    }
    var combined: [String: [PeripheryFinding]] = [:]
    for file in ["all", "prod"] {
      let combinedCopy = output.appendingPathComponent("\(file)-combined.json")
      try? FileManager.default.removeItem(at: combinedCopy)
      try FileManager.default.copyItem(
        at: output.appendingPathComponent("\(file).json"),
        to: combinedCopy
      )
      combined[file] = try PeripheryFinding.read(combinedCopy)
    }
    let usrs = Set(combined.values.joined().flatMap(\.ids))
    var seen: [String: Set<String>] = [:]
    for (name, store) in build.storesByBuild {
      seen[name] = try IndexStoreSymbols(store: store).seen(among: usrs)
    }
    for (file, byBuild) in [("all", allByBuild), ("prod", productionByBuild)] {
      let findings = combined[file] ?? []
      let kept = BuildConfirmation().confirmed(findings, byBuild: byBuild, seen: seen)
      try Self.writeFindings(
        from: output.appendingPathComponent("\(file)-combined.json"),
        keeping: Set(kept.map(BuildConfirmation.key)),
        to: output.appendingPathComponent("\(file).json")
      )
      progress(
        "\(file).json: \(findings.count - kept.count) of \(findings.count) findings dropped: no "
          + "build alone confirms them (targets share a module name)"
      )
    }
    return commands
  }

  /// Copies Periphery's JSON objects whose findings `keys` names, so every field survives.
  static func writeFindings(
    from source: URL,
    keeping keys: Set<String>,
    to destination: URL
  )
    throws
  {
    let data = try Data(contentsOf: source)
    guard let objects = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
      throw DeadCodeError.failure("\(source.path) is not a Periphery JSON array")
    }
    let kept = objects.filter { object in
      let fields = ["location", "kind", "name"].map { object[$0] as? String ?? "" }
      return keys.contains(fields.joined(separator: " "))
    }
    let output = try JSONSerialization.data(
      withJSONObject: kept,
      options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    )
    try output.write(to: destination)
  }
}

// MARK: - Environment

private extension ScanRunner {
  /// The tool versions the scan depends on, for which alone the results hold, and the
  /// Periphery command lines it ran.
  func environment(scans: [(label: String, arguments: [String])]) -> String {
    let commands: [(String, [String])] = [
      ("swift", ["--version"]),
      ("periphery", ["version"]),
      ("xcodebuild", ["-version"]),
    ]
    let versions =
      commands.map { executable, arguments in
        let result = try? runner.run(Command(executable, arguments, in: model.root))
        let text = (result?.standardOutput ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return "$ \(executable) \(arguments.joined(separator: " "))\n\(text)"
      }
      .joined(separator: "\n") + "\n"
    let runs = scans.map { label, arguments in
      "# Periphery, \(label)\n$ periphery \(arguments.joined(separator: " "))\n"
    }
    return versions + runs.joined()
  }
}
