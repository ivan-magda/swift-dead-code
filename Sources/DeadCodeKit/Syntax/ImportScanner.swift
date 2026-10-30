import Foundation
import SwiftParser
import SwiftSyntax

/// An import declaration the pruner may try to remove.
public struct ImportLine: Sendable, Hashable, Comparable {
  /// The file, relative to the project root.
  public var path: String
  /// The 1-based line of the import.
  public var line: Int
  /// The line's text without surrounding whitespace.
  public var text: String
  public var module: String

  public init(path: String, line: Int, text: String, module: String) {
    self.path = path
    self.line = line
    self.text = text
    self.module = module
  }

  public static func < (lhs: ImportLine, rhs: ImportLine) -> Bool {
    (lhs.path, lhs.line) < (rhs.path, rhs.line)
  }
}

/// Reads imports with SwiftSyntax, so comments, strings and `#if` branches parse as the
/// compiler sees them.
public enum ImportScanner {
  /// Every module a file names in an import, in any `#if` branch, plus the modules that
  /// `#externalMacro(module:type:)` expansions load.
  public static func importedModules(in source: String) -> Set<String> {
    let visitor = ModuleCollector(viewMode: .sourceAccurate)
    visitor.walk(Parser.parse(source: source))
    return visitor.modules
  }

  /// The plain top-level imports outside `#if`: the ones the pruner may remove.
  ///
  /// An import with an access level, `@_exported`, `@_implementationOnly`, a declaration
  /// kind (`import struct`), a submodule path, or a comment or other code on its line is
  /// never a candidate: removing it changes more than one file's visibility, or the line
  /// explains itself.
  public static func removableImports(in source: String, path: String) -> [ImportLine] {
    let tree = Parser.parse(source: source)
    let converter = SourceLocationConverter(fileName: path, tree: tree)
    let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
    var imports: [ImportLine] = []
    for item in tree.statements {
      guard
        let declaration = item.item.as(ImportDeclSyntax.self),
        isPlain(declaration),
        let module = declaration.path.first?.name.text
      else {
        continue
      }
      let line = converter.location(for: declaration.positionAfterSkippingLeadingTrivia).line
      guard line <= lines.count else {
        continue
      }
      let text = lines[line - 1].trimmingCharacters(in: .whitespaces)
      guard text == declaration.trimmedDescription else {
        continue
      }
      imports.append(ImportLine(path: path, line: line, text: text, module: module))
    }
    return imports
  }
}

// MARK: - Visitors

private extension ImportScanner {
  static let allowedAttributes: Set<String> = ["testable", "preconcurrency", "_spi"]

  static func isPlain(_ declaration: ImportDeclSyntax) -> Bool {
    guard declaration.modifiers.isEmpty, declaration.importKindSpecifier == nil,
      declaration.path.count == 1
    else {
      return false
    }
    return declaration.attributes.allSatisfy { element in
      guard let attribute = element.as(AttributeSyntax.self) else {
        return false
      }
      return allowedAttributes.contains(attribute.attributeName.trimmedDescription)
    }
  }
}

private final class ModuleCollector: SyntaxVisitor {
  var modules: Set<String> = []

  override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
    if let module = node.path.first?.name.text {
      modules.insert(module)
    }
    return .skipChildren
  }

  override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
    guard node.macroName.text == "externalMacro" else {
      return .visitChildren
    }
    for argument in node.arguments where argument.label?.text == "module" {
      if let literal = argument.expression.as(StringLiteralExprSyntax.self),
        let module = literal.representedLiteralValue
      {
        modules.insert(module)
      }
    }
    return .skipChildren
  }
}
