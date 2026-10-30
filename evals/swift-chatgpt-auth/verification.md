# swift-chatgpt-auth: verification

## Group 1: `ScriptedHTTPClient.requests()` and `requestCount()` (TRUE)

**Researcher** (fresh read-only subagent, brief from `evals/researcher-brief.md`):

- `requests()`, `requestCount()`: NO USE FOUND. Checks: grep of the whole tree, docs and CI;
  the double conforms only to `HTTPExecuting`, whose single requirement is `execute(_:)`
  (`HTTP.swift:115-121`); production code holds it as `any HTTPExecuting`; no `@objc`,
  `Mirror` or dynamic member lookup; `git log -S` finds only the initial commit, so no caller
  was ever removed.
- Left behind: `seen` becomes write-only (declared at `TestHelpers.swift:40`, written at :47,
  read only by the two methods); the doc comment at :29 ("records every request it saw")
  stops being true. No import becomes unused.
- Noted, not acted on: swift-claw's version of these tests read recorded requests through a
  different double; they were never ported here.

Each cited line was opened and matched.

**Applied** in the clone on branch `deadcode-eval` (commit `563a4ab`): both methods, `seen`
and its `append`, and the doc comment's last clause; 10 lines removed, 1 changed.

| Check | Command | Result |
| --- | --- | --- |
| build | `swift build --build-tests --scratch-path <scratch>` | exit 0 |
| tests | `swift test --scratch-path <scratch>` | exit 0; 70 tests in 11 suites passed |
| lint (the project's own) | `swiftlint --strict` | exit 0 |

Nothing proposed for deletion turned out alive.
