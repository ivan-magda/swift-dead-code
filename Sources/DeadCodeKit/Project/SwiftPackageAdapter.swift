import Foundation

/// Reads a SwiftPM package with `swift package dump-package`, which evaluates the manifest
/// without resolving dependencies.
public struct SwiftPackageAdapter: Sendable {
  let runner: any CommandRunning

  public init(runner: any CommandRunning = ProcessRunner()) {
    self.runner = runner
  }

  /// Loads the package at `packageRoot`; `prefix` is its path below the project root.
  public func load(
    packageRoot: URL,
    prefix: String = "",
    configuration: Configuration
  ) throws -> ProjectModel {
    // Without a scratch path, SwiftPM creates .build/ in the project.
    let scratch = FileManager.default.temporaryDirectory
      .appendingPathComponent("swift-dead-code-manifest-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: scratch)
    }
    let json = try runner.output(
      of: Command(
        "swift",
        ["package", "--scratch-path", scratch.path, "dump-package"],
        in: packageRoot
      )
    )
    let manifest: DumpedPackage
    do {
      manifest = try JSONDecoder().decode(DumpedPackage.self, from: Data(json.utf8))
    } catch {
      throw DeadCodeError.usage("cannot read `swift package dump-package` output: \(error)")
    }
    // SwiftPM compiles untracked files in a target directory, so their imports count.
    let files = try Git(directory: packageRoot, runner: runner).trackedAndUntrackedFiles()
    let sourceFiles = files.filter { path in
      SourceLanguages.compiledExtensions.contains((path as NSString).pathExtension)
    }
    let manifestPath = Self.join(prefix, "Package.swift")

    let names = PackageNames(manifest: manifest, configuration: configuration)
    var targets: [ProjectTarget] = []
    for target in manifest.targets where target.type != "binary" {
      let directory = try Self.directory(of: target, in: packageRoot)
      let placement = Placement(prefix: prefix, manifestPath: manifestPath)
      targets.append(
        Self.target(
          target,
          directory: directory,
          sources: Self.sources(of: target, directory: directory, files: sourceFiles),
          placement: placement,
          names: names
        )
      )
    }
    let externalModules = Set(
      targets.flatMap(\.dependencies).filter { $0.kind == .product }.flatMap(\.moduleNames)
    )
    return ProjectModel(
      kind: .swiftPackage,
      root: packageRoot,
      targets: targets,
      externalModules: externalModules
    )
  }
}

// MARK: - Manifest

/// The parts of `swift package dump-package` output the tool reads.
struct DumpedPackage: Decodable {
  struct Target: Decodable {
    var name: String
    var type: String
    var path: String?
    var exclude: [String]
    /// Explicit source paths; empty means the whole target directory.
    var sources: [String]
    var dependencies: [Dependency]

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      name = try container.decode(String.self, forKey: .name)
      type = try container.decode(String.self, forKey: .type)
      path = try container.decodeIfPresent(String.self, forKey: .path)
      exclude = try container.decodeIfPresent([String].self, forKey: .exclude) ?? []
      sources = try container.decodeIfPresent([String].self, forKey: .sources) ?? []
      dependencies = try container.decodeIfPresent([Dependency].self, forKey: .dependencies) ?? []
    }

    private enum CodingKeys: String, CodingKey {
      case name
      case type
      case path
      case exclude
      case sources
      case dependencies
    }
  }

  /// `{"byName": [name, condition]}`, `{"target": [name, condition]}` or
  /// `{"product": [name, package, moduleAliases, condition]}`.
  struct Dependency: Decodable {
    var byName: [JSONValue]
    var target: [JSONValue]
    var product: [JSONValue]

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      byName = try container.decodeIfPresent([JSONValue].self, forKey: .byName) ?? []
      target = try container.decodeIfPresent([JSONValue].self, forKey: .target) ?? []
      product = try container.decodeIfPresent([JSONValue].self, forKey: .product) ?? []
    }

    private enum CodingKeys: String, CodingKey {
      case byName
      case target
      case product
    }
  }

  /// A product; only executables matter, because before tools version 5.4 an executable's
  /// target is a regular one.
  struct Product: Decodable {
    var targets: [String]
    var isExecutable: Bool

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      targets = try container.decodeIfPresent([String].self, forKey: .targets) ?? []
      let type = try container.decodeIfPresent([String: JSONValue].self, forKey: .type) ?? [:]
      isExecutable = type.keys.contains("executable")
    }

    private enum CodingKeys: String, CodingKey {
      case targets
      case type
    }
  }

  var name: String
  var targets: [Target]
  var products: [Product]

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decode(String.self, forKey: .name)
    targets = try container.decode([Target].self, forKey: .targets)
    products = try container.decodeIfPresent([Product].self, forKey: .products) ?? []
  }

  private enum CodingKeys: String, CodingKey {
    case name
    case targets
    case products
  }
}

/// What a name means in one manifest: a dependency's name is a target of the package or a
/// product of a package it depends on, which `byName` can name too.
struct PackageNames {
  var targets: Set<String>
  var executables: Set<String>
  var testSupport: Set<String>
  var moduleNames: [String: [String]]

