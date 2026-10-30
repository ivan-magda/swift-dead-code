import DeadCodeKit
import Testing

@Suite
struct ConfigurationLoaderTests {
  @Test
  func readsEverySection() throws {
    // given
    let text = """
      project:
        kind: xcode
        path: App.xcworkspace
        schemes: [App, Widgets]
        destination: "generic/platform=iOS Simulator"
      test_support: [AppTestSupport, "Tests/Shared/**"]
      exclude: ["Generated/**"]
      module_names:
        Protobuf: [SwiftProtobuf]
      check:
        not_references: [docs/research/]
        min_stem_length: 5
        assets: false
      allowlist:
        - file: docs/demo.png
          reason: linked from the website
        - dependency: {target: Subscribe to Feed, module: Kit}
          reason: re-exported
        - dependency: App  Network
          reason: loaded for its side effects
      periphery:
        version: 3.8.0
        baseline: BuildTools/periphery-baseline.txt
        retain_codable_properties: false
        arguments: [--retain-public]
      prune:
        keep_modules: [Sentry]
      triage:
        seam_name_pattern: "Seam$"
      builds:
        - name: mac
          schemes: [MacApp]
          destination: "generic/platform=macOS"
      """

    // when
    let configuration = try ConfigurationLoader.parse(text)

    // then
    #expect(configuration.project.kind == .xcode)
    #expect(configuration.project.schemes == ["App", "Widgets"])
    #expect(configuration.testSupportGlobs.map(\.pattern) == ["Tests/Shared/**"])
    #expect(configuration.moduleNames["Protobuf"] == ["SwiftProtobuf"])
    #expect(configuration.check.minimumStemLength == 5)
    #expect(!configuration.check.assets)
    #expect(
      configuration.allowlist.map(\.subject) == [
        "docs/demo.png", "Subscribe to Feed Kit", "App Network",
      ]
    )
    #expect(configuration.allowlist.map(\.line) == [15, 17, 19])
    #expect(configuration.periphery.baseline == "BuildTools/periphery-baseline.txt")
    #expect(!configuration.periphery.retainCodableProperties)
    #expect(configuration.periphery.arguments == ["--retain-public"])
    #expect(configuration.prune.keepModules == ["Sentry"])
    #expect(configuration.triage.seamNamePattern == "Seam$")
    #expect(configuration.builds.first?.schemes == ["MacApp"])
  }

  @Test
  func missingFileMeansDefaults() throws {
    // given
    let directory = FixtureProject.fixtures

    // when
    let configuration = try ConfigurationLoader.load(root: directory, path: "absent.yml")

    // then
    #expect(configuration.periphery.version == "3.8.0")
    #expect(configuration.periphery.retainCodableProperties)
    #expect(configuration.prune.toolchainModules == ["Testing", "Synchronization"])
    #expect(configuration.allowlist.isEmpty)
  }

  @Test(arguments: [
    ("periphery:\n  verison: 3.8.0\n", "2:3: error: 'periphery.verison': unknown key"),
    ("allowlist:\n  - file: a.png\n", "2:5: error: 'allowlist': entry 'file' needs a 'reason'"),
    ("allowlist:\n  - file: a.png\n    reason: ''\n", "the reason must not be empty"),
    ("check:\n  assets: maybe\n", "error: 'check.assets': expected true or false"),
    ("project:\n  kind: bazel\n", "expected one of auto, swiftpm, xcode, found 'bazel'"),
  ])
  func rejectsMistakesWithTheirLine(text: String, message: String) {
    // when
    let error = #expect(throws: DeadCodeError.self) {
      try ConfigurationLoader.parse(text)
    }

    // then
    #expect(error?.message.contains(message) == true, "\(error?.message ?? "")")
    #expect(error?.exitStatus == 2)
  }
}
