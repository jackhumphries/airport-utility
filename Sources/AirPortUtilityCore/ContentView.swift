import AppKit
import SwiftUI

func airPortResourceImage(named name: String, fallbackSystemName: String) -> Image {
  if let image = airPortReplacementNSImage(named: name) {
    return Image(nsImage: image)
  }
  return Image(systemName: fallbackSystemName)
}

func airPortReplacementNSImage(named name: String) -> NSImage? {
  guard let replacementName = AirPortReplacementArtwork.resourceName(for: name) else {
    return nil
  }
  guard let url = airPortReplacementResourceURL(named: replacementName) else {
    return nil
  }
  return NSImage(contentsOf: url)
}

private func airPortReplacementResourceURL(named name: String) -> URL? {
  if let url = Bundle.main.url(forResource: name, withExtension: nil) {
    return url
  }
  if let url = Bundle.module.url(forResource: name, withExtension: nil) {
    return url
  }
  let resourceURL = URL(fileURLWithPath: name)
  return Bundle.module.url(
    forResource: resourceURL.deletingPathExtension().lastPathComponent,
    withExtension: resourceURL.pathExtension)
}

enum AirPortReplacementArtwork {
  static func resourceName(for legacyName: String) -> String? {
    switch legacyName {
    case "Internet-3D~mac.tiff",
      "AirPortExpress-3D-cropped~mac.tiff",
      "AirPortEx-3D-cropped~mac.tiff",
      "TimeCapsule-3D-cropped~mac.tiff",
      "AirPort-8-3D-cropped~mac.tiff",
      "AirPortExtremeN-3D-cropped~mac.tiff",
      "AirPortExtremeG-3D-cropped~mac.tiff",
      "GenericBase-3D-cropped~mac.tiff",
      "AirDisk.icns",
      "Drives.icns":
      return legacyName
    default:
      return nil
    }
  }
}

public struct ContentView: View {
  @EnvironmentObject private var model: AirportAppModel
  @State private var appView: AppView = .dashboard

  public init() {}

