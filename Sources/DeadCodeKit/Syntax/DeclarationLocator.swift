import Foundation
import SwiftParser
import SwiftSyntax

/// A type or extension that encloses a declaration.
public struct EnclosingType: Sendable, Equatable {
  /// `struct`, `class`, `enum`, `actor`, `protocol` or `extension`.
  public var kind: String
  public var name: String
  /// The inherited types and conformances, as written.
  public var inheritance: [String]
  public var attributes: [String]
}

/// What the source says about the declaration at a Periphery location.
public struct DeclarationContext: Sendable, Equatable {
  /// Attribute names without `@`, such as `objc`, `IBAction`, `Test` or `State`.
  public var attributes: [String]
  /// Attributes and comments above the declaration, as written.
  public var leadingText: String
  /// The innermost enclosing type first.
  public var enclosingTypes: [EnclosingType]
  /// A type declaration's own inherited types and conformances.
  public var ownInheritance: [String]
  /// Modifiers such as `dynamic`, `override` or `public`.
  public var modifiers: [String]
  /// The function a parameter belongs to: its attributes, such as `Test(arguments:)`.
  public var functionAttributes: [String]
  /// Whether the function's `@Test` attribute passes `arguments:`.
  public var isParameterizedTest: Bool
  /// The declared type or initial value of a property, as written.
  public var typeText: String
  /// Whether the declaration sits inside a `#Preview` body.
  public var isInsidePreview: Bool
}

/// Parses Swift files once and answers questions about declarations in them.
public final class SourceIndex {
  fileprivate struct ParsedFile {
    var tree: SourceFileSyntax
    var converter: SourceLocationConverter
    var lineCount: Int
  }

  private let root: URL
  private var files: [String: ParsedFile?] = [:]
  // Built on first use per file: a report asks about thousands of declarations in a large
  // project, so each question must not walk the whole file again.
  private var identifierTokens: [String: [String: [TokenSyntax]]] = [:]
  private var projectedNames: [String: Set<String>] = [:]
  private var inheritanceByType: [String: [String: [String]]] = [:]
  private var topLevelTypes: [String: Set<String>] = [:]

  public init(root: URL) {
    self.root = root
  }

  /// The number of lines in a file, or nil if it is gone.
  public func lineCount(of path: String) -> Int? {
    parsed(path)?.lineCount
  }

  /// The declaration whose name sits at `line:column`, or nil when no declaration is there.
  public func declaration(in path: String, line: Int, column: Int) -> DeclarationContext? {
    guard let file = parsed(path), let node = declarationNode(in: file, line: line, column: column)
    else {
      return nil
    }
    return context(of: node)
  }

  /// The names of the functions in the file that mention `name` outside the declaration at
  /// `line`, with `nil` standing for a mention outside any function.
  public func users(of name: String, in path: String, excludingLine line: Int) -> Set<String?> {
    guard let file = parsed(path) else {
      return []
    }
    var users: Set<String?> = []
    for token in identifiers(in: path, file: file)[name] ?? [] {
      let tokenLine = file.converter.location(for: token.positionAfterSkippingLeadingTrivia).line
      guard tokenLine != line else {
        continue
      }
      let function = Self.enclosingFunction(of: Syntax(token))
      // A use inside the declaration itself, such as a call to an overload, is no user.
      if let function,
        file.converter.location(for: function.name.positionAfterSkippingLeadingTrivia).line == line
      {
        continue
      }
      users.insert(function?.name.text)
    }
    return users
  }

  /// Whether the file names `$name`, the projected value of a property wrapper.
  public func mentionsProjectedValue(_ name: String, in path: String) -> Bool {
    if projectedNames[path] == nil, let file = parsed(path) {
      projectedNames[path] = Set(
        file.tree.tokens(viewMode: .sourceAccurate).map(\.text).filter { $0.hasPrefix("$") }
      )
    }
    return projectedNames[path]?.contains("$" + name) ?? false
  }

