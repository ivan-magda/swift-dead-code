# Marky-Mark: labels

Clone at `b7adfa0` (m2mobi/Marky-Mark), a Markdown parser and renderer for iOS: 146 Swift files of
library code, which its example app, a Today extension and 27 test files build as a CocoaPods
development pod (`pod 'markymark', :path => '../'`) in `Example/markymark.xcworkspace`, below the
repository root. Configuration: [`deadcode.yml`](deadcode.yml). Setup in the clone: `pod install`
in `Example/` with the locked versions.

`describe` reads the workspace as the app, the extension, the tests and the development pod,
which CocoaPods splits by deployment target into `markymark-iOS8.3` and `markymark-iOS12.1`
(the same 146 files, module `markymark`); the SwiftLint pod has no module.

The example app's scheme runs the locked SwiftLint 0.28.1 as a build phase. Under Xcode 27.1 it
stops with "Loading sourcekitd.framework … failed" (the cached SwiftLint 0.50.1 instead fails
the build on a `large_tuple` error in a test file), so the app and the tests cannot be built
without changing the project. The scan builds the library's own scheme, so it covers the 146
library files but not the tests: a finding may be code only the tests use.

## `check --report` (3 findings)

| Finding | Verdict | Evidence |
| --- | --- | --- |
| `asset Example/markymark/Images.xcassets/appleLogoBlue.imageset`, `…Green…`, `…Red…` | TRUE, not applied | added as per-level bullet images in `b4e020e` (2018); both view controllers now set `bulletImages` to `circle`, `emptyCircle`, `line` and `square` (`AdvancedMarkdownViewController.swift:59`, `SimpleMarkDownViewController.swift:45`), and `markdown.txt` names only `appleLogo` and `appleLogoSmall` |

The first run also listed `markymark/Assets/.gitkeep` and `markymark/Classes/.gitkeep`: FALSE,
placeholders that keep a directory in git, conventional files now.

## `scan` (16 unused declarations, public API retained)

| Class | Count | Verdict | Triage note |
| --- | --- | --- | --- |
| `numberOfLines()` (`MarkDownLines.swift:35`) | 1 | FALSE in this scan: a test file calls it, and the tests were not built | none |
| `HasIndex`, `HasLevel`, `HasListItems` and their four conformances | 7 | AMBIGUOUS: protocols nothing uses as a type; whether they document a shape or are leftovers is the maintainers' call | "protocol nothing uses as a type" / "conformance to a protocol …" |
| Other declarations (`StringComposer`, `LayoutBuilder`, `isDirectlyConnectTo(_:)`, `getInlineTextItem(…)` and what only it calls, `removeConstraints()`, `listRules`, a parameter) | 8 | not labeled one by one | some have "used only by flagged" or "check the signature" |

Nothing is proposed for deletion: without the tests in the build, a deletion here could not be
verified by them.