  init(manifest: DumpedPackage, configuration: Configuration) {
    targets = Set(manifest.targets.map(\.name))
    executables = Set(manifest.products.filter(\.isExecutable).flatMap(\.targets))
    testSupport = Set(configuration.testSupport)
    moduleNames = configuration.moduleNames
  }
}

/// Just enough of an arbitrary JSON value to read manifest arrays.
enum JSONValue: Decodable, Equatable {
  case string(String)
  case object([String: JSONValue])
  case other

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let string = try? container.decode(String.self) {
      self = .string(string)
    } else if let object = try? container.decode([String: JSONValue].self) {
      self = .object(object)
    } else {
      self = .other
    }
  }

  var string: String? {
    if case .string(let value) = self {
      value
    } else {
      nil
    }
  }
}

private extension SwiftPackageAdapter {
  /// Where a package sits in the project: its directory and its manifest, for messages.
  struct Placement {
    var prefix: String
    var manifestPath: String
  }

  static func target(
    _ target: DumpedPackage.Target,
    directory: String,
    sources: [String],
    placement: Placement,
    names: PackageNames
  ) -> ProjectTarget {
    let prefix = placement.prefix
    let dependencies = target.dependencies.compactMap { dependency in
      Self.dependency(dependency, names: names)
    }
    let role: ProjectTarget.Role =
      if target.type == "test" {
        .test
      } else if names.testSupport.contains(target.name) {
        .testSupport
      } else {
        .product
      }
    return ProjectTarget(
      name: target.name,
      role: role,
      productType: target.type == "regular" && names.executables.contains(target.name)
        ? .executable : Self.productType(of: target.type),
      sourceFiles: sources.filter { $0.hasSuffix(".swift") }.map { Self.join(prefix, $0) },
      directories: [Self.join(prefix, directory)],
      dependencies: dependencies,
      otherSourceFiles: sources.filter { !$0.hasSuffix(".swift") }.map { Self.join(prefix, $0) },
      manifestPath: placement.manifestPath
    )
  }

  /// Where SwiftPM looks for a target that has no explicit path, by target type.
  static func defaultRoots(for type: String) -> [String] {
    switch type {
    case "test":
      ["Tests", "Sources", "Source", "src", "srcs"]
    case "plugin":
      ["Plugins"]
    default:
      ["Sources", "Source", "src", "srcs"]
    }
  }

  static func directory(of target: DumpedPackage.Target, in root: URL) throws -> String {
    if let path = target.path, !path.isEmpty {
      return TextFiles.normalize(path)
    }
    let roots = defaultRoots(for: target.type)
    for base in roots where isDirectory("\(base)/\(target.name)", in: root) {
      return "\(base)/\(target.name)"
    }
    // SwiftPM also accepts sources directly in the predefined directory.
    for base in roots where isDirectory(base, in: root) {
      return base
    }
    throw DeadCodeError.usage("cannot find the directory of target \(target.name)")
  }

  static func isDirectory(_ path: String, in root: URL) -> Bool {
    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(
      atPath: root.appendingPathComponent(path).path,
      isDirectory: &isDirectory
    )
    return exists && isDirectory.boolValue
  }

  static func sources(
    of target: DumpedPackage.Target,
    directory: String,
    files: [String]
  ) -> [String] {
    let base = directory.isEmpty ? "" : directory + "/"
    let excluded = target.exclude.map { base + TextFiles.normalize($0) }
    let included = target.sources.map { base + TextFiles.normalize($0) }
    return files.filter { path in
      guard path.hasPrefix(base) else {
        return false
      }
      if excluded.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
        return false
      }
      return included.isEmpty || included.contains { path == $0 || path.hasPrefix($0 + "/") }
    }
  }

  static func dependency(
    _ dependency: DumpedPackage.Dependency,
    names: PackageNames
  ) -> TargetDependency? {
    let moduleNames = names.moduleNames
    if let name = dependency.target.first?.string {
      return TargetDependency(
        name: name,
        moduleNames: Set([name] + (moduleNames[name] ?? [])),
        kind: .target
      )
    }
    if let name = dependency.byName.first?.string {
      return TargetDependency(
        name: name,
        moduleNames: Set([name] + (moduleNames[name] ?? [])),
        kind: names.targets.contains(name) ? .target : .product
      )
    }
    let product = dependency.product
    guard let name = product.first?.string else {
      return nil
    }
    var names: Set<String> = [name]
    if product.count > 2, case .object(let aliases) = product[2] {
      names.formUnion(aliases.values.compactMap(\.string))
    }
    names.formUnion(moduleNames[name] ?? [])
    return TargetDependency(name: name, moduleNames: names, kind: .product)
  }

  static func productType(of type: String) -> ProjectTarget.ProductType {
    switch type {
    case "executable":
      .executable
    case "test":
      .unitTest
    case "macro":
      .macro
    case "plugin":
      .plugin
    case "regular", "system":
      .library
    default:
      .other
    }
  }

  static func join(_ prefix: String, _ path: String) -> String {
    prefix.isEmpty ? path : (path.isEmpty ? prefix : "\(prefix)/\(path)")
  }
}
