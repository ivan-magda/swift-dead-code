# swift-debounce: labels

Clone at `acebe11`, a SwiftPM library (debounce and throttle for Swift concurrency, with a
SwiftUI module and nested `Benchmarks/` and `Examples/` packages). Configuration:
[`deadcode.yml`](deadcode.yml) (`--retain-public`).

## `check --report`

The first run, before the tool learned two conventions, gave 5 findings, all FALSE; both
rules were added to the tool (DECISIONS.md, 2026-10-30) and the run is now clean.

| Finding | Verdict | Evidence | Fixed by |
| --- | --- | --- | --- |
| `file Benchmarks/results/prototype-{locks,scenarios,storage}.md` | FALSE | `Benchmarks/README.md:158` links them as `results/prototype-*.md` | wildcard mentions |
| `file Sources/Debounce/Debounce.docc/Resources/{debouncer-states,edges-timeline}~dark.svg` | FALSE | DocC picks the `~dark` variant of an image the catalog names | variant suffixes |

## `scan`

| Location | Kind | Name | Verdict | Evidence | Triage note |
| --- | --- | --- | --- | --- | --- |
| Sources/Debounce/Internal/Pacer.swift:137:5 | var.parameter | `isolation` | FALSE | `isolation: isolated (any Actor)?` runs `_runIfCurrent` on the caller's actor; the doc comment above says the check and the call must not be separated by a hop | flags it since the isolated-parameter note was added; before, only the generic signature hint |
| Sources/Debounce/Internal/Pacer.swift:149:5 | var.parameter | `isolation` | FALSE | same, for the overload without a value | same |
| Tests/DebounceE2ETests/Support.swift:74:5 | var.parameter | `isolation` | FALSE | `eventually(timeout:isolation:_:)` defaults it to `#isolation` so the polling runs on the caller's actor | same |
| Sources/Debounce/Internal/PacingMachine.swift:25:19 | function.method.instance | `send(_:now:)` | KEEP | a requirement of `_PacingMachine`, the documented contract both machines implement; callers use the concrete machines (`Throttler.swift:106`), so nothing calls it through the protocol | flags it: "protocol requirement" |

## `prune-imports`

0 of 0 candidate imports; no file borrows an import.
