import AppKit
import SwiftUI

private enum AirPortTopologyStyle {
  static let connector = Color.white.opacity(0.46)
  static let connectorHighlight = Color.white.opacity(0.14)
  static let selectedStroke = Color.white.opacity(0.86)
  static let selectedGlow = Color.black.opacity(0.32)
  static let labelShadow = Color.black.opacity(0.46)
  static let rootColumnWidth = AirPortMainWindowMetrics.topologyRootColumnWidth
}

struct TopologyView: View {
  @EnvironmentObject private var model: AirportAppModel
  @State private var selectedNetworkInterfaceTitle = OtherWiFiDevicesMenu.defaultNetworkInterface

  var body: some View {
    ZStack(alignment: .topLeading) {
      TopologyBackground()
      OtherWiFiDevicesMenu(
        showConnectItem: model.showConnectionDetails && !model.mockMode,
        devices: model.otherWiFiDevicesMenuDevices,
        selectedDeviceID: model.selectedTopologyDeviceID,
        selectedNetworkInterfaceTitle: selectedNetworkInterfaceTitle
      ) {
        DispatchQueue.main.async {
          presentConnectionPopover()
        }
      } onSelectDeviceID: { deviceID in
        DispatchQueue.main.async {
          model.presentOtherWiFiDeviceFromMenu(id: deviceID)
        }
      } onSelectNetworkInterface: { title in
        selectedNetworkInterfaceTitle = title
      }
      .frame(width: 140, height: 22)
      .popover(isPresented: $model.isConnectionPopoverPresented, arrowEdge: .bottom) {
        ConnectionPopover()
          .environmentObject(model)
      }
      .padding(.leading, 19)
      .padding(.top, 19)

      VStack(spacing: 0) {
        TopologyNode(
          imageName: "Internet-3D~mac.tiff",
          title: "Internet",
          subtitle: nil,
          accessibilityTitle: model.internetTopologyAccessibilityTitle,
          accessibilityIdentifier: "topology.internet",
          isSelected: model.isInternetSelected,
          selectionOutlineSize: CGSize(width: 154, height: 148),
          statusColor: internetStatusColor,
          action: {
            presentInternetPopover()
          }
        )
        .overlay {
          Rectangle()
            .fill(Color.clear)
            .frame(width: 168, height: 190)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .popover(
              isPresented: internetPopoverBinding,
              arrowEdge: .trailing
            ) {
              InternetPopover()
                .environmentObject(model)
            }
        }

        if model.visibleTopologyDevices.isEmpty {
          Text("No AirPort base stations discovered")
            .font(.system(size: 14))
            .foregroundStyle(.white.opacity(0.78))
            .shadow(color: AirPortTopologyStyle.labelShadow, radius: 2, x: 0, y: 1)
            .frame(width: 240, height: 120)
        } else {
          VStack(spacing: 0) {
            TopologyRootConnector(
              rootCount: model.topologyTrees.count,
              rootSpacing: rootTreeSpacing
            )
            .frame(height: 42)
            .accessibilityHidden(true)
            HStack(alignment: .top, spacing: rootTreeSpacing) {
              ForEach(model.topologyTrees) { tree in
                TopologyTreeView(tree: tree, isCompact: hasTopologyHierarchy) { device in
                  presentBaseStationPopover(for: device)
                }
                .environmentObject(model)
              }
            }
            .frame(minWidth: topologyRootsWidth)
          }
        }
      }
      .padding(.top, 28)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    .frame(
      minWidth: topologyContentSize.width,
      maxWidth: .infinity,
      minHeight: topologyContentSize.height,
      maxHeight: .infinity)
  }

  private func baseStationAccessibilityTitle(for device: AirportDiscoveredDevice) -> String {
    "\(device.displayName) \(device.displayModelName) \(model.deviceStatusText(for: device))"
  }

  private var normalStatusColor: Color {
    Color(red: 0.29, green: 0.86, blue: 0.25)
  }

  private var updatingStatusColor: Color {
    Color(red: 1.0, green: 0.73, blue: 0.2)
  }

  private var inactiveStatusColor: Color {
    Color(red: 0.52, green: 0.55, blue: 0.58)
  }

  private var internetStatusColor: Color {
    model.isHostInternetConnected ? normalStatusColor : inactiveStatusColor
  }

  private var hasTopologyHierarchy: Bool {
    model.topologyTrees.contains(where: containsHierarchy)
  }

  private var rootTreeSpacing: CGFloat {
    AirPortMainWindowMetrics.topologyRootSpacing(forRootCount: model.topologyTrees.count)
  }

  private var topologyRootsWidth: CGFloat {
    AirPortMainWindowMetrics.topologyRootsWidth(forRootCount: model.topologyTrees.count)
  }

  private var topologyContentSize: CGSize {
    AirPortMainWindowMetrics.contentSize(
      forTopologyRootCount: model.topologyTrees.count,
      topologyDepth: model.topologyTreeDepth)
  }

  private func containsHierarchy(_ tree: AirportTopologyTree) -> Bool {
    !tree.children.isEmpty || tree.children.contains(where: containsHierarchy)
  }

  private func baseStationStatusColor(for device: AirportDiscoveredDevice) -> Color {
    let status = model.deviceStatusText(for: device)
    if model.isTopologyDeviceUpdating(device) || status == "Restarting" {
      return updatingStatusColor
    }
    return status == "Working normally" ? normalStatusColor : updatingStatusColor
  }

  private func presentInternetPopover() {
    model.isConnectionPopoverPresented = false
    model.selectInternetNode()
    model.refreshHostInternetSettings()
    model.isInternetPopoverPresented = true
  }

  private func presentBaseStationPopover(for device: AirportDiscoveredDevice) {
    model.isConnectionPopoverPresented = false
    model.selectTopologyDevice(device)
    if device.requiresSetup {
      model.beginSetup(for: device)
      return
    }
    model.loadInitialSettingsIfPossible()
    guard DevicePopoverPresentationPolicy.shouldPresentDeviceDetails() else { return }
    model.isDevicePopoverPresented = true
  }

  private func devicePopoverBinding(for device: AirportDiscoveredDevice) -> Binding<Bool> {
    Binding {
      model.isDevicePopoverPresented && model.selectedTopologyDeviceID == device.id
    } set: { isPresented in
      if !isPresented {
        model.isDevicePopoverPresented = false
        model.deselectTopologyDevice(device)
      }
    }
  }

  private var internetPopoverBinding: Binding<Bool> {
    Binding {
      model.isInternetPopoverPresented && model.isInternetSelected
    } set: { isPresented in
      if !isPresented {
        model.isInternetPopoverPresented = false
        model.deselectInternetNode()
      }
    }
  }

  private func presentConnectionPopover() {
    guard !model.isDevicePopoverPresented else {
      return
    }
    model.isConnectionPopoverPresented = true
  }
}

private struct TopologyTreeView: View {
  @EnvironmentObject private var model: AirportAppModel
  let tree: AirportTopologyTree
  let isCompact: Bool
  var present: (AirportDiscoveredDevice) -> Void

