# Moving swift-claw to swift-dead-code

swift-claw was the proving ground; this is the plan for the owner to move it onto the general
tool. Nothing here has been applied to swift-claw. [`evals/swift-claw/parity.md`](../evals/swift-claw/parity.md)
lists what the tool gives on a clone of swift-claw today and every difference from the
scripts.

## 1. `.deadcode.yml`

Add at the repository root. The allowlist moves from `BuildTools/dead-code-allowlist.txt`
with its reasons; the baseline stays where it is.

```yaml
# Dead-code analysis settings: scripts/lint.sh runs `swift-dead-code check`, and
# .github/workflows/dead-code.yml runs scan, baseline and prune-imports weekly.
test_support: [ClawTestSupport]

check:
  # Dated research is evidence, not a user of anything, and is never itself checked.
  not_references: [docs/research/]

allowlist:
  - file: docs/assets/branding/BRAND-ASSETS.md
    reason: index of the brand files in its own directory
  - file: docs/assets/demo/card-approve-deny.png
    reason: approval demo still; may be linked from outside the repository
  - file: docs/assets/demo/card-privileged.png
    reason: approval demo still; may be linked from outside the repository
  - file: docs/audits/duplication-audit-2026-07-13.md
    reason: point-in-time audit report, kept as a record

periphery:
  # Keep in step with CLAW_PERIPHERY_VERSION in BuildTools/lint-versions.env.
  version: 3.8.0
  baseline: BuildTools/periphery-baseline.txt

docs:
  contracts: [docs/ARCHITECTURE.md, docs/TESTING.md]
```

The parity run used the same file plus `not_references` entries for the old checker and its
allowlist ([`evals/swift-claw/deadcode.yml`](../evals/swift-claw/deadcode.yml)); both files go
away with this migration, so those entries go too. The defaults already retain Codable,
Equatable and Hashable properties and run the pruner's `--modules deps` over the package
products plus Testing and Synchronization, as `.periphery.yml` and `prune_imports.py` did.

## 2. What is replaced

| swift-claw today | Becomes |
| --- | --- |
| `scripts/check-dead-code.py` | `swift-dead-code check` |
| `BuildTools/dead-code-allowlist.txt` | `allowlist:` in `.deadcode.yml` (delete the file) |
| `.claude/skills/removing-dead-code/scripts/periphery_scan.sh OUT` | `swift-dead-code scan --output OUT` |
| `.claude/skills/removing-dead-code/scripts/triage.py` | part of `scan`; `swift-dead-code triage ALL PROD` on its own |
| `.claude/skills/removing-dead-code/scripts/prune_imports.py` | `swift-dead-code prune-imports` with the same flags |
| `scripts/check-periphery-baseline.py` | `swift-dead-code baseline` (same output, same baseline file) |
| `.periphery.yml` | delete: the tool writes its own Periphery configuration, and its two settings are defaults |
| `scripts/test-periphery-baseline.sh` | delete: swift-dead-code's `BaselineTests` cover the same four scenarios |
| dead-code cases in `scripts/test-lint.sh` | keep one case: whole-repository `scripts/lint.sh` reports a planted dependency through `swift-dead-code check`; the gate's own cases live in swift-dead-code's `GateTests` |
| `.claude/skills/removing-dead-code/SKILL.md` | the generic skill from `skills/removing-dead-code/`; swift-claw specifics come from `.deadcode.yml` (`docs.contracts`, `test_support`) |

Line by line:

- `scripts/lint.sh`: the dead-code stage runs `swift-dead-code check` instead of
  `python3 -I scripts/check-dead-code.py`; the prerequisite check looks for `swift-dead-code`
  instead of `python3`. Pin the tool like the other lint tools: add
  `CLAW_SWIFT_DEAD_CODE_REVISION=<commit>` to `BuildTools/lint-versions.env` and build it in
  `BuildTools/Package.swift`, as SwiftFormat is built today, so contributors need no global
  install.
- `.github/workflows/dead-code.yml`: keep the schedule, triggers, permissions and the Periphery
  install step. Replace "Scan with and without tests" by
  `swift-dead-code scan --output "$RUNNER_TEMP/scan"`, the baseline step's command by
  `swift-dead-code baseline "$scan/all.json" "$scan/prod.json"`, and the imports step's command
  by `swift-dead-code prune-imports --work "$work" --all --modules deps --strict` (the `--strict`
  exit replaces the `-s prune.patch` test). Change the `pull_request.paths` filter from the
  skill's scripts to `.deadcode.yml`. [`examples/github-workflow.yml`](../examples/github-workflow.yml)
  is the whole file.
- `.github/workflows/lint.yml`: drop `python3` from the container packages once no Python
  script remains, drop `scripts/test-periphery-baseline.sh` from ShellCheck and its run step,
  and drop `periphery_scan.sh` from ShellCheck.
- `BuildTools/lint-versions.env`: keep `CLAW_PERIPHERY_VERSION` and its checksum for the CI
  install; `CLAW_RUFF_VERSION` and `.ruff.toml` can go when the last Python script does.
- `docs/ARCHITECTURE.md` §19.2, `docs/LOCAL_DEV.md` ("Weekly dead-code analysis"),
  `docs/CODE_STYLE.md` (Python section): replace the script names with the subcommands, and
  say that `.deadcode.yml` holds the allowlist.

## 3. What stays

- `BuildTools/periphery-baseline.txt` and its entries: `baseline --write` produces the same 91
  entries today; only its `#` header changes on the next write.
- The rules: product code first, test code never fails CI, no `periphery:ignore` in product
  code, allowlist entries with reasons, heavy builds one at a time.
- The research report in `docs/research/`, which stays evidence and never a mention.
- The weekly schedule and the pinned Periphery release.

## 4. Order

1. Add `.deadcode.yml` and run `swift-dead-code check`, `scan` and `baseline` next to the
   scripts; compare with `evals/swift-claw/parity.md`.
2. Switch `scripts/lint.sh` and the weekly workflow; run both once.
3. Replace the skill and delete the scripts, `.periphery.yml`, the allowlist file and their
   tests; update the docs.
