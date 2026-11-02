import DeadCodeKit
import Foundation
import Testing

/// Subcommands that build: they run one at a time, as the tool itself requires.
@Suite(.serialized)
struct IntegrationTests {
  /// The suite serializes its own builds; a real scan on the machine must not block it.
  static let lockName = "swift-dead-code-tests.lock"

  @Test(.enabled(if: Tools.hasPeriphery), .timeLimit(.minutes(10)))
  func scanFindsPlantedDeadCodeWithoutTouchingTheProject() throws {
    // given
    let project = try FixtureProject.copy("ScanPackage")
    defer {
      project.remove()
    }
    let configuration = Configuration()
    let model = try project.load(configuration)
    let before = try project.status()

    // when
    let report = try ScanRunner(
      model: model,
      configuration: configuration,
      lockName: Self.lockName
    )
    .run(output: project.scratch, skipBuild: false) { _ in }

    // then
    let all = try PeripheryFinding.read(project.scratch.appendingPathComponent("all.json"))
    let production = try PeripheryFinding.read(project.scratch.appendingPathComponent("prod.json"))
    let allNames = Set(all.map(\.name))
    let productionNames = Set(production.map(\.name))
    #expect(allNames.contains("forgottenHelper()"))
    #expect(allNames.contains("slow"))
    #expect(!allNames.contains("makeGreeterForTesting()"))
    #expect(productionNames.contains("makeGreeterForTesting()"))
    #expect(all.contains { $0.kind == "module" && $0.path == "Sources/Lib/Unneeded.swift" })
    #expect(!all.contains { $0.path.hasPrefix("Tests/") && $0.kind != "module" })
    let text = try #require(TextFiles.read(report))
    #expect(text.contains("Mode is CaseIterable: reachable through allCases"))
    #expect(text.contains("`makeGreeterForTesting()` | named or documented as a test seam"))
    #expect(try project.status() == before)

    // when: the same build is scanned again.
    try ScanRunner(model: model, configuration: configuration, lockName: Self.lockName)
      .run(output: project.scratch, skipBuild: true) { _ in }

    // then
    #expect(TextFiles.read(report) == text)
  }

