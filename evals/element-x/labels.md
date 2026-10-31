# Element X: labels

Clone at `65bab49` (element-hq/element-x-ios), an XcodeGen project whose generated
`ElementX.xcodeproj` is committed: an app, three extensions, five test bundles, local packages
from `Package.swift` and the `compound-ios` package. Configuration: [`deadcode.yml`](deadcode.yml),
which carries over the project's own `.periphery.yml` (six schemes, excludes, retain flags).
Setup in the clone: cloned with `GIT_LFS_SKIP_SMUDGE=1` (snapshot images only). The `Enterprise`
submodule is private and was not initialized, so every result holds for the open-source
configuration only.

## `check --report` (24 findings)

| Finding | Verdict | Evidence |
| --- | --- | --- |
| 11 `dependency UITests …` (AnalyticsEvents, Collections, DeviceKit, GZIP, KeychainAccess, Kingfisher, MatrixRustSDK, PostHog, Sentry, SwiftOGG, SwiftState) | TRUE, not applied | of packages, the 21 files UITests compiles import only SnapshotTesting and KZFileWatchers; a UI test bundle drives the app in another process |
| 8 `dependency IntegrationTests …` (Collections, DeviceKit, GZIP, KeychainAccess, Kingfisher, MatrixRustSDK, Sentry, SwiftState) | TRUE, not applied | its 6 files import XCTest, Foundation and SwiftUI only |
| `dependency NSE Collections`, `dependency ShareExtension Collections` | TRUE, not applied | 13 app files and one unit-test file import `Collections` or `OrderedCollections`; neither extension's `target.yml` lists one of them or its directory |
| `dependency PreviewTests MatrixRustSDK`, `dependency UnitTests MapLibreInterface` | AMBIGUOUS | both bundles `@testable import ElementX`, whose module imports these; a test bundle may need the dependency to load that module (MatrixRustSDK wraps a binary FFI module). Not tested |
| `file Tools/SwiftGen/Templates/Plists/runtime-swift5-element-info.stencil` | TRUE, not applied | `swiftgen-config.yml` names `templateName: swift5` and the two `Templates/Strings` stencils; nothing else names the file |

The dependency rows are left out of the verified group: removing them means editing the
targets' `target.yml` files and regenerating the project, and the UI and integration tests
need a running app and a homeserver, so the change could be built but not run here.

Earlier runs also listed `.githooks/*` (5), `LICENSE-COMMERCIAL` and `dependency ElementX
MapLibreShim`. All FALSE, all fixed in the tool: git hooks and license variants are
conventional files, and a framework a string literal names (here
`dlopen("\(frameworksPath)/MapLibreShim.framework/MapLibreShim")`) counts as used.

## `scan` (277 unused declarations, 47 test-only, 1 unused import)

| Class | Count | Verdict | Triage note |
| --- | --- | --- | --- |
| `TestablePreview` conformances of preview providers | 237 | KEEP: the Sourcery templates `PreviewTests.stencil`, `AccessibilityTests.stencil` and `TestablePreviewsDictionary.stencil` generate tests from every conforming type | "SwiftUI preview"; "a marker for code generators (Sourcery)" |
| `MapLibreShim` and what only it uses (`MapLibreMapView` and its extension, `MapLibreAnnotation`, `MapLibreAnnotationView`, `CoordinateAnimator`) | 6 | FALSE: the app `dlopen`s the framework and creates the class with `NSClassFromString("MapLibreShim")` (`ElementX/Sources/Other/MapLibre/MapLibreMapView.swift:105-110`) | on `MapLibreShim`: "exposed to Objective-C"; "named in a string". The other five have no note |
| `@State` read only through `$name` (`showingClearDataConfirmation`, `isExpanded`, `dragOver`, the preview's `sheetHeight`) | 4 | FALSE | "read through its projected value" |
| Fields of `Equatable` types (`TimelineItemIdentifier.transactionID`, `VideoInfoProxy.size`) | 2 | KEEP: part of `==` | "takes part in ==" |
| Protocol requirements (`AuthenticationServiceProtocol.flow`, `ClientProxyProtocol.isLiveKitRTCSupported`, `UserSessionStoreProtocol.userIDs`) | 3 | not labeled one by one: contracts with mocks generated from them | "protocol requirement" |
| Unused parameters (`appHooks`, `spanName`, `originalRequest`) | 3 | not labeled one by one | "check the signature it must match" |
| The verified group below | 7 | TRUE | none |
| `ClientProxyError.invalidHomeserverURL` (`ClientProxyProtocol.swift:45`) | 1 | AMBIGUOUS | none |
| Other declarations (two screen view-model protocols, `TextBasedRoomTimelineViewProtocol` and its three conformances, `AppHooks.setUp()`, `LinkNewDeviceService.cancel()`, `ClientProxy.userProfileListenerTaskHandle`, `ClientProxy.isLiveKitRTCSupported`, two `rustValue` properties, `isPresentingAccountDeactivationConfirmation`, `hardwareKeyboardDidConnect(_:)`) | 14 | not labeled one by one | some have "used only by flagged" or "may witness" |

`invalidHomeserverURL` has no thrower or matcher in the open-source code. It came with upstream
element-hq/element-x-ios#5953, "Update the Enterprise submodule." (merge commit `743c22d9`),
whose description says it adds a new `ClientProxyError` case; the private submodule may throw
it. Kept and reported as AMBIGUOUS.

## Verified deletion group

[`verification.md`](verification.md): 7 declarations (`readWidth(_:)`, a private `items` list,
five accessibility identifiers), researched, applied in a clone, built for all six schemes and
unit-tested.
