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
  func allSkipsPathsTheConfigurationExcludes() throws {
    // given: generated code the project excludes from every check.
    let project = try FixtureProject.copy("GatePackage")
    defer {
      project.remove()
    }
    try project.write("import Kit\n", to: "Sources/App/Generated/Strings.swift")
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
  func baseSelectsAChangedFileWhoseNameGitWouldQuote() throws {
    // given: git quotes non-ASCII paths in its default output.
    let project = try FixtureProject.copy("GatePackage")
    defer {
      project.remove()
    }
    _ = try project.git([
      "-c", "user.name=Test", "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false",
      "-c", "core.hooksPath=/dev/null", "commit", "--quiet", "-m", "base",
    ])
    try project.write("import Kit\n", to: "Sources/App/Über.swift")
    _ = try project.git(["add", "--all"])

    // when
    let files = try Self.pruner(project) { $0.base = "HEAD" }.filesToCheck()

    // then
    #expect(files == ["Sources/App/Über.swift"])
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
}
