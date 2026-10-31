import Foundation

/// Hints about why Periphery may be wrong about a declaration. They point at the check to
/// make; they never prove that a declaration is dead or alive.
struct TriageNotes {
  static let parameterHint =
    "check the signature it must match: protocol, override, closure or function type"
  static let sourceMissing = "source not found at this location; rescan"

  /// Protocols whose conformers the system finds at runtime, by metadata or Info.plist.
  static let runtimeProtocols: Set<String> = [
    "AppEntity", "AppEnum", "AppIntent", "AppIntentTimelineProvider", "AppShortcutsProvider",
    "ControlWidget", "EntityQuery", "EntityStringQuery", "IntentTimelineProvider",
    "LiveActivityIntent", "TimelineProvider", "Widget", "WidgetBundle",
    "WidgetConfigurationIntent", "ControlConfigurationIntent", "SetValueIntent", "OpenIntent",
    "AudioPlaybackIntent", "ForegroundContinuableIntent", "DynamicOptionsProvider",
    "EntityPropertyQuery",
  ]
  static let projectedWrappers: Set<String> = [
    "AppStorage", "Bindable", "Binding", "Environment", "EnvironmentObject", "FocusState",
    "GestureState", "ObservedObject", "Published", "SceneStorage", "State", "StateObject",
  ]
  /// SwiftUI installs these even when nothing reads them.
  static let dynamicProperties: Set<String> = [
    "AccessibilityFocusState", "AppStorage", "Bindable", "Environment", "EnvironmentObject",
    "FocusState", "FocusedObject", "FocusedValue", "GestureState", "Namespace", "ObservedObject",
    "Query", "ScaledMetric", "SceneStorage", "State", "StateObject",
  ]
  static let interfaceBuilderAttributes: Set<String> = [
    "IBAction", "IBInspectable", "IBOutlet", "IBSegueAction",
  ]
  static let entryPointAttributes: Set<String> = ["main", "NSApplicationMain", "UIApplicationMain"]
  static let lifetimeTypes = try? NSRegularExpression(
    pattern: #"Cancellable|Task\b|Observation|Observer|Token|Subscription|Lease|Timer|Handle"#
  )
  static let seamComment = try? NSRegularExpression(
    pattern: #"\b(?:tests?|seam)\b"#,
    options: .caseInsensitive
  )

  let model: ProjectModel
  let configuration: Configuration
  let sources: SourceIndex
  let mentions: StringMentions
  let twins: ModuleTwins

  /// The notes for one finding; `flaggedFunctions` are the bare names of flagged functions.
  func notes(for finding: PeripheryFinding, flaggedFunctions: Set<String> = []) -> [String] {
    guard let lineCount = sources.lineCount(of: finding.path), finding.line >= 1,
      finding.line <= lineCount
    else {
      return [Self.sourceMissing]
    }
    let context = sources.declaration(in: finding.path, line: finding.line, column: finding.column)
    var notes: [String] = []
    if finding.kind == "var.parameter", context?.isParameterizedTest == true {
      notes.append("argument of a parameterized @Test")
    }
    if finding.hints.contains("redundantConformance") || finding.hints.contains("redundantProtocol")
    {
      notes.append(
        "nothing uses it as the protocol: a marker for code generators (Sourcery) or runtime "
          + "discovery keeps it"
      )
    }
    if finding.kind == "var.parameter", context?.typeText.hasPrefix("isolated ") == true {
      notes.append("isolated parameter: it runs the function on that actor, a use by effect")
    }
    if let context, let type = context.enclosingTypes.first {
      notes += enclosingTypeNotes(finding, type: type)
    }
    if finding.kind == "var.parameter" && notes.isEmpty {
      notes.append(Self.parameterHint)
    }
    if !model.isTestCode(finding.path, testGlobs: configuration.testSupportGlobs),
      isTestSeam(finding, context: context)
    {
      notes.append("named or documented as a test seam")
    }
    if !flaggedFunctions.isEmpty, let note = flaggedCallerNote(finding, flaggedFunctions) {
      notes.append(note)
    }
    if let context {
      notes += platformNotes(finding, context: context)
    }
    if let context, let note = moduleTwinNote(finding, context: context) {
      notes.append(note)
    }
    return notes
  }
}

