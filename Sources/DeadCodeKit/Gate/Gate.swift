import Foundation

/// The build-free gate: target dependencies nothing imports, and files and assets nothing
/// mentions, checked against the allowlist.
public struct Gate: Sendable {
  public let model: ProjectModel
  public let configuration: Configuration
  let runner: any CommandRunning

  public init(
    model: ProjectModel,
    configuration: Configuration,
    runner: any CommandRunning = ProcessRunner()
  ) {
    self.model = model
    self.configuration = configuration
    self.runner = runner
  }

  /// Every finding, allowlisted or not.
  public func findings() throws -> Set<GateFinding> {
    let tracked = try Git(directory: model.root, runner: runner).trackedFiles()
    return DependencyCheck(model: model).findings()
      .union(
        ReferenceCheck(model: model, configuration: configuration, trackedFiles: tracked)
          .findings()
      )
  }

  /// The compiler-style errors for findings the allowlist lacks and for bad allowlist entries.
  public func errors(for findings: Set<GateFinding>) -> [String] {
    let config = configuration.sourcePath
    var seen: Set<GateFinding> = []
    var entries: [AllowlistEntry] = []
    var errors: [String] = []
    for entry in configuration.allowlist.sorted(by: { $0.line < $1.line }) {
      if seen.insert(entry.finding).inserted {
        entries.append(entry)
      } else {
        errors.append("\(config):\(entry.line):1: error: duplicate entry '\(entry.finding)'")
      }
    }
    for finding in findings.sorted() where !entries.contains(where: { $0.allows(finding) }) {
      errors.append(message(for: finding))
    }
    let stale = entries.filter { entry in
      !findings.contains { entry.allows($0) }
    }
    for entry in stale.sorted(by: { $0.finding < $1.finding }) {
      errors.append(
        "\(config):\(entry.line):1: error: '\(entry.finding)' no longer matches a finding; "
          + "remove the entry"
      )
    }
    return errors
  }

  /// Every finding, one per line, allowlisted ones marked: the leads for an audit.
  public func report(for findings: Set<GateFinding>) -> String {
    findings.sorted()
      .map { finding in
        isAllowlisted(finding) ? "\(finding)  (allowlisted)" : "\(finding)"
      }
      .joined(separator: "\n")
  }

  public func isAllowlisted(_ finding: GateFinding) -> Bool {
    configuration.allowlist.contains { $0.allows(finding) }
  }

  /// The findings as JSON, sorted, for other tools.
  public func json(for findings: Set<GateFinding>) throws -> String {
    struct Entry: Encodable {
      var kind: String
      var subject: String
      var allowlisted: Bool
    }
    let entries = findings.sorted().map { finding in
      Entry(
        kind: finding.kind.rawValue,
        subject: finding.subject,
        allowlisted: isAllowlisted(finding)
      )
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return String(bytes: try encoder.encode(entries), encoding: .utf8) ?? "[]"
  }
}

// MARK: - Messages

private extension Gate {
  func message(for finding: GateFinding) -> String {
    let keep =
      "add '\(finding.kind.rawValue): \(finding.subject)' with a reason to the allowlist in "
      + configuration.sourcePath
    switch finding.kind {
    case .dependency:
      let parts = finding.subject.split(separator: " ", maxSplits: 1).map(String.init)
      let manifest = model.target(named: parts[0])?.manifestPath ?? "Package.swift"
      return
        "\(manifest):1:1: error: \(parts[0]) declares \(parts[1]), but no file in the target "
        + "imports it; remove it or \(keep)"
    case .file:
      return "\(finding.subject):1:1: error: no other file mentions this file; delete it or \(keep)"
    case .asset:
      return
        "\(finding.subject):1:1: error: no file outside asset catalogs names this asset; "
        + "delete it or \(keep)"
    }
  }
}

public extension AllowlistEntry {
  /// Whether the entry keeps the finding: the same subject, or a `file` or `asset` glob that
  /// matches it.
  func allows(_ finding: GateFinding) -> Bool {
    guard finding.kind == kind else {
      return false
    }
    if kind != .dependency, subject.contains("*") || subject.contains("?") {
      return Glob(subject).matches(finding.subject)
    }
    return finding.subject == subject
  }
}
