# Evals

Each directory checks the tool on one real project: that it finds real dead code there, that
it proposes no live code for deletion, and that the project needs nothing but a
`.deadcode.yml` (no code change in the tool).

## How a project is evaluated

1. **Clone.** `git clone --local <repo> ~/Developer/swift-dead-code-work/<name>`;
   the original checkout is never touched. The cloned commit is recorded in `summary.json`.
   Setup the project's own README asks for (an xcconfig from its template, `pod install`,
   generating an XcodeGen project) is done in the clone and noted there.
2. **Configure.** `deadcode.yml` here is copied into the clone as `.deadcode.yml`. It is the
   only input besides the clone.
3. **Run.** `check --report`, `scan --output runs/<name>/scan`, and for SwiftPM packages
   `prune-imports --all` and `prune-imports --check-only --all`, one build at a time. Outputs
   stay under `~/Developer/swift-dead-code-work/runs/<name>/`.
4. **Label.** `labels.md` gives every finding a verdict with evidence:
   - **TRUE**: dead; proposed for deletion.
   - **FALSE**: alive; the scanner is wrong. Says whether the triage note flags it.
   - **KEEP**: unused on purpose (seam, contract, public API, published asset); goes to the
     allowlist or the baseline.
   - **AMBIGUOUS**: cannot be decided from the code.
5. **Verify.** Before a TRUE group is applied, a fresh read-only subagent researches it with the
   brief from the skill (§3); its claims count only after the cited code is opened. The group is
   then applied in the clone, and the clone must build and pass its tests. `verification.md`
   records the commands and results. A TRUE row that turns out alive is a failed eval.

## Files

| File | Holds |
| --- | --- |
| `deadcode.yml` | the configuration the project needed |
| `labels.md` | every finding with its verdict and evidence |
| `verification.md` | the researcher's report and the build and test results of the deletions |
| `deletions.patch` | the applied deletions, as `git format-patch` output against the recorded commit |
| `summary.json` | commit, counts per verdict, timings, for REPORT.md |

[`swift-claw/parity.md`](swift-claw/parity.md) compares the tool with the scripts it replaces.

## Projects

| Project | Kind | Status |
| --- | --- | --- |
| [swift-claw](swift-claw/parity.md) | SwiftPM | parity with the scripts the tool replaces |
| [swift-ssrf-guard](swift-ssrf-guard/labels.md), [swift-speech-lanes](swift-speech-lanes/labels.md), [swift-chatgpt-auth](swift-chatgpt-auth/labels.md), [swift-debounce](swift-debounce/labels.md), [swift-claude-code](swift-claude-code/labels.md) | SwiftPM | labeled; two groups verified |
| [IceCubes](icecubes/labels.md) | xcodeproj with local packages | labeled; two groups verified |
| [NetNewsWire](netnewswire/labels.md) | xcodeproj, iOS and macOS | labeled; two groups verified (20 deletions); a live method the first scan listed was caught before it was applied, and the scan now confirms findings per build |
| [Element X](element-x/labels.md) | XcodeGen | labeled; one group verified |
| [GhActionsTest](gh-actions-test/labels.md) | CocoaPods | full cycle on a small app |
| [Presentr](presentr/labels.md) | CocoaPods, development pod | full cycle: the whole workspace built and scanned; labeled |
| [Marky-Mark](marky-mark/labels.md) | CocoaPods, development pod | labeled; the library's scheme scanned, the example and tests cannot build with Xcode 27.1 |
| [GitHawk](githawk/labels.md) | CocoaPods | `describe` and `check` only: does not compile with Xcode 27.1 |
| [stepik-ios](stepik-ios/deadcode.yml), [Tagger](tagger/deadcode.yml) | CocoaPods | struck: stepik-ios needs a git-crypt key, Tagger has a compile error with Xcode 27.1 |

[`skill-test-xcdiff.md`](skill-test-xcdiff.md) records a fresh agent using the skill on a project
it had never seen, and what changed because of it.
