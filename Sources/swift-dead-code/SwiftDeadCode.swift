import ArgumentParser
import DeadCodeKit
import Foundation

@main
struct SwiftDeadCode: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "swift-dead-code",
    abstract: "Find and remove dead code in SwiftPM packages and Xcode projects.",
    discussion: """
      Configuration lives in .deadcode.yml at the project root. Every subcommand reads it;
      only `scan` and `prune-imports` build, and they build into their own directory.
      """,
    version: "0.1.0",
    subcommands: [
      Check.self, Scan.self, Triage.self, BaselineCommand.self, PruneImports.self,
      Describe.self, Init.self,
    ]
  )
}

/// Options every subcommand shares.
struct ProjectOptions: ParsableArguments {
  @Option(help: "The project root (default: the current directory).")
  var projectRoot: String?

  @Option(help: "The configuration file, relative to the project root.")
  var config = DeadCodeKit.Configuration.fileName

  var rootURL: URL {
    URL(fileURLWithPath: projectRoot ?? FileManager.default.currentDirectoryPath)
      .standardizedFileURL
  }

  func loadConfiguration() throws -> DeadCodeKit.Configuration {
    try ConfigurationLoader.load(root: rootURL, path: config)
  }

  func loadProject(_ configuration: DeadCodeKit.Configuration) throws -> ProjectModel {
    try ProjectLoader().load(root: rootURL, configuration: configuration)
  }
}

/// Runs a subcommand body and turns a `DeadCodeError` into its message and exit status.
func runReportingErrors(_ body: () throws -> Int32) throws {
  let status: Int32
  do {
    status = try body()
  } catch let error as DeadCodeError {
    Output.error(error.message)
    throw ExitCode(error.exitStatus)
  }
  if status != 0 {
    throw ExitCode(status)
  }
}

/// Standard output for results, standard error for diagnostics and progress.
enum Output {
  static func print(_ text: String) {
    guard !text.isEmpty else {
      return
    }
    FileHandle.standardOutput.write(Data((text.hasSuffix("\n") ? text : text + "\n").utf8))
  }

  static func error(_ text: String) {
    FileHandle.standardError.write(Data((text.hasSuffix("\n") ? text : text + "\n").utf8))
  }
}
