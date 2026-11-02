@testable import DeadCodeKit
import Foundation
import Testing

@Suite
struct PruneSelectionTests {
  static func pruner(
    _ project: FixtureProject,
    _ configuration: Configuration = Configuration(),
    options: (inout PruneOptions) -> Void
  ) throws -> ImportPruner {
    var pruneOptions = PruneOptions(work: project.scratch)
    options(&pruneOptions)
    return ImportPruner(
      model: try project.load(configuration),
      configuration: configuration,
      options: pruneOptions,
      progress: { _ in },
      output: { _ in }
    )
  }

  @Test
  func allSkipsExcludedPathsAndResources() throws {
    // given: generated code the project excludes from every check, and a Swift template the
    // app copies as a resource, which SwiftPM does not compile.
    let project = try FixtureProject.copy("GatePackage")
    defer {
      project.remove()
    }
    try project.write("import Kit\n", to: "Sources/App/Generated/Strings.swift")
    let manifest = try #require(project.read("Package.swift"))
    try project.write(
      manifest.replacingOccurrences(
        of: #"resources: [.process("Media.xcassets")]"#,
        with: #"resources: [.process("Media.xcassets"), .copy("Templates")]"#
      ),
      to: "Package.swift"
    )
    try project.write("import Kit\n", to: "Sources/App/Templates/Model.swift")
    _ = try project.git(["add", "--all"])
    var configuration = Configuration()
    configuration.exclude = [Glob("Sources/App/Generated/**")]

    // when
    let files = try Self.pruner(project, configuration) { $0.all = true }.filesToCheck()

    // then
    #expect(
      files == ["Sources/App/App.swift", "Sources/Kit/Kit.swift", "Sources/Spare/Spare.swift"]
    )
  }

  @Test
  func baseSelectsRenamedFilesAndNamesGitWouldQuote() throws {
    // given: git quotes non-ASCII paths in its default output, and reports an edited file
    // under a new name as a rename.
    let project = try FixtureProject.copy("GatePackage")
    defer {
      project.remove()
    }
    _ = try project.git([
      "-c", "user.name=Test", "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false",
      "-c", "core.hooksPath=/dev/null", "commit", "--quiet", "-m", "base",
    ])
    try project.write("import Kit\n", to: "Sources/App/Über.swift")
    _ = try project.git(["mv", "Sources/Kit/Kit.swift", "Sources/Kit/Toolkit.swift"])
    let kit = try #require(project.read("Sources/Kit/Toolkit.swift"))
    try project.write(kit + "// edited\n", to: "Sources/Kit/Toolkit.swift")
    _ = try project.git(["add", "--all"])

    // when
    let files = try Self.pruner(project) { $0.base = "HEAD" }.filesToCheck()

    // then
    #expect(files == ["Sources/App/Über.swift", "Sources/Kit/Toolkit.swift"])
  }

  @Test
  func theCopyHoldsTheFilesThatLinksOutOfTheProjectPointAt() throws {
    // given: a source that is an absolute link to a file outside the project, such as the
    // original checkout; writing through it would change that file.
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("swift-dead-code-tests-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: directory)
    }
    let outside = directory.appendingPathComponent("outside/Real.swift")
    try TextFiles.write("let real = 1\n", to: outside)
    let source = directory.appendingPathComponent("project")
    try FileManager.default.createDirectory(
      at: source.appendingPathComponent("Sources"),
      withIntermediateDirectories: true
    )
    try FileManager.default.createSymbolicLink(
      at: source.appendingPathComponent("Sources/Linked.swift"),
      withDestinationURL: outside
    )
    let copy = directory.appendingPathComponent("copy")

    // when
    try WorkingCopy(source: source, copy: copy, output: copy).refresh()

    // then
    let copied = try FileManager.default.attributesOfItem(
      atPath: copy.appendingPathComponent("Sources/Linked.swift").path
    )
    #expect(copied[.type] as? FileAttributeType == .typeRegular)
  }

  @Test(
    arguments: [
      // App reaches Libs/Shared two levels up, and through it Libs/Core.
      (
        ["Apps/App": ["../../Libs/Shared"], "Libs/Shared": ["../Core"], "Libs/Core": []],
        "Apps/App", ["../../Libs/Shared", "../../Libs/Core"]
      ),
      // Kit holds App: Kit's copy needs a directory of its own, named Kit.
      (["Kit/Examples/App": ["../.."], "Kit": []], "Kit/Examples/App", ["../.."]),
    ]
  )
  func everyLocalPackageLeadsToACopyOfTheSameName(
    packages: [String: [String]],
    project: String,
    reached: [String]
  ) throws {
    // given: packages below a temporary directory that depend on each other by path.
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("swift-dead-code-tests-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: directory)
    }
    for (path, dependencies) in packages {
      try FixtureProject.writePackage(
        at: directory.appendingPathComponent(path),
        dependencies: dependencies
      )
    }
    let root = directory.appendingPathComponent(project)
    _ = try ProcessRunner().output(of: Command("git", ["init", "--quiet"], in: root))
    let model = try ProjectLoader().load(root: root, configuration: Configuration())
    let work = directory.appendingPathComponent("work/source")

    // when
    let workingCopy = try WorkingCopy(
      model: model,
      directory: work,
      output: directory.appendingPathComponent("work")
    )
    try workingCopy.refresh()

    // then: each path leads from the copy, inside the work directory, to a package whose
    // directory has the name SwiftPM takes as its identity.
    for path in reached {
      let copied = workingCopy.copy.appendingPathComponent(path).standardizedFileURL
      let original = root.appendingPathComponent(path).standardizedFileURL
      #expect(copied.path.hasPrefix(work.path + "/"))
      #expect(copied.lastPathComponent == original.lastPathComponent)
      #expect(
        FileManager.default.fileExists(atPath: copied.appendingPathComponent("Package.swift").path)
      )
    }
  }

  @Test(
    arguments: [
      // Kit holds App, and the output sits in Kit beside App.
      (["Kit/Examples/App": ["../.."], "Kit": []], "Kit/Examples/App", "Kit/Examples/out"),
      // The output sits inside the project, outside `.build`.
      (["App": []], "App", "App/tmp/scan"),
    ]
  )
  func noCopyTakesInTheOutputDirectory(
    packages: [String: [String]],
    project: String,
    output: String
  ) throws {
    // given: a report that the previous run left in the output directory.
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("swift-dead-code-tests-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: directory)
    }
    for (path, dependencies) in packages {
      try FixtureProject.writePackage(
        at: directory.appendingPathComponent(path),
        dependencies: dependencies
      )
    }
    let root = directory.appendingPathComponent(project)
    _ = try ProcessRunner().output(of: Command("git", ["init", "--quiet"], in: root))
    let model = try ProjectLoader().load(root: root, configuration: Configuration())
    let out = directory.appendingPathComponent(output)
    try TextFiles.write("previous run\n", to: out.appendingPathComponent("report.md"))

    // when
    try WorkingCopy(model: model, directory: out.appendingPathComponent("source"), output: out)
      .refresh()

    // then
    let copied = FileManager.default.enumerator(atPath: out.appendingPathComponent("source").path)
    #expect(!(copied?.allObjects as? [String] ?? []).contains { $0.hasSuffix("report.md") })
  }

  @Test(.enabled(if: Tools.hasXcodeGen))
  func anXcodeLocalPackageBesideTheProjectIsCopiedBesideItsCopy() throws {
    // given: the project references Shared, a local package beside it.
    let project = try FixtureProject.copy("XcodeShop")
    defer {
      project.remove()
    }
    let shared = project.root.deletingLastPathComponent().appendingPathComponent("Shared")
    try FixtureProject.writePackage(at: shared)
    let spec = try #require(project.read("project.yml"))
    try project.write(
      spec.replacingOccurrences(
        of: "    path: Packages/Feature\n",
        with: "    path: Packages/Feature\n  Shared:\n    path: ../Shared\n"
      ),
      to: "project.yml"
    )
    try project.generateXcodeProject()
    let work = project.scratch.appendingPathComponent("source")

    // when
    let workingCopy = try WorkingCopy(
      model: try project.load(),
      directory: work,
      output: project.scratch
    )
    try workingCopy.refresh()

    // then
    let copied = workingCopy.copy.appendingPathComponent("../Shared").standardizedFileURL
    #expect(copied.path.hasPrefix(work.path + "/"))
    #expect(
      FileManager.default.fileExists(atPath: copied.appendingPathComponent("Package.swift").path)
    )
  }

  @Test
  func readsTheTargetsAnXcodeBuildCovers() {
    // given: the dependency graph Xcode 27 printed for Presentr's example app, abridged.
    let log = """
      note: Target dependency graph (3 targets)
          Target 'PresentrExample' in project 'PresentrExample'
              ➜ Implicit dependency on target 'Pods-PresentrExample' in project 'Pods'
          Target 'Pods-PresentrExample' in project 'Pods'
              ➜ Explicit dependency on target 'Presentr' in project 'Pods'
          Target 'Presentr' in project 'Pods' (no dependencies)
      """

    // when
    let targets = PruneWorkspace.targetsInDependencyGraph(log)

    // then
    #expect(targets == ["PresentrExample", "Pods-PresentrExample", "Presentr"])
  }

  @Test
  func anXcodePruneBuildKeepsTheConfiguredSwiftFlags() throws {
    // given: the configured build defines FEATURE; xcodebuild keeps only the last assignment
    // of a setting, so the pruner's own flag must not replace it.
    let work = FileManager.default.temporaryDirectory
      .appendingPathComponent("swift-dead-code-tests-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: work)
    }
    var configuration = Configuration()
    configuration.project.schemes = ["App"]
    configuration.project.buildArguments = ["OTHER_SWIFT_FLAGS=$(inherited) -DFEATURE"]
    let runner = RecordingRunner()
    let workspace = try PruneWorkspace(
      model: ScanSetupTests.model,
      configuration: configuration,
      work: work,
      files: [],
      runner: runner
    )

    // when
    _ = try workspace.build()

    // then
    let build = try #require(runner.commands.last)
    #expect(
      build.arguments.last { $0.hasPrefix("OTHER_SWIFT_FLAGS=") }
        == "OTHER_SWIFT_FLAGS=$(inherited) -DFEATURE -continue-building-after-errors"
    )
  }
}

/// Records each command and reports success without running it.
private final class RecordingRunner: CommandRunning, @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [Command] = []

  var commands: [Command] {
    lock.withLock { recorded }
  }

  func run(_ command: Command) throws -> CommandResult {
    lock.withLock { recorded.append(command) }
    return CommandResult(status: 0, standardOutput: "", standardError: "")
  }
}