  /// The inherited types of the type named `typeName` declared anywhere in the file.
  public func declaredInheritance(of typeName: String, in path: String) -> [String] {
    inheritance(in: path)[typeName] ?? []
  }

  /// The names of the types the file declares at top level, extensions excluded.
  public func topLevelTypeNames(in path: String) -> Set<String> {
    if topLevelTypes[path] == nil {
      _ = inheritance(in: path)
    }
    return topLevelTypes[path] ?? []
  }
}

// MARK: - Parsing

private extension SourceIndex {
  func parsed(_ path: String) -> ParsedFile? {
    if let cached = files[path] {
      return cached
    }
    var parsed: ParsedFile?
    if let text = TextFiles.read(root.appendingPathComponent(path)) {
      let tree = Parser.parse(source: text)
      let converter = SourceLocationConverter(fileName: path, tree: tree)
      // The parser's line count: Swift reads "\r\n" as one Character, not "\n".
      parsed = ParsedFile(
        tree: tree,
        converter: converter,
        lineCount: converter.location(for: tree.endPosition).line
      )
    }
    files[path] = parsed
    return parsed
  }

  /// Identifier tokens by name.
  func identifiers(in path: String, file: ParsedFile) -> [String: [TokenSyntax]] {
    if let cached = identifierTokens[path] {
      return cached
    }
    var tokens: [String: [TokenSyntax]] = [:]
    for token in file.tree.tokens(viewMode: .sourceAccurate) {
      if case .identifier(let text) = token.tokenKind {
        tokens[text, default: []].append(token)
      }
    }
    identifierTokens[path] = tokens
    return tokens
  }

  /// Inherited types and conformances by type name, from declarations and extensions.
  func inheritance(in path: String) -> [String: [String]] {
    if let cached = inheritanceByType[path] {
      return cached
    }
    guard let file = parsed(path) else {
      topLevelTypes[path] = []
      return [:]
    }
    let collector = TypeDeclarationCollector()
    collector.walk(file.tree)
    inheritanceByType[path] = collector.inheritance
    topLevelTypes[path] = collector.topLevelTypes
    return collector.inheritance
  }

  func declarationNode(in file: ParsedFile, line: Int, column: Int) -> Syntax? {
    guard line >= 1, line <= file.lineCount else {
      return nil
    }
    let position = file.converter.position(ofLine: line, column: max(column, 1))
    let token =
      file.tree.token(at: position)
      ?? file.tree.tokens(viewMode: .sourceAccurate).first { token in
        file.converter.location(for: token.positionAfterSkippingLeadingTrivia).line == line
      }
    var node = token.map(Syntax.init)
    while let current = node {
      if Self.isDeclaration(current) {
        return current
      }
      node = current.parent
    }
    return nil
  }

  static func isDeclaration(_ node: Syntax) -> Bool {
    node.is(VariableDeclSyntax.self) || node.is(FunctionDeclSyntax.self)
      || node.is(InitializerDeclSyntax.self) || node.is(SubscriptDeclSyntax.self)
      || node.is(EnumCaseElementSyntax.self) || node.is(FunctionParameterSyntax.self)
      || node.is(ClosureParameterSyntax.self) || node.is(EnumCaseParameterSyntax.self)
      || node.is(StructDeclSyntax.self) || node.is(ClassDeclSyntax.self)
      || node.is(EnumDeclSyntax.self) || node.is(ProtocolDeclSyntax.self)
      || node.is(ActorDeclSyntax.self) || node.is(TypeAliasDeclSyntax.self)
      || node.is(AssociatedTypeDeclSyntax.self) || node.is(ImportDeclSyntax.self)
      || node.is(MacroDeclSyntax.self) || node.is(ExtensionDeclSyntax.self)
  }
}

// MARK: - Context

