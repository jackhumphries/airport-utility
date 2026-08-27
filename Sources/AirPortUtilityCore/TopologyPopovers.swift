import AppKit
import SwiftUI

enum DevicePopoverLayout {
  static let rowHeight: CGFloat = 17.5
  static let minimumDetailsHeight: CGFloat = 107
  static let maximumDetailsHeight: CGFloat = 280

  static func detailsContentHeight(
    detailRowCount: Int,
    wirelessClientCount: Int
  ) -> CGFloat {
    max(
      minimumDetailsHeight,
      CGFloat(detailRowCount + wirelessClientCount) * rowHeight + 2)
  }

  static func detailsViewportHeight(
    detailRowCount: Int,
    wirelessClientCount: Int
  ) -> CGFloat {
    min(
      detailsContentHeight(
        detailRowCount: detailRowCount,
        wirelessClientCount: wirelessClientCount),
      maximumDetailsHeight)
  }
}

struct DevicePopover: View {
  @EnvironmentObject private var model: AirportAppModel

  var body: some View {
    if model.shouldShowDeviceLoading {
      DeviceLoadingPopover()
    } else if model.shouldShowDeviceConnectionPrompt {
      ConnectionPopover(mode: DevicePopoverPresentationPolicy.connectionPromptMode)
    } else {
      deviceDetails
    }
  }

  private var deviceDetails: some View {
    VStack(alignment: .leading, spacing: 0) {
      PopoverTitleLabel(
        text: model.baseStation.name.isEmpty ? "time capsule" : model.baseStation.name
      )
      .frame(width: 303, height: 19)
      .padding(.bottom, 6)
      PopoverDetailsRows(
        rows: deviceDetailRows,
        wirelessClients: model.wirelessClients,
        viewportHeight: deviceDetailsHeight)
        .frame(width: 294, height: deviceDetailsHeight)
      HStack {
        Spacer()
        PopoverEditButton {
          if model.selectedDeviceFirmwareUpdateBadgeCount > 0 {
            model.beginEditingFirmware()
          } else {
            model.beginEditing()
          }
        }
        .fixedSize()
        .frame(height: 18)
      }
      .padding(.top, 7)
    }
    .padding(13)
    .frame(width: 320, height: devicePopoverHeight, alignment: .leading)
  }

  private var deviceDetailRows: [(String, String)] {
    var rows = [
      (localized("status"), model.selectedDeviceStatusText()),
      (localized("network"), model.wireless.networkName),
      (localized("IP address"), model.internet.ipv4Address),
      (localized("LAN IP address"), model.network.lanIPAddress),
      (localized("serial number"), model.baseStation.serialNumber),
      (localized("version"), model.baseStation.version),
    ]
    let protocols = model.selectedTopologyDevice()?.publishedProtocols ?? []
    if !protocols.isEmpty {
      // Omitted when the device advertises nothing, matching how the popover
      // already leaves out values it does not have.
      rows.append((localized("file sharing"), protocols.joined(separator: " · ")))
    }
    let firmwareUpdate = model.selectedDeviceFirmwareUpdateDetail
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if !firmwareUpdate.isEmpty {
      rows.insert((localized("firmware update"), firmwareUpdate), at: 1)
    }
    let statusDetails = model.selectedDeviceStatusDetails()
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    for detail in statusDetails.reversed() {
      rows.insert(("detail", detail), at: firmwareUpdate.isEmpty ? 1 : 2)
    }
    return rows
  }

  private var deviceDetailsHeight: CGFloat {
    DevicePopoverLayout.detailsViewportHeight(
      detailRowCount: deviceDetailRows.count,
      wirelessClientCount: model.wirelessClients.count)
  }

  private var devicePopoverHeight: CGFloat {
    deviceDetailsHeight + 69
  }
}

struct DeviceLoadingPopover: View {
  @EnvironmentObject private var model: AirportAppModel

  var body: some View {
    SettingsLoadingPopover(
      title:
        model.hasLoadedSettings && !model.hasLoadedWirelessClients
        ? localized("Loading Wireless Clients")
        : localized("Connecting to Base Station"))
  }
}

