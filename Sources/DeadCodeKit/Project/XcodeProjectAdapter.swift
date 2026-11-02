import Foundation
import PathKit
import XcodeProj

/// Reads an Xcode workspace or project with XcodeProj: its native targets, their Swift
/// sources (build phases and synchronized folders), local Swift packages, package products
/// and CocoaPods modules.
public struct XcodeProjectAdapter: Sendable {
  let runner: any CommandRunning

  public init(runner: any CommandRunning = ProcessRunner()) {
    self.runner = runner
  }

  /// Loads the container at `containerPath`, relative to `root`.
  public func load(
    root: URL,
    containerPath: String,
    configuration: Configuration
  ) throws
    -> ProjectModel
  {
    let files = try Git(directory: root, runner: runner).trackedAndUntrackedFiles()
    var context = LoadContext(root: root, files: files, configuration: configuration)
    let containerURL = root.appendingPathComponent(containerPath)
    if containerPath.hasSuffix(".xcworkspace") {
      for reference in try Self.workspaceReferences(containerURL) {
        try load(reference: reference, context: &context)
      }
    } else {
      try loadProject(at: containerURL, context: &context)
    }
    try loadLocalPackages(context: &context)
    context.resolveCrossProjectDependencies()

    return ProjectModel(
      kind: .xcode(container: containerPath),
      root: root,
      targets: context.targets,
      externalModules: context.externalModules,
      buildSettingText: context.buildSettingLines.sorted().joined(separator: "\n"),
      membershipFiles: context.membershipFiles,
      localPackageDependencies: context.localPackages.union(context.packageDependencies)
    )
  }
}

/// What a load accumulates across the projects of a workspace.
private struct LoadContext {
  let root: URL
  let files: [String]
  let configuration: Configuration
  var targets: [ProjectTarget] = []
  var externalModules: Set<String> = []
  var buildSettingLines: Set<String> = []
  var membershipFiles: Set<String> = []
  /// Local package directories inside the root, relative to it: the load reads them.
  var localPackages: Set<String> = []
  /// Other local packages the projects and the loaded packages depend on, relative to the root:
  /// `../Shared` for one beside it.
  var packageDependencies: Set<String> = []
  /// Unresolved dependencies on targets of other projects, by depending target.
  var remoteTargetDependencies: [String: Set<String>] = [:]
  var loadedProjects: Set<String> = []

  init(root: URL, files: [String], configuration: Configuration) {
    self.root = root
    self.files = files
    self.configuration = configuration
  }

  func relative(_ url: URL) -> String? {
    TextFiles.relativePath(of: url, under: root)
  }

  /// Adds a local package: one inside the root is loaded with the project; one outside it is
  /// only remembered, since a build in a copy of the root needs it beside the copy.
  mutating func addLocalPackage(_ directory: URL) {
    if let path = relative(directory) {
      localPackages.insert(TextFiles.normalize(path))
    } else {
      packageDependencies.insert(
        TextFiles.relativePath(
          of: directory.standardizedFileURL.path,
          from: root.standardizedFileURL.path
        )
      )
    }
  }

