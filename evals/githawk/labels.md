# GitHawk: labels

Clone at `837bf6c6` (GitHawkApp/GitHawk), a UIKit app with a watchOS app in a CocoaPods
workspace (`Freetime.xcworkspace`) whose `Pods/` directory is committed, plus development pods
in `Local Pods/`. Configuration: [`deadcode.yml`](deadcode.yml).

`describe` reads the workspace as 13 targets: the app, its tests, the watch app and extension,
and the iOS and watchOS copies of the development pods (`GitHubAPI`, `DateAgo` and others),
with the CocoaPods pods as external modules and the `Pods-*` aggregate targets skipped.

The scan is not possible here: with Xcode 27.1 and the deployment targets raised to iOS 15.0 and
watchOS 9.0 in `build_arguments` (the minimum Xcode 27.1 builds), the app fails to compile at
`BadgeNotifications.swift:46:17: error: switch must be exhaustive`, which only a code change
fixes. GitHawk is struck as a scan candidate; the CocoaPods scan runs on
[`gh-actions-test`](../gh-actions-test/labels.md).

## `check --report` (26 findings)

| Finding | Verdict | Evidence |
| --- | --- | --- |
| `file FreetimeTests/IssueCommentTableTests.swift`, `file FreetimeTests/SortUsers.swift` | TRUE, not applied | no target compiles them: the project file has never named either (`git log -S` on `project.pbxproj` finds nothing) |
| `file FreetimeTests/Snapshot Tests/ReferenceImages_64/FreetimeTests.AttributedStringViewTests/…@2x.png` (2) | TRUE, not applied | reference images of `AttributedStringViewTests`, deleted with its subject in `e9899fb9` ("Delete NSAttributedStringSizing (#1826)") |
| `file Resources/FreetimeSamples-Info.plist`, `file Resources/Snapshots-Info.plist` | TRUE, not applied | no `INFOPLIST_FILE` names them; the samples and snapshots targets left the project (`0fb9eaa6`, `5f9926d3`) |
| `file Playgrounds/Github API/.config.json` and five `examples/*.json` | AMBIGUOUS | sample payloads and the settings of a model generator (`"destination": "gen"`, a rename map) run by hand; nothing in the repository names the generator |
| 14 `asset Resources/Assets.xcassets/…` octicons (`bar-ol`, `beaker`, `checklist`, `clippy`, `ellipses`, `git-branch`, `git-compare`, `grabber`, `hubot`, `no-newline`, `octoface`, `paintcan`, `tasklist`, `trashcan`) | AMBIGUOUS | no file names them, but the app builds image names at runtime (`UIImage(named: "\(icon)-small")` in `Classes/Issues/Labels/IssueLabelStatusCell.swift:70`, `UIImage(named: viewModel.imageName)`), so a name may come from data; not researched |

The first run listed 33 findings. The other 7 were FALSE and are fixed in the tool, with no
change to the configuration:
- `build-phases/generate-apollo-graphql-api.sh` and `build-phases/validate-api-keys.sh`, run by
  Run Script phases: the phases' scripts and input and output paths now count as mentions.
- `Resources/GoogleService-Info.plist`, which Firebase reads by name, and
  `Local Pods/SwipeCellKit/.travis.yml`: conventional files now.
- Two CocoaPods support scripts in `Local Pods/GitHubAPI/Pods/`: `Pods/` counts at any depth
  now.
- `Local Pods/SwipeCellKit/docs/docsets/SwipeCellKit.docset/…/docSet.dsidx`: documentation
  sets are bundles found by convention.
