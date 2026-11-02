import Foundation

/// Small file-system helpers shared by the checks.
public enum TextFiles {
  /// A file's text, or nil for a missing or binary file, which mentions nothing.
  public static func read(_ url: URL) -> String? {
    guard let data = FileManager.default.contents(atPath: url.path) else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  /// Writes text, creating the parent directory.
  public static func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data(text.utf8).write(to: url)
  }

  /// Build output without terminal colors and hyperlinks, so that error lines parse.
  public static func strippingTerminalEscapes(_ text: String) -> String {
    text.replacingOccurrences(
      of: "\u{1B}\\[[0-9;]*m|\u{1B}\\]8;;[^\u{1B}]*\u{1B}\\\\",
      with: "",
      options: .regularExpression
    )
  }

  /// The path of `url` relative to `root`, or nil when it lies outside.
  public static func relativePath(of url: URL, under root: URL) -> String? {
    let path = url.standardizedFileURL.resolvingSymlinksInPath().path
    let base = root.standardizedFileURL.resolvingSymlinksInPath().path
    if path == base {
      return ""
    }
    let prefix = base.hasSuffix("/") ? base : base + "/"
    guard path.hasPrefix(prefix) else {
      return nil
    }
    return String(path.dropFirst(prefix.count))
  }

  /// The path from the directory `base` to `path`, both absolute and normalized, climbing with
  /// `..` where needed: `../Shared` for a sibling of `base`.
  static func relativePath(of path: String, from base: String) -> String {
    let target = path.split(separator: "/")
    let start = base.split(separator: "/")
    let common = zip(target, start).prefix { $0 == $1 }.count
    let climb = Array(repeating: "..", count: start.count - common)
    return (climb + target.dropFirst(common).map(String.init)).joined(separator: "/")
  }

  /// The path with every link resolved, as a process running there sees its directory:
  /// `/private/var/...` for `/var/...`, which `resolvingSymlinksInPath()` shortens instead.
  static func realPath(_ url: URL) -> String {
    guard let resolved = realpath(url.path, nil) else {
      return url.standardizedFileURL.path
    }
    defer {
      free(resolved)
    }
    return String(cString: resolved)
  }

  /// Joins and normalizes a relative path: `a/./b/../c` becomes `a/c`.
  public static func normalize(_ path: String) -> String {
    var components: [Substring] = []
    for component in path.split(separator: "/", omittingEmptySubsequences: true) {
      switch component {
      case ".":
        continue
      case "..":
        if let last = components.last, last != ".." {
          components.removeLast()
        } else {
          components.append(component)
        }
      default:
        components.append(component)
      }
    }
    return components.joined(separator: "/")
  }
}
