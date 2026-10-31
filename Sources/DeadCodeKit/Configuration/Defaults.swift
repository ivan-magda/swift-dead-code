/// Built-in lists that the configuration extends.
public enum Defaults {
  /// File names that tools find by name, so no other file has to mention them.
  public static let conventionalFiles = [
    ".deadcode.yml",
    ".editorconfig",
    ".gitattributes",
    ".gitignore",
    ".gitmodules",
    ".periphery.yml",
    ".pre-commit-config.yaml",
    ".ruff.toml",
    ".spi.yml",
    ".swift-format",
    ".swift-version",
    ".swiftformat",
    ".swiftlint.yml",
    // Codecov reads it from the repository root.
    ".codecov.yml",
    "codecov.yml",
    // Placeholders that keep an empty directory in git.
    ".gitkeep",
    ".keep",
    ".travis.yml",
    ".xcode-version",
    "AGENTS.md",
    "Brewfile",
    "CHANGELOG.md",
    "CLAUDE.md",
    "CODE_OF_CONDUCT.md",
    "CONTRIBUTING.md",
    "Cartfile",
    "AppShortcuts.strings",
    "AppShortcuts.xcstrings",
    "Cartfile.resolved",
    "Contents.json",
    // macOS reads it from the app bundle to migrate a sandbox container.
    "container-migration.plist",
    "Gemfile",
    "Gemfile.lock",
    // Firebase reads it from the app bundle by name.
    "GoogleService-Info.plist",
    "InfoPlist.strings",
    "InfoPlist.xcstrings",
    "LICENCE*",
    "LICENSE*",
    "Localizable.strings",
    "Localizable.stringsdict",
    "Localizable.xcstrings",
    "Mintfile",
    "Package.resolved",
    "Package.swift",
    "Package@swift-*.swift",
    "Podfile",
    "Podfile.lock",
    "PrivacyInfo.xcprivacy",
    "Project.swift",
    "README.md",
    "SECURITY.md",
    "project.yml",
    "*.xctestplan",
  ]

  /// Path prefixes (ending in `/`) or globs of files that tools find by location.
  public static let conventionalPaths = [
    ".agents/",
    ".circleci/",
    ".claude/",
    ".github/",
    // Git finds hooks there once the project's setup sets core.hooksPath.
    ".githooks/",
    // Dependency managers own these directories, at any depth.
    "**/Carthage/**",
    "**/Pods/**",
    ".gitlab/",
    "fastlane/",
    // SwiftPM's Xcode metadata, Xcode Cloud scripts, Settings bundles and documentation sets,
    // at any depth.
    "**/.swiftpm/**",
    "**/ci_scripts/**",
    "**/Settings.bundle/**",
    "**/*.docset/**",
  ]

  /// Files whose mentions keep nothing alive, besides the configuration and the baseline.
  public static let notReferences: [String] = []

  /// Modules a build for one platform cannot prove removable: on Linux, Foundation is split
  /// into several modules and libc has another name.
  public static let platformModules = [
    "Android",
    "CoreFoundation",
    "Crypto",
    "Darwin",
    "Dispatch",
    "Foundation",
    "FoundationEssentials",
    "FoundationNetworking",
    "FoundationXML",
    "Glibc",
    "Musl",
    "System",
    "SystemPackage",
    "WinSDK",
    "os",
  ]
}
