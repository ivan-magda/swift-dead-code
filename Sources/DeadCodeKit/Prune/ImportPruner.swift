import Foundation

/// What `prune-imports` checks and how.
public struct PruneOptions: Sendable {
  /// Which modules' imports the run may remove.
  public enum Modules: Sendable, Equatable {
    case all
    /// Dependency modules (package products, pods) plus the configured toolchain modules:
    /// the imports Periphery never reports.
    case dependencies
    case named(Set<String>)
  }

  public var work: URL
  public var checkOnly = false
  public var modules = Modules.all
  public var includePlatform = false
  public var includeTests = false
  public var base: String?
  public var all = false
  public var files: [String] = []
  /// The machine-wide build lock; tests pass their own.
  public var lockName = ScanRunner.lockName

  public init(work: URL) {
    self.work = work
  }
}

/// Finds imports the compiler proves removable, in a copy of the project, and writes them as
/// a patch. A port of swift-claw's `prune_imports.py` that also builds Xcode projects.
///
/// Imports are removed one module at a time, so each new error comes from that module; every
/// import the compiler then needs is put back. Pruning uses the default visibility rule, where
/// a file can compile by borrowing a module that another file of its target imports, so each
/// affected target is then built with MemberImportVisibility and every removed import an error
/// names as a missing defining module is restored.
public final class ImportPruner {
  static let borrowed = try? NSRegularExpression(
    pattern: #"missing import of defining module '(\w+)'"#
  )

  let model: ProjectModel
  let configuration: Configuration
  let options: PruneOptions
  let runner: any CommandRunning
  let progress: (String) -> Void
  let output: (String) -> Void

  public init(
    model: ProjectModel,
    configuration: Configuration,
    options: PruneOptions,
    runner: any CommandRunning = ProcessRunner(),
    progress: @escaping (String) -> Void,
    output: @escaping (String) -> Void
  ) {
    self.model = model
    self.configuration = configuration
    self.options = options
    self.runner = runner
    self.progress = progress
    self.output = output
  }

  /// Runs the check or the prune and returns the exit status: for `--check-only`, 1 when a
  /// listed file borrows imports; for a prune, 0, with the removable imports in the patch.
  public func run() throws -> (status: Int32, removable: Int) {
    let files = try filesToCheck()
    guard !files.isEmpty else {
      throw DeadCodeError.usage("no Swift files inside a target to check")
    }
    let lock = try FileLock(name: options.lockName) {
      progress("another swift-dead-code build is running; waiting for it")
    }
    defer {
      withExtendedLifetime(lock) {}
    }
    let workspace = try PruneWorkspace(
      model: model,
      configuration: configuration,
      work: options.work,
      files: files,
      runner: runner
    )
    if options.checkOnly {
      let owners = Set(files.flatMap { model.owningTargets(of: $0) })
      return (try checkOnly(workspace, owners: owners), 0)
    }
    return try pruneFiles(workspace, files: files)
  }
}

// MARK: - Selection

extension ImportPruner {
  /// The Swift files inside a target that the options select. `--base` and `--all` skip
  /// excluded paths, and test code unless `includeTests`; files named explicitly are always
  /// checked.
  func filesToCheck() throws -> [String] {
    let git = Git(directory: model.root, runner: runner)
    var selected: [String] = []
    if let base = options.base {
      selected += try git.changedFiles(since: base)
    }
    if options.all {
      selected += try git.trackedFiles().filter { $0.hasSuffix(".swift") }
    }
    selected = selected.filter { !configuration.exclude.matchesAny($0) }
    if !options.includeTests {
      let testGlobs = configuration.testSupportGlobs
      selected = selected.filter { !model.isTestCode($0, testGlobs: testGlobs) }
    }
    let compiled = model.compiledFiles
    // A manifest is in no target; rewriting it would also erase the strict setting.
    return Set(options.files + selected)
      .filter { $0.hasSuffix(".swift") && compiled.contains($0) }
      .sorted()
  }

