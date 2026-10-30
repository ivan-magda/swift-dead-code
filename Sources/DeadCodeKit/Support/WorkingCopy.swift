import Foundation

/// A copy of the project where builds run, so that nothing a build writes (`.build/`,
/// `Package.resolved`, files a run script generates) lands in the working tree.
///
/// The copy holds every file except `.git` and build directories, ignored files included:
/// Xcode builds need ignored xcconfigs, `Pods/` and generated projects. Reruns copy only what
/// changed, and keep modification times, so builds stay incremental.
public struct WorkingCopy: Sendable {
  public static let excludedDirectories = [".git", ".build", "DerivedData"]

  public let source: URL
  public let copy: URL
  let runner: any CommandRunning

  public init(source: URL, copy: URL, runner: any CommandRunning = ProcessRunner()) {
    self.source = source
    self.copy = copy
    self.runner = runner
  }

  /// Brings the copy up to date with the working tree.
  public func refresh() throws {
    try FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)
    var arguments = ["-a", "--delete"]
    for directory in Self.excludedDirectories {
      arguments.append("--exclude=\(directory)")
    }
    // The trailing slashes copy the contents into the copy, not the directory beside it.
    arguments += [source.path + "/", copy.path + "/"]
    let result = try runner.run(Command("rsync", arguments, in: source))
    guard result.succeeded else {
      throw DeadCodeError.usage(
        "cannot copy the project into \(copy.path)\n\(result.standardError)"
      )
    }
  }
}
