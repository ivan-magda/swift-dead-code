# swift-chatgpt-auth: labels

Clone at `aa064da` (the original checkout has uncommitted changes to `.gitignore`, `CLAUDE.md`
and untracked notes, none in Swift). A SwiftPM library: device-authorization OAuth for
ChatGPT/Codex. Configuration: [`deadcode.yml`](deadcode.yml) (`--retain-public`).

## `check --report`

No findings.

## `scan`

| Location | Kind | Name | Verdict | Evidence | Triage note |
| --- | --- | --- | --- | --- | --- |
| Sources/ChatGPTAuth/Credential/ChatGPTCredentialSource.swift:331:15 | var.parameter | `flight` | AMBIGUOUS | `join(_ flight:)` never reads `flight`, but its callers start a flight inline (`join(startFlight(...))`, lines 67 and 73); dropping the parameter means restructuring them while keeping the evaluation order, not a deletion | flags it: "check the signature it must match" |
| Tests/ChatGPTAuthTests/TestHelpers.swift:63:8 | function.method.instance | `requests()` | TRUE | no caller in tests or sources; the double conforms to `HTTPExecuting`, which requires only `execute(_:)` (Sources/ChatGPTAuth/Transport/HTTP.swift:115-121); present since the initial commit | "may witness a requirement of: HTTPExecuting", checked and not the case |
| Tests/ChatGPTAuthTests/TestHelpers.swift:67:8 | function.method.instance | `requestCount()` | TRUE | same | same |

## `prune-imports`

0 of 0 candidate imports; no file borrows an import.
