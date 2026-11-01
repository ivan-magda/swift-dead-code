import Foundation

/// Finds declared target dependencies that no source file of the target imports.
///
/// Imports count in every `#if` branch, so a dependency used only on another platform stays.
/// `#externalMacro(module:)` counts as a use of its module, and an Objective-C source's
/// `@import` or `#import <Module/...>` counts too, as do those of the headers it includes by a
/// relative path. Plugin targets are skipped: their
/// dependencies are tools they run, never modules they import. A dependency also stays when
/// removing it would cut a target that has it, directly or through others, off a module that
/// target imports without declaring it. Each dependency is judged with the ones already found
/// removed, so removing them all at once still leaves every such import a way in.
struct DependencyCheck {
  /// A declared dependency, by the target that declares it and the name it declares.
  struct Edge: Hashable {
    var target: String
    var dependency: String
  }

  let model: ProjectModel

  func findings() -> Set<GateFinding> {
    let imports = importsByTarget()
    var dead: Set<Edge> = []
    for target in model.targets where target.productType != .plugin {
      let imported = imports[target.name] ?? []
      for dependency in target.dependencies
      where dependency.moduleNames.isDisjoint(with: imported)
        && !(dependency.kind == .target && namesInStrings(dependency, of: target))
      {
        let edge = Edge(target: target.name, dependency: dependency.name)
        let cutsAnImport = ([target] + dependents(of: target)).contains { client in
          let needed = reachableModules(from: client, without: dead)
            .intersection(imports[client.name] ?? [])
          return !needed.isSubset(of: reachableModules(from: client, without: dead.union([edge])))
        }
        if !cutsAnImport {
          dead.insert(edge)
        }
      }
    }
    return Set(
      dead.map { GateFinding(kind: .dependency, subject: "\($0.target) \($0.dependency)") }
    )
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

  /// The modules `client` can import through its dependencies, directly or through the targets
  /// they name, without the `removed` ones.
  func reachableModules(from client: ProjectTarget, without removed: Set<Edge>) -> Set<String> {
    var modules: Set<String> = []
    var stack = [client]
    var visited: Set<String> = [client.name]
    while let current = stack.popLast() {
      for dependency in current.dependencies
      where !removed.contains(Edge(target: current.name, dependency: dependency.name)) {
        modules.formUnion(dependency.moduleNames)
        // A target dependency names one target; twins share its module name.
        for next in model.targets
        where !visited.contains(next.name)
          && (dependency.kind == .target
            ? next.name == dependency.name : dependency.moduleNames.contains(next.moduleName))
        {
          visited.insert(next.name)
          stack.append(next)
        }
      }
    }
    return modules
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
    pattern: #"^\s*(?:@import\s+(\w+)|#(?:import|include)\s+(?:<(\w+)/|"([^"\n]+)"))"#,
    options: [.anchorsMatchLines]
  )

  /// The modules a file imports; for a C-family file, also those of the headers it includes
  /// by a path relative to itself, such as `Foo.m` its `Foo.h` or a bridging header the
  /// headers it lists.
  static func importedModules(at url: URL, visited: Set<URL> = []) -> Set<String> {
    guard !visited.contains(url), let text = TextFiles.read(url) else {
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
      if let header = Range(match.range(at: 3), in: text) {
        let included = url.deletingLastPathComponent()
          .appendingPathComponent(String(text[header])).standardizedFileURL
        modules.formUnion(importedModules(at: included, visited: visited.union([url])))
      }
    }
    return modules
  }
}
