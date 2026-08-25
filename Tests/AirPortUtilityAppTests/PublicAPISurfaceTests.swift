import XCTest

final class PublicAPISurfaceTests: XCTestCase {
  func testCorePublicSurfaceStaysIntentional() throws {
    let declarations = try publicDeclarations(in: "Sources/AirPortUtilityCore")

    XCTAssertEqual(
      declarations,
      [
        "Sources/AirPortUtilityCore/AirPortServices.swift:public convenience init() {",
        "Sources/AirPortUtilityCore/AirPortServices.swift:public final class AirportAppModel: ObservableObject {",
        "Sources/AirPortUtilityCore/AirPortSetup.swift:public func requestRestoreDefaultSettings() {",
        "Sources/AirPortUtilityCore/AirPortSetup.swift:public func restoreDefaultSettings() {",
        "Sources/AirPortUtilityCore/AirPortSetup.swift:public var canRequestRestoreDefaultSettings: Bool {",
        "Sources/AirPortUtilityCore/AirportAppModelConfiguration.swift:public func beginEditing() {",
        "Sources/AirPortUtilityCore/AirportAppModelConfiguration.swift:public func exportConfiguration(to url: URL) throws {",
        "Sources/AirPortUtilityCore/AirportAppModelConfiguration.swift:public func importConfiguration(from url: URL) throws {",
        "Sources/AirPortUtilityCore/AirportAppModelConfiguration.swift:public func showConfigureOther() {",
        "Sources/AirPortUtilityCore/AirportAppModelConfiguration.swift:public func showPasswords() {",
        "Sources/AirPortUtilityCore/AirportAppModelConfiguration.swift:public func showPreferences() {",
        "Sources/AirPortUtilityCore/AirportAppModelConfiguration.swift:public func showSites() {",
        "Sources/AirPortUtilityCore/AirportAppModelConfiguration.swift:public var canShowPasswords: Bool {",
        "Sources/AirPortUtilityCore/AirportAppModelConfiguration.swift:public var defaultConfigurationFileName: String {",
        "Sources/AirPortUtilityCore/AirportAppModelRestart.swift:public func requestRestartBaseStation() {",
        "Sources/AirPortUtilityCore/AirportAppModelRestart.swift:public func restartBaseStation() {",
        "Sources/AirPortUtilityCore/AirportAppModelRestart.swift:public var canRequestRestartBaseStation: Bool {",
        "Sources/AirPortUtilityCore/AirportAppModelTopology.swift:public func refreshNetwork() {",
        "Sources/AirPortUtilityCore/AirportAppModelTopology.swift:public func topologyDisplayLogSnapshot() -> String {",
        "Sources/AirPortUtilityCore/AirportAppModelTopology.swift:public var canRefreshNetwork: Bool {",
        "Sources/AirPortUtilityCore/ContentView.swift:public enum AirPortMainWindowMetrics {",
        "Sources/AirPortUtilityCore/ContentView.swift:public init() {}",
        "Sources/AirPortUtilityCore/ContentView.swift:public static let contentSize = CGSize(width: 800, height: 504)",
        "Sources/AirPortUtilityCore/ContentView.swift:public static let fullSnapshotSize = CGSize(",
        "Sources/AirPortUtilityCore/ContentView.swift:public static let titleBarHeight: CGFloat = 28",
        "Sources/AirPortUtilityCore/ContentView.swift:public struct ContentView: View {",
        "Sources/AirPortUtilityCore/ContentView.swift:public var body: some View {",
        "Sources/AirPortUtilityCore/SnapshotRenderer.swift:public enum AirPortSnapshotRenderer {",
        "Sources/AirPortUtilityCore/SnapshotRenderer.swift:public static func renderAll(model: AirportAppModel, outputDirectory: URL) throws -> [URL] {",
        "Sources/AirPortUtilityCore/StorageNotifications.swift:public enum HealthNotificationCenter {",
        "Sources/AirPortUtilityCore/StorageNotifications.swift:public nonisolated static var isAvailableForCurrentProcess: Bool {",
      ])
  }

  func testReviewedModelTypesRemainInternal() throws {
    let models = try sourceText(at: "Sources/AirPortUtilityCore/AirPortModels.swift")

    XCTAssertTrue(models.contains("struct AirportConnection: Equatable, Sendable {"))
    XCTAssertTrue(models.contains("struct CommandResult: Equatable, Sendable {"))
    XCTAssertTrue(models.contains("enum EraseMethod: String, CaseIterable, Identifiable, Sendable {"))

    XCTAssertFalse(models.contains("public struct AirportConnection"))
    XCTAssertFalse(models.contains("public struct CommandResult"))
    XCTAssertFalse(models.contains("public enum EraseMethod"))
  }

  private func publicDeclarations(in relativeDirectory: String) throws -> [String] {
    let root = packageRoot.appendingPathComponent(relativeDirectory)
    let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
    var declarations: [String] = []

    for case let url as URL in enumerator where url.pathExtension == "swift" {
      let relativePath = url.path.replacingOccurrences(of: packageRoot.path + "/", with: "")
      let text = try String(contentsOf: url, encoding: .utf8)
      for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("public ") {
          declarations.append("\(relativePath):\(trimmed)")
        }
      }
    }

    return declarations.sorted()
  }

  private func sourceText(at relativePath: String) throws -> String {
    try String(contentsOf: packageRoot.appendingPathComponent(relativePath), encoding: .utf8)
  }

  private var packageRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }
}
