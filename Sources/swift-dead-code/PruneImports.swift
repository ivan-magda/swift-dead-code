import ArgumentParser
import DeadCodeKit
import Foundation

struct PruneImports: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Find imports the compiler proves removable, in a copy of the project.",
    discussion: """
      Periphery reports unused imports only for modules it indexed, so imports of package
      dependencies and some project imports never show up. This command removes imports in
      WORK/copy one module at a time, builds, and restores every import the compiler needs,
      then restores imports a file borrows from another file of its target
      (MemberImportVisibility). It writes WORK/prune.patch and never touches the working tree.

      --check-only lists the files that compile only because another file of their target
      imports a module. --base and --all skip test code unless --include-tests is given.
      Imports of Foundation and OS modules are skipped unless --include-platform: a build
      for one platform cannot prove another still compiles without them. Imports inside #if
      are never candidates. Runs take a machine-wide lock.
      """
  )

  @OptionGroup
  var options: ProjectOptions

  @Option(help: "Scratch directory for the copy, the builds and the patch.")
  var work: String

  @Flag(help: "List files that borrow imports instead of pruning.")
  var checkOnly = false

  @Option(help: "Comma-separated modules to try, or `deps` for dependency modules.")
  var modules: String?

  @Flag(help: "Also try Foundation, OS modules and Crypto.")
  var includePlatform = false

  @Flag(help: "Also check test code with --base or --all.")
  var includeTests = false

  @Option(help: "Check Swift files added or changed since this git ref.")
  var base: String?

  @Flag(help: "Check every Swift file in a target.")
  var all = false

  @Flag(help: "Exit 1 when the patch removes anything (for CI).")
  var strict = false

  @Argument(help: "Swift files to check, relative to the project root.")
  var files: [String] = []

  func run() throws {
    try runReportingErrors {
      let configuration = try options.loadConfiguration()
      let model = try options.loadProject(configuration)
      var pruneOptions = PruneOptions(work: URL(fileURLWithPath: work).standardizedFileURL)
      pruneOptions.checkOnly = checkOnly
      pruneOptions.includePlatform = includePlatform
      pruneOptions.includeTests = includeTests
      pruneOptions.base = base
      pruneOptions.all = all
      pruneOptions.files = files
      switch modules {
      case nil:
        pruneOptions.modules = .all
      case "deps":
        pruneOptions.modules = .dependencies
      case let list?:
        pruneOptions.modules = .named(Set(list.split(separator: ",").map(String.init)))
      }
      let pruner = ImportPruner(
        model: model,
        configuration: configuration,
        options: pruneOptions,
        progress: { Output.error($0) },
        output: { Output.print($0) }
      )
      let (status, removable) = try pruner.run()
      return strict && removable > 0 ? 1 : status
    }
  }
}