/// Targets that share a module name, such as an iOS and a macOS app both named after the
/// product. Their builds share one index, where same-named types in them merge.
struct ModuleTwins {
  /// For each target that has twins, each twin and the top-level types it declares.
  private let twins: [String: [(target: ProjectTarget, types: Set<String>)]]

  init(model: ProjectModel, sources: SourceIndex) {
    var twins: [String: [(target: ProjectTarget, types: Set<String>)]] = [:]
    for group in Dictionary(grouping: model.targets, by: \.moduleName).values where group.count > 1
    {
      let declared = group.map { target in
        let types = target.sourceFiles.reduce(into: Set<String>()) { types, path in
          types.formUnion(sources.topLevelTypeNames(in: path))
        }
        return (target: target, types: types)
      }
      for target in group {
        twins[target.name] = declared.filter { $0.target.name != target.name }
      }
    }
    self.twins = twins
  }

  /// A twin of a target compiling `path` that declares `typeName` in a file of its own.
  func twin(declaring typeName: String, in path: String, model: ProjectModel) -> ProjectTarget? {
    for owner in model.targets where owner.compiles(path) {
      let twin = twins[owner.name]?.first { twin in
        !twin.target.compiles(path) && twin.types.contains(typeName)
      }
      if let twin {
        return twin.target
      }
    }
    return nil
  }
}

// MARK: - swift-claw Notes

private extension TriageNotes {
  func enclosingTypeNotes(_ finding: PeripheryFinding, type: EnclosingType) -> [String] {
    var notes: [String] = []
    let name = type.name
    if finding.kind == "enumelement" && conforms(type, to: ["CaseIterable"], in: finding.path) {
      notes.append("\(name) is CaseIterable: reachable through allCases")
    }
    if finding.kind.hasPrefix("var.instance") {
      if conforms(type, to: ["Encodable", "Codable"], in: finding.path) {
        notes.append("\(name) is Encodable: the field is serialized")
      } else if conforms(type, to: ["Equatable", "Hashable"], in: finding.path) {
        notes.append("\(name) is Equatable/Hashable: the field takes part in ==")
      }
    }
    if type.kind == "protocol" {
      notes.append(
        "protocol requirement: check calls on conforming types and documented contracts"
      )
    }
    // A protocol's own requirements get the note above; only implementations witness.
    if finding.kind.hasPrefix("function") && type.kind != "protocol" && !type.inheritance.isEmpty {
      notes.append("may witness a requirement of: \(type.inheritance.joined(separator: ", "))")
    }
    return notes
  }

  /// Whether the type adopts one of the protocols where it is declared, or in an extension
  /// in the same file.
  func conforms(_ type: EnclosingType, to protocols: Set<String>, in path: String) -> Bool {
    let inherited = type.inheritance + sources.declaredInheritance(of: type.name, in: path)
    return inherited.contains { protocols.contains(Self.baseName($0)) }
      || sources.hasConformingExtension(of: type.name, to: protocols, in: path)
  }

  func isTestSeam(_ finding: PeripheryFinding, context: DeclarationContext?) -> Bool {
    let name = finding.name
    if name.range(of: configuration.triage.seamNamePattern, options: .regularExpression) != nil {
      return true
    }
    guard let text = context?.leadingText, let expression = Self.seamComment else {
      return false
    }
    return expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
  }

