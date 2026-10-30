public struct HelperThing {
  public init() {}

  public var label: String {
    "helper"
  }
}

extension String {
  /// The string in capitals.
  public var shouted: String {
    uppercased()
  }
}
