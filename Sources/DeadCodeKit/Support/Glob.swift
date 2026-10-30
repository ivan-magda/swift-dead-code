import Foundation

/// A path pattern from the configuration: `*` matches within one path component, `**` across
/// components, `?` one character. A pattern ending in `/` matches everything below it.
public struct Glob: Sendable, Hashable, CustomStringConvertible {
  public let pattern: String
  private let expression: String

  public init(_ pattern: String) {
    self.pattern = pattern
    self.expression = Self.regularExpression(for: pattern)
  }

  public var description: String {
    pattern
  }

  /// Whether a relative path matches the whole pattern.
  public func matches(_ path: String) -> Bool {
    path.range(of: expression, options: .regularExpression) != nil
  }
}

public extension Collection<Glob> {
  /// Whether any pattern matches the path.
  func matchesAny(_ path: String) -> Bool {
    contains { glob in
      glob.matches(path)
    }
  }
}

// MARK: - Translation

private extension Glob {
  static func regularExpression(for pattern: String) -> String {
    var source = pattern
    if source.hasSuffix("/") {
      source += "**"
    }
    var expression = "^"
    var characters = Array(source)[...]
    while let character = characters.popFirst() {
      switch character {
      case "*" where characters.first == "*":
        characters.removeFirst()
        if characters.first == "/" {
          // `**/` also matches no directory at all.
          characters.removeFirst()
          expression += "(?:.*/)?"
        } else {
          expression += ".*"
        }
      case "*":
        expression += "[^/]*"
      case "?":
        expression += "[^/]"
      default:
        expression += NSRegularExpression.escapedPattern(for: String(character))
      }
    }
    return expression + "$"
  }
}