  @Test(.timeLimit(.minutes(10)))
  func pruneRemovesUnusedImportsAndKeepsBorrowedOnes() throws {
    // given
    let project = try FixtureProject.copy("ScanPackage")
    defer {
      project.remove()
    }
    let configuration = Configuration()
    let model = try project.load(configuration)
    var options = PruneOptions(work: project.scratch)
    options.all = true
    options.lockName = Self.lockName
    var printed: [String] = []
    var progress: [String] = []
    let before = try project.status()

    // when
    let (status, removable) = try ImportPruner(
      model: model,
      configuration: configuration,
      options: options,
      progress: { progress.append($0) },
      output: { printed.append($0) }
    )
    .run()

    // then
    #expect(status == 0)
    #expect(removable == 1)
    #expect(printed.contains("Sources/Lib/Unneeded.swift:1: import Helper"))
    #expect(printed.contains("\n1 of 2 candidate imports are removable."))
    #expect(
      progress.contains("prune: kept Sources/Lib/Twin.swift:1 (import Helper): the file borrows it")
    )
    let patch = try #require(TextFiles.read(project.scratch.appendingPathComponent("prune.patch")))
    #expect(patch.hasPrefix("--- a/Sources/Lib/Unneeded.swift\n+++ b/Sources/Lib/Unneeded.swift\n"))
    #expect(try project.status() == before)
    _ = try project.git([
      "apply", "--check", project.scratch.appendingPathComponent("prune.patch").path,
    ])
  }

  @Test(.timeLimit(.minutes(10)))
  func checkOnlyListsFilesThatBorrowImports() throws {
    // given
    let project = try FixtureProject.copy("ScanPackage")
    defer {
      project.remove()
    }
    let configuration = Configuration()
    var options = PruneOptions(work: project.scratch)
    options.checkOnly = true
    options.lockName = Self.lockName
    options.files = ["Sources/Lib/Borrower.swift", "Sources/Lib/Twin.swift"]
    var printed: [String] = []

    // when
    let (status, _) = try ImportPruner(
      model: try project.load(configuration),
      configuration: configuration,
      options: options,
      progress: { _ in },
      output: { printed.append($0) }
    )
    .run()

    // then
    #expect(status == 1)
    #expect(printed.first == "Sources/Lib/Borrower.swift: needs imports it gets from other files")
    #expect(printed.contains { $0.contains("missing import of defining module 'Helper'") })
    #expect(!printed.contains { $0.hasPrefix("Sources/Lib/Twin.swift") })
  }

  @Test(.timeLimit(.minutes(10)))
  func pruneKeepsAnImportAFileReachesABorrowedModuleThrough() throws {
    // given: Twin.swift imports Facade, which re-exports Helper, for Helper's `shouted`;
    // without the import it compiles only by borrowing Greeter.swift's `import Helper`.
    let project = try FixtureProject.copy("ScanPackage")
    defer {
      project.remove()
    }
    let manifest = try #require(project.read("Package.swift"))
    try project.write(
      manifest.replacingOccurrences(
        of: #".target(name: "Lib", dependencies: ["Helper"]),"#,
        with: #".target(name: "Facade", dependencies: ["Helper"]),"#
          + #"\#n    .target(name: "Lib", dependencies: ["Helper", "Facade"]),"#
      ),
      to: "Package.swift"
    )
    try project.write("@_exported import Helper\n", to: "Sources/Facade/Facade.swift")
    let twin = try #require(project.read("Sources/Lib/Twin.swift"))
    try project.write(
      twin.replacingOccurrences(of: "import Helper\n", with: "import Facade\n"),
      to: "Sources/Lib/Twin.swift"
    )
    _ = try project.git(["add", "--all"])
    let configuration = Configuration()
    var options = PruneOptions(work: project.scratch)
    options.files = ["Sources/Lib/Twin.swift"]
    options.lockName = Self.lockName

    // when
    let (_, removable) = try ImportPruner(
      model: try project.load(configuration),
      configuration: configuration,
      options: options,
      progress: { _ in },
      output: { _ in }
    )
    .run()

    // then
    #expect(removable == 0)
  }

  @Test(.timeLimit(.minutes(10)))
  func pruneBuildsEveryConfiguredBuild() throws {
    // given: Featured.swift uses Helper only when the second build defines FEATURE.
    let project = try FixtureProject.copy("ScanPackage")
    defer {
      project.remove()
    }
    try project.write(
      "import Helper\n\n#if FEATURE\n  public let featured = HelperThing().label\n#endif\n",
      to: "Sources/Lib/Featured.swift"
    )
    _ = try project.git(["add", "--all"])
    var configuration = Configuration()
    var feature = BuildVariant(name: "feature")
    feature.buildArguments = ["-Xswiftc", "-DFEATURE"]
    configuration.builds = [BuildVariant(name: "default"), feature]
    var options = PruneOptions(work: project.scratch)
    options.files = ["Sources/Lib/Featured.swift"]
    options.lockName = Self.lockName

    // when
    let (_, removable) = try ImportPruner(
      model: try project.load(configuration),
      configuration: configuration,
      options: options,
      progress: { _ in },
      output: { _ in }
    )
    .run()

    // then
    #expect(removable == 0)
  }

  @Test(.timeLimit(.minutes(10)))
  func checkOnlyFailsWhenATargetCouldNotBeChecked() throws {
    // given: Helper, which Lib depends on, no longer compiles.
    let project = try FixtureProject.copy("ScanPackage")
    defer {
      project.remove()
    }
    let helper = try #require(project.read("Sources/Helper/Helper.swift"))
    try project.write(helper + "let broken: Int = \"text\"\n", to: "Sources/Helper/Helper.swift")
    let configuration = Configuration()
    var options = PruneOptions(work: project.scratch)
    options.checkOnly = true
    options.lockName = Self.lockName
    options.files = ["Sources/Lib/Borrower.swift"]
    let pruner = ImportPruner(
      model: try project.load(configuration),
      configuration: configuration,
      options: options,
      progress: { _ in },
      output: { _ in }
    )

    // when
    let error = #expect(throws: DeadCodeError.self) {
      try pruner.run()
    }

    // then
    #expect(error?.message == "not checked: Lib")
  }

  @Test(.timeLimit(.minutes(10)))
  func theStrictCheckReachesAnOldVersionSpecificManifest() throws {
    // given: SwiftPM 6 reads Package@swift-6.swift instead of Package.swift, and its
    // PackageDescription 5.7 has no enableUpcomingFeature.
    let project = try FixtureProject.copy("ScanPackage")
    defer {
      project.remove()
    }
    let manifest = try #require(project.read("Package.swift"))
    try project.write(
      manifest.replacingOccurrences(of: "6.0", with: "5.7")
        .replacingOccurrences(of: ".v14", with: ".v13"),
      to: "Package@swift-6.swift"
    )
    let configuration = Configuration()
    var options = PruneOptions(work: project.scratch)
    options.all = true
    options.lockName = Self.lockName
    var progress: [String] = []

    // when
    let (_, removable) = try ImportPruner(
      model: try project.load(configuration),
      configuration: configuration,
      options: options,
      progress: { progress.append($0) },
      output: { _ in }
    )
    .run()

    // then: Twin.swift compiles without its import only by borrowing Greeter.swift's.
    #expect(removable == 1)
    #expect(
      progress.contains("prune: kept Sources/Lib/Twin.swift:1 (import Helper): the file borrows it")
    )
  }
}

