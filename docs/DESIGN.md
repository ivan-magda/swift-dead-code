# swift-dead-code: design

Status: implemented. Sections 14–17 record what reviews and evals changed, and why.

## 1. Purpose

`swift-dead-code` is a deterministic command-line tool that finds dead code in SwiftPM
packages and Xcode projects and proposes its removal as a patch. It orchestrates the
compiler, the project's build system and Periphery; it does not reimplement them. A thin
agent skill (`skills/removing-dead-code/`) covers what a tool cannot decide: the verdict on
Periphery findings (seam, contract, AMBIGUOUS), the independent researcher, and the
completeness sweep before a pull request.

The tool replaces five swift-claw scripts with one Swift package, and moves everything
swift-claw hard-codes into a per-project configuration file, `.deadcode.yml`.

| swift-claw script | Subcommand |
| --- | --- |
| `scripts/check-dead-code.py` | `swift-dead-code check` |
| `periphery_scan.sh` | `swift-dead-code scan` |
| `triage.py` | `swift-dead-code triage` (also run by `scan`) |
| `prune_imports.py` | `swift-dead-code prune-imports` |
| `scripts/check-periphery-baseline.py` | `swift-dead-code baseline` |

Two new subcommands support adoption: `describe` prints the project model the tool sees
(targets, test code, dependencies, files), and `init` prints a starter configuration.

Non-goals, from the brief: rewriting Periphery or indexing ourselves, merging deletions
automatically, Objective-C-only code and non-Swift KMP code, runtime telemetry.

## 2. Evidence from swift-claw

### 2.1 Decisions that swift-claw verified, and how

