import Foundation
import SwiftParser
import SwiftSyntax

/// Where identifiers appear inside string literals and resource files: the places a runtime
/// lookup (`NSClassFromString`, nib names, `NSExtensionPrincipalClass`, KVO keys) names code
/// that no index reference reaches.
public final class StringMentions {
  /// File extensions whose text names classes, selectors or keys at runtime.
  public static let resourceExtensions: Set<String> = [
    "intentdefinition", "plist", "storyboard", "strings", "xcstrings", "xib",
  ]

  private let root: URL
  private let swiftFiles: [String]
  private let resourceFiles: [String]
  private var firstMention: [String: String] = [:]
  private var isIndexed = false

  public init(root: URL, swiftFiles: [String], resourceFiles: [String]) {
    self.root = root
    self.swiftFiles = swiftFiles.sorted()
    self.resourceFiles = resourceFiles.sorted()
  }

  /// The first `path:line` whose string or resource text names `identifier`, if any.
  public func location(of identifier: String) -> String? {
    if !isIndexed {
      firstMention = buildIndex()
      isIndexed = true
    }
    return firstMention[identifier]
  }

  /// Resource files among `paths`, including Core Data model contents.
  public static func resources(among paths: [String]) -> [String] {
    paths.filter { path in
      resourceExtensions.contains((path as NSString).pathExtension)
        || (path.hasSuffix("/contents") && path.contains(".xcdatamodel/"))
    }
  }
}

// MARK: - Index

private extension StringMentions {
  func buildIndex() -> [String: String] {
    var index: [String: String] = [:]
    for path in swiftFiles {
      guard let text = TextFiles.read(root.appendingPathComponent(path)) else {
        continue
      }
      let tree = Parser.parse(source: text)
      let converter = SourceLocationConverter(fileName: path, tree: tree)
      for token in tree.tokens(viewMode: .sourceAccurate) {
        guard case .stringSegment(let segment) = token.tokenKind else {
          continue
        }
        let line = converter.location(for: token.positionAfterSkippingLeadingTrivia).line
        Self.record(segment, at: "\(path):\(line)", into: &index)
      }
    }
    for path in resourceFiles {
      guard let text = TextFiles.read(root.appendingPathComponent(path)) else {
        continue
      }
      for (offset, line) in text.split(separator: "\n", omittingEmptySubsequences: false)
        .enumerated()
      {
        Self.record(Substring(line), at: "\(path):\(offset + 1)", into: &index)
      }
    }
    return index
  }

  static func record<Text: StringProtocol>(
    _ text: Text,
    at location: String,
    into index: inout [String: String]
  ) {
    var word = ""
    for character in text {
      if character.isLetter || character.isNumber || character == "_" {
        word.append(character)
      } else if !word.isEmpty {
        if index[word] == nil {
          index[word] = location
        }
        word = ""
      }
    }
    if !word.isEmpty, index[word] == nil {
      index[word] = location
    }
  }
}
