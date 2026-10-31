import DeadCodeKit
import Foundation
import Testing

@Suite
struct TriageTests {
  static let source = """
    import Foundation
    import UIKit

    enum Mode: CaseIterable {
      case fast
      case slow
    }

    struct Payload: Codable {
      let id: Int
    }

    protocol Store {
      func load()
    }

    final class ViewController: UIViewController {
      @IBAction func tapped(_ sender: Any) {}
      @objc dynamic func refresh() {}
      @State private var selection = 0

      func render() {
        _ = $selection
        caller()
      }

      func caller() {
        helper()
      }

      func helper() {}
    }

    enum CodingKeys: String, CodingKey {
      case legacyName
    }

    /// Kept for tests.
    func makeStoreForTesting() {}

    func onActor(isolation: isolated (any Actor)?, _ work: () -> Void) {
      work()
    }

    let observer = NotificationCenter.default.addObserver(
      forName: nil, object: nil, queue: nil
    ) { _ in
    }

    struct SettingsView: View {
      @Environment(\\.dismiss) private var dismiss

      var body: some View {
        Text("Settings")
      }
    }
    """

  static func finding(
    _ line: Int,
    _ column: Int,
    _ kind: String,
    _ name: String
  ) -> PeripheryFinding {
    PeripheryFinding(
      kind: kind,
      name: name,
      location: "Sources/App/Main.swift:\(line):\(column)",
      ids: ["s:\(name)"],
      hints: ["unused"]
    )
  }

  static func target(_ name: String, module: String, file: String) -> ProjectTarget {
    ProjectTarget(
      name: name,
      moduleName: module,
      role: .product,
      productType: .application,
      sourceFiles: [file],
      manifestPath: "App.xcodeproj"
    )
  }

  /// The rows `notesPointAtTheCheckThatDecides` expects, by line, kind and name.
  static let expectedRows = [
    ("6:8 | enumelement | `slow`", "Mode is CaseIterable: reachable through allCases"),
    ("10:7 | var.instance | `id`", "Payload is Encodable: the field is serialized"),
    (
      "14:8 | function.method.instance | `load()`",
      "protocol requirement: check calls on conforming types and documented contracts"
    ),
    (
      "18:18 | function.method.instance | `tapped(_:)`",
      "may witness a requirement of: UIViewController; @IBAction: connected in a storyboard "
        + "or XIB? check nibs the scan did not read"
    ),
    ("20:22 | var.instance | `selection`", "read through its projected value $selection"),
    (
      "31:8 | function.method.instance | `helper()`",
      "may witness a requirement of: UIViewController; used only by flagged caller: settle "
        + "that first"
    ),
    ("35:8 | enumelement | `legacyName`", "CodingKeys case: synthesized Codable uses it"),
    ("39:6 | function.free | `makeStoreForTesting()`", "named or documented as a test seam"),
    (
      "41:14 | var.parameter | `isolation`",
      "isolated parameter: it runs the function on that actor, a use by effect"
    ),
    (
      "9:17 | protocol | `Codable`",
      "conformance to a protocol nothing uses as a type: a marker for code generators "
        + "(Sourcery) or runtime discovery may keep it"
    ),
    (
      "51:39 | var.instance | `dismiss`",
      "@Environment nothing reads: usually a leftover, unless a comment makes its declaration "
        + "a workaround; check #if branches for platforms the scan did not build"
    ),
  ]

  @Test
  func notesPointAtTheCheckThatDecides() throws {
    // given
    let project = try FixtureProject.copy("GatePackage")
    defer {
      project.remove()
    }
    try project.write(Self.source, to: "Sources/App/Main.swift")
    let all = [
      Self.finding(6, 8, "enumelement", "slow"),
      Self.finding(10, 7, "var.instance", "id"),
      Self.finding(14, 8, "function.method.instance", "load()"),
      Self.finding(18, 18, "function.method.instance", "tapped(_:)"),
      Self.finding(19, 22, "function.method.instance", "refresh()"),
      Self.finding(20, 22, "var.instance", "selection"),
      Self.finding(27, 8, "function.method.instance", "caller()"),
      Self.finding(31, 8, "function.method.instance", "helper()"),
      Self.finding(35, 8, "enumelement", "legacyName"),
    ]
    let production = all + [Self.finding(39, 6, "function.free", "makeStoreForTesting()")]
    let isolation = Self.finding(41, 14, "var.parameter", "isolation")
    let dismiss = Self.finding(51, 39, "var.instance", "dismiss")
    let conformance = PeripheryFinding(
      kind: "protocol",
      name: "Codable",
      location: "Sources/App/Main.swift:9:17",
      ids: ["s:Codable"],
      hints: ["redundantConformance"]
    )

    // when
    let report = TriageReport(
      all: (all + [isolation, dismiss, conformance]).shuffled(),
      production: production + [isolation, dismiss],
      model: try project.load(),
      configuration: Configuration(),
      sourceRoot: project.root
    )
    .render()

    // then
    for (declaration, notes) in Self.expectedRows {
      let row = "| Sources/App/Main.swift:\(declaration) | \(notes) |"
      #expect(report.contains(row), "missing: \(row)")
    }
    #expect(report.contains("exposed to Objective-C: check selectors"))
    #expect(report.contains("Unused declarations: 12. Test-only production declarations: 1."))
  }

