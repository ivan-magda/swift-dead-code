# Contributing

Issues and pull requests are welcome. For anything larger than a fix, open an issue first.

## Setup

- macOS 14 or later, and Xcode with the Swift version `Package.swift` declares.
- Periphery 3.8.0 and XcodeGen for the whole test suite: the tests that need them are skipped
  without them.
- SwiftLint at the version in `BuildTools/lint-versions.env`, for `scripts/lint.sh`.

## Before a pull request

- `swift build` and `swift test` pass.
- `STRICT=1 scripts/lint.sh` passes; `scripts/lint.sh --fix` applies the formatting.
- `swift run swift-dead-code check` passes: the repository checks itself.
- A bug fix comes with a test that fails without it.
- When a check's rules, the configuration or the CLI's output change, the README,
  `docs/DESIGN.md` and the skill in `skills/removing-dead-code/` change with them.

[`AGENTS.md`](AGENTS.md) has the architecture in short, for people and coding agents alike.
