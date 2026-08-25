import AppKit
import SwiftUI

public enum AirPortSnapshotRenderer {
  @MainActor
  public static func renderAll(model: AirportAppModel, outputDirectory: URL) throws -> [URL] {
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

    var urls: [URL] = []
    model.isEditingDevice = true
    for pane in model.visiblePanes {
      model.selectedPane = pane
      let url = outputDirectory.appendingPathComponent(fileName(for: pane))
      try renderEditWindow(model: model, to: url)
      urls.append(url)
    }
    model.selectedPane = .wireless
    let wirelessSheetURL = outputDirectory.appendingPathComponent("wireless-sheet.png")
    try renderFullEditSheet(model: model, to: wirelessSheetURL)
    urls.append(wirelessSheetURL)
    model.selectedPane = .internet
    let internetOptionsURL = outputDirectory.appendingPathComponent("internet-options.png")
    try renderInternetOptionsWindow(model: model, to: internetOptionsURL)
    urls.append(internetOptionsURL)
    model.selectedPane = .wireless
    let wirelessOptionsURL = outputDirectory.appendingPathComponent("wireless-options.png")
    try renderWirelessOptionsWindow(model: model, to: wirelessOptionsURL)
    urls.append(wirelessOptionsURL)
    model.selectedPane = .network
    let networkOptionsURL = outputDirectory.appendingPathComponent("network-options.png")
    try renderNetworkOptionsWindow(model: model, to: networkOptionsURL)
    urls.append(networkOptionsURL)

    model.isEditingDevice = false
    model.selectedPane = .baseStation
    let topologyURL = outputDirectory.appendingPathComponent("main.png")
    try renderTopology(model: model, to: topologyURL)
    urls.append(topologyURL)

    model.isDevicePopoverPresented = true
    let popoverURL = outputDirectory.appendingPathComponent("device-popover.png")
    try renderDevicePopover(model: model, to: popoverURL)
    urls.append(popoverURL)
    model.isDevicePopoverPresented = false

    model.wirelessClients = AirportMockBackend.sampleWirelessClients
    model.hasLoadedWirelessClients = true
    let dashboardURL = outputDirectory.appendingPathComponent("dashboard.png")
    try renderDashboard(model: model, to: dashboardURL)
    urls.append(dashboardURL)
    model.setup = AirPortSetupState(
      step: .recommendation, mode: .create, deviceName: "new airport",
      networkName: "new network", password: "password", verifyPassword: "password")
    for step in [
      AirPortSetupStep.recommendation, .choices, .details, .applying, .complete,
    ] {
      model.setup.step = step
      if step == .applying {
        model.setup.progressText = "Setting up this AirPort Base Station to create a network."
      }
      let setupURL = outputDirectory.appendingPathComponent("setup-\(setupFileName(step)).png")
      try renderSetup(model: model, to: setupURL)
      urls.append(setupURL)
    }
    return urls
  }

  @MainActor
  private static func renderSetup(model: AirportAppModel, to url: URL) throws {
    let size = NSSize(width: 650, height: 430)
    try render(root: AirPortSetupSheet().environmentObject(model), size: size, to: url)
  }

  private static func setupFileName(_ step: AirPortSetupStep) -> String {
    switch step {
    case .examining: "examining"
    case .recommendation: "recommendation"
    case .choices: "choices"
    case .details: "details"
    case .applying: "applying"
    case .complete: "complete"
    }
  }

  @MainActor
  private static func renderTopology(model: AirportAppModel, to url: URL) throws {
    let size = AirPortMainWindowMetrics.fullSnapshotSize
    let root = SnapshotWindow(controlState: .normal) {
      TopologyView()
        .environmentObject(model)
    }
    try render(root: root, size: size, to: url)
  }

  @MainActor
  private static func renderDashboard(model: AirportAppModel, to url: URL) throws {
    let size = AirPortMainWindowMetrics.fullSnapshotSize
    let root = SnapshotWindow(controlState: .normal) {
      DashboardPane()
        .environmentObject(model)
    }
    try render(root: root, size: size, to: url)
  }