private struct InternetLoadingPopover: View {
  var body: some View {
    SettingsLoadingPopover(title: localized("Loading Internet Settings"))
  }
}

private struct SettingsLoadingPopover: View {
  @EnvironmentObject private var model: AirportAppModel
  let title: String

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title)
        .font(.system(size: 13, weight: .semibold))
      HStack(spacing: 10) {
        ProgressView()
          .controlSize(.small)
        Text(model.status)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
    }
    .padding(14)
    .frame(width: 277, alignment: .leading)
  }
}

struct InternetPopover: View {
  @EnvironmentObject private var model: AirportAppModel

  var body: some View {
    if model.shouldShowInternetLoading {
      InternetLoadingPopover()
    } else {
      internetDetails
    }
  }

  private var internetDetails: some View {
    VStack(alignment: .leading, spacing: 0) {
      PopoverTitleLabel(text: "Internet")
        .frame(width: 303, height: 19)
        .padding(.bottom, 6)
      PopoverDetailsRows(
        rows: [
          ("connection", model.internetPopoverConnectionStatus),
          (localized("router address"), model.hostInternet.routerAddress),
          (localized("DNS servers"), model.hostInternet.dnsServers),
        ])
        .frame(width: 274, height: 54)
    }
    .padding(13)
    .frame(width: 300, height: 92, alignment: .leading)
  }
}

private struct PopoverTitleLabel: NSViewRepresentable {
  var text: String

  func makeNSView(context: Context) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.frame = NSRect(x: 0, y: 0, width: 283, height: 19)
    field.alignment = .center
    field.font = .systemFont(ofSize: 16, weight: .semibold)
    field.textColor = .labelColor
    field.lineBreakMode = .byTruncatingTail
    field.drawsBackground = false
    field.isBezeled = false
    field.isEditable = false
    field.isSelectable = false
    return field
  }

  func updateNSView(_ field: NSTextField, context: Context) {
    field.stringValue = text
  }
}

private struct PopoverDetailsRows: NSViewRepresentable {
  var rows: [(String, String)]
  var wirelessClients: [WirelessClient] = []
  var viewportHeight: CGFloat = DevicePopoverLayout.minimumDetailsHeight

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = PopoverDetailsScrollView(
      frame: NSRect(x: 0, y: 0, width: 294, height: viewportHeight))
    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder
    scrollView.hasVerticalScroller = false
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.scrollerStyle = .overlay
    scrollView.documentView = PopoverDetailsDocumentView()
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    let documentView: PopoverDetailsDocumentView
    if let existingDocumentView = scrollView.documentView as? PopoverDetailsDocumentView {
      documentView = existingDocumentView
    } else {
      documentView = PopoverDetailsDocumentView()
      scrollView.documentView = documentView
    }
    documentView.configure(rows: rows, wirelessClients: wirelessClients)
    let contentHeight = DevicePopoverLayout.detailsContentHeight(
      detailRowCount: rows.count,
      wirelessClientCount: wirelessClients.count)
    scrollView.hasVerticalScroller = contentHeight > viewportHeight
  }
}

private final class PopoverDetailsDocumentView: NSView {
  private var renderedLayoutContent: [String] = []
  private var wirelessClientFields: [String: WirelessClientHoverField] = [:]
  private let wirelessClientDetailsPanel = WirelessClientDetailsPanelController()
  private var presentedWirelessClientID: String?

