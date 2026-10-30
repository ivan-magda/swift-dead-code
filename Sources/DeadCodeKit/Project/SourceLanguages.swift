/// File types that targets compile, by language.
public enum SourceLanguages {
  /// Extensions of files a target compiles rather than copies as resources.
  public static let compiledExtensions: Set<String> = [
    "c", "cc", "cpp", "cxx", "m", "mm", "metal", "s", "swift",
  ]

  /// Extensions of Objective-C sources, whose uses of Swift declarations Periphery cannot see.
  public static let objectiveCExtensions: Set<String> = ["m", "mm"]
}
