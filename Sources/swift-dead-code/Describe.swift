import ArgumentParser
import DeadCodeKit

struct Describe: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Print the project as the tool sees it: targets, test code, dependencies."
  )

  @OptionGroup
  var options: ProjectOptions

  @Option(help: "Output format: text or json.")
  var format = OutputFormat.text

  func run() throws {
    try runReportingErrors {
      let configuration = try options.loadConfiguration()
      let model = try options.loadProject(configuration)
      let description = ProjectDescription(model: model, configuration: configuration)
      Output.print(format == .json ? try description.json() : description.text())
      return 0
    }
  }
}
