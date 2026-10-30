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

    // when
    let report = TriageReport(
      all: (all + [isolation, dismiss]).shuffled(),
      production: production + [isolation, dismiss],
      model: try project.load(),
      configuration: Configuration(),
      sourceRoot: project.root
    )
    .render()

    // then
    let expectedRows = [
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
        "51:39 | var.instance | `dismiss`",
        "@Environment nothing reads: usually a leftover, unless a comment makes its declaration "
          + "a workaround; check #if branches for platforms the scan did not build"
      ),
    ]
    for (declaration, notes) in expectedRows {
      let row = "| Sources/App/Main.swift:\(declaration) | \(notes) |"
      #expect(report.contains(row), "missing: \(row)")
    }
    #expect(report.contains("exposed to Objective-C: check selectors"))
    #expect(report.contains("Unused declarations: 11. Test-only production declarations: 1."))
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
