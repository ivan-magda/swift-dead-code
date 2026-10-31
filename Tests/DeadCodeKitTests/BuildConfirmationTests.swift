import DeadCodeKit
import Foundation
import Testing

@Suite
struct BuildConfirmationTests {
  @Test
  func buildsConfirmOnlyWhatEachBuildThatIndexedItReports() throws {
    // given: an iOS and a macOS app, both module App, built and scanned one by one.
    func finding(_ name: String) -> PeripheryFinding {
      PeripheryFinding(
        kind: "function.method.instance",
        name: name,
        location: "Sources/\(name).swift:1:7",
        ids: ["s:\(name)"],
        hints: ["unused"]
      )
    }
    // The combined index lost the macOS copy's call.
    let lostCall = finding("lostCall")
    let macOnly = finding("macOnly")
    // Shared code that only the macOS app calls, from a type both apps declare.
    let macUses = finding("macUses")
    // Shared code under `#if os(macOS)`, which the iOS build never indexed.
    let macConditional = finding("macConditional")
    let nobodyUses = finding("nobodyUses")
    // Generated code outside every build's index, which no build reports on its own.
    let generated = finding("generated")
    let byBuild = [
      "ios": [macUses, nobodyUses],
      "mac": [macOnly, macConditional, nobodyUses],
    ]
    let seen: [String: Set<String>] = [
      "ios": ["s:macUses", "s:nobodyUses"],
      "mac": ["s:lostCall", "s:macOnly", "s:macUses", "s:macConditional", "s:nobodyUses"],
    ]

    // when
    let kept = BuildConfirmation().confirmed(
      [lostCall, macOnly, macUses, macConditional, nobodyUses, generated],
      byBuild: byBuild,
      seen: seen
    )

    // then
    #expect(kept.map(\.name) == ["macOnly", "macConditional", "nobodyUses"])
  }

  @Test
  func readsTheUSRsAnIndexStoresRecordsContain() throws {
    // given: two record files, one holding a USR between other bytes.
    let store = FileManager.default.temporaryDirectory
      .appendingPathComponent("swift-dead-code-tests-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: store)
    }
    let records = store.appendingPathComponent("v5/records/AB")
    try FileManager.default.createDirectory(at: records, withIntermediateDirectories: true)
    let bytes = Data([0x00, 0xFF]) + Data("helper()s:4Shop6HelperC6helperyyF".utf8) + Data([0x01])
    try bytes.write(to: records.appendingPathComponent("Helper.swift-1A2B"))
    try Data("unrelated".utf8).write(to: records.appendingPathComponent("Other.swift-3C4D"))

    // when
    let seen = try IndexStoreSymbols(store: store)
      .seen(among: ["s:4Shop6HelperC6helperyyF", "s:4Shop5OtherC"])

    // then
    #expect(seen == ["s:4Shop6HelperC6helperyyF"])
  }
}
