import DeadCodeKit
import Foundation
import Testing

/// Subcommands that build: they run one at a time, as the tool itself requires.
@Suite(.serialized)
struct IntegrationTests {
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
    let report = try ScanRunner(model: model, configuration: configuration)
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
    try ScanRunner(model: model, configuration: configuration)
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
}
