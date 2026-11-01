# swift-claude-code: labels

Clone at `88ed290` (the original checkout has uncommitted changes; the clone has the last
commit). An executable package: `cli` runs the `Core` library, which uses AsyncHTTPClient.
Configuration: [`deadcode.yml`](deadcode.yml).

## `check --report`

| Finding | Verdict | Evidence |
| --- | --- | --- |
| `file docs/s00.md` … `docs/s08.md` (9) | KEEP | sources of the guide series published on ivanmagda.dev, which the README links (`README.md:11`); nothing in the repository names the files. Allowlisted with that reason |

## `scan`

| Location | Kind | Name | Verdict | Evidence | Triage note |
| --- | --- | --- | --- | --- | --- |
| Sources/Core/Agent.swift:659:33 | var.parameter | `input` | FALSE | `executeCompact` is stored in the tool table (`"compact": executeCompact`, line 469), whose value type fixes the signature | flags it: "check the signature it must match" |
| Sources/Core/Agent.swift:698:34 | var.parameter | `input` | FALSE | same, `"task_list": executeTaskList` (line 472) | flags it |

61 redundant-public notes are access-level findings, not dead code.

Production declarations that only tests reach. Two of the 61 are public declarations only tests
use: Periphery ignores test callers when it judges public access, so the scan with tests calls
them redundant public, and the scan without tests calls them unused. Triage hid them until the
2026-11-01 review fix (`TriageReport`: a redundant-public note no longer counts as a finding
with tests); the same JSON now gives these two rows:

| Location | Kind | Name | Verdict | Evidence | Triage note |
| --- | --- | --- | --- | --- | --- |
| Sources/Core/BackgroundManager.swift:104:15 | function.method.instance | `awaitCompletion(jobId:)` | KEEP | a test seam: its doc comment says "Used for test determinism"; only `AgentLoopTests` and `BackgroundManagerTests` call it | "named or documented as a test seam" |
| Sources/Core/SkillLoader.swift:49:14 | var.instance | `isEmpty` | TRUE (test-only) | only `Tests/CoreTests/SkillLoaderTests.swift` reads it (lines 54, 75, 109, 119, 129); `Agent` uses `descriptions` and `content(for:)`, and `SkillLoader` checks `skills.isEmpty` itself. Removing it means rewriting those assertions, so it was not deleted | - |

## `prune-imports`

`--all`: 0 of 4 candidate imports are removable.

`--check-only --all` (exit 1):

| File | Verdict | Evidence |
| --- | --- | --- |
| Sources/Core/API/APIClient.swift | TRUE (borrows an import) | uses `.POST`, `add(name:value:)` and `.code` from NIOHTTP1 without importing it; it compiles only because the module reaches the target through AsyncHTTPClient. The fix adds `import NIOHTTP1` (and the `swift-nio` product dependency), not a deletion |