  @Test
  func privateHelpersAndCallsInsideTheirOwnBodyGetNoCallerOrWitnessNote() throws {
    // given: printUsage() calls another module's printUsage(on:); the conformance hint carries
    // Periphery's replacement.
    let project = try FixtureProject.copy("GatePackage")
    defer {
      project.remove()
    }
    let source = """
      import Foundation

      final class Runner: NSObject {
        private func printUsage() {
          FileHandle.standardOutput.printUsage(on: "out")
        }
      }

      extension Runner: Reporting {}
      """
    try project.write(source, to: "Sources/App/Main.swift")
    let usage = Self.finding(4, 16, "function.method.instance", "printUsage()")
    let conformance = PeripheryFinding(
      kind: "protocol",
      name: "Reporting",
      location: "Sources/App/Main.swift:9:19",
      ids: ["s:Reporting"],
      hints: ["redundantConformance(replace with: 'Output')"]
    )

    // when
    let report = TriageReport(
      all: [usage, conformance],
      production: [usage, conformance],
      model: try project.load(),
      configuration: Configuration(),
      sourceRoot: project.root
    )
    .render()

    // then
    let usageRow = "| Sources/App/Main.swift:4:16 | function.method.instance | `printUsage()` | - |"
    let conformanceNote =
      "conformance to a protocol nothing uses as a type: a marker for code generators "
      + "(Sourcery) or runtime discovery may keep it"
    #expect(report.contains(usageRow))
    #expect(
      report.contains(
        "| Sources/App/Main.swift:9:19 | protocol | `Reporting` | \(conformanceNote) |"
      )
    )
  }

  @Test
  func notesTypesATargetWithTheSameModuleNameAlsoDeclares() throws {
    // given: the iOS and macOS apps are both module App and both declare Inspector; Kit's
    // Inspector belongs to another module.
    let project = try FixtureProject.copy("GatePackage")
    defer {
      project.remove()
    }
    let source = """
      final class Inspector {
        func refresh() {}
      }

      private extension Inspector {
        func showError() {}
      }
      """
    for directory in ["iOS", "Mac", "Kit"] {
      try project.write(source, to: "\(directory)/Inspector.swift")
    }
    let model = ProjectModel(
      kind: .xcode(container: "App.xcodeproj"),
      root: project.root,
      targets: [
        Self.target("App-iOS", module: "App", file: "iOS/Inspector.swift"),
        Self.target("App-macOS", module: "App", file: "Mac/Inspector.swift"),
        Self.target("Kit", module: "Kit", file: "Kit/Inspector.swift"),
      ]
    )
    let findings = ["Mac", "Kit"].map { directory in
      PeripheryFinding(
        kind: "function.method.instance",
        name: "showError()",
        location: "\(directory)/Inspector.swift:6:8",
        ids: ["s:\(directory)"],
        hints: ["unused"]
      )
    }

    // when
    let report = TriageReport(
      all: findings,
      production: findings,
      model: model,
      configuration: Configuration(),
      sourceRoot: project.root
    )
    .render()

    // then
    let twinNote =
      "Inspector is declared again in App-iOS, also module App: the builds share one index, "
      + "which merges the two and can lose this copy's callers"
    #expect(
      report.contains(
        "| Mac/Inspector.swift:6:8 | function.method.instance | `showError()` | \(twinNote) |"
      )
    )
    #expect(
      report.contains("| Kit/Inspector.swift:6:8 | function.method.instance | `showError()` | - |")
    )
  }

  @Test
  func shuffledScansGiveTheSameReport() throws {
    // given
    let project = try FixtureProject.copy("GatePackage")
    defer {
      project.remove()
    }
    try project.write(Self.source, to: "Sources/App/Main.swift")
    let findings = [
      Self.finding(6, 8, "enumelement", "slow"),
      Self.finding(14, 8, "function.method.instance", "load()"),
      Self.finding(31, 8, "function.method.instance", "helper()"),
    ]
    let model = try project.load()

    // when
    let reports = (0..<3).map { _ in
      TriageReport(
        all: findings.shuffled(),
        production: findings.shuffled(),
        model: model,
        configuration: Configuration(),
        sourceRoot: project.root
      )
      .render()
    }

    // then
    #expect(Set(reports).count == 1)
  }
}
