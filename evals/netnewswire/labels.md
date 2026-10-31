# NetNewsWire: labels

Clone at `aea7795` (Ranchero-Software/NetNewsWire), an xcodeproj with an iOS and a macOS app,
their extensions, synchronized folders, xcconfig chains and 17 local packages in `Modules/`.
Configuration: [`deadcode.yml`](deadcode.yml): two builds, iOS and macOS, the macOS one without
its test targets. Setup in the clone: `Modules/Secrets/Sources/Secrets/SecretKey.swift`
generated with the project's own `buildscripts/gyb.py`, with empty keys.

## `check --report` (16 findings with the binary of the scan, 12 with the final one)

The first four rows are gone from the final binary's output.

| Finding | Verdict | Evidence |
| --- | --- | --- |
| `file Mac/Resources/NetNewsWire-dev.entitlements`, `file iOS/Resources/NetNewsWire-dev.entitlements` | FALSE, fixed in the tool | `CODE_SIGN_ENTITLEMENTS = Mac/Resources/NetNewsWire$(DEVELOPER_ENTITLEMENTS).entitlements` (`xcconfig/NetNewsWire_macapp_target.xcconfig:4`, iOS likewise): a build-setting variable in a path now counts as a wildcard |
| `file Modules/RSParser/Tests/RSParserTests/Resources/atp.rss` | FALSE, fixed in the tool | `parserData("atp", "rss", …)` (`RSSParserTests.swift:91`): a stem shorter than four characters now counts when a string literal is exactly that stem |
| `dependency RSCore RSCoreObjC` | FALSE, fixed in the tool | no RSCore file imports RSCoreObjC, but `Mac/AppDelegate.swift` does, and the macOS app gets the module only through RSCore: a dependency a downstream target imports without declaring now stays |
| `file Mac/Base.lproj/AddFeedFromListSheet.xib` | TRUE | its File's Owner is `AddFeedFromListWindowController` (xib:9), a class that no longer exists; the synchronized `Mac/` folder still ships it as a nib nothing loads |
| `asset Mac/Resources/Assets.xcassets/preferencesToolbarExtensions.symbolset` | TRUE | the preferences toolbar has General, Accounts and Advanced only, all SF Symbols (`Shared/Assets.swift:80-82`) |
| `asset Widget/Assets.xcassets/CornerIcon.imageset`, `asset Widget/Assets.xcassets/WidgetBackground.colorset` | TRUE | no file names them; every widget sets `containerBackground(for: .widget) { Color.clear }` (`Widget/WidgetBundle.swift:22`), and no build setting names a widget background color |
| 4 `file Modules/Account/Tests/AccountTests/JSON/feedly_*.json` | TRUE | the only loader, `TestingURLProtocol.setResponse(_:file:)`, is called with literal Feedbin fixture names |
| `file Modules/RSParser/Tests/RSParserTests/Resources/489.rss` | TRUE | every `parserData` call passes a literal name, and none is `489` |
| `dependency NetNewsWire SyncDatabase`, `dependency NetNewsWire-iOS SyncDatabase` | AMBIGUOUS | no app file imports SyncDatabase, which `Account` uses; it is a dynamic library, and the apps may list it so that Xcode embeds it. Not tested |
| `dependency RSWeb RSParser` | TRUE, not applied | no RSWeb source or test imports RSParser, and every target that imports RSParser declares it or reaches it through another declaration |

Earlier runs also listed `container-migration.plist`, which macOS reads from the app bundle (a
tool convention now), and files in `Technotes/`, `AppStore/`, `Appcasts/`, `buildscripts/` and
`scripts/`, read by people and release tooling (`conventional_paths` in the configuration).
All FALSE.

## `scan` (456 unused declarations, iOS and macOS, each build confirming)

Both apps are module `NetNewsWire`, so the scan gives each build its own index and keeps a
finding of the combined index only when the builds confirm it (DESIGN.md §15.3): the combined
index reported 699 findings with tests and the builds confirmed 673; without tests, 538 of 560.
Counted on that final scan; each row is in one class only.

