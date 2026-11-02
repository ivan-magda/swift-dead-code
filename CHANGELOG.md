# Changelog

Notable changes to swift-dead-code. Versions follow [Semantic Versioning](https://semver.org).

## Unreleased

- `scan` and `prune-imports` build a project that depends on a local package outside its root,
  such as `.package(path: "../Shared")` or an Xcode local package reference. The build used to
  stop with "the package at '…' cannot be accessed"; both commands now copy the package beside
  the project's copy. `scan` leaves such a package out of its results, as it does remote
  packages, unless the package contains the project.

## 0.1.1 (2026-11-02)

- Removed the command plugin this package built from source: it added swift-syntax, XcodeProj
  and Yams to the package graph of every package that used it.
  [swift-dead-code-plugin](https://github.com/ivan-magda/swift-dead-code-plugin) runs the release
  binary instead.
- The skill says how to install the CLI, and the README installs the skill with
  [`npx skills`](https://github.com/vercel-labs/skills).

## 0.1.0 (2026-11-02)

The first public release.

- `check`: a gate that needs no build, for target dependencies no file imports and for files
  and asset catalog entries nothing names.
- `scan`: Periphery 3.8.0 with and without test code, confirmed build by build when targets share
  a module name, plus a triage report.
- `triage`, `baseline`, `prune-imports`, `describe` and `init`.
- SwiftPM packages, and Xcode projects and workspaces: XcodeGen and Tuist output, local
  packages, synchronized folders, xcconfig files and CocoaPods.
- The `removing-dead-code` agent skill.
