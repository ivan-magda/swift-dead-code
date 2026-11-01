import DeadCodeKit
import Foundation
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
  func aDependencyAClientImportsWithoutDeclaringItStays() throws {
    // given: App imports Base, which it gets only through Kit; Tool declares Core itself;
    // Suite imports Parser, which it gets through Feed's declaration too; Hub imports Shared,
    // which it gets through both Left and Right; Viewer imports only Codec, which it gets
    // only through Bridge.
    let project = try FixtureProject.copy("GatePackage")
    defer {
      project.remove()
    }
    let imports = [
      "App": "import Kit\nimport Base\n", "Tool": "import Lib\nimport Core\n",
      "Suite": "import Feed\nimport Parser\n", "Feed": "import Web\nimport Parser\n",
      "Hub": "import Left\nimport Right\nimport Shared\n", "Viewer": "import Codec\n",
      "Bridge": "import Codec\n",
    ]
    let dependencies = [
      "App": ["Kit"], "Kit": ["Base"], "Tool": ["Lib", "Core"], "Lib": ["Core"],
      "Suite": ["Feed"], "Feed": ["Web", "Parser"], "Web": ["Parser"],
      "Hub": ["Left", "Right"], "Left": ["Shared"], "Right": ["Shared"], "Viewer": ["Bridge"],
      "Bridge": ["Codec"],
    ]
    let names = [
      "App", "Kit", "Base", "Tool", "Lib", "Core", "Suite", "Feed", "Web", "Parser", "Hub", "Left",
      "Right", "Shared", "Viewer", "Bridge", "Codec",
    ]
    for name in names {
      try project.write(imports[name] ?? "import Foundation\n", to: "\(name)/\(name).swift")
    }
    let targets = names.map { name in
      ProjectTarget(
        name: name,
        role: .product,
        productType: .framework,
        sourceFiles: ["\(name)/\(name).swift"],
        dependencies: (dependencies[name] ?? []).map { dependency in
          TargetDependency(name: dependency, moduleNames: [dependency], kind: .target)
        },
        manifestPath: "Package.swift"
      )
    }
    let model = ProjectModel(kind: .swiftPackage, root: project.root, targets: targets)

    // when
    let findings = try Gate(model: model, configuration: Configuration()).findings()

    // then
    #expect(!findings.contains(GateFinding(kind: .dependency, subject: "Kit Base")))
    #expect(findings.contains(GateFinding(kind: .dependency, subject: "Lib Core")))
    #expect(findings.contains(GateFinding(kind: .dependency, subject: "Web Parser")))
    // Removing both of Hub's routes to Shared would break its import.
    let routes = ["Left Shared", "Right Shared"].filter { subject in
      findings.contains(GateFinding(kind: .dependency, subject: subject))
    }
    #expect(routes.count == 1)
    #expect(!findings.contains(GateFinding(kind: .dependency, subject: "Viewer Bridge")))
  }

  @Test
  func aHyphenatedTargetIsImportedByItsModuleName() throws {
    // given: SwiftPM names the module of target My-Core My_Core.
    let project = try FixtureProject.copy("GatePackage")
    defer {
      project.remove()
    }
    let manifest = try #require(project.read("Package.swift"))
    try project.write(
      manifest.replacingOccurrences(
        of: #"dependencies: ["Kit", "Spare"]"#,
        with: #"dependencies: ["Kit", "Spare", "My-Core"]"#
      ) + #"package.targets.append(.target(name: "My-Core"))"# + "\n",
      to: "Package.swift"
    )
    try project.write("public let core = 1\n", to: "Sources/My-Core/Core.swift")
    let app = try #require(project.read("Sources/App/App.swift"))
    try project.write("import My_Core\n" + app, to: "Sources/App/App.swift")
    _ = try project.git(["add", "--all"])

    // when
    let model = try project.load()
    let findings = try Gate(model: model, configuration: Configuration()).findings()

    // then
    #expect(model.target(named: "My-Core")?.moduleName == "My_Core")
    #expect(!findings.contains(GateFinding(kind: .dependency, subject: "App My-Core")))
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
  func aShortStemCountsAsAWholeStringLiteral() throws {
    // given: code loads atp.rss by its stem and extension; "abc" is only part of a literal.
    let project = try FixtureProject.copy("GatePackage")
    defer {
      project.remove()
    }
    try project.write("<rss/>", to: "docs/atp.rss")
    try project.write("<rss/>", to: "docs/abc.rss")
    let code = """
      let feed = Bundle.main.url(forResource: "atp", withExtension: "rss")
      let label = "abc feed"
      """
    try project.write(code, to: "Sources/App/Feeds.swift")
    _ = try project.git(["add", "--all"])

    // when
    let findings = try Gate(model: try project.load(), configuration: Configuration()).findings()

    // then
    #expect(!findings.contains(GateFinding(kind: .file, subject: "docs/atp.rss")))
    #expect(findings.contains(GateFinding(kind: .file, subject: "docs/abc.rss")))
  }

  @Test
  func wildcardsAndVariantSuffixesCountAsMentions() throws {
    // given: DocC finds `~dark` variants by name, a README may name files by pattern, and a
    // build setting picks a file by a variable.
    let project = try FixtureProject.copy("GatePackage")
    defer {
      project.remove()
    }
    try project.write("dark", to: "docs/architecture-diagram~dark.png")
    try project.write("run", to: "docs/results/run-2026-10-30.md")
    try project.write("Results are in docs/results/run-*.md.\n", to: "CONTRIBUTING.md")
    try project.write("<plist/>", to: "Config/Shop-dev.entitlements")
    let setting = "CODE_SIGN_ENTITLEMENTS = Config/Shop$(DEVELOPER_ENTITLEMENTS).entitlements\n"
    try project.write(setting, to: "Config/Shop.xcconfig")
    _ = try project.git(["add", "--all"])

    // when
    let findings = try Gate(model: try project.load(), configuration: Configuration()).findings()

    // then
    let variant = GateFinding(kind: .file, subject: "docs/architecture-diagram~dark.png")
    let matched = GateFinding(kind: .file, subject: "docs/results/run-2026-10-30.md")
    let selected = GateFinding(kind: .file, subject: "Config/Shop-dev.entitlements")
    #expect(!findings.contains(variant))
    #expect(!findings.contains(matched))
    #expect(!findings.contains(selected))
    #expect(findings.contains(GateFinding(kind: .file, subject: "docs/orphan-note.txt")))
  }

  @Test
  func aSystemLibraryModuleMapIsFoundByName() throws {
    // given: SwiftPM reads a system library target's module.modulemap; no file names it.
    let project = try FixtureProject.copy("GatePackage")
    defer {
      project.remove()
    }
    let manifest = try #require(project.read("Package.swift"))
    try project.write(
      manifest + #"package.targets.append(.systemLibrary(name: "CSQLite"))"# + "\n",
      to: "Package.swift"
    )
    try project.write(
      "module CSQLite [system] {\n  link \"sqlite3\"\n}\n",
      to: "Sources/CSQLite/module.modulemap"
    )
    _ = try project.git(["add", "--all"])

    // when
    let findings = try Gate(model: try project.load(), configuration: Configuration()).findings()

    // then
    #expect(
      !findings.contains(GateFinding(kind: .file, subject: "Sources/CSQLite/module.modulemap"))
    )
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
}

