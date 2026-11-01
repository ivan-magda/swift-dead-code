import Foundation

/// An external program to run, such as `swift`, `git`, `xcodebuild` or `periphery`.
public struct Command: Sendable, Equatable {
  public var executable: String
  public var arguments: [String]
  public var workingDirectory: URL
  /// Variables added to the inherited environment.
  public var environment: [String: String]

  public init(
    _ executable: String,
    _ arguments: [String],
    in workingDirectory: URL,
    environment: [String: String] = [:]
  ) {
    self.executable = executable
    self.arguments = arguments
    self.workingDirectory = workingDirectory
    self.environment = environment
  }

  /// The command as a shell user would type it, for messages.
  public var displayString: String {
    ([executable] + arguments).joined(separator: " ")
  }
}

/// What a finished program printed and how it exited.
public struct CommandResult: Sendable, Equatable {
  public var status: Int32
  public var standardOutput: String
  public var standardError: String

  public init(status: Int32, standardOutput: String, standardError: String) {
    self.status = status
    self.standardOutput = standardOutput
    self.standardError = standardError
  }

  public var succeeded: Bool {
    status == 0
  }

  /// Adds another run's output; a failure of either makes the whole a failure.
  mutating func append(_ other: CommandResult) {
    standardOutput += other.standardOutput
    standardError += other.standardError
    if !other.succeeded {
      status = other.status
    }
  }
}

/// Runs external programs. Tests substitute a recording runner.
public protocol CommandRunning: Sendable {
  func run(_ command: Command) throws -> CommandResult
}

/// Runs programs with `Process`, capturing their output through temporary files so that a
/// large build log cannot fill a pipe and block the child.
public struct ProcessRunner: CommandRunning {
  public init() {}

  public func run(_ command: Command) throws -> CommandResult {
    let scratch = FileManager.default.temporaryDirectory
      .appendingPathComponent("swift-dead-code-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer {
      try? FileManager.default.removeItem(at: scratch)
    }
    let outputURL = scratch.appendingPathComponent("stdout")
    let errorURL = scratch.appendingPathComponent("stderr")
    FileManager.default.createFile(atPath: outputURL.path, contents: nil)
    FileManager.default.createFile(atPath: errorURL.path, contents: nil)
    let output = try FileHandle(forWritingTo: outputURL)
    let error = try FileHandle(forWritingTo: errorURL)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [command.executable] + command.arguments
    process.currentDirectoryURL = command.workingDirectory
    process.environment = ProcessInfo.processInfo.environment.merging(command.environment) {
      _,
      override in
      override
    }
    process.standardOutput = output
    process.standardError = error
    process.standardInput = FileHandle.nullDevice

    do {
      try process.run()
    } catch {
      throw DeadCodeError.usage("cannot run `\(command.displayString)`: \(error)")
    }
    process.waitUntilExit()
    try output.close()
    try error.close()

    return CommandResult(
      status: process.terminationStatus,
      standardOutput: Self.text(at: outputURL),
      standardError: Self.text(at: errorURL)
    )
  }
}

// MARK: - Output Decoding

private extension ProcessRunner {
  static func text(at url: URL) -> String {
    guard let data = FileManager.default.contents(atPath: url.path) else {
      return ""
    }
    // Build logs are UTF-8; a stray byte must not lose the whole log.
    return String(bytes: data, encoding: .utf8) ?? String(bytes: data, encoding: .isoLatin1) ?? ""
  }
}

public extension CommandRunning {
  /// Runs the command and returns its standard output, or throws its error output.
  func output(of command: Command) throws -> String {
    let result = try run(command)
    guard result.succeeded else {
      let detail = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
      throw DeadCodeError.usage("`\(command.displayString)` failed\n\(detail)")
    }
    return result.standardOutput
  }
}
