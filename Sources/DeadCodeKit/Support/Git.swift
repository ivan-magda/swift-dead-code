import Foundation

/// Read-only git queries in a project directory. Paths are relative to that directory.
public struct Git: Sendable {
  public let directory: URL
  let runner: any CommandRunning

  public init(directory: URL, runner: any CommandRunning = ProcessRunner()) {
    self.directory = directory
    self.runner = runner
  }

  /// Files git tracks, sorted, that exist on disk.
  public func trackedFiles() throws -> [String] {
    try existingFiles(listing: ["ls-files", "-z", "--cached"])
  }

  /// Tracked files plus untracked ones that git does not ignore, sorted, that exist on disk.
  ///
  /// SwiftPM compiles untracked files in a target directory, so their imports count.
  public func trackedAndUntrackedFiles() throws -> [String] {
    try existingFiles(listing: ["ls-files", "-z", "--cached", "--others", "--exclude-standard"])
  }

  /// Files added, modified or renamed since `base`, relative to the project directory.
  public func changedFiles(since base: String) throws -> [String] {
    let output = try runner.output(
      of: Command(
        "git",
        ["diff", "-z", "--name-only", "--relative", "--diff-filter=AMR", base],
        in: directory
      )
    )
    // -z keeps paths unquoted: without it git escapes names such as `Über.swift`.
    return output.split(separator: "\0").map(String.init).sorted()
  }

  /// Whether the directory is inside a git work tree.
  public func isRepository() -> Bool {
    let result = try? runner.run(
      Command("git", ["rev-parse", "--is-inside-work-tree"], in: directory)
    )
    return result?.succeeded == true
  }
}

// MARK: - Listing

private extension Git {
  func existingFiles(listing arguments: [String]) throws -> [String] {
    let output = try runner.output(of: Command("git", arguments, in: directory))
    var isDirectory: ObjCBool = false
    return Set(output.split(separator: "\0").map(String.init))
      .filter { path in
        let exists = FileManager.default.fileExists(
          atPath: directory.appendingPathComponent(path).path,
          isDirectory: &isDirectory
        )
        return exists && !isDirectory.boolValue
      }
      .sorted()
  }
}
