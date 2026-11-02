import Foundation

/// A copy of the project where builds run, so that nothing a build writes (`.build/`,
/// `Package.resolved`, files a run script generates) lands in the working tree.
///
/// The copy holds every file except `.git` and build directories, ignored files included:
/// Xcode builds need ignored xcconfigs, `Pods/` and generated projects. Reruns copy only what
/// changed, and keep modification times, so builds stay incremental. Local packages outside the
/// project that a build needs are copied too, at the same place relative to the project's copy,
/// so that `../Shared` leads to Shared in the copy as it does in the project.
public struct WorkingCopy: Sendable {
  public static let excludedDirectories = [".git", ".build", "DerivedData"]

  public let source: URL
  public let copy: URL
  /// The local packages outside the project that a build needs, and where their copies go.
  public let packages: [(source: URL, copy: URL)]
  let runner: any CommandRunning

  public init(
    source: URL,
    copy: URL,
    packages: [(source: URL, copy: URL)] = [],
    runner: any CommandRunning = ProcessRunner()
  ) {
    self.source = source
    self.copy = copy
    self.packages = packages
    self.runner = runner
  }

  /// The copy of `model`'s project in `directory`: the directory itself, or, when a build needs
  /// local packages outside the project, the project's place among their copies below it. A
  /// package two levels above the project puts the project's copy two levels down.
  public init(
    model: ProjectModel,
    directory: URL,
    runner: any CommandRunning = ProcessRunner()
  )
    throws
  {
    let paths = try Self.packagesOutside(model, runner: runner)
    // A copy keeps its directory's name, which SwiftPM takes as the package's identity, so a
    // package that holds the project puts its copy one level further down.
    let depth =
      paths.map { path in
        let components = path.split(separator: "/")
        let climb = components.prefix { $0 == ".." }.count
        return climb == components.count ? climb + 1 : climb
      }
      .max() ?? 0
    let place = URL(fileURLWithPath: TextFiles.realPath(model.root)).pathComponents.dropFirst()
      .suffix(depth).joined(separator: "/")
    var packages: [(source: URL, copy: URL)] = []
    for path in paths {
      let destination = TextFiles.normalize(place + "/" + path)
      // Copies stay inside the directory.
      if destination != "..", !destination.hasPrefix("../") {
        packages.append(
          (
            model.root.appendingPathComponent(path).standardizedFileURL,
            directory.appendingPathComponent(destination)
          )
        )
      }
    }
    self.init(
      source: model.root,
      copy: place.isEmpty ? directory : directory.appendingPathComponent(place),
      packages: packages,
      runner: runner
    )
  }

  /// Brings the copy up to date with the working tree and the packages it needs.
  public func refresh() throws {
    // A package that holds the project copies the project too; the project's own copy wins.
    for package in packages {
      try sync(package.source, to: package.copy)
    }
    try sync(source, to: copy)
  }
}

private extension WorkingCopy {
  func sync(_ source: URL, to copy: URL) throws {
    try FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)
    // A link out of the project becomes a file, so writing into the copy never reaches the
    // working tree through it.
    var arguments = ["-a", "--delete", "--copy-unsafe-links"]
    for directory in Self.excludedDirectories {
      arguments.append("--exclude=\(directory)")
    }
    // The trailing slashes copy the contents into the copy, not the directory beside it.
    arguments += [source.path + "/", copy.path + "/"]
    let result = try runner.run(Command("rsync", arguments, in: source))
    guard result.succeeded else {
      throw DeadCodeError.usage(
        "cannot copy \(source.path) into \(copy.path)\n\(result.standardError)"
      )
    }
  }

  /// The local packages outside the project that a build needs, relative to its root: the ones
  /// the project depends on by path, and theirs in turn. A missing package is left to the build
  /// to report.
  static func packagesOutside(
    _ model: ProjectModel,
    runner: any CommandRunning
  ) throws
    -> [String]
  {
    // The packages whose manifests the model already holds.
    var seen = Set(
      [""]
        + model.targets.map(\.manifestPath).filter { $0.hasSuffix("Package.swift") }.map {
          TextFiles.normalize(($0 as NSString).deletingLastPathComponent)
        }
    )
    var pending = model.localPackageDependencies
    var outside: [String] = []
    let adapter = SwiftPackageAdapter(runner: runner)
    while let path = pending.popLast() {
      let directory = model.root.appendingPathComponent(path).standardizedFileURL
      guard seen.insert(path).inserted,
        FileManager.default.fileExists(
          atPath: directory.appendingPathComponent("Package.swift").path
        )
      else {
        continue
      }
      if path == ".." || path.hasPrefix("../") {
        outside.append(path)
      }
      pending += try adapter.localPackageDependencies(of: directory).map { dependency in
        TextFiles.normalize(path + "/" + dependency)
      }
    }
    return outside.sorted()
  }
}