| Decision | Evidence |
| --- | --- |
| A build-free gate for target dependencies and unreferenced files belongs in lint | `511a9108`: 0.6 s per run; 12 gate mutants killed by `test-lint.sh`; first finding (`ClawdCompositionTests` → `ServiceLifecycle`) was real |
| `swift package dump-package` for the manifest, not `describe` | dump-package evaluates without resolving (about 1.4 s); describe resolves the graph |
| Untracked Swift files count for imports, only tracked files count as files | SwiftPM compiles untracked files; the `.build/` that dump-package creates was flagged in the gate fixture until files became tracked-only |
| Stem of four or more characters as the mention term | Code that builds resource names from parts keeps the file alive; shorter stems match unrelated text |
| The checker and allowlist do not count as mentions; dated research does not either | Code review of #257: the checker's own text kept files alive |
| Allowlist entries need a reason, and stale or duplicate entries fail | Review of #257; the gate test asserts each message |
| Periphery 3.8.0, scanned twice: with tests, and without tests and test support | `d1a8e6b9`: 268 findings with tests, 428 without; the prod-only scan isolates declarations only tests reach (Knip's production mode) |
| Own index store, own scratch path, dependency checkouts excluded | Plain `periphery scan` fails with "index store path does not exist"; without the exclusion 3.8.0 reported 7,738 findings and dropped witnesses of dependency protocols |
| JSON output, `--quiet`, `PERIPHERY_API_BASE_URL` to a closed port | 3.8.0 CSV leaves the comma in `@available(*, unavailable)` unquoted; the plan suggester sends the line count to api.periphery.pro and prints a banner to stdout |
| Retain Codable, Equatable and Hashable properties | `13e2df08`: the with-tests scan fell from 268 to 42 findings |
| `--disable-redundant-public-analysis` on the scan without tests | 112 of 200 prod findings were redundant-public notes caused only by leaving the tests out |
| Baseline keyed by USR, product code only, test code listed but never failing | `13e2df08`: USRs survive line moves; 8 baseline-gate mutants killed |
| No `periphery:ignore` comments in product code | `13e2df08`: comments moved to the baseline; Periphery's superfluous-ignore check then reports any new comment |
| Import pruning by the compiler, one module at a time | Mass removal took hours of retries; per-module passes attribute each new error to one module |
| MemberImportVisibility strict check after pruning | Of 17 imports a review removed, 10 were borrowed from sibling files; "missing import of defining module 'X'" names them |
| Strict checks per target, native build system, `-continue-building-after-errors` | `swift build` stops at the first failing target; the default backend cancels remaining compile batches, so its error set was non-deterministic; two native runs were identical |
| Product code before test code in the pruner | 2026-10-14: a run with tests kept all 103 Logging imports; a product-only run removed 3 |
| Foundation, OS modules and Crypto are never pruned automatically | A macOS-only prune removed an import Linux needed |
| Heavy builds one at a time, machine-wide lock | Evaluation runs with parallel builds took over 60 minutes; two at once finish later than the same two in sequence |
| Researcher brief with "left behind?" and "still needed?" parts | Baseline skill runs never asked what a deletion leaves behind; GREEN runs did |
| Test-only rule: a declaration a test calls is KEEP unless only its own tests call it | A GREEN run over-deleted a seam; early sweeps kept 11 protocol operations because test doubles "buy" them |

### 2.2 What is specific to swift-claw

- Test code is `Tests/**` and `Sources/ClawTestSupport/**`: becomes test targets from the
  project model plus `test_support` in the configuration.
- Paths `BuildTools/dead-code-allowlist.txt`, `BuildTools/periphery-baseline.txt`,
  `docs/research/`, the checker's own path: become configuration fields.
- Conventional files (`.github/`, `.agents/`, `.claude/`, `AGENTS.md`...): become a default
  list that a project extends.
- The Periphery version pin in `BuildTools/lint-versions.env`: becomes `periphery.version`.
- `--modules deps` means the `Package.swift` products plus Testing and Synchronization:
  becomes the dependency modules of the adapter (SwiftPM products, Xcode package products,
  CocoaPods modules) plus `prune.toolchain_modules`.
- The triage notes check `Sources/` and `Tests/` prefixes: become "product code" and "test
  code" from the project model.
- Documents such as `docs/ARCHITECTURE.md` and `TESTING.md` named in the skill: become
  `docs.contracts` in the configuration, or the project's `AGENTS.md`/`CLAUDE.md`.

### 2.3 Pitfalls the tool must encode

1. A plain `periphery scan` fails without an index store; the Swift Build backend writes it
   to `<scratch>/out`, the native one to `<scratch>/debug/index/store`.
2. Periphery 3 scans every unit in the index store, dependency checkouts included.
3. Periphery's CSV is not CSV; its stdout can carry a plan banner.
4. Periphery's unused-import report covers only indexed modules: never package
   dependencies, Testing or Synchronization.
5. A file that compiles without an import can still need it: it borrows the module from a
   sibling file. Only MemberImportVisibility proves otherwise.
6. Build output carries ANSI escapes; errors must be parsed after stripping them.
7. `swift build --target` and `--build-tests` are mutually exclusive.
8. A strict manifest suffix is lost if `Package.swift` is among the rewritten files.
9. A patch built from lines without their endings gains a phantom trailing line.
10. A failing test file during pruning keeps a module everywhere; product code first.
11. A scan or prune is valid only for the platforms and configurations that were built;
    `#if os(Linux)` code is invisible to a macOS scan.
12. Swift 6.4 credits glibc declarations to CDispatch or CoreFoundation on Linux, so
    MemberImportVisibility stays macOS-only there.
13. Misleading compiler errors exist (a missing `import ClawAgent` surfaced as "'let' binding
    pattern cannot appear in an expression"): any error in a file keeps its trial imports.
14. Old Periphery from the abandoned tap (2.21.2) misreports parameterized tests; uninstall
    order matters (`brew untap` first).
15. Protocol requirements nobody calls through the protocol are often deliberate contracts;
    deleting the requirement moves weight rather than removing it.
16. CaseIterable cases, synthesized `==`, `deinit` side effects of stored "leases" and
    `@Test(arguments:)` labels were all reported as unused and were all alive.

## 3. Periphery as a library: rejected

Periphery 3.8.0 exports one library product, `PeripheryKit`; the scan orchestration
(`ScanCommand`, the project drivers' wiring) lives in the `Frontend` executable target and
cannot be imported. Its manifest pins `swift-index-store` to a revision of a fork
(`ileitch/swift-index-store`), so any package depending on Periphery must also use
revision-based requirements and cannot be consumed by version. It requires
`swift-syntax` `from: "603.0.0"`, which SwiftPM reads as `603.0.0..<604.0.0`; our package
needs 604 to match the Swift 6.4 parser, and the archived repository will never move. The
repository was archived on 2026-08-12, so a compiler change that breaks indexing (as the
Xcode 27 `$projectedValue` regression did) cannot be fixed upstream.

The binary has the same archival risk, but it is replaceable without rebuilding this tool:
a fork, a Homebrew bottle or Periphery Pro with the same JSON format drops in. The tool
therefore runs `periphery` as a process, pins its version in configuration, and reads its
JSON. Rollback: a `PeripheryRunner` protocol isolates the process boundary, so a library
backend could be added behind it.

## 4. Package layout

```
Package.swift                 swift-tools-version 6.2, Swift 6 language mode, macOS 14
Sources/
  DeadCodeKit/                the library: everything testable
    Configuration/            .deadcode.yml model, loading, validation, defaults
    Project/                  ProjectModel, SwiftPM and Xcode adapters, detection
    Syntax/                   SwiftSyntax: imports, declarations, attributes, strings
    Gate/                     check: dependencies, files, assets, allowlist
    Periphery/                runner, JSON model, scan plan, baseline
    Triage/                   notes and report.md
    Prune/                    workspace copy, build loop, strict check, patch
    Support/                  process runner, git, paths, file lock, output
  swift-dead-code/            ArgumentParser commands, exit codes
Tests/DeadCodeKitTests/       Swift Testing, unit and fixture tests
Tests/Fixtures/               fixture projects (SwiftPM packages, an Xcode project)
skills/removing-dead-code/    the agent skill
evals/                        per-project configurations, labels and results
examples/                     .deadcode.yml samples, github-workflow.yml
```

Dependencies, all by version: `swift-argument-parser` 1.x, `swift-syntax` 604.x
(`SwiftSyntax`, `SwiftParser`), `XcodeProj` 9.x (`.xcodeproj`, `.xcworkspace`,
`Pods.xcodeproj`), `Yams` 6.x (configuration). No other runtime dependency.

Concurrency: the library is synchronous where it shells out (builds are sequential by
design), and every model type is `Sendable`. Swift 6 language mode with complete checking.

## 5. Project model and adapters

`ProjectModel` is the only input the checks see:

```swift
struct ProjectModel: Sendable {
  var kind: ProjectKind            // .swiftPackage, .xcode(XcodeContainer)
  var root: AbsolutePath           // the repository or package root
  var targets: [ProjectTarget]
  var externalModules: [ExternalModule]   // package products, pods: what `deps` means
}
struct ProjectTarget: Sendable {
  var name: String
  var moduleName: String
  var role: TargetRole             // product, test, testSupport
  var productType: ProductType     // library, executable, app, appExtension, framework,
                                   // unitTest, uiTest, macro, plugin, other
  var sourceFiles: [RelativePath]  // compiled Swift files
  var directories: [RelativePath]  // owning directories (SwiftPM path, synchronized groups)
  var dependencies: [TargetDependency]   // name, accepted module names, kind
}
```

`role` is `test` for SwiftPM `testTarget`s and Xcode `*.xctest` product types (unit and UI
tests), `testSupport` for targets named in `test_support`, otherwise `product`. Test code is
the files of `test` and `testSupport` targets plus `test_support` globs.

Detection, unless `project.kind` is set: a `Package.swift` at the root without an
`.xcodeproj`/`.xcworkspace` beside it is SwiftPM; otherwise the single `.xcworkspace`, or the
single `.xcodeproj`, is Xcode. An `.xcworkspace` wins over its `.xcodeproj` (CocoaPods). With
several candidates the tool stops and asks for `project.path`. A `project.yml` (XcodeGen) or
`Project.swift` (Tuist) without a generated project stops with "run `xcodegen generate` (or
`tuist generate`) first": the tool never writes into the working tree, and generators do.

### 5.1 SwiftPM adapter

- Manifest: `swift package dump-package` (no resolution), with one temporary directory as both
  `--scratch-path` and `TMPDIR`, removed afterwards, since SwiftPM keeps a lock file for each
  scratch path in `TMPDIR`. Target directory: `path`, or the
  first existing default root (`Sources`, `Source`, `src`, `srcs`; tests also look in
  `Tests`; plugins in `Plugins`), as swift-claw's gate did.
- Source files: Swift files under the target directory, tracked or untracked-but-not-ignored
  (`git ls-files --cached --others --exclude-standard`), minus the target's `exclude` and
  `resources` paths: SwiftPM compiles nothing inside a resource.
- Dependencies: `byName`, `target`, `product` entries; a product accepts its name, its
  module aliases and the names configured in `module_names`. A target's module name is its
  name as an identifier (`My-Core` → `My_Core`), as SwiftPM spells it.
- External modules (`deps`): every product dependency of every target.
- Build for scan: `swift build --build-tests --scratch-path W/build`; index store at
  `W/build/out` (Swift Build) or `W/build/debug/index/store` (native), whichever exists.
- Strict check of one target: the copy's `Package.swift` and every `Package@swift-*.swift`
  (SwiftPM may read one of those instead) get the MemberImportVisibility suffix for that
  target, as `unsafeFlags`, which PackageDescription before 5.8 accepts too;
  `swift build --build-system native --target T --scratch-path W/build-native
  -Xswiftc -continue-building-after-errors`.

### 5.2 Xcode adapter (`.xcodeproj`, `.xcworkspace`)

- Parsing with XcodeProj. A workspace contributes every project it references; a project
  named `Pods.xcodeproj`, or under `Pods/`, is CocoaPods: its native targets other than the
  `Pods-*` aggregates become external modules (module name from `PRODUCT_MODULE_NAME`, then
  `PRODUCT_NAME`, then the target name), never project targets.
- Local Swift packages referenced by a project (`XCLocalSwiftPackageReference`, or a folder
  with `Package.swift` in the workspace) are loaded with the SwiftPM adapter and merged: their
  targets are project code, their test targets test code.
- Target sources: the Sources build phase file references, resolved against the source root,
  plus every Swift file under `PBXFileSystemSynchronizedRootGroup` folders minus membership
  exceptions (Xcode 16+ projects).
- Module name: `PRODUCT_MODULE_NAME`, else `PRODUCT_NAME` when it is not a variable, else the
  target name, with characters outside `[A-Za-z0-9_]` replaced by `_`. A dependency on a
  target gets the module name from the same setting layers, project ones included.
- The file `SWIFT_OBJC_BRIDGING_HEADER` names counts among the target's other sources, so the
  modules it imports count as used by the target.
- Dependencies: target dependencies whose product is a framework or library (apps, app
  extensions, watch apps and bundles are embedded, not imported), plus
  `packageProductDependencies` by product name. CocoaPods dependencies are not checked by
  the gate (the Podfile is Ruby); their modules feed `deps` for the pruner.
- Build for scan, per configured scheme: `xcodebuild build-for-testing -workspace|-project P
  -scheme S -configuration C -destination D -derivedDataPath W/DerivedData
  CODE_SIGNING_ALLOWED=NO`; index store at `W/DerivedData/Index.noindex/DataStore`.
  Periphery then runs with `--project P --schemes S... --skip-build --index-store-path ...`,
  so it also reads storyboards, XIBs, Info.plists and Core Data models.
- Excluded from the index: `W/DerivedData/SourcePackages/checkouts/**`, `Pods/**`,
  `Carthage/**` and configured `exclude` globs.
- Strict check: the copy's `project.pbxproj` gets
  `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES` on the checked target's build
  configurations (XcodeProj writes it), and one `xcodebuild build` of the scheme with that
  copy. An error in another target means "not checked", as in swift-claw, and the run fails.
- A scheme builds only its own targets and their dependencies. Each build's target dependency
  graph, which xcodebuild prints before it builds, tells the pruner which targets it covered;
  files of other targets are skipped and listed.

XcodeGen and Tuist projects use the generated `.xcodeproj`. Reading their manifests is not
needed for any check, so it is left out until a candidate needs it (brief: add abstraction
only where a candidate needs it).

## 6. Configuration: `.deadcode.yml`

One YAML file at the repository root. Unknown keys are errors, so typos do not silently
fall back to defaults. Every field is optional; `swift-dead-code init` prints a commented
starter with the detected values.

```yaml
project:
  kind: auto                    # auto | swiftpm | xcode
  path: App.xcworkspace         # xcode: the workspace or project; default: detected
  schemes: [App]                # xcode: schemes to build and scan; default: all shared
  configuration: Debug          # xcode build configuration
  destination: "generic/platform=iOS Simulator"
  build_arguments: []           # extra arguments for swift build / xcodebuild

test_support: [AppTestSupport]  # targets or path globs that count as test code
exclude: ["Generated/**"]       # paths no check reports on (generated, vendored code)
module_names:                   # product or pod name -> modules it provides
  SwiftProtobuf: [SwiftProtobuf]

check:
  conventional_paths: [".github/", ".agents/", ".claude/"]   # added to the defaults
  conventional_files: ["Brewfile"]                           # added to the defaults
  not_references: ["docs/research/"]   # files whose mentions keep nothing alive
  min_stem_length: 4
  assets: true                  # check asset catalog entries

allowlist:                      # every entry needs a reason; stale entries fail
  - file: docs/assets/demo.png
    reason: linked from the website
  - dependency: App Kit         # "<target> <module>"
    reason: re-exported for clients
  - asset: Assets.xcassets/LaunchLogo.imageset
    reason: named in a remote config

periphery:
  version: 3.8.0                # required `periphery version`
  baseline: .deadcode/periphery-baseline.txt
  retain_codable_properties: true
  retain_equatable_properties: true
  retain_hashable_properties: true
  arguments: []                 # extra `periphery scan` options for both scans

prune:
  toolchain_modules: [Testing, Synchronization]   # tried by `--modules deps`
  platform_modules: []          # added to the never-pruned default list
  keep_modules: []              # never pruned (e.g. modules imported for side effects)

docs:
  contracts: [docs/ARCHITECTURE.md]   # where the project documents its contracts

builds:                         # optional: scan each and intersect the findings
  - name: ios
    destination: "generic/platform=iOS Simulator"
  - name: macos
    destination: "generic/platform=macOS"
```

Defaults: conventional files are swift-claw's list (`.editorconfig`, `.gitattributes`,
`.gitignore`, `.swift-format`, `.swift-version`, `.swiftlint.yml`, `.periphery.yml`,
`.deadcode.yml`, `AGENTS.md`, `CLAUDE.md`, `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`,
`LICENSE`, `Package.resolved`, `README.md`, `SECURITY.md`) plus Xcode and CocoaPods ones
(`Podfile`, `Podfile.lock`, `Gemfile`, `Gemfile.lock`, `Cartfile`, `Cartfile.resolved`,
`Mintfile`, `Brewfile`, `project.yml`, `Project.swift`, `Contents.json`, `*.xctestplan`,
`PrivacyInfo.xcprivacy`, `Info.plist`, `*.entitlements` named by a build setting).
Conventional paths: `.github/`, `.gitlab/`, `.circleci/`, `.agents/`, `.claude/`,
`fastlane/`, `.swiftpm/`. The default baseline path is `.deadcode/periphery-baseline.txt`.
Platform modules: swift-claw's list (Foundation family, Darwin, Glibc, Musl, WinSDK,
Android, Dispatch, os, System, SystemPackage, CoreFoundation, Crypto).