  var body: some View {
    VStack(spacing: 0) {
      deviceNode(tree.device)
      if !tree.children.isEmpty {
        TopologyChildrenConnector(
          wirelessConnections: tree.children.map {
            model.isWirelessTopologyConnection(from: $0.device, to: tree.device)
          },
          childSpacing: tree.children.count > 1 ? 42 : 24
        )
        .frame(maxWidth: .infinity)
        .frame(height: isCompact ? 24 : 44)
        .accessibilityHidden(true)
        HStack(alignment: .top, spacing: tree.children.count > 1 ? 42 : 24) {
          ForEach(tree.children) { child in
            TopologyTreeView(tree: child, isCompact: isCompact, present: present)
              .environmentObject(model)
          }
        }
      }
    }
  }

  private func deviceNode(_ device: AirportDiscoveredDevice) -> some View {
    TopologyNode(
      imageName: device.topologyImageName,
      title: device.displayName,
      subtitle: device.displayModelName,
      accessibilityTitle:
        "\(device.displayName) \(device.displayModelName) \(model.deviceStatusText(for: device))",
      accessibilityIdentifier: "topology.device.\(device.id)",
      imageFrameHeight: isCompact ? 72 : 120,
      imageOffsetY: isCompact ? 10 : 35,
      labelTopPadding: isCompact ? 0 : 19,
      nodeFrameHeight: isCompact ? 115 : 200,
      isSelected: model.selectedTopologyDeviceID == device.id,
      selectionOutlineSize: selectionOutlineSize(for: device.topologyImageName),
      statusColor: statusColor(for: device),
      badgeCount: model.firmwareUpdateBadgeCount(for: device),
      badgeText: device.requiresSetup ? "NEW" : nil,
      action: {
        present(device)
      }
    )
    .overlay {
      Rectangle()
        .fill(Color.clear)
        .frame(width: 168, height: 200)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .popover(
          isPresented: devicePopoverBinding(for: device),
          arrowEdge: .trailing
        ) {
          DevicePopover()
            .environmentObject(model)
        }
    }
  }