  @MainActor
  private static func renderDevicePopover(model: AirportAppModel, to url: URL) throws {
    let size = AirPortMainWindowMetrics.fullSnapshotSize
    let root = SnapshotWindow(controlState: .normal) {
      ZStack(alignment: .topLeading) {
        TopologyView()
          .environmentObject(model)
        DevicePopover()
          .environmentObject(model)
          .background(
            SnapshotDevicePopoverBackground()
              .fill(
                LinearGradient(
                  colors: [
                    Color(red: 0.25, green: 0.25, blue: 0.31).opacity(0.96),
                    Color(red: 0.20, green: 0.20, blue: 0.25).opacity(0.96),
                  ],
                  startPoint: .top,
                  endPoint: .bottom
                )
              )
          )
          .overlay(
            SnapshotDevicePopoverBackground()
              .stroke(Color.white.opacity(0.22), lineWidth: 1)
          )
          .shadow(color: .black.opacity(0.34), radius: 16, x: 0, y: 8)
          .frame(width: 326, height: 202)
          .offset(x: 348, y: 286)
      }
    }
    try render(root: root, size: size, to: url)
  }

  @MainActor
  private static func renderEditWindow(model: AirportAppModel, to url: URL) throws {
    let size = AirPortMainWindowMetrics.fullSnapshotSize
    let sheetWidth = AirPortLayout.configurationSheetWidth(for: model.visiblePanes)
    let root = SnapshotWindow(controlState: .sheet) {
      ZStack(alignment: .top) {
        TopologyView()
          .environmentObject(model)
          .saturation(0.62)
          .brightness(-0.12)
        Color.black.opacity(0.28)
        ConfigurationSheet {
          pane(for: model.selectedPane)
        }
        .environmentObject(model)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
          RoundedRectangle(cornerRadius: 10)
            .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.36), radius: 18, x: 0, y: 8)
        .frame(width: sheetWidth, height: AirPortLayout.configurationSheetHeight)
      }
    }
    try render(root: root, size: size, to: url)
  }

  @MainActor
  private static func renderFullEditSheet(model: AirportAppModel, to url: URL) throws {
    let sheetWidth = AirPortLayout.configurationSheetWidth(for: model.visiblePanes)
    let size = NSSize(width: sheetWidth, height: AirPortLayout.configurationSheetHeight)
    let root = ConfigurationSheet {
      pane(for: model.selectedPane)
    }
    .environmentObject(model)
    try render(root: root, size: size, to: url)
  }

  @MainActor
  private static func renderInternetOptionsWindow(model: AirportAppModel, to url: URL) throws {
    let size = AirPortMainWindowMetrics.fullSnapshotSize
    let sheetWidth = AirPortLayout.configurationSheetWidth(for: model.visiblePanes)
    let root = SnapshotWindow(controlState: .modalSheet) {
      ZStack(alignment: .topLeading) {
        TopologyView()
          .environmentObject(model)
          .saturation(0.62)
          .brightness(-0.12)
        Color.black.opacity(0.28)
        ConfigurationSheet {
          InternetPane()
        }
        .environmentObject(model)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
          RoundedRectangle(cornerRadius: 10)
            .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.36), radius: 18, x: 0, y: 8)
        .frame(width: sheetWidth, height: AirPortLayout.configurationSheetHeight)
        .frame(maxWidth: .infinity, alignment: .center)
        .brightness(-0.24)

        Color.black.opacity(0.22)

        InternetOptionsSheet()
          .environmentObject(model)
          .clipShape(RoundedRectangle(cornerRadius: 10))
          .overlay(
            RoundedRectangle(cornerRadius: 10)
              .stroke(Color.white.opacity(0.20), lineWidth: 1)
          )
          .shadow(color: .black.opacity(0.42), radius: 18, x: 0, y: 8)
          .frame(width: 520, height: 259)
          .offset(x: (AirPortMainWindowMetrics.contentSize.width - 520) / 2, y: 108)
      }
    }
    try render(root: root, size: size, to: url)
  }

  @MainActor
  private static func renderWirelessOptionsWindow(model: AirportAppModel, to url: URL) throws {
    let size = AirPortMainWindowMetrics.fullSnapshotSize
    let sheetWidth = AirPortLayout.configurationSheetWidth(for: model.visiblePanes)
    let root = SnapshotWindow(controlState: .modalSheet) {
      ZStack(alignment: .topLeading) {
        TopologyView()
          .environmentObject(model)
          .saturation(0.62)
          .brightness(-0.12)
        Color.black.opacity(0.28)
        ConfigurationSheet {
          WirelessPane()
        }
        .environmentObject(model)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
          RoundedRectangle(cornerRadius: 10)
            .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.36), radius: 18, x: 0, y: 8)
        .frame(width: sheetWidth, height: AirPortLayout.configurationSheetHeight)
        .frame(maxWidth: .infinity, alignment: .center)
        .brightness(-0.24)

        Color.black.opacity(0.22)

        WirelessOptionsSheet()
          .environmentObject(model)
          .clipShape(RoundedRectangle(cornerRadius: 10))
          .overlay(
            RoundedRectangle(cornerRadius: 10)
              .stroke(Color.white.opacity(0.20), lineWidth: 1)
          )
          .shadow(color: .black.opacity(0.42), radius: 18, x: 0, y: 8)
          .frame(width: 480, height: 280)
          .offset(x: (AirPortMainWindowMetrics.contentSize.width - 480) / 2, y: 98)
      }
    }
    try render(root: root, size: size, to: url)
  }

  @MainActor
  private static func renderNetworkOptionsWindow(model: AirportAppModel, to url: URL) throws {
    let size = AirPortMainWindowMetrics.fullSnapshotSize
    let sheetWidth = AirPortLayout.configurationSheetWidth(for: model.visiblePanes)
    let root = SnapshotWindow(controlState: .modalSheet) {
      ZStack(alignment: .topLeading) {
        TopologyView()
          .environmentObject(model)
          .saturation(0.62)
          .brightness(-0.12)
        Color.black.opacity(0.28)
        ConfigurationSheet {
          NetworkPane()
        }
        .environmentObject(model)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
          RoundedRectangle(cornerRadius: 10)
            .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.36), radius: 18, x: 0, y: 8)
        .frame(width: sheetWidth, height: AirPortLayout.configurationSheetHeight)
        .frame(maxWidth: .infinity, alignment: .center)
        .brightness(-0.24)

        Color.black.opacity(0.22)

        NetworkOptionsSheet()
          .environmentObject(model)
          .clipShape(RoundedRectangle(cornerRadius: 10))
          .overlay(
            RoundedRectangle(cornerRadius: 10)
              .stroke(Color.white.opacity(0.20), lineWidth: 1)
          )
          .shadow(color: .black.opacity(0.42), radius: 18, x: 0, y: 8)
          .frame(width: 511, height: 264)
          .offset(x: (AirPortMainWindowMetrics.contentSize.width - 511) / 2, y: 134)
      }
    }
    try render(root: root, size: size, to: url)
  }

  @ViewBuilder
  @MainActor
  private static func pane(for pane: Pane) -> some View {
    switch pane {
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

  @MainActor
  private static func render<Content: View>(root: Content, size: NSSize, to url: URL) throws {
    let hostingView = NSHostingView(rootView: root)
    hostingView.frame = NSRect(origin: .zero, size: size)
    hostingView.wantsLayer = true
    hostingView.layer?.contentsScale = 2
    hostingView.layoutSubtreeIfNeeded()

    let scale: CGFloat = 2
    guard
      let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width * scale),
        pixelsHigh: Int(size.height * scale),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      )
    else {
      throw SnapshotError.couldNotCreateBitmap
    }
    representation.size = size
    hostingView.cacheDisplay(in: hostingView.bounds, to: representation)

    guard let data = representation.representation(using: .png, properties: [:]) else {
      throw SnapshotError.couldNotEncodePNG
    }
    try data.write(to: url, options: .atomic)
  }

  private static func fileName(for pane: Pane) -> String {
    pane.rawValue
      .lowercased()
      .replacingOccurrences(of: " ", with: "-") + ".png"
  }
}

