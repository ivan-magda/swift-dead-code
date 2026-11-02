import Foundation

/// Where an indexed build left its index store, and how Periphery should read it.
public struct IndexedBuild: Sendable, Equatable {
  public var indexStores: [URL]
  /// Each build's own index store, when the builds do not share one (see
  /// `ProjectModel.hasModuleTwins`); empty otherwise.
  public var storesByBuild: [String: URL] = [:]
  /// `--index-exclude` globs for dependency sources, which would otherwise be scanned.
  public var dependencyExcludes: [String]
  /// `--report-exclude` globs for sources outside the project that stay indexed: what a build
  /// generates, and local packages beside the project, whose calls into it count.
  public var generatedExcludes: [String]
  /// The options that tell Periphery which project the index belongs to.
  public var projectArguments: [String]
}

/// Builds the project in its working copy with an index store, for SwiftPM or Xcode.
public struct ProjectBuilder: Sendable {
  public static let defaultDestination = "generic/platform=iOS Simulator"

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

  /// Builds the copy at `copy` into `work`, or with `skipBuild` only locates the previous
  /// build's index store.
  public func build(
    copy: URL,
    work: URL,
    skipBuild: Bool,
    progress: (String) -> Void
  ) throws
    -> IndexedBuild
  {
    switch model.kind {
    case .swiftPackage:
      return try buildPackage(copy: copy, work: work, skipBuild: skipBuild, progress: progress)
    case .xcode(let container):
      return try buildXcode(
        container: container,
        copy: copy,
        work: work,
        skipBuild: skipBuild,
        progress: progress
      )
    }
  }

  /// The arguments of one xcodebuild run, without the action: container, scheme,
  /// configuration, destination, DerivedData, no code signing, and the configured extras.
  public func xcodebuildArguments(
    scheme: String,
    variant: BuildVariant,
    container: String,
    derivedData: URL
  ) -> [String] {
    let containerFlag = container.hasSuffix(".xcworkspace") ? "-workspace" : "-project"
    var arguments = [containerFlag, container, "-scheme", scheme]
    if let buildConfiguration = variant.configuration ?? configuration.project.configuration {
      arguments += ["-configuration", buildConfiguration]
    }
    let destination =
      variant.destination ?? configuration.project.destination ?? Self.defaultDestination
    arguments += [
      "-destination", destination,
      "-derivedDataPath", derivedData.path,
      "CODE_SIGNING_ALLOWED=NO",
    ]
    return arguments + configuration.project.buildArguments + variant.buildArguments
  }

  /// The schemes a build runs: its own, the project's, or the only shared scheme.
  public func schemes(of variant: BuildVariant, container: String) throws -> [String] {
    try resolvedSchemes(variant, container: container)
  }

  /// The builds to run: the configured ones, or one with only the project settings.
  public var variants: [BuildVariant] {
    configuration.builds.isEmpty ? [BuildVariant(name: "default")] : configuration.builds
  }
}

// MARK: - SwiftPM

private extension ProjectBuilder {
  func buildPackage(
    copy: URL,
    work: URL,
    skipBuild: Bool,
    progress: (String) -> Void
  ) throws
    -> IndexedBuild
  {
    let scratch = work.appendingPathComponent("build")
    if !skipBuild {
      progress("building the package and its tests with an index store")
      for variant in variants {
        let arguments =
          ["build", "--build-tests", "--scratch-path", scratch.path]
          + configuration.project.buildArguments + variant.buildArguments
        try runBuild(
          Command("swift", arguments, in: copy),
          log: work.appendingPathComponent("build.log")
        )
      }
    }
    // Periphery would run `swift package describe` in the project; hand it the description.
    let description = try runner.output(
      of: Command(
        "swift",
        ["package", "--scratch-path", scratch.path, "describe", "--type", "json"],
        in: copy
      )
    )
    let manifest = work.appendingPathComponent("package.json")
    try TextFiles.write(description, to: manifest)

    // The Swift Build backend writes the store to out/, the native one under debug/.
    let candidates = [
      scratch.appendingPathComponent("out"),
      scratch.appendingPathComponent("debug/index/store"),
    ]
    let stores = candidates.filter { store in
      FileManager.default.fileExists(atPath: store.appendingPathComponent("v5/units").path)
    }
    guard let store = stores.first else {
      throw DeadCodeError.failure(
        "no index store in \(scratch.path); find where swift build now writes it"
      )
    }
    return IndexedBuild(
      indexStores: [store],
      dependencyExcludes: [scratch.appendingPathComponent("checkouts").path + "/**"],
      generatedExcludes: [scratch.path + "/**"],
      projectArguments: ["--json-package-manifest-path", manifest.path]
    )
  }
}

// MARK: - Xcode