  private func selectionOutlineSize(for imageName: String) -> CGSize {
    if isCompact {
      switch imageName {
      case "AirPortExpress-3D-cropped~mac.tiff", "AirPort-8-3D-cropped~mac.tiff":
        return CGSize(width: 146, height: 70)
      default:
        return CGSize(width: 146, height: 62)
      }
    }

    switch imageName {
    case "AirPortExpress-3D-cropped~mac.tiff", "AirPort-8-3D-cropped~mac.tiff":
      return CGSize(width: 176, height: 100)
    case "AirPortEx-3D-cropped~mac.tiff":
      return CGSize(width: 176, height: 94)
    case "TimeCapsule-3D-cropped~mac.tiff", "AirPortExtremeN-3D-cropped~mac.tiff":
      return CGSize(width: 176, height: 82)
    default:
      return CGSize(width: 176, height: 94)
    }
  }

  private func devicePopoverBinding(for device: AirportDiscoveredDevice) -> Binding<Bool> {
    Binding {
      model.isDevicePopoverPresented && model.selectedTopologyDeviceID == device.id
    } set: { isPresented in
      if !isPresented {
        model.isDevicePopoverPresented = false
        model.deselectTopologyDevice(device)
      }
    }
  }

  private func statusColor(for device: AirportDiscoveredDevice) -> Color {
    let normal = Color(red: 0.29, green: 0.86, blue: 0.25)
    let warning = Color(red: 1.0, green: 0.73, blue: 0.2)
    let status = model.deviceStatusText(for: device)
    if model.isTopologyDeviceUpdating(device) || status == "Restarting" {
      return warning
    }
    return status == "Working normally" ? normal : warning
  }

}

private struct TopologyChildrenConnector: View {
  var wirelessConnections: [Bool]
  var childSpacing: CGFloat

  var body: some View {
    Canvas { context, size in
      guard !wirelessConnections.isEmpty else { return }
      let middleX = size.width / 2
      let middleY = size.height / 2
      let centerSpacing = AirPortTopologyStyle.rootColumnWidth + childSpacing
      let firstCenterX =
        middleX
        - CGFloat(wirelessConnections.count - 1) * centerSpacing / 2

      for (index, isWireless) in wirelessConnections.enumerated() {
        let childX = firstCenterX + CGFloat(index) * centerSpacing
        var path = Path()
        path.move(to: CGPoint(x: middleX, y: 0))
        path.addLine(to: CGPoint(x: middleX, y: middleY))
        path.addLine(to: CGPoint(x: childX, y: middleY))
        path.addLine(to: CGPoint(x: childX, y: size.height))
        context.stroke(
          path,
          with: .color(AirPortTopologyStyle.connector),
          style: StrokeStyle(
            lineWidth: 4,
            lineCap: .round,
            lineJoin: .round,
            dash: isWireless ? [1, 8] : []))
      }
    }
  }
}

private struct TopologyConnectorLine: View {
  enum Axis {
    case vertical
    case horizontal
  }

  var length: CGFloat
  var axis: Axis = .vertical

  var body: some View {
    RoundedRectangle(cornerRadius: 2)
      .fill(AirPortTopologyStyle.connector)
      .overlay(alignment: axis == .vertical ? .leading : .top) {
        RoundedRectangle(cornerRadius: 1)
          .fill(AirPortTopologyStyle.connectorHighlight)
          .frame(
            width: axis == .vertical ? 1 : nil,
            height: axis == .horizontal ? 1 : nil)
      }
      .frame(
        width: axis == .vertical ? 4 : length,
        height: axis == .vertical ? length : 4
      )
      .shadow(color: .black.opacity(0.22), radius: 1, x: 0, y: 1)
  }
}

private struct TopologyRootConnector: View {
  var rootCount: Int
  var rootSpacing: CGFloat

