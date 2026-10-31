import ArgumentParser
import DeadCodeKit

struct Check: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Fail on target dependencies nothing imports and files or assets nothing names.",
    discussion: """
      Needs no build: it reads the manifest or project file and the tracked files. Findings \
      kept on purpose go to the allowlist in .deadcode.yml with a reason; a stale, duplicate \
      or reasonless entry also fails.
      """
  )

  @OptionGroup
  var options: ProjectOptions

  @Flag(help: "Print every finding, allowlisted ones included, and exit 0.")
  var report = false

  @Option(help: "Output format with --report: text or json.")
  var format = OutputFormat.text

  func run() throws {
    try runReportingErrors {
      let configuration = try options.loadConfiguration()
      let model = try options.loadProject(configuration)
      let gate = Gate(model: model, configuration: configuration)
      let findings = try gate.findings()
      if report {
        Output.print(format == .json ? try gate.json(for: findings) : gate.report(for: findings))
        return 0
      }
      let errors = gate.errors(for: findings)
      for error in errors {
        Output.error(error)
      }
      return errors.isEmpty ? 0 : 1
    }
  }
}

enum OutputFormat: String, ExpressibleByArgument {
  case text
  case json
}
