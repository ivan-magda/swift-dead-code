import DeadCodeKit
import Foundation
import Testing

/// The scenarios of swift-claw's `scripts/test-periphery-baseline.sh`.
@Suite
struct BaselineTests {
  static func finding(_ location: String, _ name: String, _ usr: String) -> PeripheryFinding {
    PeripheryFinding(
      kind: "function.method.instance",
      name: name,
      location: location,
      ids: [usr],
      hints: ["unused"]
    )
  }

  let old = finding("Sources/Lib/Greeter.swift:3:8", "old()", "s:3Lib3oldyyF")
  let seam = finding("Sources/Lib/Greeter.swift:7:8", "seam()", "s:3Lib4seamyyF")
  let helper = finding("Tests/LibTests/LibTests.swift:2:8", "helper()", "s:8LibTests6helperyyF")

  @Test
  func newFindingFailsAndMovedBacklogStillMatches() throws {
    // given
    let project = try FixtureProject.copy("ScanPackage")
    defer {
      project.remove()
    }
    let configuration = Configuration()
    let baseline = Baseline(model: try project.load(configuration), configuration: configuration)
    _ = try baseline.write([old, helper])
    let recorded = project.read(configuration.periphery.baseline) ?? ""

    // when: old() moved, and both scans report a new declaration.
    let moved = Self.finding("Sources/Lib/Greeter.swift:9:8", "old()", "s:3Lib3oldyyF")
    let new = Self.finding("Sources/Lib/Twin.swift:5:8", "new()", "s:3Lib3newyyF")
    let outcome = try baseline.check(Baseline.merge([[moved, new], [new]]))

    // then
    #expect(!recorded.contains("s:8LibTests6helperyyF"), "test code is never backlog")
    #expect(
      recorded.hasSuffix(
        "s:3Lib3oldyyF  # Sources/Lib/Greeter.swift: "
          + "function.method.instance old()\n"
      )
    )
    #expect(outcome.new == [new])
    #expect(outcome.stale.isEmpty)
  }

  @Test
  func testCodeIsListedAndStaleEntriesAreNamedWithoutFailing() throws {
    // given
    let project = try FixtureProject.copy("ScanPackage")
    defer {
      project.remove()
    }
    let configuration = Configuration()
    let baseline = Baseline(model: try project.load(configuration), configuration: configuration)
    _ = try baseline.write([old, seam])

    // when: the code behind one backlog entry is gone, and a test helper is reported.
    let outcome = try baseline.check([seam, helper])

    // then
    #expect(outcome.new.isEmpty)
    #expect(outcome.inTests == [helper])
    #expect(outcome.stale == ["s:3Lib3oldyyF"])
  }

  @Test
  func scanWithoutProductFindingsCannotClearARecordedBacklog() throws {
    // given
    let project = try FixtureProject.copy("ScanPackage")
    defer {
      project.remove()
    }
    let configuration = Configuration()
    let baseline = Baseline(model: try project.load(configuration), configuration: configuration)
    _ = try baseline.write([old, seam])
    let recorded = project.read(configuration.periphery.baseline)

    // when: a scan that indexed nothing reports only a test helper.
    let checked = #expect(throws: DeadCodeError.self) {
      try baseline.check([helper])
    }
    let written = #expect(throws: DeadCodeError.self) {
      try baseline.write([helper])
    }

    // then
    #expect(checked?.kind == .failure)
    #expect(checked?.message.contains("no finding in product code") == true)
    #expect(written == checked)
    #expect(project.read(configuration.periphery.baseline) == recorded)
  }
}
