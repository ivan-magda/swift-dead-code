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
    try WorkingCopy(source: source, copy: copy).refresh()

    // then
    let copied = try FileManager.default.attributesOfItem(
      atPath: copy.appendingPathComponent("Sources/Linked.swift").path
    )
    #expect(copied[.type] as? FileAttributeType == .typeRegular)
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
