#if canImport(Kit)
  import Kit
#endif

/// Names the assets the app shows.
public enum Artwork {
  public static let icon = "UsedIcon"
  public static func badge(_ level: String) -> String {
    "Badge-\(level)"
  }
}
