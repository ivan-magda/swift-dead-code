import Foundation

/// One result of a Periphery JSON scan (`--format json`).
public struct PeripheryFinding: Sendable, Hashable, Decodable {
  public var kind: String
  public var name: String
  /// `path:line:column`, relative to the scan's working directory with `--relative-results`.
  public var location: String
  /// The declaration's USRs, sorted; they stay the same when code moves.
  public var ids: [String]
  public var hints: [String]
  public var modifiers: [String]
  public var attributes: [String]
  public var accessibility: String

  public init(
    kind: String,
    name: String,
    location: String,
    ids: [String],
    hints: [String],
    modifiers: [String] = [],
    attributes: [String] = [],
    accessibility: String = ""
  ) {
    self.kind = kind
    self.name = name
    self.location = location
    self.ids = ids
    self.hints = hints
    self.modifiers = modifiers
    self.attributes = attributes
    self.accessibility = accessibility
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    kind = try container.decode(String.self, forKey: .kind)
    name = try container.decode(String.self, forKey: .name)
    location = try container.decode(String.self, forKey: .location)
    ids = try container.decode([String].self, forKey: .ids)
    hints = try container.decode([String].self, forKey: .hints)
    modifiers = try container.decodeIfPresent([String].self, forKey: .modifiers) ?? []
    attributes = try container.decodeIfPresent([String].self, forKey: .attributes) ?? []
    accessibility = try container.decodeIfPresent(String.self, forKey: .accessibility) ?? ""
  }

  private enum CodingKeys: String, CodingKey {
    case kind
    case name
    case location
    case ids
    case hints
    case modifiers
    case attributes
    case accessibility
  }

  /// The file that declares it.
  public var path: String {
    Location(location).path
  }

  /// The 1-based line of the declaration.
  public var line: Int {
    Location(location).line
  }

  /// The 1-based column of the declaration's name.
  public var column: Int {
    Location(location).column
  }

  /// Periphery lists exactly one hint per result.
  public var hint: String {
    hints.joined(separator: ",")
  }

  /// The USRs as a set key: a declaration both scans report counts once.
  public var identity: [String] {
    ids.sorted()
  }

  /// The declaration's name without its parameter list: `start(at:)` becomes `start`.
  public var bareName: String {
    String(name.prefix { $0 != "(" })
  }

  /// Reads a Periphery JSON scan.
  public static func read(_ url: URL) throws -> [PeripheryFinding] {
    guard let data = FileManager.default.contents(atPath: url.path) else {
      throw DeadCodeError.usage("cannot read Periphery scan \(url.path)")
    }
    do {
      return try JSONDecoder().decode([PeripheryFinding].self, from: data)
    } catch {
      throw DeadCodeError.usage("\(url.path) is not a Periphery JSON scan: \(error)")
    }
  }
}

// MARK: - Location

/// A `path:line:column` string taken apart; the path may itself contain colons.
private struct Location {
  var path: String
  var line = 0
  var column = 0

  init(_ location: String) {
    let parts = location.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count >= 3, let line = Int(parts[parts.count - 2]),
      let column = Int(parts[parts.count - 1])
    else {
      path = location
      return
    }
    path = parts.dropLast(2).joined(separator: ":")
    self.line = line
    self.column = column
  }
}
