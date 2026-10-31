# IceCubes: labels

Clone at `2ad6e68` (Dimillian/IceCubesApp), an xcodeproj: SwiftUI app, five extensions in
synchronized folders, 13 local packages added as folder references. Configuration:
[`deadcode.yml`](deadcode.yml). Setup in the clone: `IceCubesApp.xcconfig` from its template.

## `check --report` (10 findings)

| Finding | Verdict | Evidence |
| --- | --- | --- |
| `dependency Account WrappingHStack` | TRUE | no file imports it; its last user was deleted upstream in `24cccfad` |
| `dependency StatusKit LRUCache` | TRUE | last user deleted in `2f5307bf` |
| `dependency Timeline SwiftUIIntrospect` | TRUE | unused since `9ec6a4ef` |
| `dependency IceCubesAppWidgetsExtensionExtension Account` | TRUE | never imported by the widget's files (folder plus three entity files added by exception sets) |
| `dependency IceCubesNotifications Account`, `DesignSystem`, `StatusKit` | TRUE | the extension's two files import neither; DesignSystem and StatusKit still reach it through the Notifications package |
| `dependency IceCubesShareExtension KeychainSwift` | TRUE | never imported; keychain access goes through AppAccount, which gets KeychainSwift through Env |
| `dependency NetworkClientTests NetworkClient` | AMBIGUOUS | the test file has `@testable import Network` (Apple's framework), so the test target is broken; the fix is the import, not the dependency |
| `file scripts/launch_sim.sh` | KEEP | a developer script run by hand; belongs in the allowlist |

The first run, before the tool learned three conventions, also listed `AGENTS.MD` (case),
`Localizable.xcstrings`, nested `.swiftpm/` schemes, `ci_scripts/*` and 38 alternate-icon
image sets loaded as `"AppIconAlternate\(index)-image"`; all FALSE, all fixed in the tool
(DECISIONS.md, 2026-10-30).

## `scan`, iOS build (210 unused declarations)

| Class | Count | Verdict | Triage note |
| --- | --- | --- | --- |
| `@Environment` property nothing reads | 97 | TRUE as a class; 30 verified below | "@Environment nothing reads: usually a leftover..." |
| App Intents and widget-configuration static metadata (`description`, `typeDisplayName`) | 17 | FALSE: the system reads them | "a AppIntent / WidgetConfigurationIntent: the system finds and calls it" |
| `@State` read only through `$name` | part of 22 | FALSE: Xcode 27 indexes the projected value separately | "read through its projected value $name" |
| `*_Previews` structs and preview-only data (`previewAccount`) | 9 + 5 | KEEP: design time | "SwiftUI preview" for the structs; preview data has no note |
| Other declarations (methods, inits, statics, properties) | ~60 | not labeled one by one | — |

`@AccessibilityFocusState private var initialFocusBugWorkaround` (StatusDetailView.swift:24)
is AMBIGUOUS: its doc comment calls it a VoiceOver workaround, yet nothing sets it; the
dynamic-property note asks exactly this question.

40 unused imports and 233 redundant-public notes are reported but not labeled here.

## Verified deletion groups

See [`verification.md`](verification.md): 8 dependency removals and 30 declarations, built for
iOS and tested (48 tests in AccountTests, StatusKitTests and TimelineTests).
