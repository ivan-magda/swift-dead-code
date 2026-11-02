@testable import DeadCodeKit
import Foundation
import Testing

@Suite
struct ImportScannerTests {
  @Test
  func collectsImportsInEveryBranchAndMacroModules() {
    // given
    let source = """
      import Foundation
      @testable import App
      @_exported import Kit
      public import Models
      import struct Collections.Deque
      import UIKit.UIGestureRecognizerSubclass
      #if os(Linux)
        import Glibc
      #endif
      /* import Commented */
      let text = \"\"\"
      import InString
      \"\"\"
      @freestanding(expression)
      public macro stringify(_ value: Int) = #externalMacro(module: "Macros", type: "Stringify")
      """

    // when
    let modules = ImportScanner.importedModules(in: source)

    // then
    #expect(
      modules == [
        "Foundation", "App", "Kit", "Models", "Collections", "UIKit", "Glibc", "Macros",
      ]
    )
  }

  @Test
  func offersOnlyPlainTopLevelImportsToThePruner() {
    // given
    let source = """
      import Foundation
      @testable import App
      @preconcurrency import Dispatch
      @_spi(Internal) import Kit
      @_exported import Exported
      public import Models
      import struct Collections.Deque
      import UIKit.UIGestureRecognizerSubclass
      import Logging  // used on Linux
      #if canImport(Glibc)
        import Glibc
      #endif
      """

    // when
    let imports = ImportScanner.removableImports(in: source, path: "A.swift")

    // then
    #expect(imports.map(\.module) == ["Foundation", "App", "Dispatch", "Kit"])
    #expect(imports.map(\.line) == [1, 2, 3, 4])
    #expect(imports[1].text == "@testable import App")
  }

  @Test
  func findsImportsInAFileWithWindowsLineEndings() {
    // when: Swift reads "\r\n" as one Character, not "\n".
    let imports = ImportScanner.removableImports(
      in: "import Foundation\r\n\r\nimport Kit\r\n",
      path: "A.swift"
    )

    // then
    #expect(imports.map(\.line) == [1, 3])
  }
}

@Suite
struct SourceIndexTests {
  @Test
  func countsTheLinesOfAFileWithWindowsLineEndings() throws {
    // given: Swift reads "\r\n" as one Character, which is not "\n".
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("swift-dead-code-tests-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: root)
    }
    try TextFiles.write(
      "let first = 1\r\nlet second = 2\r\n",
      to: root.appendingPathComponent("A.swift")
    )

    // when
    let lines = SourceIndex(root: root).lineCount(of: "A.swift")

    // then: two lines and the empty one after the last line break.
    #expect(lines == 3)
  }
}

@Suite
struct GlobTests {
  @Test(arguments: [
    ("Tests/**", "Tests/AppTests/A.swift", true),
    ("Tests/**", "Sources/Tests/A.swift", false),
    ("**/.swiftpm/**", ".swiftpm/xcode/a.xcscheme", true),
    ("**/.swiftpm/**", "Packages/Env/.swiftpm/xcode/a.xcscheme", true),
    ("*.xctestplan", "App.xctestplan", true),
    ("*.xctestplan", "Plans/App.xctestplan", false),
    ("docs/", "docs/research/a.md", true),
    ("Assets.xcassets/achievement-*.imageset", "Assets.xcassets/achievement-gold.imageset", true),
    ("Sources/?.swift", "Sources/AB.swift", false),
  ])
  func matchesWholePaths(pattern: String, path: String, expected: Bool) {
    #expect(Glob(pattern).matches(path) == expected)
  }
}

@Suite
struct MultiPatternSearchTests {
  @Test
  func findsOverlappingAndNestedTerms() {
    // given
    let search = MultiPatternSearch(terms: ["icon", "app-icon", "con", "missing", ""])

    // when
    let found = search.matches(in: "see Assets/app-icon.png")

    // then
    #expect(found == [0, 1, 2])
  }
}

@Suite
struct UnifiedDiffTests {
  @Test
  func laysOutHunksLikeDifflib() {
    // given: the expected text comes from Python's difflib.unified_diff on the same input.
    let lines = (1...20).map { "line \($0)\n" }

    // when
    let diff = UnifiedDiff.removing([2, 8, 19], from: lines, path: "A.swift")

    // then
    #expect(
      diff == """
        --- a/A.swift
        +++ b/A.swift
        @@ -1,11 +1,9 @@
         line 1
        -line 2
         line 3
         line 4
         line 5
         line 6
         line 7
        -line 8
         line 9
         line 10
         line 11
        @@ -16,5 +14,4 @@
         line 16
         line 17
         line 18
        -line 19
         line 20

        """
    )
  }

  @Test
  func marksAMissingFinalNewline() {
    // when
    let diff = UnifiedDiff.removing([1], from: ["import Kit\n", "let a = 1"], path: "B.swift")

    // then
    #expect(diff.hasSuffix(" let a = 1\n\\ No newline at end of file\n"))
    #expect(diff.contains("@@ -1,2 +1 @@"))
  }

  @Test
  func keepsWindowsLineEndings() {
    // when: a CRLF line ends with the Character "\r\n", which is not "\n".
    let diff = UnifiedDiff.removing(
      [1],
      from: ["import Kit\r\n", "let a = 1\r\n"],
      path: "C.swift"
    )

    // then
    #expect(diff == "--- a/C.swift\n+++ b/C.swift\n@@ -1,2 +1 @@\n-import Kit\r\n let a = 1\r\n")
  }
}
