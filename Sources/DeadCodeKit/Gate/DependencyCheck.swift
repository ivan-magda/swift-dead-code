import Foundation

/// Finds declared target dependencies that no source file of the target imports.
///
/// Imports count in every `#if` branch, so a dependency used only on another platform stays.
/// `#externalMacro(module:)` counts as a use of its module, and an Objective-C source's
/// `@import` or `#import <Module/...>` counts too. Plugin targets are skipped: their
/// dependencies are tools they run, never modules they import. A dependency also stays when a
/// target that depends on this one imports it without declaring it and has no other way to it.
struct DependencyCheck {
  let model: ProjectModel

  func findings() -> Set<GateFinding> {
    var findings: Set<GateFinding> = []
    let imports = importsByTarget()
    for target in model.targets where target.productType != .plugin {
      let imported = imports[target.name] ?? []
      for dependency in target.dependencies
      where dependency.moduleNames.isDisjoint(with: imported)
        && !(dependency.kind == .target && namesInStrings(dependency, of: target))
        && !passesOn(dependency, of: target, imports: imports)
      {
        findings.insert(
          GateFinding(kind: .dependency, subject: "\(target.name) \(dependency.name)")
        )
      }
    }
    return findings
  }
}

// MARK: - Dependents

private extension DependencyCheck {
  /// The modules each target imports, by target name.
  func importsByTarget() -> [String: Set<String>] {
    var cache: [String: Set<String>] = [:]
    var imports: [String: Set<String>] = [:]
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
      imports[target.name] = imported
    }
    return imports
  }

  /// Whether a target that depends on `target`, directly or through others, imports the
  /// dependency without declaring it and reaches it only through `target`.
  func passesOn(
    _ dependency: TargetDependency,
    of target: ProjectTarget,
    imports: [String: Set<String>]
  ) -> Bool {
    dependents(of: target).contains { client in
      !(imports[client.name] ?? []).isDisjoint(with: dependency.moduleNames)
        && !Self.declares(client, dependency)
        && !reaches(dependency, from: client, avoiding: target)
    }
  }

  /// The targets that depend on `target`, directly or through others.
  func dependents(of target: ProjectTarget) -> [ProjectTarget] {
    var modules = [target.moduleName]
    var visited: Set<String> = [target.name]
    var dependents: [ProjectTarget] = []
    while let module = modules.popLast() {
      for client in model.targets
      where !visited.contains(client.name)
        && client.dependencies.contains(where: { $0.moduleNames.contains(module) })
      {
        visited.insert(client.name)
        dependents.append(client)
        modules.append(client.moduleName)
      }
    }
    return dependents
  }

  /// Whether a target that `client` depends on, directly or through others, declares the
  /// dependency; `avoided`'s own declaration does not count.
  func reaches(
    _ dependency: TargetDependency,
    from client: ProjectTarget,
    avoiding avoided: ProjectTarget
  ) -> Bool {
    var stack = [client]
    var visited: Set<String> = [client.name]
    while let current = stack.popLast() {
      for declared in current.dependencies {
        for next in model.targets
        where !visited.contains(next.name) && declared.moduleNames.contains(next.moduleName) {
          visited.insert(next.name)
          if next.name != avoided.name, Self.declares(next, dependency) {
            return true
          }
          stack.append(next)
        }
      }
    }
    return false
  }

  static func declares(_ target: ProjectTarget, _ dependency: TargetDependency) -> Bool {
    target.dependencies.contains { declared in
      !declared.moduleNames.isDisjoint(with: dependency.moduleNames)
    }
  }
}

// MARK: - Imports

private extension DependencyCheck {
  /// Whether a string literal in the target names the framework, as `dlopen` of an embedded,
  /// unlinked framework and `NSClassFromString` do: then the dependency builds and embeds it.
  func namesInStrings(_ dependency: TargetDependency, of target: ProjectTarget) -> Bool {
    let names = dependency.moduleNames.union([dependency.name])
    return target.sourceFiles.contains { path in
      guard let text = TextFiles.read(model.root.appendingPathComponent(path)) else {
        return false
      }
      return names.contains { name in
        let escaped = NSRegularExpression.escapedPattern(for: name)
        return text.range(of: #""[^"\n]*\b"# + escaped + #"\b"#, options: .regularExpression)
          != nil
      }
    }
  }

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
