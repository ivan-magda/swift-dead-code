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

## `prune-imports`

`--all`: 0 of 4 candidate imports are removable.

`--check-only --all` (exit 1):

| File | Verdict | Evidence |
| --- | --- | --- |
| Sources/Core/API/APIClient.swift | TRUE (borrows an import) | uses `.POST`, `add(name:value:)` and `.code` from NIOHTTP1 without importing it; it compiles only because the module reaches the target through AsyncHTTPClient. The fix adds `import NIOHTTP1` (and the `swift-nio` product dependency), not a deletion |