| Class | Count | Verdict | Triage note |
| --- | --- | --- | --- |
| Unused parameters | 143 | not labeled one by one | "check the signature it must match" |
| Protocol requirements | 9 | not labeled one by one | "protocol requirement" |
| Conformances nothing uses as the protocol (`ScriptingAppDelegate`, `AppDelegateAppleEvents`, `Renamable`, `OAuthAccessTokenResponse`) | 9 | not labeled one by one | "conformance to a protocol nothing uses as a type: a marker …" |
| Findings in a type both apps declare (9 in `AppDefaults`, one each in `AppDelegate`, `ErrorHandler`, `IconView`) | 11 | not labeled one by one | "declared again in NetNewsWire-iOS, also module NetNewsWire …" |
| The proposed group | 13 | 11 TRUE, 2 AMBIGUOUS (below) | none, or "used only by flagged" |
| Other declarations | 271 | not labeled one by one | various |

The 26 findings the builds did not confirm include `Mac/Inspector/FeedInspectorViewController.swift:199`
(below) and 13 rows of the iOS `AppDefaults`; the ones checked are alive
(`timelineSortDirection` at `iOS/SceneCoordinator.swift:101`, `isFirstRun` at
`iOS/SceneDelegate.swift:30`, `Assets.Images.todayFeed` at
`Shared/SmartFeeds/TodayFeedDelegate.swift:24`). All 11 verified deletions are still reported,
and so is macOS-only code under `#if` in shared packages (`KeyboardConstant` in RSCore).

### A live method proposed by the first run

The first scans used one index for both builds. Both apps declare `FeedInspectorViewController`,
whose `newArticleNotificationsEnabledChanged:` action has the same USR in each, and Periphery
reported `showNotificationsDeniedError()` (`FeedInspectorViewController.swift:199`) as unused
although the macOS copy calls it at :86; one scan listed it with tests, the next only without.
It went to the researcher with the group below, came back NEEDED, and was never applied. The
fix is the per-build confirmation above: the final combined index reported it again, and no
build alone did, so the final scan does not list it.

### The group sent to the researcher (14 declarations)

| Declaration | Verdict | Evidence |
| --- | --- | --- |
| `Mac/Inspector/FeedInspectorViewController.swift:199` `showNotificationsDeniedError()` | FALSE | called at :86 in `@IBAction newArticleNotificationsEnabledChanged(_:)`, wired in `FeedInspector.xib:78` |
| `Mac/Preferences/General/GeneralPrefencesViewController.swift:237` `showNotificationsDeniedError()` | TRUE | its only caller, `toggleShowingUnreadCount(_:)`, was removed upstream in `c1a6c42b` |
| `Mac/MainWindow/AddFeed/AddFeedController.swift:154` `showInitialDownloadError(_:)` | TRUE | last caller removed in `43d32b12`; its two strings in `Shared/Localizable.xcstrings` go with it |
| `SidebarOutlineDataSource.swift:264` `accountForNode(_:)`, `:277` `commonAccountsFor(_:)` | TRUE | the last call was removed in `bead6ae1`; `nodeAccount(_:)` at :567 is the copy in use |
| `SidebarViewController.swift:745` `nodeForItem(_:)` | TRUE | the calls in `SidebarOutlineDataSource.swift` go to that file's own private copy |
| `SidebarViewController.swift:908` `nodeRepresentsTodayFeed(_:)` | TRUE | split out with no caller in `2bbd135c` |
| `TimelineViewController+ContextualMenus.swift:136` `unreadArticles(from:)`, `:141` `readArticles(from:)` | TRUE | last caller removed in `3731648d` |
| `TimelineViewController.swift:1190` `rows(for: Article)` | TRUE | the call at :1219 passes a `String`, so it reaches the :1185 overload |
| `TimelineViewController.swift:1366` `representedObjectsContainsTodayFeed()` | TRUE | its caller `calendarDayChanged(_:)` was removed in `8b0c8156` |
| `Modules/Account/Sources/Account/Account.swift:1304` `_fetchUnreadArticles(feed:)` | TRUE | its caller became `preconditionFailure` in `7a204ad6`; `database.fetchUnreadArticles(feedIDs:)` keeps its other caller at :1266 |
| `Account.swift:1383` `_fetchUnreadCounts(for:)`, `:1397` `_fetchUnreadCount(feed:)` | AMBIGUOUS | the doc comment promises a choice by feed count, but since `d7c20f5f` `updateUnreadCounts(feeds:)` (:802) calls the batched query directly; that may be a slip to fix rather than code to delete |

Upstream commit hashes come from the researcher's reading of the full history; the clone itself
is shallow.

## Verified deletion groups

[`verification.md`](verification.md).
