import DeadCodeKit
import Foundation
import Testing

@Suite
struct BuildConfirmationTests {
  @Test
  func buildsConfirmOnlyWhatEachBuildThatCompilesTheCodeReports() throws {
    // given: the iOS and macOS apps are both module App; Shared/S.swift is in both.
    let model = ProjectModel(
      kind: .xcode(container: "App.xcodeproj"),
      root: URL(fileURLWithPath: "/tmp"),
      targets: [
        TriageTests.target("App-iOS", module: "App", file: "iOS/A.swift", shared: "Shared/S.swift"),
        TriageTests.target(
          "App-macOS",
          module: "App",
          file: "Mac/A.swift",
          shared: "Shared/S.swift"
        ),
      ]
    )
    func finding(_ location: String, _ name: String) -> PeripheryFinding {
      PeripheryFinding(
        kind: "function.method.instance",
        name: name,
        location: location,
        ids: ["s:\(name)"],
        hints: ["unused"]
      )
    }
    let merged = finding("Mac/A.swift:10:7", "lostCaller()")
    let macOnly = finding("Mac/A.swift:20:7", "unused()")
    let iOSUses = finding("Shared/S.swift:5:7", "iOSHelper()")
    let nobodyUses = finding("Shared/S.swift:9:7", "leftover()")
    // No target owns a generated file, so no build's coverage speaks for it.
    let generated = finding("Generated/G.swift:1:7", "generated()")
    let iOS = [finding("iOS/A.swift:3:7", "other()"), iOSUses, nobodyUses]
    let macOS = [macOnly, nobodyUses]

    // when
    let kept = BuildConfirmation(model: model).confirmed(
      [merged, macOnly, iOSUses, nobodyUses, generated],
      byBuild: ["ios": iOS, "mac": macOS]
    )

    // then: the merge artifact and the helper the macOS build uses are gone.
    #expect(kept.map(\.name) == ["unused()", "leftover()"])
  }
}
