import Foundation

/// Finds tracked files and asset catalog entries that no other file mentions.
///
/// A file is mentioned when another tracked text file contains its stem, or its whole name
/// when the stem is shorter than the configured minimum. Searching the stem keeps alive a
/// resource whose name code builds from parts. Project membership lists (`project.pbxproj`,
/// `contents.xcworkspacedata`) are not mentions; build settings are.
struct ReferenceCheck {
  let model: ProjectModel
  let configuration: Configuration
  let trackedFiles: [String]

  func findings() -> Set<GateFinding> {
    let sources = mentionSources()
    var findings = unmentionedFiles(sources: sources)
    if configuration.check.assets {
      findings.formUnion(unmentionedAssets(sources: sources))
    }
    return findings
  }
}

// MARK: - Classification

extension ReferenceCheck {
  /// Files that are neither checked nor count as mentions: the tool's own files and the
  /// configured ones, such as dated research.
  func isNotReference(_ path: String) -> Bool {
    let ownFiles = [configuration.sourcePath, configuration.periphery.baseline]
    return ownFiles.contains(path)
      || Self.matches(path, patterns: Defaults.notReferences + configuration.check.notReferences)
  }

  /// Files that tools find by name or location. Names match regardless of case, as on a
  /// default macOS file system.
  func isConventional(_ path: String) -> Bool {
    let name = (path as NSString).lastPathComponent.lowercased()
    let names = (Defaults.conventionalFiles + configuration.check.conventionalFiles)
      .map { Glob($0.lowercased()) }
    let paths = Defaults.conventionalPaths + configuration.check.conventionalPaths
    return names.matchesAny(name) || Self.matches(path, patterns: paths)
  }

  /// A prefix ending in `/` matches everything below it; anything else is a glob.
  static func matches(_ path: String, patterns: [String]) -> Bool {
    patterns.contains { pattern in
      pattern.hasSuffix("/") ? path.hasPrefix(pattern) : Glob(pattern).matches(path)
    }
  }

  static func isInsideAssetCatalog(_ path: String) -> Bool {
    path.contains(".xcassets/")
  }

  static func isInsideProjectBundle(_ path: String) -> Bool {
    path.contains(".xcodeproj/") || path.contains(".xcworkspace/")
  }
}

// MARK: - Files

private extension ReferenceCheck {
  struct MentionSource {
    var path: String
    var text: String
  }

  func mentionSources() -> [MentionSource] {
    var sources: [MentionSource] = []
    for path in trackedFiles {
      if isNotReference(path) || model.membershipFiles.contains(path)
        || path.hasSuffix("contents.xcworkspacedata") || Self.isInsideAssetCatalog(path)
      {
        continue
      }
      if let text = TextFiles.read(model.root.appendingPathComponent(path)) {
        sources.append(MentionSource(path: path, text: text))
      }
    }
    if !model.buildSettingText.isEmpty {
      sources.append(MentionSource(path: "", text: model.buildSettingText))
    }
    return sources
  }

  func unmentionedFiles(sources: [MentionSource]) -> Set<GateFinding> {
    let compiled = model.compiledFiles
    let nestedProjects = nestedProjectDirectories()
    let candidates = trackedFiles.filter { path in
      !compiled.contains(path) && !isNotReference(path) && !isConventional(path)
        && !configuration.exclude.matchesAny(path) && !Self.isInsideAssetCatalog(path)
        && !Self.isInsideProjectBundle(path)
        && !(Self.isSource(path) && nestedProjects.contains { path.hasPrefix($0 + "/") })
    }
    let terms = candidates.map(searchTerm)
    var mentioned = mentionedTerms(
      terms,
      owners: candidates.map { [$0] },
      sources: sources
    )
    let patterns = Self.wildcardMentions(in: sources)
    for index in candidates.indices where !mentioned.contains(index) {
      if patterns.contains(where: { $0.matches(candidates[index]) }) {
        mentioned.insert(index)
      }
    }
    return Set(
      candidates.indices.filter { !mentioned.contains($0) }
        .map { GateFinding(kind: .file, subject: candidates[$0]) }
    )
  }

  /// A file pattern a text names, such as `results/prototype-*.md`: it mentions every file
  /// it matches, by name, or by the end of the path when the pattern has directories.
  struct WildcardMention {
    var pattern: Glob
    var hasDirectories: Bool

    func matches(_ path: String) -> Bool {
      guard hasDirectories else {
        return pattern.matches((path as NSString).lastPathComponent)
      }
      let components = path.split(separator: "/")
      return components.indices.contains { start in
        pattern.matches(components[start...].joined(separator: "/"))
      }
    }
  }

  static let wildcardToken = try? NSRegularExpression(
    pattern: #"[A-Za-z0-9_.\-/]*\*[A-Za-z0-9_.*\-/]*"#
  )

