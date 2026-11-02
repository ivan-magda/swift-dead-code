# GhActionsTest: labels

Clone at `7e669e2` of a small test repository
([gh-actions-test](https://github.com/ivan-magda/gh-actions-test)): a SwiftUI app in a CocoaPods workspace one
directory below the repository root, with one pod, SwiftLint 0.50.1, which ships a binary and no
module. Configuration: [`deadcode.yml`](deadcode.yml). Setup in the clone: `pod install` (the
`Pods/` directory is not committed; `Podfile.lock` gains the CocoaPods version line).

It is the CocoaPods project that runs the whole cycle here: GitHawk, the real CocoaPods app,
does not compile with Xcode 27.1 ([`../githawk/labels.md`](../githawk/labels.md)), and
stepik-ios needs a git-crypt key. The project is small, so this run shows that the tool reads a
CocoaPods workspace, skips the `Pods-*` aggregate target and builds through the pods; it says
little about finding dead code.

| Command | Result |
| --- | --- |
| `describe` | one target, `GhActionsTest`, module `GhActionsTest`, 2 Swift files; no external modules (the pod has none) |
| `check --report` | no findings: the entitlements file is named by `CODE_SIGN_ENTITLEMENTS`, `Preview Content` by `DEVELOPMENT_ASSET_PATHS`, the workflows are conventional |
| `scan` | 10 s; one unused declaration, `ContentView_Previews` (`ContentView.swift:23`): KEEP, a SwiftUI preview, with the note "SwiftUI preview: used at design time only" |

The first `scan` failed: the Pods project gives the SwiftLint target iOS 9.0, below the iOS 15.0
that Xcode 27.1 builds. `build_arguments` raises it to 16.2, the app's own target; nothing in the
project changes.

Nothing was proposed for deletion.
