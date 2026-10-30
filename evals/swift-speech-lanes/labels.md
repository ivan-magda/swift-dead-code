# swift-speech-lanes: labels

Clone at `2c6aa99`, a SwiftPM library for iOS, macOS and visionOS on Apple's `SpeechAnalyzer`.
Configuration: [`deadcode.yml`](deadcode.yml) (`--retain-public`).

## `check --report`

No findings.

## `scan`

| Location | Kind | Name | Verdict | Evidence | Triage note |
| --- | --- | --- | --- | --- | --- |
| Tests/SpeechLanesTests/LaneAssignmentTests.swift:6:29 | var.parameter | `locale` | FALSE | `noEquivalent(_:)` is passed as `speechEquivalent: noEquivalent` (line 18), so its signature is fixed by the function type `(Locale) async -> Locale?` | flags it: "check the signature it must match" |
| Tests/SpeechLanesTests/LaneAssignmentTests.swift:7:29 | var.parameter | `locale` | FALSE | same, for `ruEquivalent(_:)` | flags it |

## `prune-imports --all`

| Import | Verdict | Evidence |
| --- | --- | --- |
| Sources/SpeechLanes/Lanes/LaneExecutor.swift:1 `import AVFAudio` | TRUE (removable) | the file also imports `Speech`; the macOS build and the strict MemberImportVisibility build of `SpeechLanes` pass without it; see [`verification.md`](verification.md) |
| Sources/SpeechLanes/Transcriber/SpeechLaneTranscriber.swift:1 `import AVFAudio` | TRUE (removable) | same |

6 more candidates (`import Speech` ×5, `import AVFAudio` in `DurationGuard.swift`) are needed.
`--check-only`: no file borrows an import.
