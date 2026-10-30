import Foundation
import PackagePlugin

/// `swift package --disable-sandbox dead-code <subcommand> ...` runs the CLI on this package.
///
/// The CLI runs `swift`, `git` and `periphery` itself, so the plugin needs the sandbox off.
@main
struct DeadCodeCommand: CommandPlugin {
  func performCommand(context: PluginContext, arguments: [String]) async throws {
    let tool = try context.tool(named: "swift-dead-code")
    let process = Process()
    process.executableURL = tool.url
    process.arguments = arguments + ["--project-root", context.package.directoryURL.path]
    process.currentDirectoryURL = context.package.directoryURL
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
      Diagnostics.error("swift-dead-code exited with status \(process.terminationStatus)")
    }
  }
}
