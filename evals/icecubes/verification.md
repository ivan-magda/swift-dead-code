# IceCubes: verification

Both groups are applied in a separate clone, `swift-dead-code-work/icecubes-verify` (branch
`deadcode-eval`), so the scans of `swift-dead-code-work/icecubes` see the original code.

## Group 1: target dependencies no file imports (TRUE, from `check`)

| Target | Dependency | Where declared |
| --- | --- | --- |
| Account | WrappingHStack | `Packages/Account/Package.swift:26,38` |
| StatusKit | LRUCache | `Packages/StatusKit/Package.swift:26,38` |
| Timeline | SwiftUIIntrospect | `Packages/Timeline/Package.swift:25,37` |
| IceCubesAppWidgetsExtensionExtension | Account | `project.pbxproj` |
| IceCubesNotifications | Account, DesignSystem, StatusKit | `project.pbxproj` |
| IceCubesShareExtension | KeychainSwift | `project.pbxproj` |

**Researcher** (fresh read-only subagent): NO USE FOUND for all six. Each target's file list was
taken from the synchronized-folder exception sets; no extension file has `#if`; the products have
no resources, `@objc`, plugins, macros or load-time registration that would need them linked
without an import. History (upstream, read through the GitHub API because the clone is shallow)
shows each last user removed on purpose: WrappingHStack's only user went in `24cccfad`,
LRUCache's in `2f5307bf`; SwiftUIIntrospect stopped being used in `9ec6a4ef`; the widget's
`Account` was never imported; DesignSystem and StatusKit still reach the notifications
extension through the Notifications package, and KeychainSwift reaches the share extension
through Env. Left behind: the three `.package` lines (removed with the products), the
Package.resolved pins (Xcode updates them), the pbxproj objects (removed by object ID:
build file, frameworks-phase entry, product-dependency entry and object, 36 lines), and the
About screen credits that still name LRUCache and SwiftUI-Introspect (kept: they are
localization keys, and the list already credits a non-dependency).

Opened and matched: the manifest lines and the pbxproj objects of the widget's `Account` and the
share extension's `KeychainSwift`. After the removal, `check --report` on the verification clone
lists only the two findings not in this group (`dependency NetworkClientTests NetworkClient`,
`file scripts/launch_sim.sh`), so the edited project still parses.

## Group 2: SwiftUI properties nothing reads (TRUE, from `scan`)

29 `private` `@Environment` properties in seven files with no `#if` (`ExploreTab`,
`MessagesTab`, `NavigationTab`, `NotificationTab`, `ProfileTab`, `TimelineTab`,
`AccountDetailHeaderView`) and `AccountDetailHeaderView.Constants`. `private` keeps every use
inside the file, so a platform the scan did not build cannot use them.

**Researcher**: NO USE FOUND for all 30. Each name appears only on its declaration (`name`,
`_name`, `$name`); no extension of the seven types exists; no body reads the objects, so no
update subscription is lost. Upstream history shows the readers removed deliberately: the tabs'
toolbar backgrounds (`theme`) in `24cccfad`, the inline toolbar code (`preferences`,
`isSecondaryColumn`) in `c328c6c0`, `.onChange(of: currentAccount...)` in `363164d9`,
`.id(appAccount...)` in `875d89c1`, `watcher.unreadMessagesCount = 0` in `d59ba03b`,
`context.insert` in `23a83d69`; the header view's readers moved to its component views in
`24cccfad`. Left behind: imports that become unused in six of the files (not part of this
group: they are `prune-imports`' job, because without MemberImportVisibility a build cannot
prove an import unneeded), and `AccountsListRow.appAccountsManager`, whose only use injects an
environment value the header view no longer reads (noted, not applied).

Opened and matched: the declarations in `AccountDetailHeaderView.swift:11-25` (`watcher` at
:20 is read and stays).

**Applied**: commit `7ee3d45`, 33 lines removed in 7 files.

## Build and tests

Both groups together, in the verification clone, with a separate DerivedData:

| Check | Command | Result |
| --- | --- | --- |
| iOS | `xcodebuild build-for-testing -scheme IceCubesApp -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO` | TEST BUILD SUCCEEDED |
| Mac Catalyst | same with `'generic/platform=macOS,variant=Mac Catalyst'` | exit 0 |
| visionOS | same with `'generic/platform=visionOS Simulator'` | fails, and fails identically without the deletions: `'glassEffect(_:in:)' is unavailable in visionOS` at `Packages/DesignSystem/Sources/DesignSystem/CardBackgroundModifier.swift:10:15`, an upstream incompatibility with Xcode 27.1 |
| Account tests | `xcodebuild test -scheme AccountTests -destination 'platform=iOS Simulator,name=iPhone 17'` | 3 tests, 0 failures |
| StatusKit tests | same, `-scheme StatusKitTests` | 36 tests, 0 failures |
| Timeline tests | same, `-scheme TimelineTests` | 9 tests passed |

The scan with iOS and Mac Catalyst together still reports all 30 deleted declarations as
unused. It no longer reports 15 declarations the iOS-only scan did (13 `openWindow`
properties, `windowResize()`, `accountPopover(_:)`): Mac Catalyst code reads them. None of those
was proposed for deletion.

Nothing proposed for deletion turned out alive.