  private let rootWidth = AirPortTopologyStyle.rootColumnWidth
  private let lineWidth: CGFloat = 5

  var body: some View {
    TopologyRootConnectorShape(rootCount: rootCount, rootSpacing: rootSpacing, rootWidth: rootWidth)
      .stroke(
        AirPortTopologyStyle.connector,
        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
      )
      .overlay {
        TopologyRootConnectorShape(
          rootCount: rootCount, rootSpacing: rootSpacing, rootWidth: rootWidth
        )
        .stroke(
          AirPortTopologyStyle.connectorHighlight,
          style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round)
        )
        .offset(x: -1.2, y: -1.2)
      }
      .frame(width: connectorWidth)
      .shadow(color: .black.opacity(0.22), radius: 1, x: 0, y: 1)
  }

  private var connectorWidth: CGFloat {
    guard rootCount > 0 else { return rootWidth }
    return CGFloat(rootCount) * rootWidth + CGFloat(max(rootCount - 1, 0)) * rootSpacing
  }
}

private struct TopologyRootConnectorShape: Shape {
  var rootCount: Int
  var rootSpacing: CGFloat
  var rootWidth: CGFloat

  func path(in rect: CGRect) -> Path {
    var path = Path()
    guard rootCount > 0 else { return path }

    let rootStep = rootWidth + rootSpacing
    let firstCenterX = rect.minX + rootWidth / 2
    let lastCenterX = firstCenterX + CGFloat(rootCount - 1) * rootStep
    let centerX = (firstCenterX + lastCenterX) / 2
    let topY = rect.minY + 2
    let busY = rect.minY + 26
    let bottomY = rect.maxY
    let radius: CGFloat = 10

    if rootCount == 1 {
      path.move(to: CGPoint(x: centerX, y: topY))
      path.addLine(to: CGPoint(x: centerX, y: bottomY))
      return path
    }

    path.move(to: CGPoint(x: centerX, y: topY))
    path.addLine(to: CGPoint(x: centerX, y: busY - radius))
    path.addQuadCurve(
      to: CGPoint(x: centerX - radius, y: busY),
      control: CGPoint(x: centerX, y: busY))
    path.addLine(to: CGPoint(x: firstCenterX + radius, y: busY))
    path.addQuadCurve(
      to: CGPoint(x: firstCenterX, y: busY + radius),
      control: CGPoint(x: firstCenterX, y: busY))
    path.addLine(to: CGPoint(x: firstCenterX, y: bottomY))

    if rootCount > 1 {
      path.move(to: CGPoint(x: centerX, y: busY - radius))
      path.addQuadCurve(
        to: CGPoint(x: centerX + radius, y: busY),
        control: CGPoint(x: centerX, y: busY))
      path.addLine(to: CGPoint(x: lastCenterX - radius, y: busY))
      path.addQuadCurve(
        to: CGPoint(x: lastCenterX, y: busY + radius),
        control: CGPoint(x: lastCenterX, y: busY))
      path.addLine(to: CGPoint(x: lastCenterX, y: bottomY))
    }

    if rootCount > 2 {
      for index in 1..<(rootCount - 1) {
        let childCenterX = firstCenterX + CGFloat(index) * rootStep
        path.move(to: CGPoint(x: childCenterX, y: busY))
        path.addLine(to: CGPoint(x: childCenterX, y: bottomY))
      }
    }

    return path
  }
}

extension AirportDiscoveredDevice {
  var topologyImageName: String {
    switch productID.trimmingCharacters(in: .whitespacesAndNewlines) {
    case "102":
      return "AirPortExpress-3D-cropped~mac.tiff"
    case "107", "115":
      return "AirPortEx-3D-cropped~mac.tiff"
    case "106", "109", "113", "116":
      return "TimeCapsule-3D-cropped~mac.tiff"
    case "119", "120":
      return "AirPort-8-3D-cropped~mac.tiff"
    case "3":
      return "AirPortExtremeG-3D-cropped~mac.tiff"
    case "104", "105", "108", "114", "117":
      return "AirPortExtremeN-3D-cropped~mac.tiff"
    default:
      return topologyImageNameFromDisplayedText
    }
  }