@Suite
struct XcodeGateTests {
  @Test(.enabled(if: Tools.hasXcodeGen))
  func frameworksLoadedByNameAndConventionalFilesAreNotFindings() throws {
    // given: the app dlopens Spare instead of importing it; git hooks and licenses are found
    // by convention, and Core Data models in the app bundle.
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
    let dataModel = "Shop/Store.xcdatamodeld"
    try project.write("<plist/>\n", to: "\(dataModel)/.xccurrentversion")
    try project.write("<model/>\n", to: "\(dataModel)/Store 2.xcdatamodel/contents")
    _ = try project.git(["add", "--all"])

    // when
    let findings = try Gate(model: try project.load(), configuration: Configuration()).findings()

    // then
    #expect(!findings.contains(GateFinding(kind: .dependency, subject: "Shop Spare")))
    #expect(!findings.contains(GateFinding(kind: .file, subject: ".githooks/pre-commit")))
    #expect(!findings.contains(GateFinding(kind: .file, subject: "LICENSE-COMMERCIAL")))
    #expect(!findings.contains(GateFinding(kind: .file, subject: "Pods/Manifest.lock")))
    #expect(!findings.contains(GateFinding(kind: .file, subject: "Vendor/Kit/Pods/Manifest.lock")))
    #expect(!findings.contains(GateFinding(kind: .file, subject: "\(dataModel)/.xccurrentversion")))
    #expect(
      !findings.contains(
        GateFinding(kind: .file, subject: "\(dataModel)/Store 2.xcdatamodel/contents")
      )
    )
    #expect(findings.contains(GateFinding(kind: .file, subject: "docs/unused-mockup.png")))
  }

  @Test(.enabled(if: Tools.hasXcodeGen))
  func aFrameworkTheBridgingHeaderImportsIsUsed() throws {
    // given: Shop uses Spare only through its bridging header.
    let project = try FixtureProject.copy("XcodeShop")
    defer {
      project.remove()
    }
    let spec = try #require(project.read("project.yml"))
    let setting = "    settings:\n      base:\n        SWIFT_OBJC_BRIDGING_HEADER: Shop/Bridge.h\n"
    try project.write(
      spec.replacingOccurrences(
        of: "    info:\n      path: Shop/Info.plist",
        with: setting + "    info:\n      path: Shop/Info.plist"
      ),
      to: "project.yml"
    )
    try project.write("#import <Spare/Spare.h>\n", to: "Shop/Bridge.h")
    try project.generateXcodeProject()

    // when
    let findings = try Gate(model: try project.load(), configuration: Configuration()).findings()

    // then
    #expect(!findings.contains(GateFinding(kind: .dependency, subject: "Shop Spare")))
  }

  @Test(.enabled(if: Tools.hasXcodeGen))
  func aDependencyHasTheModuleNameItsTargetBuilds() throws {
    // given: a project-level setting names every module after its target.
    let project = try FixtureProject.copy("XcodeShop")
    defer {
      project.remove()
    }
    let spec = try #require(project.read("project.yml"))
    let setting = "settings:\n  base:\n    PRODUCT_MODULE_NAME: $(TARGET_NAME)Module\n"
    try project.write(
      spec.replacingOccurrences(of: "packages:", with: setting + "packages:"),
      to: "project.yml"
    )
    try project.generateXcodeProject()

    // when
    let model = try project.load()

    // then
    let spare = model.target(named: "Shop")?.dependencies.first { $0.name == "Spare" }
    #expect(model.target(named: "Spare")?.moduleName == "SpareModule")
    #expect(spare?.moduleNames == ["SpareModule"])
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