  /// Adds a dependency on a target of another project once every project is loaded.
  mutating func resolveCrossProjectDependencies() {
    let byName = Dictionary(
      targets.map { ($0.name, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    for index in targets.indices {
      for name in remoteTargetDependencies[targets[index].name] ?? [] {
        guard let dependency = byName[name], dependency.isImportable else {
          continue
        }
        let declared = TargetDependency(
          name: name,
          moduleNames: [dependency.moduleName],
          kind: .target
        )
        if !targets[index].dependencies.contains(declared) {
          targets[index].dependencies.append(declared)
        }
      }
    }
  }
}

private extension ProjectTarget {
  /// Frameworks and libraries are imported; apps, extensions and bundles are embedded.
  var isImportable: Bool {
    productType == .framework || productType == .library
  }
}

// MARK: - Workspaces

private extension XcodeProjectAdapter {
  enum WorkspaceReference {
    case project(URL)
    case folder(URL)
  }

  static func workspaceReferences(_ workspace: URL) throws -> [WorkspaceReference] {
    let data = try XCWorkspace(path: Path(workspace.path)).data
    let base = workspace.deletingLastPathComponent()
    var references: [WorkspaceReference] = []
    collect(data.children, groupDirectory: base, containerDirectory: base, into: &references)
    return references
  }

  static func collect(
    _ elements: [XCWorkspaceDataElement],
    groupDirectory: URL,
    containerDirectory: URL,
    into references: inout [WorkspaceReference]
  ) {
    for element in elements {
      switch element {
      case .file(let file):
        guard
          let url = resolve(file.location, group: groupDirectory, container: containerDirectory)
        else {
          continue
        }
        references.append(url.pathExtension == "xcodeproj" ? .project(url) : .folder(url))
      case .group(let group), .fileSystemSynchronizedGroup(let group):
        let directory =
          resolve(group.location, group: groupDirectory, container: containerDirectory)
          ?? groupDirectory
        collect(
          group.children,
          groupDirectory: directory,
          containerDirectory: containerDirectory,
          into: &references
        )
      }
    }
  }

  static func resolve(
    _ location: XCWorkspaceDataElementLocationType,
    group: URL,
    container: URL
  ) -> URL? {
    switch location {
    case .absolute(let path):
      URL(fileURLWithPath: path)
    case .container(let path):
      container.appendingPathComponent(path)
    case .group(let path):
      group.appendingPathComponent(path)
    case .current, .developer, .other:
      nil
    }
  }

  func load(reference: WorkspaceReference, context: inout LoadContext) throws {
    switch reference {
    case .project(let url):
      try loadProject(at: url, context: &context)
    case .folder(let url):
      let manifest = url.appendingPathComponent("Package.swift")
      if FileManager.default.fileExists(atPath: manifest.path) {
        context.addLocalPackage(url)
      }
    }
  }
}

// MARK: - Projects

private extension XcodeProjectAdapter {
  func loadProject(at url: URL, context: inout LoadContext) throws {
    guard let projectPath = context.relative(url) else {
      return
    }
    guard context.loadedProjects.insert(projectPath).inserted else {
      return
    }
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw DeadCodeError.usage("\(projectPath) does not exist")
    }
    let project: XcodeProj
    do {
      project = try XcodeProj(path: Path(url.path))
    } catch {
      throw DeadCodeError.usage("cannot read \(projectPath): \(error)")
    }
    context.membershipFiles.insert(projectPath + "/project.pbxproj")
    let sourceRoot = url.deletingLastPathComponent()
    let pbxproj = project.pbxproj

    if url.lastPathComponent == "Pods.xcodeproj" {
      try loadPods(pbxproj, projectPath: projectPath, context: &context)
      return
    }

    try recordProjectWideFacts(pbxproj, sourceRoot: sourceRoot, context: &context)
    let manifestPath = projectPath + "/project.pbxproj"
    let synchronized = Self.synchronizedMembership(
      pbxproj,
      sourceRoot: sourceRoot,
      context: context
    )
    for target in pbxproj.nativeTargets {
      var loaded = try Self.target(
        target,
        sourceRoot: sourceRoot,
        project: pbxproj.rootObject,
        manifestPath: manifestPath,
        context: &context
      )
      Self.add(synchronized, of: target, to: &loaded)
      context.targets.append(loaded)
    }
  }

  /// Build settings that mention files, and the local packages the project references.
  func recordProjectWideFacts(
    _ pbxproj: PBXProj,
    sourceRoot: URL,
    context: inout LoadContext
  ) throws {
    for configuration in pbxproj.buildConfigurations {
      Self.recordBuildSettings(of: configuration, sourceRoot: sourceRoot, context: &context)
    }
    // Run Script phases name the scripts and files they use, as build settings do.
    for phase in pbxproj.shellScriptBuildPhases {
      let paths =
        phase.inputPaths + phase.outputPaths + (phase.inputFileListPaths ?? [])
        + (phase.outputFileListPaths ?? [])
      context.buildSettingLines.insert(([phase.shellScript ?? ""] + paths).joined(separator: "\n"))
    }
    for package in pbxproj.rootObject?.localPackages ?? [] {
      context.addLocalPackage(sourceRoot.appendingPathComponent(package.relativePath))
    }
    for reference in pbxproj.fileReferences {
      try Self.recordFolderPackage(reference, sourceRoot: sourceRoot, context: &context)
    }
    Self.recordSynchronizedPackages(pbxproj, sourceRoot: sourceRoot, context: &context)
  }

  static func add(
    _ synchronized: SynchronizedMembership,
    of target: PBXNativeTarget,
    to loaded: inout ProjectTarget
  ) {
    let members = synchronized.files[ObjectIdentifier(target)] ?? []
    loaded.sourceFiles = Array(Set(loaded.sourceFiles).union(members.filter(isSwift))).sorted()
    loaded.otherSourceFiles = Array(
      Set(loaded.otherSourceFiles).union(members.filter { !isSwift($0) })
    )
    .sorted()
    loaded.directories = Array(
      Set(loaded.directories).union(synchronized.directories[ObjectIdentifier(target)] ?? [])
    )
    .sorted()
  }

  struct SynchronizedMembership {
    /// Compiled files by target.
    var files: [ObjectIdentifier: Set<String>] = [:]
    /// Synchronized folders by target.
    var directories: [ObjectIdentifier: Set<String>] = [:]
  }

  /// The files that synchronized folders (Xcode 16) give each target.
  ///
  /// A folder belongs to the targets that list it. An exception set for one of those targets
  /// removes the files it names from that target; an exception set for any other target adds
  /// them to it, which is how an extension shares a few files of the app's folder.
  static func synchronizedMembership(
    _ pbxproj: PBXProj,
    sourceRoot: URL,
    context: LoadContext
  ) -> SynchronizedMembership {
    var owners: [ObjectIdentifier: [PBXNativeTarget]] = [:]
    for target in pbxproj.nativeTargets {
      for group in target.fileSystemSynchronizedGroups ?? [] {
        owners[ObjectIdentifier(group), default: []].append(target)
      }
    }
    var membership = SynchronizedMembership()
    let root = Path(sourceRoot.path)
    for group in pbxproj.fileSystemSynchronizedRootGroups {
      guard
        let path = try? group.fullPath(sourceRoot: root),
        let directory = context.relative(URL(fileURLWithPath: path.string))
      else {
        continue
      }
      let files = context.files.filter { $0.hasPrefix(directory + "/") && isSourceFile($0) }
      let groupOwners = owners[ObjectIdentifier(group)] ?? []
      var excluded: [ObjectIdentifier: Set<String>] = [:]
      for exceptions in group.exceptions ?? [] {
        guard
          let exceptions = exceptions as? PBXFileSystemSynchronizedBuildFileExceptionSet,
          let target = exceptions.target as? PBXNativeTarget
        else {
          continue
        }
        let named = Set((exceptions.membershipExceptions ?? []).map { directory + "/" + $0 })
        let selected = files.filter { file in
          named.contains(file) || named.contains { file.hasPrefix($0 + "/") }
        }
        if groupOwners.contains(where: { $0 === target }) {
          excluded[ObjectIdentifier(target), default: []].formUnion(selected)
        } else {
          membership.files[ObjectIdentifier(target), default: []].formUnion(selected)
        }
      }
      for target in groupOwners {
        let identifier = ObjectIdentifier(target)
        membership.directories[identifier, default: []].insert(directory)
        membership.files[identifier, default: []]
          .formUnion(Set(files).subtracting(excluded[identifier] ?? []))
      }
    }
    return membership
  }

  static func isSwift(_ path: String) -> Bool {
    path.hasSuffix(".swift")
  }

  static func recordBuildSettings(
    of configuration: XCBuildConfiguration,
    sourceRoot: URL,
    context: inout LoadContext
  ) {
    for (key, value) in configuration.buildSettings {
      context.buildSettingLines.insert("\(key) = \(value.description)")
    }
    let root = Path(sourceRoot.path)
    if let base = configuration.baseConfiguration,
      let path = try? base.fullPath(sourceRoot: root),
      let relative = context.relative(URL(fileURLWithPath: path.string))
    {
      context.buildSettingLines.insert("baseConfigurationReference = \(relative)")
    }
    // Xcode 16 anchors an xcconfig in a synchronized folder by a relative path.
    if let anchor = configuration.baseConfigurationAnchor,
      let relativePath = configuration.baseConfigurationReferenceRelativePath,
      let path = try? anchor.fullPath(sourceRoot: root),
      let relative = context.relative(URL(fileURLWithPath: path.string + "/" + relativePath))
    {
      context.buildSettingLines.insert("baseConfigurationReference = \(relative)")
    }
  }

  /// Packages kept in a synchronized folder, which no file reference names (NetNewsWire's
  /// `Modules/`).
  static func recordSynchronizedPackages(
    _ pbxproj: PBXProj,
    sourceRoot: URL,
    context: inout LoadContext
  ) {
    let root = Path(sourceRoot.path)
    for group in pbxproj.fileSystemSynchronizedRootGroups {
      guard
        let path = try? group.fullPath(sourceRoot: root),
        let directory = context.relative(URL(fileURLWithPath: path.string))
      else {
        continue
      }
      for file in context.files
      where file.hasPrefix(directory + "/") && file.hasSuffix("/Package.swift") {
        context.localPackages.insert((file as NSString).deletingLastPathComponent)
      }
    }
  }

  /// CocoaPods targets are external modules, except development pods (`:path`), whose
  /// sources live in the repository outside `Pods/`: those are project code.
  func loadPods(_ pbxproj: PBXProj, projectPath: String, context: inout LoadContext) throws {
    let podsDirectory = (projectPath as NSString).deletingLastPathComponent
    // `Pods-*` aggregates link the pods into an app; resource bundles are no modules.
    for target in pbxproj.nativeTargets
    where !target.name.hasPrefix("Pods-") && target.productType != .bundle {
      let loaded = try Self.target(
        target,
        sourceRoot: URL(fileURLWithPath: podsDirectory, relativeTo: context.root)
          .standardizedFileURL,
        project: pbxproj.rootObject,
        manifestPath: projectPath + "/project.pbxproj",
        context: &context
      )
      let local = (loaded.sourceFiles + loaded.otherSourceFiles).filter { path in
        !path.hasPrefix(podsDirectory + "/")
      }
      if local.isEmpty {
        context.externalModules.insert(loaded.moduleName)
      } else {
        context.targets.append(loaded)
      }
    }
  }

  /// Projects made before Xcode 15 add a local package as a folder reference.
  static func recordFolderPackage(
    _ reference: PBXFileReference,
    sourceRoot: URL,
    context: inout LoadContext
  ) throws {
    guard
      let path = try? reference.fullPath(sourceRoot: Path(sourceRoot.path)),
      FileManager.default.fileExists(atPath: path.string + "/Package.swift")
    else {
      return
    }
    context.addLocalPackage(URL(fileURLWithPath: path.string))
  }

  static func target(
    _ target: PBXNativeTarget,
    sourceRoot: URL,
    project: PBXProject?,
    manifestPath: String,
    context: inout LoadContext
  ) throws -> ProjectTarget {
    var sources: Set<String> = []
    let root = Path(sourceRoot.path)
    for file in try target.sourcesBuildPhase()?.files ?? [] {
      guard
        let element = file.file,
        let path = try? element.fullPath(sourceRoot: root),
        let relative = context.relative(URL(fileURLWithPath: path.string))
      else {
        continue
      }
      sources.insert(TextFiles.normalize(relative))
    }
    let resolver = BuildSettingsResolver(sourceRoot: sourceRoot)
    let settings = resolver.settings(of: target, project: project)
    // Swift sources use the modules the bridging header imports.
    if let header = bridgingHeader(
      of: target,
      settings: settings,
      sourceRoot: sourceRoot,
      context: context
    ) {
      sources.insert(header)
    }
    // A dependency's module name comes from the same setting layers as the target's own.
    let dependencies = Self.dependencies(of: target, context: &context) { dependedOn in
      BuildSettingsResolver.moduleName(
        targetName: dependedOn.name,
        settings: resolver.settings(of: dependedOn, project: project)
      )
    }

    let productType = Self.productType(of: target)
    let isTestSupport = context.configuration.testSupport.contains(target.name)
    let role: ProjectTarget.Role =
      if productType == .unitTest || productType == .uiTest {
        .test
      } else if isTestSupport {
        .testSupport
      } else {
        .product
      }
    return ProjectTarget(
      name: target.name,
      moduleName: BuildSettingsResolver.moduleName(targetName: target.name, settings: settings),
      role: role,
      productType: productType,
      sourceFiles: sources.filter { $0.hasSuffix(".swift") }.sorted(),
      dependencies: dependencies,
      otherSourceFiles: sources.filter { !$0.hasSuffix(".swift") }.sorted(),
      manifestPath: manifestPath
    )
  }

  /// The declared dependencies; one on a target of another project waits in the context until
  /// every project is loaded.
  static func dependencies(
    of target: PBXNativeTarget,
    context: inout LoadContext,
    moduleName: (PBXTarget) -> String
  ) -> [TargetDependency] {
    var dependencies: [TargetDependency] = []
    for dependency in target.dependencies {
      if let product = dependency.product {
        // Build tool plugins are dependencies too, spelled `plugin:<name>`.
        if !product.productName.hasPrefix("plugin:") {
          dependencies.append(productDependency(product.productName, context: context))
        }
      } else if let dependedOn = dependency.target as? PBXNativeTarget {
        if [.framework, .library].contains(Self.productType(of: dependedOn)) {
          dependencies.append(
            TargetDependency(
              name: dependedOn.name,
              moduleNames: [moduleName(dependedOn)],
              kind: .target
            )
          )
        }
      } else if let name = dependency.targetProxy?.remoteInfo ?? dependency.name {
        context.remoteTargetDependencies[target.name, default: []].insert(name)
      }
    }
    for product in target.packageProductDependencies ?? []
    where !product.productName.hasPrefix("plugin:") {
      let declared = productDependency(product.productName, context: context)
      if !dependencies.contains(declared) {
        dependencies.append(declared)
      }
      context.externalModules.formUnion(declared.moduleNames)
    }
    return dependencies
  }

  /// `SWIFT_OBJC_BRIDGING_HEADER` as a path relative to the root, when the file exists.
  static func bridgingHeader(
    of target: PBXNativeTarget,
    settings: [String: String],
    sourceRoot: URL,
    context: LoadContext
  ) -> String? {
    guard var path = settings["SWIFT_OBJC_BRIDGING_HEADER"] else {
      return nil
    }
    let variables = [
      "SRCROOT": sourceRoot.path, "PROJECT_DIR": sourceRoot.path, "SOURCE_ROOT": sourceRoot.path,
      "TARGET_NAME": target.name,
    ]
    for (name, value) in variables {
      path = path.replacingOccurrences(of: "$(\(name))", with: value)
        .replacingOccurrences(of: "${\(name)}", with: value)
    }
    path = path.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
    let url = URL(fileURLWithPath: path, relativeTo: sourceRoot).standardizedFileURL
    guard !path.isEmpty, !path.contains("$"), FileManager.default.fileExists(atPath: url.path)
    else {
      return nil
    }
    return context.relative(url).map(TextFiles.normalize)
  }

  static func productDependency(_ name: String, context: LoadContext) -> TargetDependency {
    TargetDependency(
      name: name,
      moduleNames: Set([name] + (context.configuration.moduleNames[name] ?? [])),
      kind: .product
    )
  }

  /// Files a synchronized folder compiles rather than copies.
  static func isSourceFile(_ path: String) -> Bool {
    SourceLanguages.compiledExtensions.contains((path as NSString).pathExtension)
  }

  static func productType(of target: PBXNativeTarget) -> ProjectTarget.ProductType {
    switch target.productType {
    case .application, .watchApp, .watch2App, .watch2AppContainer, .messagesApplication,
      .onDemandInstallCapableApplication:
      .application
    case .appExtension, .extensionKitExtension, .watchExtension, .watch2Extension,
      .tvExtension, .messagesExtension, .stickerPack, .intentsServiceExtension, .xcodeExtension,
      .systemExtension, .driverExtension:
      .appExtension
    case .framework, .staticFramework, .xcFramework:
      .framework
    case .staticLibrary, .dynamicLibrary:
      .library
    case .commandLineTool:
      .executable
    case .unitTestBundle, .ocUnitTestBundle:
      .unitTest
    case .uiTestBundle:
      .uiTest
    default:
      .other
    }
  }
}

// MARK: - Local Packages

private extension XcodeProjectAdapter {
  func loadLocalPackages(context: inout LoadContext) throws {
    let adapter = SwiftPackageAdapter(runner: runner)
    for path in context.localPackages.sorted() {
      let directory = context.root.appendingPathComponent(path)
      let package = try adapter.load(
        packageRoot: directory,
        prefix: path,
        configuration: context.configuration
      )
      context.targets.append(contentsOf: package.targets)
      context.externalModules.formUnion(package.externalModules)
      context.packageDependencies.formUnion(package.localPackageDependencies)
    }
    // Products of local packages are project code, which Periphery already analyzes.
    let localModules = context.targets.filter { $0.manifestPath.hasSuffix("Package.swift") }
      .map(\.moduleName)
    context.externalModules.subtract(localModules)
  }
}