private extension ProjectBuilder {
  func buildXcode(
    container: String,
    copy: URL,
    work: URL,
    skipBuild: Bool,
    progress: (String) -> Void
  ) throws -> IndexedBuild {
    // Targets that share a module name merge in one index, so each build then gets its own.
    let separate = variants.count > 1 && model.hasModuleTwins
    var derivedDataByBuild: [String: URL] = [:]
    var schemes: [String] = []
    for variant in variants {
      let derivedData = work.appendingPathComponent(
        separate ? "DerivedData-\(Self.fileName(variant.name))" : "DerivedData"
      )
      derivedDataByBuild[variant.name] = derivedData
      let variantSchemes = try resolvedSchemes(variant, container: container)
      schemes += variantSchemes.filter { !schemes.contains($0) }
      guard !skipBuild else {
        continue
      }
      for scheme in variantSchemes {
        progress("building scheme \(scheme) (\(variant.name)) with an index store")
        let arguments = xcodebuildArguments(
          scheme: scheme,
          variant: variant,
          container: container,
          derivedData: derivedData
        )
        // Without these Xcode indexes only unoptimized builds.
        let indexing = ["COMPILER_INDEX_STORE_ENABLE=YES", "INDEX_ENABLE_DATA_STORE=YES"]
        try buildScheme(
          arguments: arguments + indexing,
          forTesting: variant.forTesting,
          copy: copy,
          log: work.appendingPathComponent("build-\(variant.name)-\(Self.fileName(scheme)).log")
        )
      }
    }
    let allDerivedData = Set(derivedDataByBuild.values).sorted { $0.path < $1.path }
    var storesByBuild: [String: URL] = [:]
    for (name, derivedData) in derivedDataByBuild {
      let store = derivedData.appendingPathComponent("Index.noindex/DataStore")
      guard FileManager.default.fileExists(atPath: store.appendingPathComponent("v5/units").path)
      else {
        throw DeadCodeError.failure("no index store in \(store.path); did the build run?")
      }
      storesByBuild[name] = store
    }
    let containerFlag = "--project"
    return IndexedBuild(
      indexStores: Set(storesByBuild.values).sorted { $0.path < $1.path },
      storesByBuild: separate ? storesByBuild : [:],
      dependencyExcludes: allDerivedData.map {
        $0.appendingPathComponent("SourcePackages/checkouts").path + "/**"
      } + ["Pods/**", "Carthage/**"],
      generatedExcludes: allDerivedData.map { $0.path + "/**" },
      projectArguments: [containerFlag, container, "--schemes"] + schemes
        + ["--skip-schemes-validation"]
    )
  }

  func resolvedSchemes(_ variant: BuildVariant, container: String) throws -> [String] {
    let schemes = variant.schemes.isEmpty ? configuration.project.schemes : variant.schemes
    if !schemes.isEmpty {
      return schemes
    }
    let shared = StarterConfiguration.sharedSchemes(
      in: model.root.appendingPathComponent(container)
    )
    guard shared.count == 1 else {
      let found = shared.isEmpty ? "none" : shared.joined(separator: ", ")
      throw DeadCodeError.usage(
        "set project.schemes in \(configuration.sourcePath); shared schemes: \(found)"
      )
    }
    return shared
  }

  /// Builds one scheme into its log; a failed build throws.
  func buildScheme(arguments: [String], forTesting: Bool, copy: URL, log: URL) throws {
    let result = try runScheme(arguments: arguments, forTesting: forTesting, in: copy)
    let output = result.standardOutput + result.standardError
    try TextFiles.write(output, to: log)
    guard result.succeeded else {
      throw DeadCodeError.failure(Self.failureMessage(output: output, log: log))
    }
  }

  static func fileName(_ scheme: String) -> String {
    String(scheme.map { $0.isLetter || $0.isNumber ? $0 : "-" })
  }
}

// MARK: - Running

extension ProjectBuilder {
  /// Runs one scheme's build for testing, or plainly when the scheme has no test action or
  /// the build turns tests off.
  func runScheme(arguments: [String], forTesting: Bool, in copy: URL) throws -> CommandResult {
    if forTesting {
      let result = try runner.run(
        Command("xcodebuild", ["build-for-testing"] + arguments, in: copy)
      )
      let output = result.standardOutput + result.standardError
      let hasNoTestAction =
        output.contains("is not currently configured for the test action")
        || output.contains("not configured for testing")
      if result.succeeded || !hasNoTestAction {
        return result
      }
    }
    return try runner.run(Command("xcodebuild", ["build"] + arguments, in: copy))
  }
}

private extension ProjectBuilder {
  func runBuild(_ command: Command, log: URL) throws {
    let result = try runner.run(command)
    let output = result.standardOutput + result.standardError
    try TextFiles.write(output, to: log)
    guard result.succeeded else {
      throw DeadCodeError.failure(Self.failureMessage(output: output, log: log))
    }
  }

  static func failureMessage(output: String, log: URL) -> String {
    let lines = TextFiles.strippingTerminalEscapes(output).split(separator: "\n")
    let errors = lines.filter { $0.contains("error:") }.prefix(20)
    let detail = (errors.isEmpty ? lines.suffix(20) : errors).joined(separator: "\n")
    return "build failed, see \(log.path)\n\(detail)"
  }
}