## 7. Subcommands

Global options: `--project-root DIR` (default: the current directory), `--config FILE`
(default `<root>/.deadcode.yml`; missing means all defaults). Exit codes: 0 clean, 1
findings or failed check, 2 usage or environment error (missing tool, wrong version,
unbuildable project).

### 7.1 `check`: the build-free gate

Finds, without building:

- `dependency <target> <module>`: a declared dependency no Swift file of the target imports.
  Imports are collected with SwiftSyntax across every `#if` branch, including `@_exported`,
  `@testable`, `@_spi`, access-level and scoped imports; `#externalMacro(module:)` counts as
  a use of that module.
- `file <path>`: a tracked file whose name, or stem of `min_stem_length` or more characters,
  no other tracked text file mentions. Swift files compiled by a target are skipped (Periphery
  covers their contents); a Swift file no target compiles is a candidate like any other file.
  Mentions in `.xcodeproj` membership lists, `.xcscheme` and `.xcworkspacedata` do not count;
  build settings (`INFOPLIST_FILE`, `CODE_SIGN_ENTITLEMENTS`...) and every other text file do.
- `asset <catalog>/<name>.<kind>`: an asset catalog entry (`imageset`, `colorset`,
  `symbolset`, `dataset`, `appiconset` excluded) whose name, or the identifier Xcode generates
  for it (`my-icon` → `myIcon`), no file outside asset catalogs mentions.