  override var isFlipped: Bool {
    true
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    self.frame = NSRect(x: 0, y: 0, width: 294, height: 107)
    wirelessClientDetailsPanel.presentationDidEnd = {
      [weak self] clientID in
      self?.wirelessClientPresentationDidEnd(clientID: clientID)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  func configure(rows: [(String, String)], wirelessClients: [WirelessClient]) {
    frame.size.height = DevicePopoverLayout.detailsContentHeight(
      detailRowCount: rows.count,
      wirelessClientCount: wirelessClients.count)
    let layoutContent =
      rows.flatMap { [$0.0, $0.1] }
      + ["\u{0}wireless-clients"]
      + wirelessClients.flatMap { [$0.id, $0.displayName] }
    guard layoutContent != renderedLayoutContent else {
      updateWirelessClients(wirelessClients)
      return
    }
    renderedLayoutContent = layoutContent
    subviews.forEach { $0.removeFromSuperview() }
    wirelessClientFields.removeAll()

    for (index, row) in rows.enumerated() {
      let y = CGFloat(index) * DevicePopoverLayout.rowHeight
      addSubview(textField(row.0, frame: NSRect(x: 0, y: y, width: 108, height: 19), label: true))
      addSubview(
        textField(
          row.1.isEmpty ? "--" : row.1,
          frame: NSRect(x: 122, y: y, width: 172, height: 19),
          label: false))
    }

    guard !wirelessClients.isEmpty else { return }
    let y = CGFloat(rows.count) * DevicePopoverLayout.rowHeight
    addSubview(
      textField(
        localized("wireless clients"),
        frame: NSRect(x: 0, y: y, width: 108, height: 19),
        label: true))
    for (index, client) in wirelessClients.enumerated() {
      let clientField = WirelessClientHoverField(
        client: client,
        frame: NSRect(
          x: 122,
          y: y + CGFloat(index) * DevicePopoverLayout.rowHeight,
          width: 172,
          height: 19))
      clientField.setAccessibilityIdentifier("popover.wirelessClients.client")
      clientField.presentationChanged = {
        [weak self] field, shouldPresent, immediately in
        self?.wirelessClientPresentationChanged(
          field: field,
          shouldPresent: shouldPresent,
          immediately: immediately)
      }
      wirelessClientFields[client.id] = clientField
      addSubview(clientField)
    }
    updateWirelessClients(wirelessClients)
  }

  fileprivate func hideWirelessClientHoverPanel() {
    presentedWirelessClientID = nil
    wirelessClientDetailsPanel.hide()
  }

  override func viewWillMove(toWindow newWindow: NSWindow?) {
    if newWindow == nil {
      hideWirelessClientHoverPanel()
    }
    super.viewWillMove(toWindow: newWindow)
  }

  private func updateWirelessClients(_ wirelessClients: [WirelessClient]) {
    let clientsByID = Dictionary(
      uniqueKeysWithValues: wirelessClients.map { ($0.id, $0) })
    for (id, field) in wirelessClientFields {
      if let client = clientsByID[id] {
        field.client = client
      }
    }
    guard let presentedWirelessClientID else { return }
    guard let client = clientsByID[presentedWirelessClientID] else {
      hideWirelessClientHoverPanel()
      return
    }
    wirelessClientDetailsPanel.update(client: client)
  }

  private func wirelessClientPresentationChanged(
    field: WirelessClientHoverField,
    shouldPresent: Bool,
    immediately: Bool
  ) {
    if shouldPresent {
      presentedWirelessClientID = field.client.id
      if immediately {
        wirelessClientDetailsPanel.presentImmediately(
          client: field.client,
          from: field)
      } else {
        wirelessClientDetailsPanel.schedule(
          client: field.client,
          from: field)
      }
    } else if presentedWirelessClientID == field.client.id {
      if immediately {
        hideWirelessClientHoverPanel()
      } else {
        wirelessClientDetailsPanel.dismissAfterGracePeriod()
      }
    }
  }

  private func wirelessClientPresentationDidEnd(clientID: String) {
    wirelessClientFields[clientID]?.detailsPresentationDidEnd()
    if presentedWirelessClientID == clientID {
      presentedWirelessClientID = nil
    }
  }

  private func textField(_ text: String, frame: NSRect, label: Bool) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.frame = frame
    field.toolTip = text
    field.alignment = label ? .right : .left
    field.font = .systemFont(ofSize: 13, weight: .semibold)
    field.textColor = label ? .secondaryLabelColor : .labelColor
    field.lineBreakMode = .byTruncatingTail
    field.drawsBackground = false
    field.isBezeled = false
    field.isEditable = false
    field.isSelectable = false
    return field
  }
}

private final class PopoverDetailsScrollView: NSScrollView {
  override func reflectScrolledClipView(_ cView: NSClipView) {
    super.reflectScrolledClipView(cView)
    (documentView as? PopoverDetailsDocumentView)?
      .hideWirelessClientHoverPanel()
  }

