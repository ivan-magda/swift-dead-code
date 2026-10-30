# swift-ssrf-guard: labels

Clone at `79438fe`, a SwiftPM library (SSRF guard for URL fetching), 7 source files.
Configuration: [`deadcode.yml`](deadcode.yml) (`--retain-public`: the public API is the contract).

| Command | Findings |
| --- | --- |
| `check --report` | none |
| `scan` | none, with or without tests |
| `prune-imports --all` | 0 of 0 candidate imports (every import is a platform module) |
| `prune-imports --check-only --all` | no file borrows an import |

Nothing to label. The package is small and recently cleaned; a clean report is the expected
outcome, and nothing was proposed for deletion.
