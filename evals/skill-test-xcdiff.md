# Skill test: a fresh agent audits xcdiff

A fresh general-purpose subagent got only the skill
([`skills/removing-dead-code/SKILL.md`](../skills/removing-dead-code/SKILL.md)), the path of a
release build of the CLI and the request "Find dead code in xcdiff. Just an audit for now —
don't change any code." It had not seen the tool before and was asked for the audit plus a log
of every place the skill or the CLI made it guess.

Project: a clone of bloomberg/xcdiff at `0a82777`, a SwiftPM package with a tools-version 5.0
manifest, an executable, two libraries other packages use, and Xcode projects as test
fixtures. The clone was unknown to every earlier step.

## What it did

About seven minutes, the scan 45 seconds. It wrote `.deadcode.yml` (`--retain-public`,
`module_names` for the `SwiftToolsSupport-auto` umbrella product, five contract documents),
left it uncommitted and changed nothing else; the scan built in its scratch copy. It ran
`describe`, `check --report`, `scan` and `baseline`, gave each finding a verdict with
evidence (`git log -S` led it to the commits that removed the last callers), and suggested
the allowlist entry for `.codecov.yml` instead of writing it. Its audit is not part of this
eval; its friction log is.

## What it tripped over, and what changed

| Friction | Change (commit `7e183ea`) |
| --- | --- |
| "fill in what it marks, and commit it": `init` marks nothing, and committing contradicts an audit's "no edits" | The skill lists what to fill in and says an audit leaves `.deadcode.yml` uncommitted |
| `init`'s header says "see the README" without saying which | It names the tool's README |
| `describe` showed `PathKit`, `XcodeProj` and `SwiftToolsSupport-auto` as targets, "external modules: none", and the executable as a library | A by-name dependency that is not a target of the package is a product of a dependency now, its modules external; a regular target that an executable product names is an executable. Without this, `prune-imports --modules deps` had nothing to prune in such a package |
| The audit asks to mark findings "the baseline check calls new", but lists no `baseline` run, and a missing baseline file passed silently | The skill names the `baseline` run and says that without a file every finding is new; the CLI says so too |
| "used only by flagged printUsage" on `printUsage()`, whose only "user" was its own call to another type's `printUsage(on:)` | Uses inside the declaration itself no longer count |
| "may witness a requirement of: XCTestCase" on a private helper | Private members get no witness note |
| A redundant protocol's conformances looked like duplicate rows, and one conformance (Periphery's "replace with" suffix) had no note | The protocol's row and each conformance's row say which they are, and the suffix no longer hides the note; the skill's table has a row for them |
| No way to see whether `--retain-public` reached Periphery | `environment.txt` records both Periphery command lines |
| `.codecov.yml` reported as unused | A conventional file now |

Rescanning the same build after the change: `printUsage()` and `buildCommand(p1:p2:_:)` carry no
note, the protocol and conformance rows read as such, and `describe` lists `PathKit`,
`SwiftToolsSupport-auto` (with `TSCBasic`, `TSCUtility`) and `XcodeProj` as external modules and
`XCDiff` as an executable. The gate's output on every other eval project did not change.

What it found clear: building in a scratch copy, the rule for code only tests reach, and "no
grep hits is not evidence" (it caught a grep hit on a different method).
