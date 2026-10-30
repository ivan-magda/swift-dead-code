import ArgumentParser
import DeadCodeKit
import Foundation

struct Triage: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Turn two Periphery JSON scans into a report with false-positive hints.",
    discussion: """
      ALL_JSON is a scan with tests included; PROD_JSON leaves test code out, so its extra
      findings are production declarations only tests use. Notes point at the check to make;
      they never prove a declaration dead or alive.
      """
  )

  @OptionGroup
  var options: ProjectOptions

  @Argument(help: "Periphery JSON scan with tests included.")
  var allJSON: String

  @Argument(help: "Periphery JSON scan without test code.")
  var prodJSON: String

  @Option(help: "Directory that holds the scanned sources (default: the project root).")
  var sourceRoot: String?

  @Option(help: "Write the report here instead of standard output.")
  var output: String?

  func run() throws {
    try runReportingErrors {
      let configuration = try options.loadConfiguration()
      let model = try options.loadProject(configuration)
      let report = TriageReport(
        all: try PeripheryFinding.read(URL(fileURLWithPath: allJSON)),
        production: try PeripheryFinding.read(URL(fileURLWithPath: prodJSON)),
        model: model,
        configuration: configuration,
        sourceRoot: sourceRoot.map { URL(fileURLWithPath: $0) } ?? model.root
      )
      .render()
      if let output {
        try TextFiles.write(report, to: URL(fileURLWithPath: output))
      } else {
        Output.print(report)
      }
      return 0
    }
  }
}
