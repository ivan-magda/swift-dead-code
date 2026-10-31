import Foundation

/// The project as every check sees it, whatever build system describes it.
public struct ProjectModel: Sendable {
  public enum Kind: Sendable, Equatable {
    case swiftPackage
    /// An Xcode workspace or project, relative to the root.
    case xcode(container: String)
  }

  public var kind: Kind
  /// The repository or package root; every path in the model is relative to it.
  public var root: URL
  public var targets: [ProjectTarget]
  /// Modules that package products or pods provide: what `--modules deps` means.
  public var externalModules: Set<String>
  /// Text from build settings, such as `INFOPLIST_FILE`, that mentions files.
  public var buildSettingText: String
  /// Files whose text lists project membership rather than uses, such as `project.pbxproj`.
  public var membershipFiles: Set<String>

  public init(
    kind: Kind,
    root: URL,
    targets: [ProjectTarget],
    externalModules: Set<String> = [],
    buildSettingText: String = "",
    membershipFiles: Set<String> = []
  ) {
    self.kind = kind
    self.root = root
    self.targets = targets.sorted { $0.name < $1.name }
    self.externalModules = externalModules
    self.buildSettingText = buildSettingText
    self.membershipFiles = membershipFiles
  }

  /// The names of the targets that compile a file.
  public func owningTargets(of path: String) -> Set<String> {
    Set(
      targets.filter { target in
        target.compiles(path)
      }
      .map(\.name)
    )
  }

  /// Whether a file belongs to test code: test targets, test support, or test globs.
  public func isTestCode(_ path: String, testGlobs: [Glob] = []) -> Bool {
    if testGlobs.matchesAny(path) {
      return true
    }
    let owners = targets.filter { target in
      target.compiles(path)
        || target.directories.contains { directory in
          path.hasPrefix(directory + "/")
        }
    }
    return !owners.isEmpty && owners.allSatisfy { $0.role != .product }
  }

  /// Every source file some target compiles, in any language.
  public var compiledFiles: Set<String> {
    Set(targets.flatMap { $0.sourceFiles + $0.otherSourceFiles })
  }

  public func target(named name: String) -> ProjectTarget? {
    targets.first { $0.name == name }
  }

  /// Whether two targets share a module name, such as an iOS and a macOS app both named after
  /// the product: their same-named types get one USR, and one index merges them.
  public var hasModuleTwins: Bool {
    Dictionary(grouping: targets, by: \.moduleName).values.contains { $0.count > 1 }
  }
}

/// A target: a module with its sources and declared dependencies.
public struct ProjectTarget: Sendable, Equatable {
  public enum Role: String, Sendable {
    case product
    case test
    case testSupport = "test-support"
  }

  public enum ProductType: String, Sendable {
    case library
    case executable
    case application
    case appExtension = "app-extension"
    case framework
    case unitTest = "unit-test"
    case uiTest = "ui-test"
    case macro
    case plugin
    case other
  }

  public var name: String
  public var moduleName: String
  public var role: Role
  public var productType: ProductType
  /// Compiled Swift files, sorted.
  public var sourceFiles: [String] {
    didSet {
      sourceFileSet = Set(sourceFiles)
    }
  }
  /// Directories that hold the target's sources.
  public var directories: [String]
  public var dependencies: [TargetDependency]
  /// Compiled sources in other languages, such as Objective-C, sorted.
  public var otherSourceFiles: [String]
  /// The manifest or project file that declares the target, for messages.
  public var manifestPath: String
  private var sourceFileSet: Set<String>

  public init(
    name: String,
    moduleName: String? = nil,
    role: Role,
    productType: ProductType,
    sourceFiles: [String],
    directories: [String] = [],
    dependencies: [TargetDependency] = [],
    otherSourceFiles: [String] = [],
    manifestPath: String
  ) {
    self.name = name
    self.moduleName = moduleName ?? name
    self.role = role
    self.productType = productType
    self.sourceFiles = sourceFiles.sorted()
    self.sourceFileSet = Set(sourceFiles)
    self.directories = directories.sorted()
    self.dependencies = dependencies
    self.otherSourceFiles = otherSourceFiles.sorted()
    self.manifestPath = manifestPath
  }

  public func compiles(_ path: String) -> Bool {
    sourceFileSet.contains(path)
  }
}

/// A declared dependency and the module names an import of it can use.
public struct TargetDependency: Sendable, Equatable, Hashable {
  public enum Kind: String, Sendable {
    case target
    case product
  }

  /// The name the manifest declares, which findings and allowlist entries use.
  public var name: String
  public var moduleNames: Set<String>
  public var kind: Kind

  public init(name: String, moduleNames: Set<String>, kind: Kind) {
    self.name = name
    self.moduleNames = moduleNames
    self.kind = kind
  }
}