Output: compiler-style errors on stderr (`path:1:1: error: ...`), as swift-claw. `--report`
prints every finding, allowlisted ones marked, and exits 0. `--format json` prints the
findings as JSON for other tools. Stale, duplicate or reason-less allowlist entries fail.

### 7.2 `scan`: Periphery with its own index store

`swift-dead-code scan --output DIR [--skip-build]` builds into `DIR` (never the project's
`.build` or DerivedData), checks `periphery version` against `periphery.version`, and runs
Periphery twice per build variant:

- `all`: tests included.
- `prod`: `--exclude-tests`, `--index-exclude` for test support, and
  `--disable-redundant-public-analysis`.

Both use `--skip-build --index-store-path ... --format json --relative-results --quiet
--disable-update-check`, the dependency exclusions, the retain options, and
`PERIPHERY_API_BASE_URL=http://127.0.0.1:9/v1`. With several `builds`, each variant scans
into `DIR/<name>/` and `DIR/all.json` and `DIR/prod.json` hold the intersection by USR.
Then `scan` runs `triage` into `DIR/report.md`. A previous `report.md` is removed first.

### 7.3 `triage`

`swift-dead-code triage ALL.json PROD.json [--output report.md]`: the swift-claw report
(sections and counts unchanged), with notes computed from SwiftSyntax instead of regular
expressions. Notes kept from swift-claw: parameterized `@Test` argument, CaseIterable case,
Encodable field, Equatable/Hashable field, protocol requirement, possible witness of the
enclosing type's conformances, signature-fixed parameter, test seam (product code only),
"used only by flagged X". New notes:

- `@IBAction`, `@IBOutlet`, `@IBInspectable`, `@IBDesignable`: check storyboards and XIBs;
- `@objc`, `dynamic`, `@NSManaged`: reachable from Objective-C, selectors, KVO;
- the name appears in a string literal or a plist, storyboard or XIB: runtime lookup
  (`NSClassFromString`, `NSExtensionPrincipalClass`, nib names);
- `@main` and app/scene delegates: entry points;
- SwiftUI previews (`#Preview`, `PreviewProvider`): design-time only;
- App Intents, widgets and extension principal types (`AppIntent`, `AppEntity`,
  `AppShortcutsProvider`, `Widget`, `WidgetBundle`, `TimelineProvider`): found by the system;
- property wrappers read through `$name`: Xcode 27 indexes the projected value separately;
- `CodingKeys` cases: used by synthesized Codable;
- an assign-only property whose value has a lifetime role (cancellables, observation tokens,
  tasks): the `deinit` may be the point.

### 7.4 `baseline`

`swift-dead-code baseline [--write] SCAN.json...`: the swift-claw gate with the baseline
path from configuration and test code from the project model. Fails on product-code findings
whose USRs the baseline lacks; lists test-code findings and stale entries without failing.
`--write` rewrites the baseline with the product findings, sorted, with the same header.

### 7.5 `prune-imports`

`swift-dead-code prune-imports --work DIR [--check-only] [--modules A,B|deps]
[--include-platform] [--include-tests] (--base REF | --all | FILE...)`: swift-claw's pruner,
generalized to the build adapter. It copies the project (tracked and unignored untracked
files) into `DIR/copy`, removes top-level imports one module at a time, builds, restores
imports in files with errors, then restores borrowed imports with a strict check per affected
target, and writes `DIR/prune.patch`. The working tree is never touched. Candidates are plain
top-level imports (`@testable`, `@preconcurrency`, `@_spi` allowed) outside `#if`, without
access modifiers, `@_exported`, scoped or submodule paths or a trailing comment. A
machine-wide lock serializes runs.

### 7.6 `describe` and `init`

`describe` prints the project model and effective configuration (targets, roles, module
names, dependencies, file counts, external modules); `--format json` for tools. `init`
prints a starter `.deadcode.yml` with detected values; it never writes the file.

## 8. Determinism

