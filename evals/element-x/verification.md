# Element X: verification

The group is applied in a separate clone, `swift-dead-code-work/element-x-verify` (branch
`deadcode-eval`), so the scans of `swift-dead-code-work/element-x` see the original code.

## The group: 7 declarations nothing uses (TRUE, from `scan`)

| Declaration | Where |
| --- | --- |
| `readWidth(_:)` | `ElementX/Sources/Other/SwiftUI/Layout/ViewFrameReader.swift:38` |
| `TimelineMediaVisibility.items` (a `private extension`) | `ElementX/Sources/Screens/Settings/LocationSharingSettingsScreen/View/LocationSharingSettingsScreen.swift:93-99` |
| `ChangeServer.dismiss` | `ElementX/Sources/Other/AccessibilityIdentifiers.swift:99` |
| `ServerConfirmationScreen.continue`, `.changeServer` | same file, :239-240 |
| `SettingsScreen.blockedUsers`, `.advancedSettings` | same file, :264-265 |

An eighth candidate, `ClientProxyError.invalidHomeserverURL`, went to the researcher too and
came back NEEDED (probably): see [`labels.md`](labels.md). It was not applied.

**Researcher** (fresh read-only subagent): NO USE FOUND for the seven.
- `readWidth`: a repository-wide search (every target, the test bundles, compound-ios, docs)
  hits only the declaration; upstream element-hq/element-x-ios#6217 (`b1ed8704`) replaced its
  last two users, in `InviteUsersScreen` and `SpaceAddRoomsScreen`, with
  `containerRelativeFrame`.
- `items`: a `private extension` the file never reads, copied from
  `ModerationAndSafetySettingsScreen.swift`, whose own copy is the one in use.
- The identifiers: neither the Swift names nor the string values appear in the five test plans,
  scripts, workflows, docs or snapshot names; nothing reads identifiers through `Mirror` or
  builds them by interpolation. `dismiss`, `continue` and `changeServer` lost their users in
  element-hq/element-x-ios#5949, which combined the server selection and confirmation screens;
  `blockedUsers` and `advancedSettings` in element-hq/element-x-ios#6288, which reorganised
  the settings screen.
- Left behind: the extension in `LocationSharingSettingsScreen.swift` empties and goes;
  `ServerConfirmationScreen` keeps `serverPicker`, still used, though its name now describes
  a screen that is gone (rename optional, not done). No import becomes unused.

Opened and matched: `ViewFrameReader.swift:33-45`, `LocationSharingSettingsScreen.swift:88-99`,
the five identifier lines, and every use of `ChangeServer.continue` (:98, which stays: it is a
different identifier from the deleted `ServerConfirmationScreen.continue`). Searching
`git grep` for the five string values and for `.blockedUsers`/`.advancedSettings` finds no
identifier use.

**Applied**: one commit on `deadcode-eval`, 24 lines removed in 3 files.

## Build and tests

In the verification clone, with a separate DerivedData, destination
`platform=iOS Simulator,name=iPhone 17`, `CODE_SIGNING_ALLOWED=NO`:

| Check | Command | Result |
| --- | --- | --- |
| App | `xcodebuild build-for-testing -scheme ElementX` | TEST BUILD SUCCEEDED (232 s) |
| Test bundles | same for `UnitTests`, `PreviewTests`, `UITests`, `IntegrationTests`, `AccessibilityTests` | all succeeded |
| Unit tests | `xcodebuild test-without-building -scheme UnitTests` | 1267 tests in 151 suites; 58 fail, all in seven suites that need what this clone lacks |
| Same seven suites, no deletions | `xcodebuild test-without-building -xctestrun <scan build of the original code> -only-testing:UnitTests/<suite>` | 97 tests; the same 58 fail, with the same 81 issues |

The seven suites are `MediaUploadPreviewScreenViewModelTests`,
`MediaUploadingPreprocessorTests`, `MediaProviderTests`, `NSItemProviderTests` and
`VoiceMessageRecorderTests`, which read test media that are Git LFS pointers in this clone
(`Components/DevelopmentAssets/Media/landscape_test_video.mov` is a 132-byte pointer), and
`AppLockServiceTests` and `KeychainControllerTests`, which need keychain access an unsigned
simulator build does not get.

The UI, integration and accessibility tests were built, not run: they drive the installed app
against a homeserver. The snapshot tests in `PreviewTests` were built, not run: their reference
images are LFS objects too.

Nothing proposed for deletion turned out alive.
