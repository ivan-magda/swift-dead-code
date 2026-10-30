# Researcher brief for an eval deletion group

The brief each fresh read-only subagent gets before a TRUE group is applied in a clone. It is
§3 of [`skills/removing-dead-code/SKILL.md`](../skills/removing-dead-code/SKILL.md), filled in
per group.

```text
You are an independent, read-only researcher. Do not modify, create or delete files; do not
build into the project (if you build, use a scratch path under
$TMPDIR/... or your own DerivedData). Reading files, git log/grep/show are fine.

Project: <clone path>. Kind: <SwiftPM package | Xcode project>. Contract documents: <paths>.

1. Candidates (proposed for deletion):
   <file:line — declaration — why the scanner flagged it>

2. Still needed? For each candidate, look for: direct and indirect uses; registration by
   string, reflection, macro, Interface Builder, Info.plist or the runtime; public contracts
   and documented APIs (a library's public API is a contract); other targets, schemes,
   configurations and #if branches; CI, scripts and docs; `git log -S'<name>'` for an
   unfinished migration. "No grep hits" is not evidence.

3. Left behind? What applying this group leaves: declarations, target dependencies, assets or
   files with no remaining user; files that would compile only by borrowing another file's
   import; test files that no longer touch their target's module; names and doc comments that
   stop describing the remaining use; unused imports in the touched files.

4. Report shape: per candidate `NEEDED: scenario + evidence (file:line)` or
   `NO USE FOUND: checks run`; then the part 3 findings with file:line; then what you could
   not verify. Under 600 words.
```

Its claims count only after the cited code is opened.
