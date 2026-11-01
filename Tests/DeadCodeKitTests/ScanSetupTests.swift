import DeadCodeKit
import Foundation
import Testing

@Suite
struct ScanSetupTests {
  static let model = ProjectModel(
    kind: .xcode(container: "App.xcodeproj"),
    root: URL(fileURLWithPath: "/tmp/App"),
    targets: [
      ProjectTarget(
        name: "App",
        role: .product,
        productType: .application,
        sourceFiles: ["App/Main.swift", "App/Shared.swift"],
        manifestPath: "App.xcodeproj/project.pbxproj"
      ),
      // Older projects add app files to the test target instead of importing the app.
      ProjectTarget(
        name: "AppTests",
        role: .test,
        productType: .unitTest,
        sourceFiles: ["AppTests/MainTests.swift", "App/Shared.swift"],
        manifestPath: "App.xcodeproj/project.pbxproj"
      ),
    ]
  )

  @Test
  func theScanWithoutTestsKeepsFilesTheAppShares() {
    // when
    let arguments = PeripheryScanner(model: Self.model, configuration: Configuration())
      .productionArguments()

    // then: App/Shared.swift stays indexed, so its calls still count.
    #expect(arguments == ["--index-exclude", "AppTests/**", "--disable-redundant-public-analysis"])
  }

  @Test
  func aBuildWithoutVariantsPassesTheProjectArgumentsOnce() throws {
    // given
    var configuration = Configuration()
    configuration.project.buildArguments = ["-skipMacroValidation"]
    let builder = ProjectBuilder(model: Self.model, configuration: configuration)
    let variant = try #require(builder.variants.first)

    // when
    let arguments = builder.xcodebuildArguments(
      scheme: "App",
      variant: variant,
      container: "App.xcodeproj",
      derivedData: URL(fileURLWithPath: "/tmp/DerivedData")
    )

    // then
    #expect(
      arguments == [
        "-project", "App.xcodeproj", "-scheme", "App", "-destination",
        "generic/platform=iOS Simulator", "-derivedDataPath", "/tmp/DerivedData",
        "CODE_SIGNING_ALLOWED=NO", "-skipMacroValidation",
      ]
    )
  }
}