private struct SnapshotDevicePopoverBackground: Shape {
  func path(in rect: CGRect) -> Path {
    let bodyMinX = rect.minX + 13
    let maxX = rect.maxX
    let minY = rect.minY
    let maxY = rect.maxY
    let radius: CGFloat = 8
    let tailMidY = rect.midY - 12
    let tailHalfHeight: CGFloat = 17

    var path = Path()
    path.move(to: CGPoint(x: bodyMinX + radius, y: minY))
    path.addLine(to: CGPoint(x: maxX - radius, y: minY))
    path.addQuadCurve(
      to: CGPoint(x: maxX, y: minY + radius),
      control: CGPoint(x: maxX, y: minY)
    )
    path.addLine(to: CGPoint(x: maxX, y: maxY - radius))
    path.addQuadCurve(
      to: CGPoint(x: maxX - radius, y: maxY),
      control: CGPoint(x: maxX, y: maxY)
    )
    path.addLine(to: CGPoint(x: bodyMinX + radius, y: maxY))
    path.addQuadCurve(
      to: CGPoint(x: bodyMinX, y: maxY - radius),
      control: CGPoint(x: bodyMinX, y: maxY)
    )
    path.addLine(to: CGPoint(x: bodyMinX, y: tailMidY + tailHalfHeight))
    path.addLine(to: CGPoint(x: rect.minX, y: tailMidY))
    path.addLine(to: CGPoint(x: bodyMinX, y: tailMidY - tailHalfHeight))
    path.addLine(to: CGPoint(x: bodyMinX, y: minY + radius))
    path.addQuadCurve(
      to: CGPoint(x: bodyMinX + radius, y: minY),
      control: CGPoint(x: bodyMinX, y: minY)
    )
    path.closeSubpath()
    return path
  }
}

