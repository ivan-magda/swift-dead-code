import Foundation

/// Turns two Periphery JSON scans into `report.md`: findings grouped as swift-claw's
/// `triage.py` grouped them, with false-positive hints.
///
/// The scan with tests gives the unused declarations; the scan without tests adds the
/// production declarations only tests reach. Rows are sorted by file and line, so the same
/// scans always give the same report.
public struct TriageReport {
  static let unused = "unused"
  static let assignOnly = "assignOnlyProperty"
  static let redundantPublic = "redundantPublicAccessibility"

  static let notesCaveat = """
    Notes are hints for the check to make. A row without notes still needs every check.

    """
  static let testOnlyCaveat = """
    Seams, test conveniences and contracts live here. A removed production caller
    (`git log -S'<name>'` on product code) is what makes one a leftover.

    """
  static let importsCaveat = """
    This list covers only modules Periphery indexed. Imports of package dependencies and
    other unindexed modules are never reported, and some project imports are missed:
    run `swift-dead-code prune-imports`.

    """

  let all: [PeripheryFinding]
  let production: [PeripheryFinding]
  let notes: TriageNotes

  /// `sourceRoot` holds the scanned sources, such as the scan's working copy.
  public init(
    all: [PeripheryFinding],
    production: [PeripheryFinding],
    model: ProjectModel,
    configuration: Configuration,
    sourceRoot: URL
  ) {
    self.all = all.sorted(by: Self.order)
    self.production = production.sorted(by: Self.order)
    let swiftFiles = model.compiledFiles.filter { $0.hasSuffix(".swift") }
    let resources = StringMentions.resources(
      among: (try? Git(directory: model.root).trackedFiles()) ?? []
    )
    notes = TriageNotes(
      model: model,
      configuration: configuration,
      sources: SourceIndex(root: sourceRoot),
      mentions: StringMentions(
        root: sourceRoot,
        swiftFiles: Array(swiftFiles),
        resourceFiles: resources
      )
    )
  }

  public func render() -> String {
    let imports = all.filter { $0.kind == "module" }
    let assignOnly = all.filter { $0.hint == Self.assignOnly }
    let redundantPublic = all.filter { $0.hint == Self.redundantPublic }
    let unused = all.filter { finding in
      finding.kind != "module" && finding.hint != Self.assignOnly
        && finding.hint != Self.redundantPublic
    }
    // A declaration flagged without tests but not with them is one that tests use.
    let flaggedWithTests = Set(all.map(\.ids))
    let onlyWithoutTests = production.filter { finding in
      !flaggedWithTests.contains(finding.ids) && finding.kind != "module"
    }
    let testOnly = onlyWithoutTests.filter { $0.hint == Self.unused }
    let readOnlyByTests = onlyWithoutTests.filter { $0.hint == Self.assignOnly }

    var output = "# Periphery triage\n\n"
    output +=
      "Unused declarations: \(unused.count). Test-only production declarations: "
      + "\(testOnly.count). Production properties only tests read: \(readOnlyByTests.count). "
      + "Unused imports: \(imports.count). Assign-only properties: \(assignOnly.count). "
      + "Redundant public (access level, not dead code): \(redundantPublic.count).\n\n"
    output += Self.notesCaveat + "\n"

    let flaggedFunctions = Set(
      unused.filter { $0.kind.hasPrefix("function") }.map(\.bareName)
    )
    output += "## Unused declarations, tests included\n\n"
    output += table(unused, flaggedFunctions: flaggedFunctions) + "\n\n"
    output += "## Production declarations that only tests reach\n\n"
    output += Self.testOnlyCaveat + "\n"
    output += table(testOnly) + "\n\n"
    output += "### Properties production writes and only tests read\n\n"
    output += table(readOnlyByTests) + "\n\n"
    output += unusedImports(imports)
    output += assignOnlySection(assignOnly)
    return output
  }
}

// MARK: - Sections

private extension TriageReport {
  func table(_ findings: [PeripheryFinding], flaggedFunctions: Set<String> = []) -> String {
    var rows = ["| Location | Kind | Name | Notes |", "| --- | --- | --- | --- |"]
    for finding in findings {
      let found = notes.notes(for: finding, flaggedFunctions: flaggedFunctions)
      let text = found.isEmpty ? "-" : found.joined(separator: "; ")
      rows.append("| \(finding.location) | \(finding.kind) | `\(finding.name)` | \(text) |")
    }
    return rows.joined(separator: "\n")
  }

  func unusedImports(_ imports: [PeripheryFinding]) -> String {
    var output = "## Unused imports reported by Periphery\n\n" + Self.importsCaveat + "\n"
    var byFile: [String: [String]] = [:]
    for finding in imports {
      byFile[finding.path, default: []].append("\(finding.name) (line \(finding.line))")
    }
    for path in byFile.keys.sorted() {
      output += "- \(path): \(byFile[path, default: []].joined(separator: ", "))\n"
    }
    return output + "\n"
  }

  /// Assign-only properties: counted when a note explains them, listed when not.
  func assignOnlySection(_ properties: [PeripheryFinding]) -> String {
    var output = "## Assign-only properties\n\n"
    var counts: [String: Int] = [:]
    var firstSeen: [String] = []
    var unexplained: [PeripheryFinding] = []
    for finding in properties {
      if let note = notes.notes(for: finding).first {
        if counts[note] == nil {
          firstSeen.append(note)
        }
        counts[note, default: 0] += 1
      } else {
        unexplained.append(finding)
      }
    }
    let ordered = firstSeen.enumerated().sorted { lhs, rhs in
      let (left, right) = (counts[lhs.element, default: 0], counts[rhs.element, default: 0])
      return left != right ? left > right : lhs.offset < rhs.offset
    }
    for (_, note) in ordered {
      output += "- \(counts[note, default: 0]) × \(note)\n"
    }
    output += "\n\(unexplained.count) without a structural explanation:\n\n"
    return output + table(unexplained) + "\n"
  }

  static func order(_ lhs: PeripheryFinding, _ rhs: PeripheryFinding) -> Bool {
    (lhs.path, lhs.line, lhs.column, lhs.kind, lhs.name)
      < (rhs.path, rhs.line, rhs.column, rhs.kind, rhs.name)
  }
}
