import Foundation
import Yams

/// Reads `.deadcode.yml`. Unknown keys and wrongly typed values are errors that name the line,
/// so a typo never silently falls back to a default.
public enum ConfigurationLoader {
  /// Loads the configuration at `path`, relative to `root`; a missing file means defaults.
  public static func load(
    root: URL,
    path: String = Configuration.fileName
  ) throws
    -> Configuration
  {
    let url = root.appendingPathComponent(path)
    guard FileManager.default.fileExists(atPath: url.path) else {
      var configuration = Configuration()
      configuration.sourcePath = path
      return configuration
    }
    guard let text = TextFiles.read(url) else {
      throw DeadCodeError.usage("\(path): cannot read the configuration as UTF-8 text")
    }
    return try parse(text, sourcePath: path)
  }

  /// Parses configuration text; `sourcePath` names the file in messages.
  public static func parse(
    _ text: String,
    sourcePath: String = Configuration.fileName
  ) throws
    -> Configuration
  {
    var configuration = Configuration()
    configuration.sourcePath = sourcePath
    let document: Node?
    do {
      document = try Yams.compose(yaml: text)
    } catch {
      throw DeadCodeError.usage("\(sourcePath): invalid YAML: \(error)")
    }
    guard let document else {
      return configuration
    }
    let root = ConfigNode(node: document, key: "", file: sourcePath)
    if case .scalar(let scalar) = document, scalar.string.isEmpty {
      return configuration
    }
    try read(root, into: &configuration)
    return configuration
  }
}

// MARK: - Sections

private extension ConfigurationLoader {
  static func read(_ root: ConfigNode, into configuration: inout Configuration) throws {
    let keys = try root.mapping(allowing: [
      "project", "test_support", "exclude", "module_names", "check", "allowlist", "periphery",
      "prune", "docs", "triage", "builds",
    ])
    if let node = keys["project"] {
      configuration.project = try projectSettings(node)
    }
    if let node = keys["test_support"] {
      configuration.testSupport = try node.strings()
    }
    if let node = keys["exclude"] {
      configuration.exclude = try node.strings().map(Glob.init)
    }
    if let node = keys["module_names"] {
      configuration.moduleNames = try node.mapping().mapValues { value in
        try value.strings()
      }
    }
    if let node = keys["check"] {
      configuration.check = try checkSettings(node)
    }
    if let node = keys["allowlist"] {
      configuration.allowlist = try node.sequence().map(allowlistEntry)
    }
    if let node = keys["periphery"] {
      configuration.periphery = try peripherySettings(node)
    }
    if let node = keys["prune"] {
      configuration.prune = try pruneSettings(node)
    }
    try readSmallSections(keys, into: &configuration)
  }

  static func readSmallSections(
    _ keys: [String: ConfigNode],
    into configuration: inout Configuration
  ) throws {
    if let node = keys["docs"] {
      let docs = try node.mapping(allowing: ["contracts"])
      configuration.docs.contracts = try docs["contracts"]?.strings() ?? []
    }
    if let node = keys["triage"] {
      let triage = try node.mapping(allowing: ["seam_name_pattern"])
      if let pattern = triage["seam_name_pattern"] {
        let value = try pattern.string()
        guard (try? NSRegularExpression(pattern: value)) != nil else {
          throw pattern.error("not a valid regular expression")
        }
        configuration.triage.seamNamePattern = value
      }
    }
    if let node = keys["builds"] {
      configuration.builds = try node.sequence().map(buildVariant)
    }
  }

  static func projectSettings(_ node: ConfigNode) throws -> ProjectSettings {
    let keys = try node.mapping(allowing: [
      "kind", "path", "schemes", "configuration", "destination", "build_arguments",
    ])
    var settings = ProjectSettings()
    if let kind = keys["kind"] {
      let value = try kind.string()
      guard let parsed = ProjectSettings.Kind(rawValue: value) else {
        let allowed = ProjectSettings.Kind.allCases.map(\.rawValue).joined(separator: ", ")
        throw kind.error("expected one of \(allowed), found '\(value)'")
      }
      settings.kind = parsed
    }
    settings.path = try keys["path"]?.string()
    settings.schemes = try keys["schemes"]?.strings() ?? []
    settings.configuration = try keys["configuration"]?.string()
    settings.destination = try keys["destination"]?.string()
    settings.buildArguments = try keys["build_arguments"]?.strings() ?? []
    return settings
  }

  static func checkSettings(_ node: ConfigNode) throws -> CheckSettings {
    let keys = try node.mapping(allowing: [
      "conventional_paths", "conventional_files", "not_references", "min_stem_length",
      "assets",
    ])
    var settings = CheckSettings()
    settings.conventionalPaths = try keys["conventional_paths"]?.strings() ?? []
    settings.conventionalFiles = try keys["conventional_files"]?.strings() ?? []
    settings.notReferences = try keys["not_references"]?.strings() ?? []
    if let length = keys["min_stem_length"] {
      settings.minimumStemLength = try length.int()
    }
    if let assets = keys["assets"] {
      settings.assets = try assets.bool()
    }
    return settings
  }

  static func allowlistEntry(_ node: ConfigNode) throws -> AllowlistEntry {
    let keys = try node.mapping(allowing: ["file", "dependency", "asset", "reason"])
    let subjects: [(GateFinding.Kind, ConfigNode)] = GateFinding.Kind.allCases.compactMap {
      kind in
      keys[kind.rawValue].map { (kind, $0) }
    }
    guard subjects.count == 1, let (kind, subjectNode) = subjects.first else {
      throw node.error("expected exactly one of 'file', 'dependency' or 'asset' with a 'reason'")
    }
    guard let reasonNode = keys["reason"] else {
      throw node.error("entry '\(kind.rawValue)' needs a 'reason'")
    }
    let reason = try reasonNode.string().trimmingCharacters(in: .whitespaces)
    guard !reason.isEmpty else {
      throw reasonNode.error("the reason must not be empty")
    }
    let subject: String
    if kind == .dependency {
      subject = try dependencySubject(subjectNode)
    } else {
      subject = try subjectNode.string().trimmingCharacters(in: .whitespaces)
    }
    return AllowlistEntry(kind: kind, subject: subject, reason: reason, line: node.line)
  }