  private var topologyImageNameFromDisplayedText: String {
    let text = "\(displayModelName) \(displayName)"
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    if text.contains("time capsule") {
      return "TimeCapsule-3D-cropped~mac.tiff"
    }
    if text.contains("express") {
      return "AirPortExpress-3D-cropped~mac.tiff"
    }
    if text.contains("extreme") {
      return "AirPortExtremeN-3D-cropped~mac.tiff"
    }
    return "GenericBase-3D-cropped~mac.tiff"
  }
}

enum DevicePopoverPresentationPolicy {
  static func shouldPresentDeviceDetails() -> Bool {
    true
  }

  static var connectionPromptMode: ConnectionPopover.Mode {
    .passwordOnly
  }
}

struct OtherWiFiDevicesMenu: NSViewRepresentable {
  static let title = "Other Wi-Fi Devices"
  static let connectTitle = "Connect to Base Station..."
  static let placeholderTitle = "No new Wi-Fi devices discovered"
  static let networkInterfacesTitle = "Network Interfaces"
  static let defaultNetworkInterface = "Ethernet 1"
  static let networkInterfaceTitles = ["Ethernet 1", "Wi-Fi"]

  var showConnectItem: Bool
  var devices: [AirportDiscoveredDevice]
  var selectedDeviceID: String?
  var selectedNetworkInterfaceTitle: String
  var onConnect: () -> Void
  var onSelectDeviceID: (String) -> Void
  var onSelectNetworkInterface: (String) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(
      onConnect: onConnect,
      onSelectDeviceID: onSelectDeviceID,
      onSelectNetworkInterface: onSelectNetworkInterface)
  }

  func makeNSView(context: Context) -> NSPopUpButton {
    let button = AirPortWiFiDevicesPopUpButton(
      frame: NSRect(x: 0, y: 0, width: 140, height: 22), pullsDown: true)
    context.coordinator.button = button
    button.target = context.coordinator
    button.action = #selector(Coordinator.selectPopUpButton(_:))
    button.controlSize = .regular
    button.bezelStyle = .rounded
    button.font = .systemFont(ofSize: 13)
    button.identifier = NSUserInterfaceItemIdentifier("topology.other.wifi.devices")
    button.setAccessibilityIdentifier("topology.other.wifi.devices")
    Self.configureButtonAppearance(button)
    button.menu = NSMenu()
    button.menu?.autoenablesItems = false
    button.setFrameSize(NSSize(width: 140, height: 22))
    Self.configure(
      button,
      showConnectItem: showConnectItem,
      devices: devices,
      selectedDeviceID: selectedDeviceID,
      selectedNetworkInterfaceTitle: selectedNetworkInterfaceTitle,
      target: context.coordinator)
    return button
  }

  func updateNSView(_ nsView: NSPopUpButton, context: Context) {
    context.coordinator.button = nsView
    context.coordinator.onConnect = onConnect
    context.coordinator.onSelectDeviceID = onSelectDeviceID
    context.coordinator.onSelectNetworkInterface = onSelectNetworkInterface
    Self.configureButtonAppearance(nsView)
    Self.configure(
      nsView,
      showConnectItem: showConnectItem,
      devices: devices,
      selectedDeviceID: selectedDeviceID,
      selectedNetworkInterfaceTitle: selectedNetworkInterfaceTitle,
      target: context.coordinator)
  }

  static func configureButtonAppearance(_ button: NSPopUpButton) {
    button.isEnabled = true
    button.title = title
    (button.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
  }

  static func configure(
    _ button: NSPopUpButton,
    showConnectItem: Bool,
    devices: [AirportDiscoveredDevice],
    selectedDeviceID: String?,
    selectedNetworkInterfaceTitle: String = defaultNetworkInterface,
    target: Coordinator? = nil
  ) {
    let menu = button.menu ?? NSMenu()
    menu.removeAllItems()
    menu.autoenablesItems = false

    menu.addItem(menuItem(title, enabled: true, target: target))
    if showConnectItem {
      menu.addItem(menuItem(connectTitle, enabled: true, target: target))
      menu.addItem(.separator())
    }

    if devices.isEmpty {
      menu.addItem(menuItem(placeholderTitle, enabled: false))
    } else {
      for device in devices {
        let item = menuItem(device.displayName, enabled: true, target: target)
        item.representedObject = device.id
        if device.id == selectedDeviceID {
          item.state = .on
        }
        menu.addItem(item)
      }
    }

    menu.addItem(.separator())
    menu.addItem(menuItem(networkInterfacesTitle, enabled: false))
    for title in networkInterfaceTitles {
      let item = menuItem(title, enabled: true, target: target)
      item.representedObject = NetworkInterfaceMenuSelection(title: title)
      if title == selectedNetworkInterfaceTitle {
        item.state = .on
      }
      menu.addItem(item)
    }
    menu.minimumWidth = 240
    button.menu = menu
    button.selectItem(at: 0)
    button.title = title
  }

  private static func menuItem(_ title: String, enabled: Bool, target: Coordinator? = nil)
    -> NSMenuItem
  {
    let item = NSMenuItem(
      title: title,
      action: enabled && target != nil ? #selector(Coordinator.selectMenuItem(_:)) : nil,
      keyEquivalent: "")
    item.isEnabled = enabled
    item.target = target
    return item
  }

  final class Coordinator: NSObject {
    weak var button: NSPopUpButton?
    var onConnect: () -> Void
    var onSelectDeviceID: (String) -> Void
    var onSelectNetworkInterface: (String) -> Void

    init(
      onConnect: @escaping () -> Void,
      onSelectDeviceID: @escaping (String) -> Void,
      onSelectNetworkInterface: @escaping (String) -> Void = { _ in }
    ) {
      self.onConnect = onConnect
      self.onSelectDeviceID = onSelectDeviceID
      self.onSelectNetworkInterface = onSelectNetworkInterface
    }

    @MainActor @objc func selectPopUpButton(_ sender: NSPopUpButton) {
      button = sender
      handleSelection(sender.selectedItem)
      resetSelection(on: sender)
    }

    @MainActor @objc func selectMenuItem(_ sender: NSMenuItem) {
      handleSelection(sender)
      if let button {
        resetSelection(on: button)
      }
    }

    @MainActor private func handleSelection(_ selectedItem: NSMenuItem?) {
      guard let selectedItem else { return }
      if selectedItem.title == OtherWiFiDevicesMenu.connectTitle {
        onConnect()
        return
      }
      if let deviceID = selectedItem.representedObject as? String {
        onSelectDeviceID(deviceID)
        return
      }
      if let selection = selectedItem.representedObject as? NetworkInterfaceMenuSelection {
        onSelectNetworkInterface(selection.title)
      }
    }

    @MainActor private func resetSelection(on button: NSPopUpButton) {
      button.selectItem(at: 0)
      button.title = OtherWiFiDevicesMenu.title
    }
  }

  struct NetworkInterfaceMenuSelection {
    var title: String
  }
}