@Suite
struct DescribeAndInitTests {
  @Test
  func describesTargetsRolesAndExternalModules() throws {
    // given
    let project = try FixtureProject.copy("ScanPackage")
    defer {
      project.remove()
    }
    let model = try project.load()

    // when
    let text = ProjectDescription(model: model, configuration: Configuration()).text()
    let json = try ProjectDescription(model: model, configuration: Configuration()).json()

    // then
    #expect(text.hasPrefix("project: swiftpm (Package.swift)\ntargets: 3 (1 test, 0 test support)"))
    #expect(text.contains("  LibTests [test, unit-test] module LibTests, 1 Swift files"))
    #expect(json.contains(#""role" : "test""#))
  }

  @Test
  func readsProductsAndExecutablesALegacyManifestNamesLikeTargets() throws {
    // given: a tools-version 5.0 manifest names Kit, a dependency's product, like a target, and
    // its executable's target is a regular one.
    let project = try FixtureProject.copy("LegacyPackage")
    defer {
      project.remove()
    }

    // when
    let model = try project.load()

    // then
    #expect(model.externalModules == ["Kit"])
    #expect(model.target(named: "Tool")?.productType == .executable)
    #expect(
      model.target(named: "Tool")?.dependencies == [
        TargetDependency(name: "Core", moduleNames: ["Core"], kind: .target),
        TargetDependency(name: "Kit", moduleNames: ["Kit"], kind: .product),
      ]
    )
  }

  @Test
  func readingAPackageLeavesNoLockFileInTheTemporaryDirectory() throws {
    // given: SwiftPM keeps a lock file per scratch path in TMPDIR, and every read of a package
    // uses a new scratch path.
    let project = try FixtureProject.copy("ScanPackage")
    defer {
      project.remove()
    }
    let before = try Self.manifestLocks()

    // when
    _ = try project.load()

    // then
    #expect(try Self.manifestLocks().subtracting(before).isEmpty)
  }

  @Test
  func aTargetWhoseSourcesAreItsDirectoryKeepsItsFiles() throws {
    // given: `sources: ["."]` names the whole target directory, as leaving `sources` out does.
    let project = try FixtureProject.copy("ScanPackage")
    defer {
      project.remove()
    }
    let manifest = try #require(project.read("Package.swift"))
    try project.write(
      manifest.replacingOccurrences(
        of: #".target(name: "Lib", dependencies: ["Helper"]),"#,
        with: #".target(name: "Lib", dependencies: ["Helper"], sources: ["."]),"#
      ),
      to: "Package.swift"
    )

    // when
    let model = try project.load()

    // then
    #expect(
      model.target(named: "Lib")?.sourceFiles == [
        "Sources/Lib/Borrower.swift", "Sources/Lib/Greeter.swift", "Sources/Lib/Twin.swift",
        "Sources/Lib/Unneeded.swift",
      ]
    )
  }

  @Test
  func initPrintsAConfigurationTheLoaderAccepts() throws {
    // given
    let project = try FixtureProject.copy("GatePackage")
    defer {
      project.remove()
    }

    // when
    let text = StarterConfiguration(model: try project.load()).text()
    let configuration = try ConfigurationLoader.parse(text)

    // then
    #expect(configuration.project.kind == .swiftpm)
    #expect(configuration.periphery.version == PeripherySettings().version)
  }

  /// The lock files the tool's manifest reads left in the temporary directory.
  static func manifestLocks() throws -> Set<String> {
    let names = try FileManager.default.contentsOfDirectory(
      atPath: FileManager.default.temporaryDirectory.path
    )
    return Set(names.filter { $0.contains("swift-dead-code-manifest") && $0.hasSuffix(".lock") })
  }
}