private extension SourceIndex {
  func context(of node: Syntax) -> DeclarationContext {
    let owner = Self.attributeOwner(of: node)
    var enclosingTypes: [EnclosingType] = []
    var functionAttributes: [String] = []
    var isParameterizedTest = false
    var isInsidePreview = false
    var ancestor = node.parent
    while let current = ancestor {
      if let type = Self.enclosingType(current) {
        enclosingTypes.append(type)
      }
      if functionAttributes.isEmpty, let function = current.as(FunctionDeclSyntax.self),
        node.is(FunctionParameterSyntax.self)
      {
        functionAttributes = Self.attributeNames(function.attributes)
        isParameterizedTest = Self.isParameterizedTest(function.attributes)
      }
      if let macro = current.as(MacroExpansionDeclSyntax.self), macro.macroName.text == "Preview" {
        isInsidePreview = true
      }
      if let macro = current.as(MacroExpansionExprSyntax.self), macro.macroName.text == "Preview" {
        isInsidePreview = true
      }
      ancestor = current.parent
    }
    return DeclarationContext(
      attributes: owner.map { Self.attributeNames($0.attributes) } ?? [],
      leadingText: owner.map(Self.leadingText) ?? "",
      enclosingTypes: enclosingTypes,
      ownInheritance: Self.enclosingType(node)?.inheritance ?? [],
      modifiers: Self.modifierNames(of: node),
      functionAttributes: functionAttributes,
      isParameterizedTest: isParameterizedTest,
      typeText: Self.typeText(of: node),
      isInsidePreview: isInsidePreview
    )
  }

  /// The declaration that carries attributes and doc comments for this node: an enum case's
  /// `case` declaration, or the node itself.
  static func attributeOwner(of node: Syntax) -> (any WithAttributesSyntax)? {
    if node.is(EnumCaseElementSyntax.self) {
      return node.parent?.parent?.asProtocol(WithAttributesSyntax.self)
    }
    return node.asProtocol(WithAttributesSyntax.self)
  }

  static func enclosingType(_ node: Syntax) -> EnclosingType? {
    if let decl = node.as(StructDeclSyntax.self) {
      return EnclosingType(
        kind: "struct",
        name: decl.name.text,
        inheritance: inheritance(decl.inheritanceClause),
        attributes: attributeNames(decl.attributes)
      )
    }
    if let decl = node.as(ClassDeclSyntax.self) {
      return EnclosingType(
        kind: "class",
        name: decl.name.text,
        inheritance: inheritance(decl.inheritanceClause),
        attributes: attributeNames(decl.attributes)
      )
    }
    if let decl = node.as(EnumDeclSyntax.self) {
      return EnclosingType(
        kind: "enum",
        name: decl.name.text,
        inheritance: inheritance(decl.inheritanceClause),
        attributes: attributeNames(decl.attributes)
      )
    }
    if let decl = node.as(ActorDeclSyntax.self) {
      return EnclosingType(
        kind: "actor",
        name: decl.name.text,
        inheritance: inheritance(decl.inheritanceClause),
        attributes: attributeNames(decl.attributes)
      )
    }
    if let decl = node.as(ProtocolDeclSyntax.self) {
      return EnclosingType(
        kind: "protocol",
        name: decl.name.text,
        inheritance: inheritance(decl.inheritanceClause),
        attributes: attributeNames(decl.attributes)
      )
    }
    if let decl = node.as(ExtensionDeclSyntax.self) {
      return EnclosingType(
        kind: "extension",
        name: decl.extendedType.trimmedDescription,
        inheritance: inheritance(decl.inheritanceClause),
        attributes: attributeNames(decl.attributes)
      )
    }
    return nil
  }

  static func modifierNames(of node: Syntax) -> [String] {
    let owner =
      node.is(EnumCaseElementSyntax.self)
      ? node.parent?.parent?.asProtocol(WithModifiersSyntax.self)
      : node.asProtocol(WithModifiersSyntax.self)
    return owner?.modifiers.map(\.name.text) ?? []
  }

