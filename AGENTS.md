# Agent instructions

This file provides guidance to coding agents working in this repository.

`swift-dead-code` finds dead code in SwiftPM packages and Xcode projects by orchestrating the
compiler, the build system and Periphery; `skills/removing-dead-code/` is a thin agent skill on
top. It never deletes code: removals come out as a patch or a list of findings.

## Commands

- Build and test: `swift build`, `swift test`; one test:
  `swift test --filter 'IntegrationTests/pruneBuildsEveryConfiguredBuild'`.
- Lint before calling work done: `STRICT=1 scripts/lint.sh`, which fails on SwiftLint warnings
  too; `scripts/lint.sh --fix` applies the fixes first.
- The repository checks itself: `swift run swift-dead-code check`, configured by `.deadcode.yml`.

## Architecture

- Put logic in `DeadCodeKit`, the only module the tests import; `Sources/swift-dead-code` stays a
  thin ArgumentParser layer.
- Checks see only `ProjectModel`, which `SwiftPackageAdapter` and `XcodeProjectAdapter` build: fix
  wrong targets, module names or dependencies there. `swift-dead-code describe` prints the model.
- Only `scan` and `prune-imports` build, in an rsync copy of the project inside their output
  directory (`WorkingCopy`), under a machine-wide `FileLock`.
- `ScanRunner`: `ProjectBuilder` index stores → Periphery with and without test code →
  `BuildConfirmation` when targets share a module name → `TriageReport`.
- Periphery runs as a process pinned to 3.8.0, its last MIT release, not as a library: PeripheryKit
  does not export scan orchestration and pins an older swift-syntax.
- Output is byte-identical across runs: sort every list, and keep timestamps, absolute paths and
  durations out of reports. Results go to stdout, progress to stderr.

## Tests

- Missing tools skip tests rather than fail them: the scan test needs `periphery version` to equal
  the pinned version, and the `XcodeShop` tests need `xcodegen`.
- `Tests/Fixtures/XcodeShop/Shop.xcodeproj` is committed but generated: after editing
  `project.yml` there, run `xcodegen generate` in that directory.

## Docs and evals

- When a check's rules or a `.deadcode.yml` key change, update the README ("Configuration", "How
  the checks decide") and `docs/DESIGN.md`, and the skill when CLI flags or output change.
- Log non-obvious decisions as dated rows in `DECISIONS.md`: the owner's gitignored local notes
  in Russian, like `REPORT.md`, `PROGRESS.md`, `docs/BRIEF.md`; everything committed is English.
- Before running or changing an eval → `evals/README.md`. Evals run in `git clone --local` copies
  in a scratch directory, never in the original checkouts.
