# Changelog

Notable changes to swift-dead-code. Versions follow [Semantic Versioning](https://semver.org).

## 0.1.0 (unreleased)

The first public release.

- `check`: a gate that needs no build, for target dependencies no file imports and for files
  and asset catalog entries nothing names.
- `scan`: Periphery 3.8.0 with and without test code, confirmed build by build when targets share
  a module name, plus a triage report.
- `triage`, `baseline`, `prune-imports`, `describe` and `init`.
- SwiftPM packages, and Xcode projects and workspaces: XcodeGen and Tuist output, local
  packages, synchronized folders, xcconfig files and CocoaPods.
- The `removing-dead-code` agent skill.
