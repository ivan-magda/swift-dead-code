import Foundation

/// Finds declared target dependencies that no source file of the target imports.
///
/// Imports count in every `#if` branch, so a dependency used only on another platform stays.
/// `#externalMacro(module:)` counts as a use of its module, and an Objective-C source's
/// `@import` or `#import <Module/...>` counts too. Plugin targets are skipped: their
/// dependencies are tools they run, never modules they import.
struct DependencyCheck {
  let model: ProjectModel

  func findings() -> Set<GateFinding> {
    var findings: Set<GateFinding> = []
    var cache: [String: Set<String>] = [:]
    for target in model.targets where target.productType != .plugin {
      var imported: Set<String> = []
      for path in target.sourceFiles + target.otherSourceFiles {
        if let modules = cache[path] {
          imported.formUnion(modules)
          continue
        }
        let modules = Self.importedModules(at: model.root.appendingPathComponent(path))
        cache[path] = modules
        imported.formUnion(modules)
      }
      for dependency in target.dependencies where dependency.moduleNames.isDisjoint(with: imported)
      {
        findings.insert(
          GateFinding(kind: .dependency, subject: "\(target.name) \(dependency.name)")
        )
      }
    }
    return findings
  }
}

// MARK: - Imports

private extension DependencyCheck {
  static let objectiveCImport = try? NSRegularExpression(
    pattern: #"^\s*(?:@import\s+(\w+)|#(?:import|include)\s+<(\w+)/)"#,
    options: [.anchorsMatchLines]
  )

  static func importedModules(at url: URL) -> Set<String> {
    guard let text = TextFiles.read(url) else {
      return []
    }
    if url.pathExtension == "swift" {
      return ImportScanner.importedModules(in: text)
    }
    guard let expression = objectiveCImport else {
      return []
    }
    var modules: Set<String> = []
    let range = NSRange(text.startIndex..., in: text)
    for match in expression.matches(in: text, range: range) {
      for group in 1...2 {
        if let found = Range(match.range(at: group), in: text) {
          modules.insert(String(text[found]))
        }
      }
    }
    return modules
  }
}
