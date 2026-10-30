/// Finds which of many terms occur in a text in one pass over its bytes (Aho–Corasick), so the
/// file check stays fast on repositories with thousands of files.
struct MultiPatternSearch {
  private struct Node {
    var next: [UInt8: Int32] = [:]
    var failure: Int32 = 0
    /// The nearest node on the failure chain that ends a term, or -1.
    var outputLink: Int32 = -1
    var terms: [Int32] = []
  }

  private var nodes = [Node()]

  init(terms: [String]) {
    for (index, term) in terms.enumerated() where !term.isEmpty {
      insert(term, index: Int32(index))
    }
    linkFailures()
  }

  /// The indices of the terms that occur in `text`.
  func matches(in text: String) -> Set<Int> {
    var found: Set<Int> = []
    var reported = Set<Int32>()
    var state: Int32 = 0
    for byte in text.utf8 {
      state = transition(from: state, on: byte)
      var node = nodes[Int(state)].terms.isEmpty ? nodes[Int(state)].outputLink : state
      while node > 0, reported.insert(node).inserted {
        for term in nodes[Int(node)].terms {
          found.insert(Int(term))
        }
        node = nodes[Int(node)].outputLink
      }
    }
    return found
  }
}

// MARK: - Automaton

private extension MultiPatternSearch {
  mutating func insert(_ term: String, index: Int32) {
    var state = 0
    for byte in term.utf8 {
      if let next = nodes[state].next[byte] {
        state = Int(next)
      } else {
        nodes.append(Node())
        let created = Int32(nodes.count - 1)
        nodes[state].next[byte] = created
        state = Int(created)
      }
    }
    nodes[state].terms.append(index)
  }

  mutating func linkFailures() {
    var queue: [Int32] = []
    for (_, child) in nodes[0].next {
      queue.append(child)
    }
    var head = 0
    while head < queue.count {
      let state = queue[head]
      head += 1
      for (byte, child) in nodes[Int(state)].next {
        queue.append(child)
        var fallback = nodes[Int(state)].failure
        while fallback > 0, nodes[Int(fallback)].next[byte] == nil {
          fallback = nodes[Int(fallback)].failure
        }
        let failure = nodes[Int(fallback)].next[byte].flatMap { $0 == child ? nil : $0 } ?? 0
        nodes[Int(child)].failure = failure
        nodes[Int(child)].outputLink =
          nodes[Int(failure)].terms.isEmpty ? nodes[Int(failure)].outputLink : failure
      }
    }
  }

  func transition(from state: Int32, on byte: UInt8) -> Int32 {
    var current = state
    while true {
      if let next = nodes[Int(current)].next[byte] {
        return next
      }
      if current == 0 {
        return 0
      }
      current = nodes[Int(current)].failure
    }
  }
}
