import Foundation

/// A failure that stops a subcommand, with the exit status the command line reports.
public struct DeadCodeError: Error, CustomStringConvertible, Equatable, Sendable {
  /// Why the tool failed: a usage or environment problem, or a failed check.
  public enum Kind: Sendable {
    /// The command line, configuration or environment is wrong: exit status 2.
    case usage
    /// A check ran and failed, or a build broke: exit status 1.
    case failure
  }

  public let kind: Kind
  public let message: String

  public init(_ kind: Kind, _ message: String) {
    self.kind = kind
    self.message = message
  }

  public var description: String {
    message
  }

  /// The process exit status for this error.
  public var exitStatus: Int32 {
    switch kind {
    case .usage:
      2
    case .failure:
      1
    }
  }

  static func usage(_ message: String) -> DeadCodeError {
    DeadCodeError(.usage, message)
  }

  static func failure(_ message: String) -> DeadCodeError {
    DeadCodeError(.failure, message)
  }
}