  static func inheritance(_ clause: InheritanceClauseSyntax?) -> [String] {
    clause?.inheritedTypes.map { $0.type.trimmedDescription } ?? []
  }

  static func attributeNames(_ attributes: AttributeListSyntax) -> [String] {
    attributes.compactMap { element in
      element.as(AttributeSyntax.self)?.attributeName.trimmedDescription
    }
  }

  static func isParameterizedTest(_ attributes: AttributeListSyntax) -> Bool {
    attributes.contains { element in
      guard let attribute = element.as(AttributeSyntax.self),
        attribute.attributeName.trimmedDescription == "Test",
        case .argumentList(let arguments)? = attribute.arguments
      else {
        return false
      }
      return arguments.contains { $0.label?.text == "arguments" }
    }
  }

  static func leadingText(_ owner: any WithAttributesSyntax) -> String {
    let comments = owner.leadingTrivia.compactMap { piece -> String? in
      switch piece {
      case .lineComment(let text), .docLineComment(let text), .blockComment(let text),
        .docBlockComment(let text):
        text
      default:
        nil
      }
    }
    return (comments + [owner.attributes.trimmedDescription]).joined(separator: "\n")
  }

  static func typeText(of node: Syntax) -> String {
    if let variable = node.as(VariableDeclSyntax.self) {
      return variable.bindings.map { binding in
        [
          binding.typeAnnotation?.type.trimmedDescription,
          binding.initializer?.value.trimmedDescription,
        ]
        .compactMap { $0 }
        .joined(separator: " = ")
      }
      .joined(separator: ", ")
    }
    if let parameter = node.as(FunctionParameterSyntax.self) {
      return parameter.type.trimmedDescription
    }
    return ""
  }

  /// The function whose body holds the node. A mention in an initializer, accessor or
  /// property initializer has no function, so it counts as a use nobody flagged.
  static func enclosingFunction(of node: Syntax) -> FunctionDeclSyntax? {
    var ancestor = node.parent
    while let current = ancestor {
      if let function = current.as(FunctionDeclSyntax.self) {
        return function
      }
      // Reaching the member boundary first means a property, accessor or initializer.
      if current.is(InitializerDeclSyntax.self) || current.is(MemberBlockItemSyntax.self) {
        return nil
      }
      ancestor = current.parent
    }
    return nil
  }
}

/// Collects the inherited types of every type declaration and extension in a file, and the
/// names of its top-level types.
private final class TypeDeclarationCollector: SyntaxVisitor {
  var inheritance: [String: [String]] = [:]
  var topLevelTypes: Set<String> = []
  private var depth = 0

  init() {
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
    enter(node.name.text, node.inheritanceClause)
    return .visitChildren
  }

  override func visitPost(_ node: StructDeclSyntax) {
    depth -= 1
  }

  override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
    enter(node.name.text, node.inheritanceClause)
    return .visitChildren
  }

  override func visitPost(_ node: ClassDeclSyntax) {
    depth -= 1
  }

  override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
    enter(node.name.text, node.inheritanceClause)
    return .visitChildren
  }

  override func visitPost(_ node: EnumDeclSyntax) {
    depth -= 1
  }

  override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
    enter(node.name.text, node.inheritanceClause)
    return .visitChildren
  }

  override func visitPost(_ node: ActorDeclSyntax) {
    depth -= 1
  }

  override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
    record(node.extendedType.trimmedDescription, node.inheritanceClause)
    depth += 1
    return .visitChildren
  }

  override func visitPost(_ node: ExtensionDeclSyntax) {
    depth -= 1
  }

  private func enter(_ name: String, _ clause: InheritanceClauseSyntax?) {
    if depth == 0 {
      topLevelTypes.insert(name)
    }
    depth += 1
    record(name, clause)
  }

  private func record(_ name: String, _ clause: InheritanceClauseSyntax?) {
    guard let clause else {
      return
    }
    inheritance[name, default: []] += clause.inheritedTypes.map { $0.type.trimmedDescription }
  }
}
