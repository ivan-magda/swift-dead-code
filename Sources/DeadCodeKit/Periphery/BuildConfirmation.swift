import Foundation

/// Keeps the findings of a scan over several builds' index stores that the builds confirm one
/// by one.
///
/// Targets that share a module name, such as an iOS and a macOS app both named after the
/// product, give their same-named types one USR, and Periphery merges them in a combined
/// index: it can lose one copy's calls, differently from run to run. Each build alone has no
/// such twins. A combined finding stays when some build reports it and every build that compiles
/// one of the finding's targets reports it too, so code one build uses stays alive. A build
/// counts as compiling a target when it reports something in a file only that target compiles.
public struct BuildConfirmation {
  let model: ProjectModel

  public init(model: ProjectModel) {
    self.model = model
  }

  /// The combined findings the builds' own findings confirm, in their original order.
  public func confirmed(
    _ combined: [PeripheryFinding],
    byBuild: [String: [PeripheryFinding]]
  ) -> [PeripheryFinding] {
    let keysByBuild = byBuild.mapValues { Set($0.map(Self.key)) }
    // A build compiles the targets it reports in. Only a file one target owns tells which: a
    // shared file's finding would make every build seem to compile every app.
    let targetsByBuild = byBuild.mapValues { findings in
      Set(
        findings.compactMap { finding -> String? in
          let owners = model.owningTargets(of: finding.path)
          return owners.count == 1 ? owners.first : nil
        }
      )
    }
    return combined.filter { finding in
      let key = Self.key(finding)
      let reporting = keysByBuild.filter { $0.value.contains(key) }
      guard !reporting.isEmpty else {
        return false
      }
      let owners = model.owningTargets(of: finding.path)
      return targetsByBuild.allSatisfy { build, targets in
        owners.isDisjoint(with: targets) || reporting[build] != nil
      }
    }
  }

  static func key(_ finding: PeripheryFinding) -> String {
    "\(finding.location) \(finding.kind) \(finding.name)"
  }
}