  /// Whether the run may remove imports of `module`, by the `--modules` option alone.
  func isCandidateModule(_ module: String) -> Bool {
    switch options.modules {
    case .all:
      true
    case .dependencies:
      model.externalModules.contains(module)
        || configuration.prune.toolchainModules.contains(module)
    case .named(let names):
      names.contains(module)
    }
  }

  func candidates(in files: [String]) -> [ImportLine] {
    let platform = Set(Defaults.platformModules + configuration.prune.platformModules)
    let kept = Set(configuration.prune.keepModules)
    return files.flatMap { path -> [ImportLine] in
      guard let text = TextFiles.read(model.root.appendingPathComponent(path)) else {
        return []
      }
      return ImportScanner.removableImports(in: text, path: path).filter { line in
        isCandidateModule(line.module) && !kept.contains(line.module)
          && (options.includePlatform || !platform.contains(line.module))
      }
    }
  }
}

// MARK: - Check Only

private extension ImportPruner {
  /// Prints the checked files that compile only by borrowing another file's import; a target
  /// it could not check makes the run fail.
  func checkOnly(_ workspace: PruneWorkspace, owners: Set<String>) throws -> Int32 {
    var borrowing: [String: Set<String>] = [:]
    var unchecked: [String] = []
    try workspace.writeSources(removing: [])
    for name in owners.sorted() {
      progress("check: strict build of \(name)")
      try workspace.writeStrictness(for: [name])
      let (_, errors) = try workspace.build(target: name)
      for (path, messages) in errors where workspace.originalLines[path] != nil {
        borrowing[path, default: []].formUnion(messages)
      }
      let outside = errors.keys.filter { workspace.originalLines[$0] == nil }
      if !workspace.built(name) {
        output("\(name): no configured build compiles it, so \(name) was not checked.")
        unchecked.append(name)
      } else if outside.contains(where: { !model.owningTargets(of: $0).contains(name) }) {
        output(
          "\(name): a dependency failed to build, so \(name) was not checked. "
            + "Log: \(workspace.log.path)"
        )
        unchecked.append(name)
      } else if !outside.isEmpty {
        output(
          "\(name): \(outside.count) files outside the list also borrow imports (not in scope)."
        )
      }
    }
    try workspace.writeStrictness(for: [])
    for (path, messages) in borrowing.sorted(by: { $0.key < $1.key }) {
      output("\(path): needs imports it gets from other files")
      for message in messages.sorted() {
        output("    \(message)")
      }
    }
    guard unchecked.isEmpty else {
      throw DeadCodeError.failure("not checked: \(unchecked.joined(separator: ", "))")
    }
    if borrowing.isEmpty {
      output("No listed file relies on another file's imports.")
    }
    return borrowing.isEmpty ? 0 : 1
  }
}

// MARK: - Prune

private extension ImportPruner {
  func pruneFiles(_ workspace: PruneWorkspace, files: [String]) throws -> (Int32, Int) {
    try workspace.writeStrictness(for: [])
    progress("prune: baseline build for \(files.count) files (the first build is slow)")
    try workspace.writeSources(removing: [])
    let (succeeded, baselineErrors) = try workspace.build()
    guard succeeded else {
      // A target that fails hides its dependents, whose imports would then look removable.
      for (path, messages) in baselineErrors.sorted(by: { $0.key < $1.key }) {
        output("\(path): \(messages.min() ?? "")")
      }
      throw DeadCodeError.failure(
        "baseline build failed; fix the project build first. Log: \(workspace.log.path)"
      )
    }
    // An import in a target no configured build compiles would look removable.
    let unbuilt = files.filter { !workspace.compiledEverywhere($0) }
    if !unbuilt.isEmpty {
      let targets = Set(unbuilt.flatMap { model.owningTargets(of: $0) })
        .filter { !workspace.built($0) }
      output(
        "Not checked: \(unbuilt.count) files of \(targets.sorted().joined(separator: ", ")), "
          + "which no configured build compiles."
      )
    }
    let candidates = candidates(in: files.filter(workspace.compiledEverywhere))
    let removed = try restoreBorrowed(workspace, removed: try prune(workspace, candidates))
    let patch = options.work.appendingPathComponent("prune.patch")
    try TextFiles.write(workspace.patch(removing: removed), to: patch)
    for line in removed.sorted() {
      output("\(line.path):\(line.line): \(line.text)")
    }
    output("\n\(removed.count) of \(candidates.count) candidate imports are removable.")
    output("Patch: \(patch.path) (apply with git apply)")
    return (0, removed.count)
  }

