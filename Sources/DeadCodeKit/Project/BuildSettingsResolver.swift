import Foundation
import PathKit
import XcodeProj

/// Resolves a target's build settings the way Xcode layers them: project xcconfig, project
/// settings, target xcconfig, target settings, each later layer overriding the earlier.
///
/// xcconfig files are read with their `#include` and optional `#include?` chains; a missing
/// optional include, such as a file outside the repository, is skipped. Conditional settings
/// (`KEY[sdk=...]`) are ignored.
struct BuildSettingsResolver {
  let sourceRoot: URL

  /// The settings of the target's first configuration, `Debug` when it has one.
  func settings(of target: PBXTarget, project: PBXProject?) -> [String: String] {
    guard let configuration = Self.preferredConfiguration(target.buildConfigurationList) else {
      return [:]
    }
    var settings: [String: String] = [:]
    let projectConfiguration = project?.buildConfigurationList?.buildConfigurations.first {
      $0.name == configuration.name
    }
    if let projectConfiguration {
      settings.merge(xcconfigSettings(of: projectConfiguration)) { _, new in new }
      settings.merge(Self.strings(projectConfiguration.buildSettings)) { _, new in new }
    }
    settings.merge(xcconfigSettings(of: configuration)) { _, new in new }
    settings.merge(Self.strings(configuration.buildSettings)) { _, new in new }
    return settings
  }

  /// Reads one xcconfig file with its includes.
  static func read(_ url: URL, visited: Set<String> = []) -> [String: String] {
    guard !visited.contains(url.path), let text = TextFiles.read(url) else {
      return [:]
    }
    var settings: [String: String] = [:]
    let seen = visited.union([url.path])
    for rawLine in text.split(whereSeparator: \.isNewline) {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      if line.hasPrefix("#include") {
        guard let start = line.firstIndex(of: "\""), let end = line.lastIndex(of: "\""),
          start < end
        else {
          continue
        }
        let included = String(line[line.index(after: start)..<end])
        let includedURL = URL(
          fileURLWithPath: included,
          relativeTo: url.deletingLastPathComponent()
        )
        settings.merge(read(includedURL.standardizedFileURL, visited: seen)) { _, new in new }
        continue
      }
      let content = line.components(separatedBy: "//").first ?? ""
      guard let equals = content.firstIndex(of: "=") else {
        continue
      }
      let key = content[..<equals].trimmingCharacters(in: .whitespaces)
      guard !key.isEmpty, !key.contains("[") else {
        continue
      }
      settings[key] = content[content.index(after: equals)...]
        .trimmingCharacters(in: .whitespaces)
    }
    return settings
  }

  /// `PRODUCT_MODULE_NAME`, else a resolvable `PRODUCT_NAME`, else the target name, as an
  /// identifier.
  static func moduleName(targetName: String, settings: [String: String]) -> String {
    let candidates = [settings["PRODUCT_MODULE_NAME"], settings["PRODUCT_NAME"]]
      .compactMap { $0 }
      .map { expand($0, targetName: targetName, settings: settings) }
    let name = candidates.first { !$0.contains("$") && !$0.isEmpty } ?? targetName
    return ProjectTarget.moduleName(of: name)
  }
}

// MARK: - Layers

private extension BuildSettingsResolver {
  static func preferredConfiguration(_ list: XCConfigurationList?) -> XCBuildConfiguration? {
    let configurations = list?.buildConfigurations ?? []
    return configurations.first { $0.name == "Debug" } ?? configurations.first
  }

  func xcconfigSettings(of configuration: XCBuildConfiguration) -> [String: String] {
    let root = Path(sourceRoot.path)
    if let base = configuration.baseConfiguration,
      let path = try? base.fullPath(sourceRoot: root)
    {
      return Self.read(URL(fileURLWithPath: path.string))
    }
    if let anchor = configuration.baseConfigurationAnchor,
      let relativePath = configuration.baseConfigurationReferenceRelativePath,
      let path = try? anchor.fullPath(sourceRoot: root)
    {
      return Self.read(URL(fileURLWithPath: path.string).appendingPathComponent(relativePath))
    }
    return [:]
  }

  static func strings(_ settings: BuildSettings) -> [String: String] {
    settings.mapValues(\.description)
  }

  /// Replaces `$(TARGET_NAME)` and references to other settings, a few levels deep.
  static func expand(_ value: String, targetName: String, settings: [String: String]) -> String {
    var result = value
    for _ in 0..<4 where result.contains("$") {
      result = result.replacingOccurrences(of: "$(TARGET_NAME)", with: targetName)
        .replacingOccurrences(of: "${TARGET_NAME}", with: targetName)
      for (key, replacement) in settings where result.contains("$(\(key))") {
        result = result.replacingOccurrences(of: "$(\(key))", with: replacement)
      }
    }
    return result
  }
}