  override func viewWillMove(toWindow newWindow: NSWindow?) {
    if newWindow == nil {
      (documentView as? PopoverDetailsDocumentView)?
        .hideWirelessClientHoverPanel()
    }
    super.viewWillMove(toWindow: newWindow)
  }
}

private struct PopoverEditButton: NSViewRepresentable {
  var action: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(action: action)
  }

  func makeNSView(context: Context) -> NSButton {
    let button = PopoverEditNSButton(
      title: localized("Edit"), target: context.coordinator, action: #selector(Coordinator.press))
    button.bezelStyle = .rounded
    button.controlSize = .small
    button.font = .systemFont(ofSize: 13)
    button.setButtonType(.momentaryPushIn)
    button.identifier = NSUserInterfaceItemIdentifier("topology.device.popover.edit")
    button.setAccessibilityIdentifier("topology.device.popover.edit")
    return button
  }

  func updateNSView(_ nsView: NSButton, context: Context) {
    context.coordinator.action = action
    nsView.target = context.coordinator
    nsView.action = #selector(Coordinator.press)
    nsView.identifier = NSUserInterfaceItemIdentifier("topology.device.popover.edit")
    nsView.setAccessibilityIdentifier("topology.device.popover.edit")
  }

  final class Coordinator: NSObject {
    var action: () -> Void

    init(action: @escaping () -> Void) {
      self.action = action
    }

    @MainActor @objc func press() {
      action()
    }
  }
}

private final class PopoverEditNSButton: NSButton {
  /// 47pt is the measured English width. A longer translation ("Modifier",
  /// "Bearbeiten") needs more, and the button is right-aligned behind a Spacer,
  /// so growing widens it leftward without disturbing anything.
  override var intrinsicContentSize: NSSize {
    NSSize(width: max(47, super.intrinsicContentSize.width), height: 18)
  }
}

struct ConnectionPopover: View {
  enum Mode {
    case full
    case passwordOnly
  }

  @EnvironmentObject private var model: AirportAppModel
  var mode: Mode = .full

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(localized("Connect to Base Station"))
        .font(.system(size: 13, weight: .semibold))
      if mode == .full {
        AirPortTextField(
          text: $model.connection.host,
          placeholder: localized("Host"),
          identifier: "connection.popover.host")
          .frame(width: 220, height: 24)
      }
      AirPortSecureField(
        text: $model.connection.password,
        placeholder: localized("Password"),
        identifier: "connection.popover.password",
        onSubmit: submitConnection)
        .frame(width: 220, height: 24)
      if mode == .passwordOnly {
        Toggle(
          localized("Remember this password in my keychain"),
          isOn: Binding(
            get: { model.rememberConnectionPassword },
            set: { model.updateRememberConnectionPassword($0) }))
          .toggleStyle(.checkbox)
          .font(.system(size: 12))
          .accessibilityIdentifier("connection.popover.remember.password")
      }
      if mode == .full && !model.mockMode {
        AirPortTextField(
          text: $model.connection.repoPath,
          placeholder: localized("Repo"),
          identifier: "connection.popover.repository")
          .frame(width: 220, height: 24)
      }
      HStack {
        Spacer()
        Button(model.isBusy ? localized("Working") : localized("Connect")) {
          submitConnection()
        }
        .accessibilityLabel(localized("Connect"))
        .accessibilityIdentifier("connection.popover.connect")
        .keyboardShortcut(.defaultAction)
        .disabled(!model.canAttemptConnection)
      }
      // model.status is "Connected to <host>", which interpolates the host and
      // is therefore still English. Do not localize this prefix without also
      // localizing the status it is matching.
      if !model.status.hasPrefix("Connected") {
        Text(model.status)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(14)
    .onAppear {
      model.prefillConnectionPasswordFromEnvironmentIfNeeded()
    }
  }

  private func submitConnection() {
    guard model.canAttemptConnection else { return }
    model.refresh()
  }
}
