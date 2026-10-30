# swift-speech-lanes: verification

## Group 1: two `import AVFAudio` lines (TRUE, removable imports)

Proposed by `prune-imports --all`: the macOS build and the strict MemberImportVisibility build
of `SpeechLanes` pass without them.

**Researcher** (fresh read-only subagent): NO USE FOUND for either.

- `LaneExecutor.swift` uses `AVAudioFile` and `init(forReading:)` (:64, passed to
  `SpeechAnalyzer.start(inputAudioFile:)` at :76); `SpeechLaneTranscriber.swift` uses
  `AVAudioFile` (:45, :47). Both reach AVFAudio through `import Speech`: the Speech Swift
  interface has `@_exported public import Speech` (the Clang module), whose headers import
  `<AVFoundation/AVFoundation.h>` under `export *`, and AVFoundation exports AVFAudio.
- The chain is the same in the macOS, iOS, iOS Simulator, visionOS and visionOS Simulator SDKs
  of Xcode 27.1; there is no `#if` in the package.
- Left behind: nothing. `DurationGuard.swift` keeps its own `import AVFAudio` because it has no
  `import Speech`. Style note: the files also keep `import Foundation`, which Speech re-exports
  the same way; the project states no rule about explicit imports.

Opened and matched: the iPhoneSimulator SDK's `Speech.swiftinterface` (`public import
AVFoundation`, `@_exported public import Speech`), `SFSpeechRecognizer.h:8`
(`#import <AVFoundation/AVFoundation.h>`) and the module map's `export *`.

**Applied** in the clone on branch `deadcode-eval` (commit `a792a4d`): `git apply` of the
generated `prune.patch`, 2 lines removed.

| Check | Command | Result |
| --- | --- | --- |
| macOS build | `swift build --build-tests --scratch-path <scratch>` | exit 0 |
| macOS tests | `swift test --scratch-path <scratch>` | exit 0; 43 tests in 10 suites passed |
| iOS build | `xcodebuild build -scheme swift-speech-lanes -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO` | BUILD SUCCEEDED |
| visionOS build | same with `generic/platform=visionOS Simulator` | BUILD SUCCEEDED |
| lint (the project's own) | `swiftlint --strict` | exit 0 |

Nothing proposed for removal turned out to be needed.