Same input and configuration give byte-identical output: every list is sorted by path, then
line, then name; no timestamps, absolute paths or durations in reports (durations go to
stderr). Tests assert it: two runs, and shuffled inputs, produce identical output. Periphery
and compiler versions are part of the input, so the scan checks the Periphery version and
records the toolchain in `DIR/environment.txt`.

## 9. Working-tree safety

`check`, `triage`, `baseline` (without `--write`), `describe` and `init` only read. `scan`
and `prune-imports` write only under their `--output`/`--work` directory. They build in a copy
there (`source/`, `copy/`), together with the local packages outside the project that the build
needs: `.package(path:)` dependencies and Xcode local package references that leave the root,
followed through the packages they reach. Each package keeps its place relative to the
project's copy, so `../Shared` resolves in the copy as in the project. A package two levels up
puts the project's copy two levels down (`source/Apps/App` beside `source/Libs/Shared`); a
package that contains the project adds one level more, because SwiftPM takes a local package's
identity from its directory name. Only `scan` and `prune-imports` read those packages'
manifests, so `check` evaluates none outside the project. `baseline --write` writes only the
configured baseline file. Tests verify that a fixture's `git status` is unchanged after each
read-only command.

## 10. Evals policy

`evals/<project>/` holds, per candidate:

- `deadcode.yml`: the configuration used (copied into the clone, never into the original);
- `labels.md`: every finding with a verdict (TRUE dead, FALSE positive, AMBIGUOUS, KEEP) and
  its evidence, and for false positives whether triage flags them;
- `verification.md`: commands and results of applying the TRUE group in the clone, building
  and testing, and the researcher's report;
- `summary.json`: counts per subcommand.

Projects run in `git clone --local` copies in a scratch directory, never in the original
checkouts; nothing is committed or pushed there. A deletion counts as verified only
after the clone builds and its tests pass with the deletion applied and a fresh read-only
researcher found no use. A candidate that does not build in 30 minutes is struck out with the
reason.

## 11. Tests and lint

Swift Testing. Unit tests cover parsing (configuration, Periphery JSON, imports, pbxproj
models through fixtures). Fixture tests run each subcommand on fixture projects in a
temporary copy: a SwiftPM package with planted dead code, and a small Xcode project generated
once with XcodeGen and committed. Tests that need `periphery` or `xcodebuild` are enabled only
when the tool is installed. Lint: `scripts/lint.sh` runs Apple swift-format (`.swift-format`
from swift-claw) and SwiftLint (`.swiftlint.yml` modeled on swift-claw) with the versions in
`BuildTools/lint-versions.env`.

## 12. Distribution

- Releases: a version tag runs `.github/workflows/release.yml`, which builds a universal binary
  with `scripts/release.sh` and publishes it as a zip and as a SwiftPM artifact bundle, with
  their SHA-256 and a build provenance attestation.
- Homebrew: the `ivan-magda/homebrew-tap` formula installs the zip; the release workflow
  updates it.
- Mint: `mint install ivan-magda/swift-dead-code` builds the `swift-dead-code` executable.
- SwiftPM command plugin: `ivan-magda/swift-dead-code-plugin` runs the artifact bundle, with
  Periphery's own artifact bundle first on the PATH, so it adds nothing to the package graph;
  the release workflow updates its checksum and tags it. `swift package --disable-sandbox
  dead-code check`: the sandbox must be off because the tool runs `swift`, `git` and
  `periphery`.

## 13. Known limits

- Results are valid only for the built platforms and configurations; use `builds` to scan
  several, and a declaration any of them uses stays (§14.3). Targets that share a module name
  merge in that shared index (§15.3).
- KMP and other non-Swift sources are invisible to Periphery and to the import checks; the
  tool reports which targets have non-Swift sources and limits itself to Swift.
- CocoaPods dependency declarations (Ruby) are not checked by the gate.
- XcodeGen and Tuist manifests are not read; generate the project first.
- `scan` keeps local packages outside the project out of the index, as it does remote
  checkouts, except a package that contains the project (an example app's library, reached by
  `../..`): that one stays in the index, and its declarations appear in the results with paths
  outside the project.

## 14. Changes after the independent review (2026-10-30)

A fresh read-only reviewer checked this design against the brief, the swift-claw scripts,
the Periphery 3.8.0 source and the candidate clones. Each accepted point was confirmed by
opening the cited code; the changes below override the sections above.

1. **Local packages** (§5.2): besides `XCLocalSwiftPackageReference`, a project may add a
   local package as a `wrapper` file reference (IceCubes) or keep packages in a synchronized
   folder no target owns (NetNewsWire `Modules/`). Every directory with a `Package.swift`
   reached through either is loaded with the SwiftPM adapter. Product dependencies without a
   package reference are resolved by product name.
