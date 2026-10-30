import ArgumentParser
import DeadCodeKit

struct Init: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Print a starter .deadcode.yml for the project; it never writes the file.",
    discussion: "Redirect it: swift-dead-code init > .deadcode.yml"
  )

  @OptionGroup
  var options: ProjectOptions

  func run() throws {
    try runReportingErrors {
      let configuration = try options.loadConfiguration()
      let model = try options.loadProject(configuration)
      Output.print(StarterConfiguration(model: model).text())
      return 0
    }
  }
}
