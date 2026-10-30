# Parity with swift-claw's scripts

The generalized tool must give swift-claw's findings from configuration alone
([`deadcode.yml`](deadcode.yml)), with every difference explained.

- Clone: `git clone --local ~/Developer/swift-claw
  ~/Developer/swift-dead-code-work/swift-claw`, HEAD `39362695` (2026-10-30).
- Toolchain: Swift 6.4 (swiftlang-6.4.0.34.1), Xcode 27.1, Periphery 3.8.0.
- The configuration is copied into the clone as `.deadcode.yml`; swift-claw itself is untouched.

## Results

| Script | Command pair | Result |
| --- | --- | --- |
| `scripts/check-dead-code.py --report` | `swift-dead-code check --report` | identical: 4 findings, all allowlisted; both exit 0 without `--report` |
| `periphery_scan.sh OUT` → `all.json` | `swift-dead-code scan --output OUT` → `all.json` | identical: 43 findings, same locations, kinds, names, hints and USRs |
| same → `prod.json` | same → `prod.json` | identical: 88 findings |
| `triage.py` → `report.md` | `scan` → `report.md` | same sections, counts and rows; 5 notes differ, explained below |
| `check-periphery-baseline.py all.json prod.json` | `swift-dead-code baseline all.json prod.json` | stdout and stderr byte-identical; both exit 0 (33 test-code findings listed) |
| `check-periphery-baseline.py --write` | `swift-dead-code baseline --write` | the same 91 entries; only the `#` header differs |
| `prune_imports.py --all --modules Yams,UnixSignals,ArgumentParser,MCP` | `swift-dead-code prune-imports --all --modules ...` | see "Pruner" below |
| `prune_imports.py --check-only FILES` | `swift-dead-code prune-imports --check-only FILES` | see "Pruner" below |

Timing on this machine: the original scan took 301 s; `scan` took 371 s, including the rsync
copy of the project and a debug build of the tool running triage.

## Explained differences in `report.md`

1. **Caveat texts.** The test-only caveat says "`git log -S'<name>'` on product code" instead of
   "`-- Sources`", and the imports caveat names `prune-imports` instead of "GRDB, Logging,
   NIO": both named swift-claw specifics.
2. **`HistoryHygiene.sanitize(_:)` lost "named or documented as a test seam".** `triage.py`
   reads every line above a declaration up to the previous member, so the enum's own doc
   comment ("The LOAD seam already bounds windows...") counted for its first member. The
   comment speaks of architectural seams, not a test seam. SwiftSyntax reads the member's own
   doc comment, which has none.
3. **Four protocol requirements lost "may witness a requirement of: Sendable"**
   (`ScheduledJobStore.create(_:now:)`, `ScheduledLearningStore.compatibility(runID:)` and
   `.evaluation(runID:)`, `SessionMessageStore.loadOrCreateSession(sessionKey:now:)`). A
   protocol's own requirement witnesses nothing; the tool keeps that note for implementations.
   The same rule removes the note `triage.py` would have given `TelegramTransport.getMe()` had
   it parsed the protocol's multi-line inheritance list, which the regular expression missed.
4. **Two assign-only `lease` properties** (`LLMStreaming.swift:139`, `HTTPExecuting.swift:364`)
   moved from "without a structural explanation" to a counted note: "assign-only, but keeps
   StreamAbandonmentLease alive: the lifetime may be the point". swift-claw's early manual
   cleanup (2026-09-12) kept such a `lease` for its `deinit` side effect.

## Pruner

Pending: filled in when the background parity run finishes.