  func flaggedCallerNote(_ finding: PeripheryFinding, _ flagged: Set<String>) -> String? {
    let bareName = finding.bareName
    guard finding.kind != "var.parameter",
      bareName.range(of: #"^\w+$"#, options: .regularExpression) != nil
    else {
      return nil
    }
    let users = sources.users(of: bareName, in: finding.path, excludingLine: finding.line)
    let names = users.compactMap { $0 }
    guard !users.isEmpty, names.count == users.count, Set(names).isSubset(of: flagged) else {
      return nil
    }
    return "used only by flagged \(names.sorted().joined(separator: ", ")): settle that first"
  }

  static func baseName(_ type: String) -> String {
    let withoutGenerics = type.prefix { $0 != "<" }
    return String(withoutGenerics.split(separator: ".").last ?? Substring(withoutGenerics))
  }
}

// MARK: - Platform Notes

private extension TriageNotes {
  /// Interface Builder, Objective-C, runtime lookups, entry points, previews, system-found
  /// types, projected values, CodingKeys and lifetime.
  func platformNotes(_ finding: PeripheryFinding, context: DeclarationContext) -> [String] {
    var notes: [String] = []
    let attributes = Set(context.attributes + finding.attributes.map(Self.attributeName))
    let typeAttributes = Set(context.enclosingTypes.flatMap(\.attributes))
    if let attribute = attributes.intersection(Self.interfaceBuilderAttributes).min() {
      notes.append(
        "@\(attribute): connected in a storyboard or XIB? check nibs the scan did not read"
      )
    }
    let isObjectiveC =
      attributes.contains("objc") || attributes.contains("NSManaged")
      || typeAttributes.contains("objcMembers") || context.modifiers.contains("dynamic")
      || finding.modifiers.contains("dynamic")
    if isObjectiveC {
      notes.append("exposed to Objective-C: check selectors, KVO key paths and Objective-C callers")
    }
    let isType = ["class", "struct", "enum", "protocol", "typealias"].contains(finding.kind)
    if isType || isObjectiveC, finding.bareName.count >= 4,
      let location = mentions.location(of: finding.bareName)
    {
      notes.append("named in a string at \(location): runtime lookup?")
    }
    if !attributes.isDisjoint(with: Self.entryPointAttributes) {
      notes.append("entry point: the runtime starts here")
    }
    let inherited = (context.ownInheritance + context.enclosingTypes.flatMap(\.inheritance))
      .map(Self.baseName)
    if context.isInsidePreview || inherited.contains("PreviewProvider") {
      notes.append("SwiftUI preview: used at design time only")
    }
    if let runtime = inherited.first(where: Self.runtimeProtocols.contains) {
      notes.append("a \(runtime): the system finds and calls it at runtime")
    }
    if finding.kind.hasPrefix("var."), !attributes.isDisjoint(with: Self.projectedWrappers),
      sources.mentionsProjectedValue(finding.bareName, in: finding.path)
    {
      notes.append("read through its projected value $\(finding.bareName)")
    } else if finding.kind.hasPrefix("var."),
      let wrapper = attributes.intersection(Self.dynamicProperties).min()
    {
      notes.append(
        "@\(wrapper) nothing reads: usually a leftover, unless a comment makes its declaration "
          + "a workaround; check #if branches for platforms the scan did not build"
      )
    }
    if finding.kind == "enumelement", context.enclosingTypes.first?.name == "CodingKeys" {
      notes.append("CodingKeys case: synthesized Codable uses it")
    }
    if finding.hints.contains("assignOnlyProperty"), let expression = Self.lifetimeTypes,
      expression.firstMatch(
        in: context.typeText,
        range: NSRange(context.typeText.startIndex..., in: context.typeText)
      ) != nil
    {
      notes.append(
        "assign-only, but keeps \(context.typeText) alive: the lifetime may be the point"
      )
    }
    return notes
  }

  /// Periphery merged a type that a target with the same module name also declares.
  func moduleTwinNote(_ finding: PeripheryFinding, context: DeclarationContext) -> String? {
    let isType = ["class", "struct", "enum"].contains(finding.kind)
    guard let outermost = context.enclosingTypes.last?.name ?? (isType ? finding.bareName : nil)
    else {
      return nil
    }
    let typeName = String(outermost.prefix { $0 != "." && $0 != "<" })
    guard let twin = twins.twin(declaring: typeName, in: finding.path, model: model) else {
      return nil
    }
    return "\(typeName) is declared again in \(twin.name), also module \(twin.moduleName): the "
      + "builds share one index, which merges the two and can lose this copy's callers"
  }

  /// Periphery spells attributes as `@objc` or `objc`.
  static func attributeName(_ attribute: String) -> String {
    let trimmed = attribute.hasPrefix("@") ? String(attribute.dropFirst()) : attribute
    return String(trimmed.prefix { $0 != "(" })
  }
}