2. **Synchronized folders** (§5.2): a target's files are its own folders minus its own
   exception sets, plus the files named by exception sets of other folders that name the
   target (that is how an extension takes files from the app's folder).
3. **Builds** (§6, §7.2): each `builds` entry has its own `schemes`, `configuration` and
   `destination`. Instead of intersecting findings by USR, which drops every finding in code
   only one build compiles, one Periphery run reads every build's index store
   (`--index-store-path` repeats): a declaration any build uses is used. Xcode projects must
   name their schemes; no configuration is passed unless set, so each scheme uses its own.
4. **Working tree** (§9): `scan` and `prune-imports` build in a copy of the working tree
   (`<work>/source`, rsync of every file except `.git`, `.build` and `DerivedData`, ignored
   files included, because Xcode builds need ignored xcconfigs, `Pods/` and generated
   projects). Every SwiftPM call outside the copy passes `--scratch-path` in a temporary
   directory (`dump-package` otherwise creates `.build/` in the project). Periphery gets
   `--json-package-manifest-path` and `--skip-schemes-validation`. Tests compare
   `git status --porcelain --ignored` before and after each command.
5. **Mentions** (§7.1): `.deadcode.yml` and the baseline are never candidates and never
   mentions. `check.not_references` paths are neither candidates nor mentions (swift-claw's
   `docs/research/` semantics). Swift files under a nested package or project directory belong
   to that project and are never "uncompiled" candidates.
6. **xcconfig** (§5.2): module names and settings follow the xcconfig chain (target settings,
   target xcconfig with includes, project settings, project xcconfig), read with XcodeProj's
   `XCConfig`.
7. **Periphery invocation** (§7.2): the tool writes its own Periphery configuration and passes
   `--config`, so a project's `.periphery.yml` (which could set `strict` or `retain_public`)
   is ignored with a warning; its options move to `periphery.arguments`. Test code is excluded
   by path (`--index-exclude` for the smallest directories that hold only test code), not by
   `--exclude-tests`, which misses local-package test targets. `exclude` becomes
   `--report-exclude`, so excluded generated code still counts as a user. xcodebuild gets
   `COMPILER_INDEX_STORE_ENABLE=YES INDEX_ENABLE_DATA_STORE=YES`. Files generated into
   DerivedData are report-excluded.
8. **CocoaPods** (§5.2): a Pods target whose sources live outside `Pods/` (a development pod
   with `:path`) is project code. A `Podfile` without `Pods/` stops with "run `pod install`
   first".
9. **Xcode prune** (§7.5): every trial builds every configured build; a file compiled by
   several targets keeps its trial imports when any owner fails; the strict check sets
   `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY` on the copy's target configurations, or
   appends the SwiftPM suffix to a local package's manifest; `-continue-building-after-errors`
   goes into `OTHER_SWIFT_FLAGS`.
10. **Defaults** (§6): `.spi.yml`, `.pre-commit-config.yaml`, `InfoPlist.strings`,
    `Localizable.*`, `ci_scripts/`, nested `.swiftpm/` are conventional; an asset name also
    matches by its part before the first digit, `-` or `_`; allowlist `file` and `asset`
    subjects may be globs; a dependency entry can be `{target: ..., module: ...}`, and the
    scalar form splits at the last space because module names have none.
11. **Parity differences to report** (§2): `prune-imports` exits 0 like the script (CI reads
    the patch); `--strict` exits 1 on a non-empty patch. Assign-only counts depend on notes,
    which now come from SwiftSyntax. The test-seam name pattern becomes
    `triage.seam_name_pattern`. Uncompiled Swift files are new candidates.
12. **Skill** (§1): `skills/removing-dead-code/SKILL.md` keeps the swift-claw stages (ledger,
    triage, researcher brief, apply, completeness sweep, verify), names CLI commands instead of
    scripts, and speaks of project, target, test code, build configuration and contract
    documents. The base-commit comparison of the sweep uses `git worktree add` in the target
    repository only when the user owns it; otherwise a `git clone --local` of the base.
13. **Monorepos**: each subproject keeps its own `.deadcode.yml`; commands take
    `--project-root apps/ios`. Git commands already scope to that directory.
14. **Evals** (§10): each project records the cloned commit, a machine-checkable
    `expected.json` (finding → verdict), and the commands that reproduce it.
15. `retain_hashable_properties` defaults to false: Periphery's Equatable retention already
    covers Hashable types.

## 15. Changes from the evals (2026-10-31)

Each change below came from a false finding on a real project and needs no project-specific
knowledge.

1. **Gate mentions** (§7.1): Run Script phases' scripts and input and output paths count, as
   build settings do; a stem shorter than `min_stem_length` also counts as a whole string
   literal (`"atp"` for `atp.rss`); `$(VAR)` and `${VAR}` in a path match anything; `Pods/`
   and `Carthage/` at any depth, `*.docset/` contents and a few platform files
   (`container-migration.plist`, `GoogleService-Info.plist`) are conventional.
2. **Gate dependencies** (§7.1): a dependency `T → D` stays when a target that depends on `T`
   imports `D` without declaring it and reaches `D` through no other declaration; a framework
   a string literal names counts as used (`dlopen`).
3. **Same module name in two targets** (§7.2, §13): an iOS and a macOS app that are both module
   `NetNewsWire` merged in the shared index of a multi-build scan, and Periphery lost one
   copy's calls, differently from run to run; a live method was proposed for deletion. When
   targets share a module name and there are several builds, each build now gets its own
   DerivedData and index store. Periphery runs on all stores together, as before, and on each
   alone, and `all.json`/`prod.json` keep a combined finding only when some build reports it and
   every build whose index records hold its USR reports it too: a build that indexed the
   declaration and did not report it uses it, and a build that never compiled it (code under
   `#if os(macOS)` in an iOS build) has no say. Records are searched as bytes for the USRs.
   Triage still notes findings in a type a same-named module declares: a twin's own copy can
   share a USR, and a single build with both twins (an iOS and a watchOS framework in one
   scheme) has only one index.
4. **Builds** (§6): `builds[].for_testing: false` builds a scheme without its test targets
   (NetNewsWire's macOS tests compile AppleScript against an installed app).

## 16. Changes from the code review (2026-11-01)

A review by another model (Codex, `gpt-6-astra`) of the whole repository found these; each fix
has a test that failed before it.

1. **Dependencies** (§7.1): a dependency stays when removing it would cut a target that has it,
   directly or through others, off a module that target imports without declaring it. Each
   one is judged with the ones already reported removed, so two routes to one module no longer
   both look dead. The target's own bridging header counts as its source; SwiftPM module names
   are identifiers (`My-Core` → `My_Core`); a dependency's Xcode module name uses the project
   settings too.
2. **Conventional files** (§7.1): `module.modulemap` and Core Data model bundles
   (`.xcdatamodeld`, `.xcdatamodel`, `.xcmappingmodel`).
3. **Confirmation by builds** (§15.3): a build that reports only the declaration's redundant
   public access uses it, so it no longer confirms another finding; a build that reports the
   declaration unused still confirms a weaker one.
4. **Scan without tests**: a file that a product target compiles stays indexed even when a test
   target compiles it too, so its calls keep counting.
5. **Triage**: a redundant-public note with tests no longer hides a production declaration
   that only tests reach (Periphery ignores test callers when it judges public access).
6. **`prune-imports`** (§7.5): Xcode files of targets that no configured scheme builds are
   skipped; `--check-only` fails when it could not check a target; the configuration's
   `exclude` applies to `--base` and `--all`; `--base` reads git's paths with `-z`, so
   non-ASCII names survive; a scheme without a test action builds plainly, as in `scan`.

A second, final pass of the same review on 2026-11-01 found 15 more points; 13 are fixed, each
with a test that failed first:

7. **Working copy**: rsync copies what a link out of the project points at
   (`--copy-unsafe-links`), so writing into the copy never reaches another tree through it.
8. **SwiftPM**: a target's `resources` are not sources; `prune-imports` builds every configured
   build, as `scan` does.
9. **Gate dependencies**: a target dependency leads only to its own target, not to every twin of
   its module; a C-family file counts the imports of the headers it includes by a relative path.
10. **`prune-imports`**: a file that fails the strict check gets back every import removed from
    it, because the error names the defining module, which a removed import may only
    re-export; `--base` takes renamed files.
11. **Smaller fixes**: `--config ./.deadcode.yml` names the same file as `.deadcode.yml`; line
    counts of files with Windows line endings; one shared-scheme lookup (with a workspace's
    projects) for `init` and `scan`; the skill's base comparison names the files.
12. **Removed**: `Command.input` and `SourceIndex.text(of:)`, which nothing used.

Not fixed: files a multiplatform target compiles for only one platform (`platformFilter`) look
covered when only another platform is built, and two projects in one workspace with a target of
the same name share coverage; both need per-file platform or project-qualified target identity
throughout the model.

## 17. Changes from the review loop (2026-11-02)

The same review then ran as a loop: each round reviewed the previous round's fixes and was told
what was already decided and why, until a round left nothing to fix, at most three rounds.
Round 1 (the whole project, above all the unreviewed `32e46bd`) found 8 points, round 2 (its
fixes) 2, round 3 none. Each fix has a test that failed before it.

1. **`prune-imports` on Xcode** (§7.5): the pruner's own `OTHER_SWIFT_FLAGS` assignment repeats
   the configured one, because xcodebuild keeps only the last assignment of a setting; a
   build's `-D` flags no longer vanish from the prune builds.
2. **Strict check** (§5.1): every `Package@swift-*.swift` gets the suffix too, because SwiftPM
   may read one of those instead of `Package.swift`, and the suffix uses `unsafeFlags`, which
   PackageDescription before 5.8 accepts. Either case used to turn the check off silently.
3. **SwiftPM sources**: `sources: ["."]` is the target directory, not nothing.
4. **CRLF files**: `prune-imports` finds their imports (round 1) and its patch keeps their lines
   as they are (round 2, a bug the first fix exposed).

Not fixed: ignored generated sources are not part of the model (§2.1, §5.1); quoted includes
resolved through header search paths or header maps (a known limit); untracked files do not
count as mentions (README, "Files"); a target at the package root that also lists
`sources: ["."]`, which says "the whole directory" twice.
