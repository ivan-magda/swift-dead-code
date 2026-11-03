import ArgumentParser
import DeadCodeKit
import Foundation

struct BaselineCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "baseline",
    abstract: "Fail on Periphery findings in product code that the baseline does not list.",
    discussion: """
      The baseline (periphery.baseline in .deadcode.yml) lists known findings by USR, which \
      stays the same when code moves. Findings in test code are listed but never fail. Entries \
      no scan reports any more are named; they do not fail. Scans with no product-code finding \
      at all fail against a non-empty baseline, and --write refuses them: such a scan most \
      likely indexed nothing. --write replaces the baseline with the product-code findings: add \
      one only for an intentional seam, contract or backlog item you decided to keep, and \
      delete dead code instead.
      """
  )

  @OptionGroup
  var options: ProjectOptions

  @Flag(help: "Replace the baseline with the findings of the scans.")
  var write = false

  @Argument(help: "Periphery JSON scans, such as all.json and prod.json from `scan`.")
  var scans: [String]

  func run() throws {
    try runReportingErrors {
      let configuration = try options.loadConfiguration()
      let model = try options.loadProject(configuration)
      let findings = Baseline.merge(
        try scans.map { try PeripheryFinding.read(URL(fileURLWithPath: $0)) }
      )
      let baseline = Baseline(model: model, configuration: configuration)
      let path = configuration.periphery.baseline
      if write {
        let count = try baseline.write(findings)
        Output.print("\(path): \(count) findings")
        return 0
      }
      if !FileManager.default.fileExists(atPath: baseline.url.path) {
        Output.print("\(path) does not exist yet: every product-code finding counts as new.")
      }
      let outcome = try baseline.check(findings)
      if !outcome.inTests.isEmpty {
        Output.print("\(outcome.inTests.count) findings in test code, listed but not checked:")
        Output.print(outcome.inTests.map { "  \(Self.describe($0))" }.joined(separator: "\n"))
      }
      for finding in outcome.new {
        Output.error(
          "\(finding.location): error: \(finding.hint): \(finding.kind) '\(finding.name)' "
            + "is not in \(path)"
        )
      }
      if !outcome.stale.isEmpty {
        Output.print("\(outcome.stale.count) entries in \(path) match no finding any more:")
        Output.print(outcome.stale.map { "  \($0)" }.joined(separator: "\n"))
      }
      if !outcome.new.isEmpty {
        Output.error(
          "\(outcome.new.count) new findings. Delete the code, or record an intentional seam, "
            + "contract or backlog item with --write."
        )
      }
      return outcome.new.isEmpty ? 0 : 1
    }
  }

  static func describe(_ finding: PeripheryFinding) -> String {
    "\(finding.location): \(finding.hint): \(finding.kind) '\(finding.name)'"
  }
}
