# Presentr: labels

Clone at `c911226` (origin ivan-magda/Presentr), the Presentr presentation library (18 Swift files) whose example app
(10 Swift files) builds it as a CocoaPods development pod (`pod 'Presentr', :path => '../'`) in
`PresentrExample/PresentrExample.xcworkspace`, below the repository root. Configuration:
[`deadcode.yml`](deadcode.yml), which raises the iOS 9.0 target and the Swift 3.0/4.2 settings
for Xcode 27.1. Setup in the clone: `pod install` in `PresentrExample/`; the pod needs no
download.

The whole cycle runs on it: `describe` reads the development pod and the app, `check` reads the
workspace, and `scan` builds the app scheme, pod included, and scans both (20 s).

| Command | Finding | Verdict | Evidence |
| --- | --- | --- | --- |
| `check --report` | `file docs/img/gh.png` | TRUE, not applied | generated jazzy documentation; no page or stylesheet in `docs/` names it, while the pages use `carat.png` and `dash.png` (`docs/Classes.html` and others) |
| `scan` | `customPresenter` (`PresentrExample/PresentrExample/MainTableViewController.swift:142`) | AMBIGUOUS | the example's table no longer presents with it, but `PRESENTATIONTYPE.md:72-83` shows the same snippet as the documented way to build a custom presentation |

The library's public API is retained (`--retain-public`); nothing else is reported. Nothing is
proposed for deletion.
