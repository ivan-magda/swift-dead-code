import Foundation

/// Keeps the findings of a scan over several builds' index stores that the builds confirm one
/// by one.
///
/// Targets that share a module name, such as an iOS and a macOS app both named after the
/// product, give their same-named types one USR, and Periphery merges them in a combined
/// index: it can lose one copy's calls, differently from run to run. Each build alone has no
/// such twins. A combined finding stays when some build reports it and every build whose index
/// holds its USR reports it too: a build that indexed the declaration and did not report it
/// uses it, and a build that never compiled it, such as code under `#if os(macOS)` in an iOS
/// build, has no say.
public struct BuildConfirmation {
  public init() {}

  /// The combined findings the builds confirm, in their original order. `seen` holds, for each
  /// build, the USRs its index contains.
  public func confirmed(
    _ combined: [PeripheryFinding],
    byBuild: [String: [PeripheryFinding]],
    seen: [String: Set<String>]
  ) -> [PeripheryFinding] {
    let keysByBuild = byBuild.mapValues { Set($0.map(Self.key)) }
    return combined.filter { finding in
      let key = Self.key(finding)
      let reporting = keysByBuild.filter { $0.value.contains(key) }
      guard !reporting.isEmpty else {
        return false
      }
      return keysByBuild.keys.allSatisfy { build in
        reporting[build] != nil || (seen[build] ?? []).isDisjoint(with: finding.ids)
      }
    }
  }

  static func key(_ finding: PeripheryFinding) -> String {
    "\(finding.location) \(finding.kind) \(finding.name)"
  }
}

/// The USRs an index store's records contain, read from the records' bytes.
public struct IndexStoreSymbols {
  let store: URL

  public init(store: URL) {
    self.store = store
  }

  /// Which of `usrs` occur in the store's records.
  public func seen(among usrs: Set<String>) throws -> Set<String> {
    let terms = usrs.sorted()
    let search = MultiPatternSearch(terms: terms)
    let records = store.appendingPathComponent("v5/records")
    guard
      let files = FileManager.default.enumerator(
        at: records,
        includingPropertiesForKeys: [.isRegularFileKey]
      )
    else {
      throw DeadCodeError.failure("no index records in \(records.path)")
    }
    var found: Set<Int> = []
    for case let file as URL in files
    where (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
      found.formUnion(search.matches(inBytes: try Data(contentsOf: file)))
    }
    return Set(found.map { terms[$0] })
  }
}
