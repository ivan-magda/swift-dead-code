import DeadCodeKit
import Testing

@Suite
struct GateTests {
  @Test
  func findsUnimportedDependenciesAndUnmentionedFilesAndAssets() throws {
    // given
    let project = try FixtureProject.copy("GatePackage")
    defer {
      project.remove()
    }
    let before = try project.status()

    // when
    let gate = Gate(model: try project.load(), configuration: Configuration())
    let findings = try gate.findings()

    // then
    #expect(
      gate.report(for: findings) == """
        asset Sources/App/Media.xcassets/LegacyIcon.imageset
        dependency App Spare
        file Scripts/Forgotten.swift
        file docs/orphan-note.txt
        """
    )
    #expect(try project.status() == before)
  }

  @Test
  func allowlistKeepsFindingsAndRejectsStaleAndDuplicateEntries() throws {
    // given
    let project = try FixtureProject.copy("GatePackage")
    defer {
      project.remove()
    }
    let configuration = try ConfigurationLoader.parse(
      """
      allowlist:
        - dependency: App Spare
          reason: kept for the next release
        - file: docs/*.txt
          reason: notes stay
        - file: docs/gone.md
          reason: deleted long ago
        - dependency: App Spare
          reason: twice
      """
    )
    let gate = Gate(model: try project.load(configuration), configuration: configuration)

    // when
    let errors = gate.errors(for: try gate.findings())

    // then
    #expect(
      errors == [
        ".deadcode.yml:8:1: error: duplicate entry 'dependency App Spare'",
        "Sources/App/Media.xcassets/LegacyIcon.imageset:1:1: error: no file outside asset "
          + "catalogs names this asset; delete it or add 'asset: "
          + "Sources/App/Media.xcassets/LegacyIcon.imageset' with a reason to the allowlist in "
          + ".deadcode.yml",
        "Scripts/Forgotten.swift:1:1: error: no other file mentions this file; delete it or add "
          + "'file: Scripts/Forgotten.swift' with a reason to the allowlist in .deadcode.yml",
        ".deadcode.yml:6:1: error: 'file docs/gone.md' no longer matches a finding; "
          + "remove the entry",
      ]
    )
  }

  @Test
  func untrackedSwiftFilesCountAsImports() throws {
    // given: SwiftPM compiles an untracked file in a target directory too.
    let project = try FixtureProject.copy("GatePackage")
    defer {
      project.remove()
    }
    try project.write("import Spare\n", to: "Sources/App/Draft.swift")

    // when
    let findings = try Gate(model: try project.load(), configuration: Configuration()).findings()

    // then
    #expect(!findings.contains(GateFinding(kind: .dependency, subject: "App Spare")))
  }

  @Test
  func wildcardsAndVariantSuffixesCountAsMentions() throws {
    // given: DocC finds `~dark` variants by name, and a README may name files by pattern.
    let project = try FixtureProject.copy("GatePackage")
    defer {
      project.remove()
    }
    try project.write("dark", to: "docs/architecture-diagram~dark.png")
    try project.write("run", to: "docs/results/run-2026-10-30.md")
    try project.write("Results are in docs/results/run-*.md.\n", to: "CONTRIBUTING.md")
    _ = try project.git(["add", "--all"])

    // when
    let findings = try Gate(model: try project.load(), configuration: Configuration()).findings()

    // then
    let variant = GateFinding(kind: .file, subject: "docs/architecture-diagram~dark.png")
    let matched = GateFinding(kind: .file, subject: "docs/results/run-2026-10-30.md")
    #expect(!findings.contains(variant))
    #expect(!findings.contains(matched))
    #expect(findings.contains(GateFinding(kind: .file, subject: "docs/orphan-note.txt")))
  }

  @Test(.enabled(if: Tools.hasXcodeGen))
  func frameworksLoadedByNameAndConventionalFilesAreNotFindings() throws {
    // given: the app dlopens Spare instead of importing it; git hooks and licenses are found
    // by convention.
    let project = try FixtureProject.copy("XcodeShop")
    defer {
      project.remove()
    }
    let app = try #require(project.read("Shop/ShopApp.swift"))
    let loader = "\nlet spare = dlopen(\"Frameworks/Spare.framework/Spare\", 0)\n"
    try project.write(app + loader, to: "Shop/ShopApp.swift")
    try project.write("#!/bin/sh\n", to: ".githooks/pre-commit")
    try project.write("Commercial terms.\n", to: "LICENSE-COMMERCIAL")
    try project.write("PODFILE CHECKSUM: 0\n", to: "Pods/Manifest.lock")
    try project.write("PODFILE CHECKSUM: 0\n", to: "Vendor/Kit/Pods/Manifest.lock")
    _ = try project.git(["add", "--all"])

    // when
    let findings = try Gate(model: try project.load(), configuration: Configuration()).findings()

    // then
    #expect(!findings.contains(GateFinding(kind: .dependency, subject: "Shop Spare")))
    #expect(!findings.contains(GateFinding(kind: .file, subject: ".githooks/pre-commit")))
    #expect(!findings.contains(GateFinding(kind: .file, subject: "LICENSE-COMMERCIAL")))
    #expect(!findings.contains(GateFinding(kind: .file, subject: "Pods/Manifest.lock")))
    #expect(!findings.contains(GateFinding(kind: .file, subject: "Vendor/Kit/Pods/Manifest.lock")))
    #expect(findings.contains(GateFinding(kind: .file, subject: "docs/unused-mockup.png")))
  }

  @Test(.enabled(if: Tools.hasXcodeGen))
  func filesARunScriptPhaseNamesAreNotFindings() throws {
    // given: without project.yml, only Shop's Run Script phase names its script and its input.
    let project = try FixtureProject.copy("XcodeShop")
    defer {
      project.remove()
    }
    _ = try project.git(["rm", "--quiet", "--force", "project.yml"])

    // when
    let findings = try Gate(model: try project.load(), configuration: Configuration()).findings()

    // then
    let script = GateFinding(kind: .file, subject: "BuildPhases/stamp-build-number.sh")
    #expect(!findings.contains(script))
    #expect(!findings.contains(GateFinding(kind: .file, subject: "Config/release-version.txt")))
    #expect(findings.contains(GateFinding(kind: .file, subject: "docs/unused-mockup.png")))
  }

  @Test
  func sameInputGivesTheSameReportAndJSON() throws {
    // given
    let project = try FixtureProject.copy("GatePackage")
    defer {
      project.remove()
    }
    let gate = Gate(model: try project.load(), configuration: Configuration())

    // when
    let first = try gate.findings()
    let second = try Gate(model: try project.load(), configuration: Configuration()).findings()

    // then
    #expect(gate.report(for: first) == gate.report(for: second))
    #expect(try gate.json(for: first) == gate.json(for: second))
    #expect(try gate.json(for: first).contains(#""subject" : "App Spare""#))
  }

  @Test(.enabled(if: Tools.hasXcodeGen))
  func readsXcodeTargetsPackagesAndBuildSettings() throws {
    // given
    let project = try FixtureProject.copy("XcodeShop")
    defer {
      project.remove()
    }
    let before = try project.status()

    // when
    let model = try project.load()
    let gate = Gate(model: model, configuration: Configuration())
    let findings = try gate.findings()

    // then
    #expect(model.kind == .xcode(container: "Shop.xcodeproj"))
    #expect(model.target(named: "ShopKit")?.moduleName == "ShopCore")
    #expect(model.target(named: "ShopTests")?.role == .test)
    #expect(model.target(named: "FeatureTests")?.role == .test)
    #expect(model.target(named: "ShopWidget")?.sourceFiles == ["Widget/ShopWidget.swift"])
    #expect(model.target(named: "Shop")?.productType == .application)
    #expect(
      gate.report(for: findings) == """
        asset Shop/Assets.xcassets/UnusedImage.imageset
        dependency Shop Spare
        file docs/unused-mockup.png
        """
    )
    #expect(try project.status() == before)
  }
}
