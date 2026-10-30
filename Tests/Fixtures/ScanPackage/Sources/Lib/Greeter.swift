import Helper  // HelperThing; the comment keeps the pruner away

/// Greets people; the package's public API.
public struct Greeter {
  public init() {}

  public func greet() -> String {
    HelperThing().label + format(mode: .fast)
  }

  /// Nothing calls this.
  func forgottenHelper() -> Int {
    42
  }

  func format(mode: Mode) -> String {
    mode == .fast ? "!" : "."
  }
}

enum Mode: CaseIterable {
  case fast
  case slow
}

/// A test seam: production never calls it.
func makeGreeterForTesting() -> Greeter {
  Greeter()
}
