import Foundation

/// The settings a project keeps in `.deadcode.yml`. Every field has a default, so a missing
/// file means the defaults.
public struct Configuration: Sendable, Equatable {
  public static let fileName = ".deadcode.yml"

  public var project = ProjectSettings()
  /// Targets, by name, or path globs that count as test code besides the test targets.
  public var testSupport: [String] = []
  /// Paths no check reports on, such as generated or vendored code.
  public var exclude: [Glob] = []
  /// Product or pod name to the module names an import of it can use.
  public var moduleNames: [String: [String]] = [:]
  public var check = CheckSettings()
  public var allowlist: [AllowlistEntry] = []
  public var periphery = PeripherySettings()
  public var prune = PruneSettings()
  public var docs = DocsSettings()
  public var triage = TriageSettings()
  /// Builds to scan together; empty means one build with the project settings.
  public var builds: [BuildVariant] = []
  /// The file the configuration came from, relative to the project root.
  public var sourcePath = Configuration.fileName

  public init() {}
}

/// Which project the tool analyzes and how to build it.
public struct ProjectSettings: Sendable, Equatable {
  public enum Kind: String, Sendable, CaseIterable {
    case auto
    case swiftpm
    case xcode
  }

  public var kind = Kind.auto
  /// The `.xcworkspace` or `.xcodeproj` for Xcode projects, relative to the root.
  public var path: String?
  public var schemes: [String] = []
  public var configuration: String?
  public var destination: String?
  public var buildArguments: [String] = []

  public init() {}
}

/// Settings of the build-free gate.
public struct CheckSettings: Sendable, Equatable {
  /// Path prefixes (ending in `/`) or globs of files that tools find by location.
  public var conventionalPaths: [String] = []
  /// File-name globs of files that tools find by name.
  public var conventionalFiles: [String] = []
  /// Path prefixes or globs of files that are neither checked nor count as mentions.
  public var notReferences: [String] = []
  /// A shorter stem would match unrelated text, so the whole file name is searched instead.
  public var minimumStemLength = 4
  /// Whether asset catalog entries are checked.
  public var assets = true

  public init() {}
}

/// A finding kept on purpose, with its reason.
public struct AllowlistEntry: Sendable, Equatable {
  public var kind: GateFinding.Kind
  public var subject: String
  public var reason: String
  /// The entry's line in the configuration file, for messages.
  public var line: Int

  public init(kind: GateFinding.Kind, subject: String, reason: String, line: Int) {
    self.kind = kind
    self.subject = subject
    self.reason = reason
    self.line = line
  }

  public var finding: GateFinding {
    GateFinding(kind: kind, subject: subject)
  }
}

/// Settings of the Periphery scans and the baseline.
public struct PeripherySettings: Sendable, Equatable {
  /// The `periphery version` the scans require: triage notes were checked against it.
  public var version = "3.8.0"
  public var baseline = ".deadcode/periphery-baseline.txt"
  public var retainCodableProperties = true
  public var retainEquatableProperties = true
  /// Equatable retention already covers Hashable types.
  public var retainHashableProperties = false
  /// Extra `periphery scan` options for both scans.
  public var arguments: [String] = []

  public init() {}
}

/// Settings of the import pruner.
public struct PruneSettings: Sendable, Equatable {
  /// Toolchain modules `--modules deps` tries besides the dependency modules.
  public var toolchainModules = ["Testing", "Synchronization"]
  /// Modules added to the default list that a build of one platform cannot prove removable.
  public var platformModules: [String] = []
  /// Modules the pruner never removes.
  public var keepModules: [String] = []

  public init() {}
}

/// Where the project documents its contracts, for the agent's triage.
public struct DocsSettings: Sendable, Equatable {
  public var contracts: [String] = []

  public init() {}
}

/// Settings of the triage notes.
public struct TriageSettings: Sendable, Equatable {
  /// A declaration whose name matches is a test seam kept on purpose.
  public var seamNamePattern = #"For(?:Testing|Tests)\b"#

  public init() {}
}

/// One build of a multi-build scan; unset fields fall back to the project settings.
public struct BuildVariant: Sendable, Equatable {
  public var name: String
  public var schemes: [String] = []
  public var destination: String?
  public var configuration: String?
  public var buildArguments: [String] = []
  /// Whether the build includes the scheme's test targets; off when they cannot build here,
  /// such as tests that compile AppleScript against an installed app.
  public var forTesting = true

  public init(name: String) {
    self.name = name
  }
}
