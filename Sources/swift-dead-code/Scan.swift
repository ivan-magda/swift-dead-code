import ArgumentParser
import DeadCodeKit
import Foundation

struct Scan: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Build with an index store and run Periphery with and without tests.",
    discussion: """
      Copies the project into OUTPUT/source and builds there, so the working tree is never \
      written. Writes OUTPUT/all.json, OUTPUT/prod.json and the triage in OUTPUT/report.md. \
      Reuse one OUTPUT directory so reruns build incrementally. Builds take a machine-wide \
      lock: two at once finish later than the same two in sequence.
      """
  )

  @OptionGroup
  var options: ProjectOptions

  @Option(help: "Directory for the copy, the build, the scans and the report.")
  var output: String

  @Flag(help: "Reuse the previous build in OUTPUT instead of copying and building again.")
  var skipBuild = false

  func run() throws {
    try runReportingErrors {
      let configuration = try options.loadConfiguration()
      let model = try options.loadProject(configuration)
      let outputURL = URL(fileURLWithPath: output).standardizedFileURL
      let report = try ScanRunner(model: model, configuration: configuration)
        .run(output: outputURL, skipBuild: skipBuild) { message in
          Output.error("scan: \(message)")
        }
      Output.error("scan: report written to \(report.path)")
      return 0
    }
  }
}
