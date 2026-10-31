# NetNewsWire: verification

The groups are applied in a separate clone, `swift-dead-code-work/netnewswire-verify` (branch
`deadcode-eval`, with the same generated `SecretKey.swift`), so the scans of
`swift-dead-code-work/netnewswire` see the original code.

## Group 1: private methods nothing calls (from `scan`)

Fourteen declarations went to the researcher; [`labels.md`](labels.md) lists them with the
verdicts. Applied: the 11 TRUE ones.

| Declarations | File |
| --- | --- |
| `showNotificationsDeniedError()` | `Mac/Preferences/General/GeneralPrefencesViewController.swift:237` |
| `showInitialDownloadError(_:)`, and its two strings in `Shared/Localizable.xcstrings` | `Mac/MainWindow/AddFeed/AddFeedController.swift:154` |
| `accountForNode(_:)`, `commonAccountsFor(_:)` | `Mac/MainWindow/Sidebar/SidebarOutlineDataSource.swift:264, 277` |
| `nodeForItem(_:)`, `nodeRepresentsTodayFeed(_:)` | `Mac/MainWindow/Sidebar/SidebarViewController.swift:745, 908` |
| `unreadArticles(from:)`, `readArticles(from:)` | `Mac/MainWindow/Timeline/TimelineViewController+ContextualMenus.swift:136, 141` |
| `rows(for: Article)`, `representedObjectsContainsTodayFeed()` | `Mac/MainWindow/Timeline/TimelineViewController.swift:1190, 1366` |
| `_fetchUnreadArticles(feed:)` | `Modules/Account/Sources/Account/Account.swift:1304` |

**Researcher** (fresh read-only subagent): NO USE FOUND for 13 of the 14; NEEDED for
`FeedInspectorViewController.swift:199`, called at :86 from an `@IBAction` that
`FeedInspector.xib:78` wires; and "confirm intent" for the `Account.swift:1383/1397` pair,
whose doc comment promises behavior a 2025 refactor bypassed. Every candidate sits in a
`private extension`, so only its own file can call it; none is `@objc` (the project sets
`SWIFT_SWIFT3_OBJC_INFERENCE = Off`), none is under `#if`, and no protocol of the enclosing
types declares the names. History came from a full clone on this machine and `gh api`, since
the eval clone is shallow. Left behind: the two catalog strings only `showInitialDownloadError`
used (removed with it), and older leftovers the deletion does not cause (noted, not applied).

Opened and matched before applying: each declaration and the line after it; the call at
`FeedInspectorViewController.swift:86` inside `newArticleNotificationsEnabledChanged(_:)`
(:70), and its action in `FeedInspector.xib:78`; `Account.swift:1376-1405` and :802-804; the
two catalog entries and that no Swift file uses their keys; that
`database.fetchUnreadArticles(feedIDs:)` keeps its caller at `Account.swift:1266`.

**Applied**: commit `c5936df`, 92 lines removed in 8 files.

## Group 2: files and assets nothing names (from `check`)

| Finding | Where |
| --- | --- |
| a nib whose File's Owner class no longer exists | `Mac/Base.lproj/AddFeedFromListSheet.xib` |
| a symbol image for a preferences pane that is gone | `Mac/Resources/Assets.xcassets/preferencesToolbarExtensions.symbolset` |
| two widget assets | `Widget/Assets.xcassets/CornerIcon.imageset`, `WidgetBackground.colorset` |
| Feedly test fixtures | `Modules/Account/Tests/AccountTests/JSON/feedly_{collections_initial,macintosh_initial,unreads_1000,unreads_initial}.json` |
| an RSS fixture | `Modules/RSParser/Tests/RSParserTests/Resources/489.rss` |

**Researcher** (fresh read-only subagent): NO USE FOUND for all nine. It checked
case-insensitive names and generated asset symbols, target membership, the xcconfig chain,
Info.plists, `Package.swift` resource rules, names built at runtime, scripts, CI, docs and
history. By its reading of the history: the nib left the build in 2018 and its controller was
deleted in 2019, and the switch of `Mac/` to a synchronized folder put the nib back into the app;
the Extensions pane, the last `Image("CornerIcon")`, the last `Color("WidgetBackground")` and
the Feedly tests were each removed upstream; `489.rss` came from the standalone RSParser
repository without a test. Left behind: nothing. The two `Package.swift` rules copy whole
directories that stay non-empty, and no project reference, localized copy or doc names the
files. It also noted two older leftovers outside the group (a hidden button in
`AddFeedSheet.xib` that sends an unimplemented `showFeedList:`, and the widget's
`AccentColor`), not applied.

Opened and matched before applying: `AddFeedFromListSheet.xib:9` and the absence of
`AddFeedFromListWindowController` in Swift; `Shared/Assets.swift:80-82`;
`Widget/WidgetBundle.swift:22-24`; `TestingURLProtocol+Responses.swift:15-17` and its callers;
that no pbxproj entry or exception set names the nib.

The researcher's own read of a full clone of NetNewsWire elsewhere on this machine fetched
missing objects into it (a partial clone), about 44 MB of packs; no file or ref there changed.

**Applied**: commit `b1d94a6`, 11 files deleted. `check --report` on the verification clone then
lists only the three dependency findings left out on purpose.

## Build and tests

In the verification clone, with a separate DerivedData, `CODE_SIGNING_ALLOWED=NO`:

| Check | Command | Result |
| --- | --- | --- |
| macOS app | `xcodebuild build -scheme NetNewsWire -destination 'platform=macOS,arch=arm64'` | BUILD SUCCEEDED, after group 1 and after both |
| iOS app | `xcodebuild build-for-testing -scheme NetNewsWire-iOS -destination 'platform=iOS Simulator,name=iPhone 17'` | TEST BUILD SUCCEEDED, after group 1 and after both |
| iOS tests | `xcodebuild test-without-building -scheme NetNewsWire-iOS` | 5 tests in 2 suites passed after group 1 (iPhone 17) and after both (iPhone 17 Pro). After both, the iPhone 17 simulator refused to launch the app ("Application failed preflight checks", `Busy`) three times, also after a shutdown; the same build passed on iPhone 17 Pro |
| RSParser | `swift test --package-path Modules/RSParser --scratch-path <scratch>` | 330 Swift Testing tests and 26 XCTest tests passed, both times |
| ArticlesDatabase | same, `Modules/ArticlesDatabase` | 19 tests passed, both times |
| Account | `xcodebuild test -scheme AccountTests -destination 'platform=macOS,arch=arm64'` in `Modules/Account` | 34 Swift Testing tests and 61 XCTest tests passed, with both groups applied and in the clone without them. Under `swift test` the same tests crash in both clones at `RSCore/AppConfig.swift:13` (`Bundle.main` has no `CFBundleExecutable` there), so that runner is not used |

The macOS tests are not built: they compile AppleScript against the dictionary of an installed
NetNewsWire, which this machine does not have (the reason for `for_testing: false` in the
configuration).

Nothing applied turned out alive. One declaration the first scan listed and I sent to the
researcher was alive; it was not applied, and the final scan no longer lists it (see
[`labels.md`](labels.md)).