  /// The file patterns the sources name; a pattern needs four literal characters, so `*.md`
  /// or `*` alone mentions nothing.
  static func wildcardMentions(in sources: [MentionSource]) -> [WildcardMention] {
    guard let expression = wildcardToken else {
      return []
    }
    var patterns: Set<String> = []
    for source in sources where source.text.contains("*") {
      let text = source.text
      for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
        guard let range = Range(match.range, in: text) else {
          continue
        }
        let token = String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: "./"))
        let literal = token.filter { $0 != "*" && $0 != "/" && $0 != "." }
        if literal.count >= 4, token.contains(".") {
          patterns.insert(token)
        }
      }
    }
    return patterns.sorted().map { pattern in
      WildcardMention(pattern: Glob(pattern), hasDirectories: pattern.contains("/"))
    }
  }

  /// Directories with their own package or project manifest, below the root: their sources
  /// belong to that project, which this model does not load.
  func nestedProjectDirectories() -> [String] {
    let manifests: Set<String> = ["Package.swift", "project.yml", "Project.swift", "Podfile"]
    var directories: Set<String> = []
    for path in trackedFiles {
      let name = (path as NSString).lastPathComponent
      let directory = (path as NSString).deletingLastPathComponent
      if manifests.contains(name), !directory.isEmpty {
        directories.insert(directory)
      }
      if let range = path.range(of: ".xcodeproj/") {
        let project = (String(path[..<range.lowerBound]) as NSString).deletingLastPathComponent
        if !project.isEmpty {
          directories.insert(project)
        }
      }
    }
    return directories.sorted()
  }

  static func isSource(_ path: String) -> Bool {
    SourceLanguages.compiledExtensions.contains((path as NSString).pathExtension)
  }

  /// The stem, so code that builds a resource name from parts still counts; the whole name
  /// when the stem is too short to be specific.
  func searchTerm(_ path: String) -> String {
    let name = (path as NSString).lastPathComponent
    let stem = Self.withoutVariantSuffixes(
      String(name.split(separator: ".", omittingEmptySubsequences: false).first ?? "")
    )
    return stem.count >= configuration.check.minimumStemLength ? stem : name
  }

  /// `icon@2x~ipad` and `diagram~dark` are variants that code and docs name by their base:
  /// UIKit picks the scale and device, DocC the appearance.
  static func withoutVariantSuffixes(_ stem: String) -> String {
    stem.replacingOccurrences(
      of: #"(?:@[0-9]x|~[A-Za-z]+)+$"#,
      with: "",
      options: .regularExpression
    )
  }

  /// The indices of the candidates whose terms some source mentions, other than the
  /// candidate's own files.
  func mentionedTerms(
    _ terms: [String],
    owners: [Set<String>],
    sources: [MentionSource]
  ) -> Set<Int> {
    let search = MultiPatternSearch(terms: terms)
    var mentioned: Set<Int> = []
    for source in sources {
      for index in search.matches(in: source.text) where !owners[index].contains(source.path) {
        mentioned.insert(index)
      }
    }
    return mentioned
  }
}

// MARK: - Assets

private extension ReferenceCheck {
  struct AssetEntry {
    /// The entry directory, such as `App/Assets.xcassets/Icons/arrow.imageset`.
    var path: String
    var names: [String]
  }

  static let checkedAssetTypes: Set<String> = ["imageset", "colorset", "symbolset", "dataset"]
  /// Entries Xcode uses by default without any file naming them.
  static let conventionalAssetNames: Set<String> = ["AccentColor", "AppIcon"]

  func unmentionedAssets(sources: [MentionSource]) -> Set<GateFinding> {
    let entries = assetEntries().filter { entry in
      !configuration.exclude.matchesAny(entry.path)
    }
    var terms: [String] = []
    var owners: [Set<String>] = []
    var entryOfTerm: [Int] = []
    for (index, entry) in entries.enumerated() {
      for name in entry.names {
        terms.append(name)
        owners.append([])
        entryOfTerm.append(index)
      }
    }
    let mentioned = Set(
      mentionedTerms(terms, owners: owners, sources: sources).map { entryOfTerm[$0] }
    )
    return Set(
      entries.indices.filter { !mentioned.contains($0) }
        .map { GateFinding(kind: .asset, subject: entries[$0].path) }
    )
  }

  func assetEntries() -> [AssetEntry] {
    var directories: Set<String> = []
    for path in trackedFiles where Self.isInsideAssetCatalog(path) {
      let components = path.split(separator: "/").map(String.init)
      guard let catalog = components.firstIndex(where: { $0.hasSuffix(".xcassets") }) else {
        continue
      }
      for index in components.indices.dropFirst(catalog + 1).dropLast() {
        let type = (components[index] as NSString).pathExtension
        if Self.checkedAssetTypes.contains(type) {
          directories.insert(components[...index].joined(separator: "/"))
          break
        }
      }
    }
    return directories.sorted().compactMap { directory in
      let name = ((directory as NSString).lastPathComponent as NSString).deletingPathExtension
      if Self.conventionalAssetNames.contains(name) {
        return nil
      }
      let type = (directory as NSString).pathExtension
      let names = Self.searchNames(
        for: name,
        type: type,
        minimumPrefix: configuration.check.minimumStemLength
      )
      return AssetEntry(path: directory, names: names)
    }
  }

  /// The asset's name and the Swift identifiers Xcode generates for it: `my-icon` becomes
  /// `myIcon`, and a `Color` or `Image` suffix may be dropped. A name with a number also
  /// matches by the part before the number, because code often builds such names
  /// (`"Icon\(index)"`).
  static func searchNames(for name: String, type: String, minimumPrefix: Int) -> [String] {
    var names = [name]
    // `"achievement-\(kind)"` and `"Icon\(index)"` build names from a fixed prefix.
    let boundaries = [
      name.firstIndex { $0.isNumber },
      name.firstIndex(of: "-"),
      name.firstIndex(of: "_"),
    ]
    for case let index? in boundaries {
      let prefix = String(name[..<index])
      if prefix.count >= minimumPrefix {
        names.append(prefix)
      }
    }
    let words = name.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    if let first = words.first {
      let identifier =
        first.prefix(1).lowercased() + first.dropFirst()
        + words.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
      names.append(identifier)
      for suffix in ["Color", "Image"] where identifier.hasSuffix(suffix) {
        let trimmed = String(identifier.dropLast(suffix.count))
        if trimmed.count >= 3 {
          names.append(trimmed)
        }
      }
    }
    return Array(Set(names)).sorted()
  }
}