  /// `<target> <module>`, split at the last space because module names have none, or
  /// `{target: ..., module: ...}` for clarity when the target name has spaces.
  static func dependencySubject(_ node: ConfigNode) throws -> String {
    if (try? node.mapping()) != nil {
      let keys = try node.mapping(allowing: ["target", "module"])
      guard let target = keys["target"], let module = keys["module"] else {
        throw node.error("expected 'target' and 'module'")
      }
      return "\(try target.string()) \(try module.string())"
    }
    let text = try node.string().trimmingCharacters(in: .whitespaces)
    guard let space = text.lastIndex(where: \.isWhitespace) else {
      throw node.error("expected 'dependency: <target> <module>'")
    }
    let target = text[..<space].trimmingCharacters(in: .whitespaces)
    let module = text[text.index(after: space)...]
    guard !target.isEmpty else {
      throw node.error("expected 'dependency: <target> <module>'")
    }
    return "\(target) \(module)"
  }

  static func peripherySettings(_ node: ConfigNode) throws -> PeripherySettings {
    let keys = try node.mapping(allowing: [
      "version", "baseline", "retain_codable_properties", "retain_equatable_properties",
      "retain_hashable_properties", "arguments",
    ])
    var settings = PeripherySettings()
    if let version = keys["version"] {
      settings.version = try version.string()
    }
    if let baseline = keys["baseline"] {
      settings.baseline = try baseline.string()
    }
    if let value = keys["retain_codable_properties"] {
      settings.retainCodableProperties = try value.bool()
    }
    if let value = keys["retain_equatable_properties"] {
      settings.retainEquatableProperties = try value.bool()
    }
    if let value = keys["retain_hashable_properties"] {
      settings.retainHashableProperties = try value.bool()
    }
    settings.arguments = try keys["arguments"]?.strings() ?? []
    return settings
  }

  static func pruneSettings(_ node: ConfigNode) throws -> PruneSettings {
    let keys = try node.mapping(allowing: [
      "toolchain_modules", "platform_modules", "keep_modules",
    ])
    var settings = PruneSettings()
    if let modules = keys["toolchain_modules"] {
      settings.toolchainModules = try modules.strings()
    }
    settings.platformModules = try keys["platform_modules"]?.strings() ?? []
    settings.keepModules = try keys["keep_modules"]?.strings() ?? []
    return settings
  }

  static func buildVariant(_ node: ConfigNode) throws -> BuildVariant {
    let keys = try node.mapping(allowing: [
      "name", "schemes", "destination", "configuration", "build_arguments", "for_testing",
    ])
    guard let name = keys["name"] else {
      throw node.error("a build needs a 'name'")
    }
    var variant = BuildVariant(name: try name.string())
    variant.schemes = try keys["schemes"]?.strings() ?? []
    if let forTesting = keys["for_testing"] {
      variant.forTesting = try forTesting.bool()
    }
    variant.destination = try keys["destination"]?.string()
    variant.configuration = try keys["configuration"]?.string()
    variant.buildArguments = try keys["build_arguments"]?.strings() ?? []
    return variant
  }
}

/// A YAML node with the key path and line that error messages name.
private struct ConfigNode {
  let node: Node
  let key: String
  let file: String

  var line: Int {
    node.mark?.line ?? 1
  }

  func error(_ message: String) -> DeadCodeError {
    let column = node.mark?.column ?? 1
    let name = key.isEmpty ? "" : "'\(key)': "
    return DeadCodeError.usage("\(file):\(line):\(column): error: \(name)\(message)")
  }

  /// The mapping's values by key; any key outside `allowed` is an error, unless `allowed` is
  /// empty, which accepts any key.
  func mapping(allowing allowed: Set<String> = []) throws -> [String: ConfigNode] {
    guard case .mapping(let mapping) = node else {
      throw error("expected a mapping")
    }
    var values: [String: ConfigNode] = [:]
    for (keyNode, value) in mapping {
      guard case .scalar(let scalar) = keyNode else {
        throw ConfigNode(node: keyNode, key: key, file: file).error("expected a string key")
      }
      let name = scalar.string
      let path = key.isEmpty ? name : "\(key).\(name)"
      if !allowed.isEmpty, !allowed.contains(name) {
        let expected = allowed.sorted().joined(separator: ", ")
        throw ConfigNode(node: keyNode, key: path, file: file)
          .error("unknown key; expected one of \(expected)")
      }
      values[name] = ConfigNode(node: value, key: path, file: file)
    }
    return values
  }

  func sequence() throws -> [ConfigNode] {
    guard case .sequence(let sequence) = node else {
      throw error("expected a list")
    }
    return sequence.map { item in
      ConfigNode(node: item, key: key, file: file)
    }
  }

  func string() throws -> String {
    guard case .scalar(let scalar) = node else {
      throw error("expected a string")
    }
    return scalar.string
  }

  func strings() throws -> [String] {
    try sequence().map { item in
      try item.string()
    }
  }

  func bool() throws -> Bool {
    switch try string().lowercased() {
    case "true", "yes", "on":
      return true
    case "false", "no", "off":
      return false
    default:
      throw error("expected true or false")
    }
  }

  func int() throws -> Int {
    guard let value = Int(try string()) else {
      throw error("expected an integer")
    }
    return value
  }
}