private final class AirPortWiFiDevicesPopUpButton: NSPopUpButton {
  override var intrinsicContentSize: NSSize {
    NSSize(width: 140, height: 22)
  }

  override func accessibilityTitle() -> String? {
    "Other Wi-Fi Devices"
  }

  override func accessibilityLabel() -> String? {
    nil
  }

  override func accessibilityFrame() -> NSRect {
    let frame = super.accessibilityFrame()
    guard frame.height > 0 else {
      return frame
    }
    return NSRect(x: frame.minX, y: frame.minY - 1, width: frame.width, height: 22)
  }
}

struct TopologyBackground: View {
  var body: some View {
    ZStack {
      LinearGradient(
        colors: [
          Color(red: 0.20, green: 0.23, blue: 0.26),
          Color(red: 0.34, green: 0.38, blue: 0.42),
          Color(red: 0.48, green: 0.51, blue: 0.54),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
      LinearGradient(
        colors: [
          Color.white.opacity(0.08),
          Color.clear,
          Color.black.opacity(0.12),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
    }
  }
}

struct TopologyNode: View {
  var imageName: String
  var title: String
  var subtitle: String?
  var accessibilityTitle: String
  var accessibilityIdentifier: String?
  var imageFrameHeight: CGFloat = 160
  var imageOffsetY: CGFloat = 0
  var labelTopPadding: CGFloat = 0
  var nodeFrameHeight: CGFloat = 200
  var isSelected = false
  var selectionOutlineSize = CGSize(width: 156, height: 128)
  var statusColor = Color(red: 0.29, green: 0.86, blue: 0.25)
  var badgeCount = 0
  var badgeText: String?
  var action: (() -> Void)?

  var body: some View {
    ZStack {
      VStack(spacing: 4) {
        airPortResourceImage(
          named: imageName,
          fallbackSystemName: imageName.hasPrefix("Internet") ? "globe" : "wifi.router"
        )
        .resizable()
        .scaledToFit()
        .frame(width: 200, height: imageFrameHeight)
        .overlay {
          if isSelected {
            RoundedRectangle(cornerRadius: 8)
              .fill(Color.white.opacity(0.06))
              .overlay {
                RoundedRectangle(cornerRadius: 8)
                  .stroke(AirPortTopologyStyle.selectedStroke, lineWidth: 2)
              }
              .shadow(color: AirPortTopologyStyle.selectedGlow, radius: 8, x: 0, y: 3)
              .frame(width: selectionOutlineSize.width, height: selectionOutlineSize.height)
              .allowsHitTesting(false)
              .accessibilityHidden(true)
          }
        }
        .offset(y: imageOffsetY)
        if labelTopPadding > 0 {
          Spacer()
            .frame(height: labelTopPadding)
        }
        HStack(spacing: 7) {
          Circle()
            .fill(
              RadialGradient(
                colors: [Color.white.opacity(0.72), statusColor, statusColor.opacity(0.74)],
                center: .topLeading,
                startRadius: 1,
                endRadius: 7)
            )
            .frame(width: 12, height: 12)
            .overlay {
              Circle()
                .stroke(Color.black.opacity(0.34), lineWidth: 1)
            }
            .shadow(color: statusColor.opacity(0.42), radius: 3, x: 0, y: 0)
          Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .layoutPriority(1)
          if badgeCount > 0 {
            Text("\(badgeCount)")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(.white)
              .monospacedDigit()
              .frame(width: 22, height: 22)
              .background {
                Circle()
                  .fill(Color(red: 1.0, green: 0.22, blue: 0.18))
                  .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
              }
              .accessibilityHidden(true)
          }
          if let badgeText, !badgeText.isEmpty {
            Text(badgeText)
              .font(.system(size: 10, weight: .bold))
              .foregroundStyle(.white)
              .frame(width: 34, height: 18)
              .background {
                Capsule()
                  .fill(Color(red: 1.0, green: 0.73, blue: 0.2))
                  .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
              }
              .accessibilityHidden(true)
          }
        }
        .frame(width: 184)
        .shadow(color: AirPortTopologyStyle.labelShadow, radius: 2, x: 0, y: 1)
        if let subtitle {
          Text(subtitle)
            .font(.system(size: 14))
            .foregroundStyle(.white.opacity(0.64))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: 184)
            .shadow(color: AirPortTopologyStyle.labelShadow, radius: 2, x: 0, y: 1)
        }
      }
      .frame(width: 200, height: nodeFrameHeight, alignment: .top)
      .accessibilityHidden(true)

      TopologyNodeAccessibilityProxy(
        label: accessibilityTitle, identifier: accessibilityIdentifier, action: action
      )
      .frame(width: 200, height: nodeFrameHeight)
    }
  }
}

private struct TopologyNodeAccessibilityProxy: NSViewRepresentable {
  var label: String
  var identifier: String?
  var action: (() -> Void)?

  func makeNSView(context: Context) -> TopologyNodeAccessibilityView {
    let view = TopologyNodeAccessibilityView()
    view.label = label
    view.identifier = identifier.map { NSUserInterfaceItemIdentifier($0) }
    view.onPress = action
    return view
  }

  func updateNSView(_ nsView: TopologyNodeAccessibilityView, context: Context) {
    nsView.label = label
    nsView.identifier = identifier.map { NSUserInterfaceItemIdentifier($0) }
    nsView.onPress = action
  }
}

private final class TopologyNodeAccessibilityView: NSView {
  var label = ""
  var onPress: (() -> Void)?

  override func hitTest(_ point: NSPoint) -> NSView? {
    self
  }

  override func isAccessibilityElement() -> Bool {
    true
  }

  override func accessibilityRole() -> NSAccessibility.Role? {
    .image
  }

  override func accessibilityTitle() -> String? {
    label
  }

  override func isAccessibilityEnabled() -> Bool {
    true
  }

  override func accessibilityActionNames() -> [NSAccessibility.Action] {
    [.press]
  }

  override func accessibilityPerformPress() -> Bool {
    guard let onPress else {
      return false
    }
    DispatchQueue.main.async {
      onPress()
    }
    return true
  }

  override func mouseDown(with event: NSEvent) {
    onPress?()
  }
}
