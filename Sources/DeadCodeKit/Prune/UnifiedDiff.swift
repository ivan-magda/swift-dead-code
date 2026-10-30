/// A unified diff that removes lines from files, laid out as Python's `difflib.unified_diff`
/// lays it out (three lines of context, hunks merged when their context overlaps), so
/// `git apply` takes it.
enum UnifiedDiff {
  static let context = 3

  /// The diff for one file; `lines` keep their line endings, `removed` holds 1-based numbers.
  static func removing(_ removed: Set<Int>, from lines: [String], path: String) -> String {
    let changes = removed.filter { $0 >= 1 && $0 <= lines.count }.sorted()
    guard !changes.isEmpty else {
      return ""
    }
    var output = "--- a/\(path)\n+++ b/\(path)\n"
    // Lines removed by earlier hunks shift where this one starts in the new file.
    var removedBefore = 0
    for hunk in hunks(changes, lineCount: lines.count) {
      let oldCount = hunk.last - hunk.first + 1
      let newCount = oldCount - hunk.removed.count
      let newStart = hunk.first - removedBefore
      removedBefore += hunk.removed.count
      output += "@@ -\(range(hunk.first, oldCount)) +\(range(newStart, newCount)) @@\n"
      for number in hunk.first...hunk.last {
        let prefix = hunk.removed.contains(number) ? "-" : " "
        output += prefix + terminated(lines[number - 1])
      }
    }
    return output
  }
}

// MARK: - Hunks

private extension UnifiedDiff {
  struct Hunk {
    var first: Int
    var last: Int
    var removed: Set<Int>
  }

  static func hunks(_ changes: [Int], lineCount: Int) -> [Hunk] {
    var hunks: [Hunk] = []
    for change in changes {
      let first = max(1, change - context)
      let last = min(lineCount, change + context)
      if var current = hunks.last, first <= current.last + 1 {
        current.last = max(current.last, last)
        current.removed.insert(change)
        hunks[hunks.count - 1] = current
      } else {
        hunks.append(Hunk(first: first, last: last, removed: [change]))
      }
    }
    return hunks
  }

  /// `difflib` writes a one-line range without its length, and an empty one from the line
  /// before it.
  static func range(_ start: Int, _ length: Int) -> String {
    switch length {
    case 1:
      "\(start)"
    case 0:
      "\(start - 1),0"
    default:
      "\(start),\(length)"
    }
  }

  static func terminated(_ line: String) -> String {
    line.hasSuffix("\n") ? line : line + "\n\\ No newline at end of file\n"
  }
}