private struct SnapshotWindow<Content: View>: View {
  var controlState: SnapshotWindowControlState
  @ViewBuilder var content: Content

  var body: some View {
    VStack(spacing: 0) {
      ZStack {
        LinearGradient(
          colors: [
            Color(red: 0.24, green: 0.22, blue: 0.25),
            Color(red: 0.16, green: 0.14, blue: 0.16),
          ],
          startPoint: .top,
          endPoint: .bottom
        )
        Text("AirPort Utility")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.white.opacity(0.42))
        HStack(spacing: 10) {
          windowButton(controlState.closeColor)
          windowButton(controlState.minimizeColor)
          windowButton(controlState.zoomColor)
          Spacer()
        }
        .padding(.leading, 8)
      }
      .frame(height: 28)
      content
        .frame(
          width: AirPortMainWindowMetrics.contentSize.width,
          height: AirPortMainWindowMetrics.contentSize.height,
          alignment: .top)
        .clipped()
    }
    .frame(
      width: AirPortMainWindowMetrics.fullSnapshotSize.width,
      height: AirPortMainWindowMetrics.fullSnapshotSize.height)
    .preferredColorScheme(.dark)
  }

  private func windowButton(_ color: Color) -> some View {
    Circle()
      .fill(color)
      .frame(width: 12, height: 12)
  }
}

private enum SnapshotWindowControlState {
  case normal
  case sheet
  case modalSheet

  var closeColor: Color {
    switch self {
    case .normal:
      return Color(red: 1.0, green: 0.36, blue: 0.32)
    case .sheet, .modalSheet:
      return disabledColor
    }
  }

  var minimizeColor: Color {
    switch self {
    case .normal, .sheet:
      return Color(red: 1.0, green: 0.73, blue: 0.2)
    case .modalSheet:
      return disabledColor
    }
  }

  var zoomColor: Color {
    switch self {
    case .normal, .sheet:
      return Color(red: 0.16, green: 0.78, blue: 0.24)
    case .modalSheet:
      return disabledColor
    }
  }

  private var disabledColor: Color {
    Color(red: 0.38, green: 0.37, blue: 0.39)
  }
}

enum SnapshotError: LocalizedError {
  case couldNotCreateBitmap
  case couldNotEncodePNG

  var errorDescription: String? {
    switch self {
    case .couldNotCreateBitmap:
      return "Could not create bitmap representation for SwiftUI snapshot."
    case .couldNotEncodePNG:
      return "Could not encode SwiftUI snapshot as PNG."
    }
  }
}
