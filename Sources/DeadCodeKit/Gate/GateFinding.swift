/// A finding of the build-free gate.
public struct GateFinding: Sendable, Hashable, Comparable, CustomStringConvertible {
  public enum Kind: String, Sendable, CaseIterable, Comparable {
    /// A tracked file whose name nothing mentions.
    case file
    /// A declared target dependency that no file of the target imports.
    case dependency
    /// An asset catalog entry whose name nothing mentions.
    case asset

    public static func < (lhs: Kind, rhs: Kind) -> Bool {
      lhs.rawValue < rhs.rawValue
    }
  }

  public var kind: Kind
  /// The file or asset path, or `<target> <module>` for a dependency.
  public var subject: String

  public init(kind: Kind, subject: String) {
    self.kind = kind
    self.subject = subject
  }

  /// The finding as an allowlist entry spells it, without the reason.
  public var description: String {
    "\(kind.rawValue) \(subject)"
  }

  public static func < (lhs: GateFinding, rhs: GateFinding) -> Bool {
    (lhs.kind, lhs.subject) < (rhs.kind, rhs.subject)
  }
}