  public var body: some View {
    appContent
      .safeAreaInset(edge: .top, spacing: 0) {
        HStack {
          Picker("View", selection: $appView) {
            ForEach(AppView.allCases) { view in
              Label(view.rawValue, systemImage: view.systemImage)
                .tag(view)
            }
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .frame(width: 260)

          Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
      }
      .background {
        MainWindowContentSizeSynchronizer(contentSize: model.mainWindowContentSize)
      }
      .sheet(isPresented: $model.isEditingDevice) {
        ConfigurationSheet {
          pane
        }
        .environmentObject(model)
      }
      .sheet(isPresented: $model.isShowingPasswords) {
        PasswordsSheet()
          .environmentObject(model)
      }
      .sheet(isPresented: $model.isShowingPreferences) {
        PreferencesSheet()
          .environmentObject(model)
      }
      .sheet(isPresented: $model.isShowingConfigureOther) {
        ConfigureOtherSheet()
          .environmentObject(model)
      }
      .sheet(isPresented: $model.isShowingSites) {
        SitesSheet()
          .environmentObject(model)
      }
      .sheet(item: $model.settingsComparison) { comparison in
        SettingsDiffSheet(comparison: comparison)
      }
      .sheet(isPresented: $model.isShowingSetup) {
        AirPortSetupSheet()
          .environmentObject(model)
      }
      .sheet(isPresented: $model.isShowingRestartConfirmation) {
        RestartBaseStationSheet()
          .environmentObject(model)
      }
      .sheet(isPresented: $model.isShowingRestoreConfirmation) {
        RestoreDefaultSettingsSheet()
          .environmentObject(model)
      }
      .task {
        model.startBonjourDiscovery()
        model.refreshHostInternetSettings()
        model.loadInitialSettingsIfPossible()
      }
      .preferredColorScheme(.dark)
  }

  @ViewBuilder
  private var appContent: some View {
    switch appView {
    case .dashboard:
      DashboardPane()
    case .topology:
      TopologyView()
    }
  }

  @ViewBuilder
  private var pane: some View {
    switch model.selectedPane {
    case .baseStation:
      BaseStationPane()
    case .internet:
      InternetPane()
    case .wireless:
      WirelessPane()
    case .network:
      NetworkPane()
    case .airPlay:
      AirPlayPane()
    case .disks:
      DisksPane()
    case .advanced:
      AdvancedPane()
    case .firmware:
      FirmwarePane()
    case .diagnostics:
      DiagnosticsPane()
    }
  }
}

private enum AppView: String, CaseIterable, Identifiable {
  case dashboard = "Dashboard"
  case topology = "Network Map"

  var id: Self { self }

  var systemImage: String {
    switch self {
    case .dashboard:
      "gauge.with.dots.needle.67percent"
    case .topology:
      "point.3.connected.trianglepath.dotted"
    }
  }
}

public enum AirPortMainWindowMetrics {
  public static let contentSize = CGSize(width: 800, height: 504)
  public static let titleBarHeight: CGFloat = 28
  static let topologyRootColumnWidth: CGFloat = 200
  static let topologyRootHorizontalSpacing: CGFloat = 72
  static let singleTopologyRootHorizontalSpacing: CGFloat = 24
  static let topologyHorizontalMargin: CGFloat = 28

  public static let fullSnapshotSize = CGSize(
    width: contentSize.width,
    height: contentSize.height + titleBarHeight)

  static func contentSize(
    forTopologyRootCount rootCount: Int,
    topologyDepth: Int = 1,
    configurationPanes: [Pane]? = nil
  ) -> CGSize {
    let topologyWidth =
      topologyRootsWidth(forRootCount: rootCount) + topologyHorizontalMargin * 2
    let configurationWidth = configurationPanes.map(AirPortLayout.configurationSheetWidth) ?? 0
    let configurationHeight =
      configurationPanes == nil ? 0 : AirPortLayout.configurationSheetHeight
    let topologyHeight = contentSize.height + CGFloat(max(topologyDepth - 1, 0)) * 150
    return CGSize(
      width: max(contentSize.width, ceil(topologyWidth), configurationWidth),
      height: max(topologyHeight, configurationHeight))
  }

  static func topologyRootsWidth(forRootCount rootCount: Int) -> CGFloat {
    let rootCount = max(rootCount, 1)
    return CGFloat(rootCount) * topologyRootColumnWidth
      + CGFloat(max(rootCount - 1, 0)) * topologyRootSpacing(forRootCount: rootCount)
  }

  static func topologyRootSpacing(forRootCount rootCount: Int) -> CGFloat {
    rootCount > 1 ? topologyRootHorizontalSpacing : singleTopologyRootHorizontalSpacing
  }

  @MainActor
  static func sync(_ window: NSWindow, toContentSize contentSize: CGSize) {
    let minimumFrameSize = window.frameRect(
      forContentRect: NSRect(origin: .zero, size: contentSize)
    ).size
    if abs(window.minSize.width - minimumFrameSize.width) > 0.5
      || abs(window.minSize.height - minimumFrameSize.height) > 0.5
    {
      window.minSize = minimumFrameSize
    }

    let currentContentSize = window.contentRect(forFrameRect: window.frame).size
    let targetContentSize = NSSize(
      width: max(currentContentSize.width, contentSize.width),
      height: max(currentContentSize.height, contentSize.height))
    guard
      abs(currentContentSize.width - targetContentSize.width) > 0.5
        || abs(currentContentSize.height - targetContentSize.height) > 0.5
    else {
      return
    }
    window.setContentSize(targetContentSize)
  }
}

@MainActor
extension AirportAppModel {
  var mainWindowContentSize: CGSize {
    AirPortMainWindowMetrics.contentSize(
      forTopologyRootCount: topologyTrees.count,
      topologyDepth: topologyTreeDepth,
      configurationPanes: isEditingDevice ? visiblePanes : nil)
  }

  var topologyTreeDepth: Int {
    topologyTrees.map(Self.depth(of:)).max() ?? 1
  }

  private static func depth(of tree: AirportTopologyTree) -> Int {
    1 + (tree.children.map(depth(of:)).max() ?? 0)
  }
}

private struct MainWindowContentSizeSynchronizer: NSViewRepresentable {
  var contentSize: CGSize

  func makeNSView(context: Context) -> MainWindowContentSizeView {
    MainWindowContentSizeView()
  }

  func updateNSView(_ nsView: MainWindowContentSizeView, context: Context) {
    nsView.contentSize = contentSize
  }
}

private final class MainWindowContentSizeView: NSView {
  var contentSize: CGSize = .zero {
    didSet {
      syncWindowSize()
    }
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    syncWindowSize()
  }

  private func syncWindowSize() {
    guard contentSize != .zero, let window else { return }
    AirPortMainWindowMetrics.sync(window, toContentSize: contentSize)
  }
}
