import Foundation

/// Where an indexed build left its index store, and how Periphery should read it.
public struct IndexedBuild: Sendable, Equatable {
  public var indexStores: [URL]
  /// `--index-exclude` globs for dependency sources, which would otherwise be scanned.
  public var dependencyExcludes: [String]
  /// `--report-exclude` globs for sources a build generates outside the project.
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

  /// The builds to run: the configured ones, or one with the project settings.
  public var variants: [BuildVariant] {
    if !configuration.builds.isEmpty {
      return configuration.builds
    }
    var variant = BuildVariant(name: "default")
    variant.schemes = configuration.project.schemes
    variant.destination = configuration.project.destination
    variant.configuration = configuration.project.configuration
    variant.buildArguments = configuration.project.buildArguments
    return [variant]
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
    let derivedData = work.appendingPathComponent("DerivedData")
    var schemes: [String] = []
    for variant in variants {
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
          copy: copy,
          log: work.appendingPathComponent("build-\(variant.name)-\(Self.fileName(scheme)).log")
        )
      }
    }
    let store = derivedData.appendingPathComponent("Index.noindex/DataStore")
    guard FileManager.default.fileExists(atPath: store.appendingPathComponent("v5/units").path)
    else {
      throw DeadCodeError.failure("no index store in \(store.path); did the build run?")
    }
    let containerFlag = "--project"
    return IndexedBuild(
      indexStores: [store],
      dependencyExcludes: [
        derivedData.appendingPathComponent("SourcePackages/checkouts").path + "/**",
        "Pods/**",
        "Carthage/**",
      ],
      generatedExcludes: [derivedData.path + "/**"],
      projectArguments: [containerFlag, container, "--schemes"] + schemes
        + ["--skip-schemes-validation"]
    )
  }

  func resolvedSchemes(_ variant: BuildVariant, container: String) throws -> [String] {
    let schemes = variant.schemes.isEmpty ? configuration.project.schemes : variant.schemes
    if !schemes.isEmpty {
      return schemes
    }
    let shared = Self.sharedSchemes(in: model.root.appendingPathComponent(container))
    guard shared.count == 1 else {
      let found = shared.isEmpty ? "none" : shared.joined(separator: ", ")
      throw DeadCodeError.usage(
        "set project.schemes in \(configuration.sourcePath); shared schemes: \(found)"
      )
    }
    return shared
  }

  /// Builds one scheme for testing, or plainly when the scheme has no test action.
  func buildScheme(arguments: [String], copy: URL, log: URL) throws {
    let forTesting = try runner.run(
      Command("xcodebuild", ["build-for-testing"] + arguments, in: copy)
    )
    if forTesting.succeeded {
      try TextFiles.write(forTesting.standardOutput + forTesting.standardError, to: log)
      return
    }
    // A scheme without a test action cannot build for testing; build it plainly.
    let output = forTesting.standardOutput + forTesting.standardError
    if output.contains("is not currently configured for the test action")
      || output.contains("not configured for testing")
    {
      try runBuild(Command("xcodebuild", ["build"] + arguments, in: copy), log: log)
      return
    }
    try TextFiles.write(output, to: log)
    throw DeadCodeError.failure(Self.failureMessage(output: output, log: log))
  }

  /// Shared schemes of a project, or of every project a workspace's directory holds.
  static func sharedSchemes(in container: URL) -> [String] {
    let directory = container.appendingPathComponent("xcshareddata/xcschemes")
    let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    return names.filter { $0.hasSuffix(".xcscheme") }
      .map { ($0 as NSString).deletingPathExtension }
      .sorted()
  }

  static func fileName(_ scheme: String) -> String {
    String(scheme.map { $0.isLetter || $0.isNumber ? $0 : "-" })
  }
}

// MARK: - Running

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