  /// Removes imports one module at a time, so each new error comes from that module.
  func prune(_ workspace: PruneWorkspace, _ candidates: [ImportLine]) throws -> Set<ImportLine> {
    let byModule = Dictionary(grouping: candidates, by: \.module)
    var removed: Set<ImportLine> = []
    for module in byModule.keys.sorted() {
      let imports = Set(byModule[module] ?? [])
      var trial = imports
      while !trial.isEmpty {
        try workspace.writeSources(removing: removed.union(trial))
        let (succeeded, errors) = try workspace.build()
        if succeeded {
          removed.formUnion(trial)
          break
        }
        for path in errors.keys.sorted() {
          trial.subtract(importsToKeep(failing: path, trial: trial))
        }
      }
      let removable = removed.intersection(imports).count
      progress("prune: \(module): \(removable) removable, \(imports.count - removable) needed")
    }
    try workspace.writeSources(removing: removed)
    return removed
  }

  /// The trial imports a build error in this file shows to be needed: the file's own; else,
  /// when the file borrowed the module from a file of its target, those of its targets; else,
  /// when the failure is elsewhere entirely, all of them.
  func importsToKeep(failing path: String, trial: Set<ImportLine>) -> Set<ImportLine> {
    let inFile = trial.filter { $0.path == path }
    if !inFile.isEmpty {
      return inFile
    }
    let owners = model.owningTargets(of: path)
    let inTargets = trial.filter { line in
      !model.owningTargets(of: line.path).isDisjoint(with: owners)
    }
    return inTargets.isEmpty ? trial : inTargets
  }

  /// Puts back removed imports that a file only seemed not to need: it compiled by borrowing
  /// the module from another file of its target.
  func restoreBorrowed(
    _ workspace: PruneWorkspace,
    removed initial: Set<ImportLine>
  ) throws
    -> Set<ImportLine>
  {
    var removed = initial
    while true {
      try workspace.writeSources(removing: removed)
      var restored: Set<ImportLine> = []
      let affected = Set(removed.flatMap { model.owningTargets(of: $0.path) })
      for name in affected.sorted() {
        progress("prune: strict check of \(name)")
        try workspace.writeStrictness(for: [name])
        let (_, errors) = try workspace.build(target: name)
        for (path, messages) in errors {
          let modules = Self.borrowedModules(messages)
          restored.formUnion(removed.filter { $0.path == path && modules.contains($0.module) })
        }
      }
      try workspace.writeStrictness(for: [])
      if restored.isEmpty {
        return removed
      }
      for line in restored.sorted() {
        progress("prune: kept \(line.path):\(line.line) (\(line.text)): the file borrows it")
      }
      removed.subtract(restored)
    }
  }

  static func borrowedModules(_ messages: Set<String>) -> Set<String> {
    guard let expression = borrowed else {
      return []
    }
    var modules: Set<String> = []
    for message in messages {
      let range = NSRange(message.startIndex..., in: message)
      if let match = expression.firstMatch(in: message, range: range),
        let module = Range(match.range(at: 1), in: message)
      {
        modules.insert(String(message[module]))
      }
    }
    return modules
  }
}
