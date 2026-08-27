import AppKit
import SwiftUI

struct NetworkOptionsSheet: View {
  @EnvironmentObject private var model: AirportAppModel
  @Environment(\.dismiss) private var dismiss
  @State private var draft = NetworkState()
  @State private var legacyDraft = LegacyDHCPOptionsState()
  @State private var dhcpRangePrefix = "10.0"
  @State private var dhcpRangeSubnet = "1"
  @State private var dhcpRangeStartHost = "2"
  @State private var dhcpRangeEndHost = "200"
  @State private var defaultHostEnabled = false
  @State private var loaded = false

  var body: some View {
    ZStack(alignment: .topLeading) {
      Text(localized("Network Options"))
        .font(.system(size: 13, weight: .semibold))
        .frame(width: 150, height: 20, alignment: .leading)
        .offset(x: 18, y: 10)
      Divider()
        .frame(width: 471)
        .offset(x: 20, y: 42)

      optionLabel(localized("DHCP Lease:"), width: 190)
        .offset(x: 19, y: 50)
      NetworkOptionsTextField(
        text: $draft.dhcpLease,
        selectOnAppear: true,
        identifier: "network.options.dhcp.lease")
        .frame(width: 126)
        .offset(x: 213, y: 50)
      Picker("", selection: $draft.dhcpLeaseUnit) {
        ForEach(DHCPLeaseUnitOption.allCases) { option in
          Text(option.label).tag(option.value)
        }
      }
      .pickerStyle(.menu)
      .labelsHidden()
      .accessibilityIdentifier("network.options.dhcp.lease.unit")
      .frame(width: 143, height: 23)
      .offset(x: 347, y: 49)

      optionLabel(localized("IPv4 DHCP Range:"), width: 190)
        .offset(x: 19, y: 83)
      Picker("", selection: $dhcpRangePrefix) {
        Text("10.0").tag("10.0")
        Text("172.16").tag("172.16")
        Text("192.168").tag("192.168")
      }
      .pickerStyle(.menu)
      .labelsHidden()
      .accessibilityIdentifier("network.options.dhcp.range.prefix")
      .frame(width: 95, height: 23)
      .offset(x: 214, y: 82)
      Text(".")
        .font(.system(size: 13))
        .frame(width: 11, height: 19)
        .offset(x: 313, y: 85)
      NetworkOptionsTextField(
        text: $dhcpRangeSubnet,
        identifier: "network.options.dhcp.range.subnet")
        .frame(width: 43)
        .offset(x: 324, y: 83)
      Text(".")
        .font(.system(size: 13))
        .frame(width: 11, height: 19)
        .offset(x: 369, y: 85)
      NetworkOptionsTextField(
        text: $dhcpRangeStartHost,
        identifier: "network.options.dhcp.range.start.host")
        .frame(width: 43)
        .offset(x: 382, y: 83)
      Text("to")
        .font(.system(size: 13))
        .frame(width: 19, height: 19)
        .offset(x: 426, y: 85)
      NetworkOptionsTextField(
        text: $dhcpRangeEndHost,
        identifier: "network.options.dhcp.range.end.host")
        .frame(width: 43)
        .offset(x: 448, y: 83)

      if model.capabilities.supportsLegacyDHCPOptions {
        optionLabel(localized("DHCP Message:"), width: 190)
          .offset(x: 19, y: 116)
        NetworkOptionsTextField(
          text: $legacyDraft.message,
          identifier: "network.options.dhcp.message")
          .frame(width: 279)
          .offset(x: 211, y: 115)

        optionLabel(localized("LDAP Server:"), width: 190)
          .offset(x: 19, y: 147)
        NetworkOptionsTextField(
          text: $legacyDraft.ldapServer,
          identifier: "network.options.ldap.server")
          .frame(width: 279)
          .offset(x: 211, y: 146)
      }

      NetworkOptionsCheckbox(
        localized("Enable NAT Port Mapping Protocol"),
        isOn: $draft.natPMP,
        identifier: "network.options.nat.pmp"
      )
      .frame(width: 247, height: 18, alignment: .leading)
      .offset(x: 212, y: 149 + legacyVerticalOffset)

      NetworkOptionsCheckbox(
        localized("Enable default host at:"),
        isOn: $defaultHostEnabled,
        identifier: "network.options.default.host.enabled")
        .frame(width: 164, height: 18, alignment: .leading)
        .offset(x: 45, y: 175 + legacyVerticalOffset)
      NetworkOptionsTextField(
        text: $draft.defaultHost,
        identifier: "network.options.default.host")
        .frame(width: 279, height: 24)
        .disabled(!defaultHostEnabled)
        .opacity(defaultHostEnabled ? 1 : 0.58)
        .offset(x: 211, y: 172 + legacyVerticalOffset)

      // Right-anchored rather than fixed x offsets: a wider translated label
      // ("Abbrechen") would otherwise grow rightward into the Save button.
      // The trailing edge and 12pt gap reproduce the English layout exactly.
      HStack(spacing: 12) {
        NetworkOptionsButton(localized("Cancel"), identifier: "network.options.cancel") {
          dismiss()
        }
        .frame(width: 70, height: 22)
        NetworkOptionsButton(
        localized("Save"), isDefault: true, isEnabled: canSave,
        identifier: "network.options.save"
      ) {
        guard applyDHCPRange() else { return }
        if !defaultHostEnabled {
          draft.defaultHost = ""
        }
        model.network = draft
        if model.capabilities.supportsLegacyDHCPOptions {
          model.legacyDeviceOptions.dhcp = legacyDraft
        }
        dismiss()
      }
        .frame(width: 70, height: 22)
      }
      .frame(width: 491, alignment: .trailing)
      .offset(x: 0, y: 220 + legacyVerticalOffset)
    }
    .onAppear {
      if !loaded {
        draft = model.network
        legacyDraft = model.legacyDeviceOptions.dhcp
        loadDHCPRangeFields(from: draft)
        defaultHostEnabled = !draft.defaultHost.trimmingCharacters(in: .whitespacesAndNewlines)
          .isEmpty
        loaded = true
      }
    }
    .frame(width: 511, height: 264 + legacyVerticalOffset, alignment: .topLeading)
    .background(AirPortSheetBackground())
  }

  private var legacyVerticalOffset: CGFloat {
    model.capabilities.supportsLegacyDHCPOptions ? 65 : 0
  }

  private func optionLabel(_ title: String, width: CGFloat) -> some View {
    Text(title)
      .font(.system(size: 13))
      .frame(width: width, height: 20, alignment: .trailing)
  }

  private func loadDHCPRangeFields(from network: NetworkState) {
    guard
      let fields = DHCPRangeFields.fields(
        start: network.dhcpRangeStart,
        end: network.dhcpRangeEnd)
    else { return }
    dhcpRangePrefix = fields.prefix
    dhcpRangeSubnet = fields.subnet
    dhcpRangeStartHost = fields.startHost
    dhcpRangeEndHost = fields.endHost
  }

  private var canSave: Bool {
    Self.canSave(
      dhcpRangePrefix: dhcpRangePrefix,
      dhcpRangeSubnet: dhcpRangeSubnet,
      dhcpRangeStartHost: dhcpRangeStartHost,
      dhcpRangeEndHost: dhcpRangeEndHost)
  }

  nonisolated static func canSave(
    dhcpRangePrefix: String,
    dhcpRangeSubnet: String,
    dhcpRangeStartHost: String,
    dhcpRangeEndHost: String
  ) -> Bool {
    DHCPRangeFields.range(
      prefix: dhcpRangePrefix,
      subnet: dhcpRangeSubnet,
      startHost: dhcpRangeStartHost,
      endHost: dhcpRangeEndHost) != nil
  }

  @discardableResult
  private func applyDHCPRange() -> Bool {
    guard
      let range = DHCPRangeFields.range(
        prefix: dhcpRangePrefix,
        subnet: dhcpRangeSubnet,
        startHost: dhcpRangeStartHost,
        endHost: dhcpRangeEndHost)
    else { return false }
    draft.dhcpRangeStart = range.start
    draft.dhcpRangeEnd = range.end
    return true
  }
}

enum DHCPRangeFields {
  static let supportedPrefixes: Set<String> = ["10.0", "172.16", "192.168"]

  static func fields(start: String, end: String) -> (
    prefix: String, subnet: String, startHost: String, endHost: String
  )? {
    let startParts = start.split(separator: ".", omittingEmptySubsequences: false).map {
      String($0).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    let endParts = end.split(separator: ".", omittingEmptySubsequences: false).map {
      String($0).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard startParts.count == 4, endParts.count == 4 else { return nil }
    let prefix = "\(startParts[0]).\(startParts[1])"
    guard supportedPrefixes.contains(prefix),
      prefix == "\(endParts[0]).\(endParts[1])",
      startParts[2] == endParts[2],
      isOctet(startParts[2]),
      isOctet(startParts[3]),
      isOctet(endParts[3]),
      hostOrderIsValid(startParts[3], endParts[3])
    else { return nil }
    return (prefix, startParts[2], startParts[3], endParts[3])
  }

  static func range(prefix: String, subnet: String, startHost: String, endHost: String) -> (
    start: String, end: String
  )? {
    let prefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
    let subnet = subnet.trimmingCharacters(in: .whitespacesAndNewlines)
    let startHost = startHost.trimmingCharacters(in: .whitespacesAndNewlines)
    let endHost = endHost.trimmingCharacters(in: .whitespacesAndNewlines)
    guard supportedPrefixes.contains(prefix),
      isOctet(subnet),
      isOctet(startHost),
      isOctet(endHost),
      hostOrderIsValid(startHost, endHost)
    else { return nil }
    return (
      start: "\(prefix).\(subnet).\(startHost)",
      end: "\(prefix).\(subnet).\(endHost)"
    )
  }

  private static func isOctet(_ value: String) -> Bool {
    !value.isEmpty && value.allSatisfy(\.isNumber) && UInt8(value) != nil
  }

  private static func hostOrderIsValid(_ startHost: String, _ endHost: String) -> Bool {
    guard let start = UInt8(startHost), let end = UInt8(endHost) else { return false }
    return start <= end
  }
}

struct NetworkOptionsTextField: NSViewRepresentable {
  @Environment(\.isEnabled) private var isEnabled

  @Binding var text: String
  var selectOnAppear = false
  var identifier: String?

  func makeNSView(context: Context) -> NSTextField {
    let textField = NetworkOptionsNSTextField(string: text)
    textField.delegate = context.coordinator
    configure(textField)
    return textField
  }

  func updateNSView(_ textField: NSTextField, context: Context) {
    context.coordinator.parent = self
    configure(textField)
    guard selectOnAppear, !context.coordinator.didSelectOnAppear else { return }
    context.coordinator.didSelectOnAppear = true
    DispatchQueue.main.async {
      textField.window?.makeFirstResponder(textField)
      textField.currentEditor()?.selectAll(nil)
    }
  }

  private func configure(_ textField: NSTextField) {
    textField.isEnabled = isEnabled
    textField.identifier = NSUserInterfaceItemIdentifier(identifier ?? "_NS:ID")
    textField.setAccessibilityIdentifier(identifier)
    if textField.stringValue != text {
      textField.stringValue = text
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  final class Coordinator: NSObject, NSTextFieldDelegate {
    var parent: NetworkOptionsTextField
    var didSelectOnAppear = false

    init(parent: NetworkOptionsTextField) {
      self.parent = parent
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
      guard let textField = notification.object as? NetworkOptionsNSTextField else { return }
      textField.isFieldFocused = true
    }

    func controlTextDidEndEditing(_ notification: Notification) {
      guard let textField = notification.object as? NetworkOptionsNSTextField else { return }
      textField.isFieldFocused = false
    }

    func controlTextDidChange(_ notification: Notification) {
      guard let textField = notification.object as? NSTextField else { return }
      parent.text = textField.stringValue
    }
  }
}

private final class NetworkOptionsNSTextField: NSTextField {
  override var intrinsicContentSize: NSSize {
    NSSize(width: NSView.noIntrinsicMetric, height: 24)
  }

  var isFieldFocused = false {
    didSet { needsDisplay = true }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    configure()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configure()
  }

  private func configure() {
    isBezeled = false
    drawsBackground = false
    focusRingType = .none
    font = .systemFont(ofSize: 13)
    textColor = .labelColor
    lineBreakMode = .byClipping
    let textCell = NetworkOptionsTextFieldCell(textCell: stringValue)
    textCell.font = .systemFont(ofSize: 13)
    textCell.textColor = .labelColor
    textCell.isScrollable = true
    textCell.usesSingleLineMode = true
    cell = textCell
  }

  override func draw(_ dirtyRect: NSRect) {
    let background = NSGradient(colors: [
      NSColor(red: 0.32, green: 0.30, blue: 0.33, alpha: 1),
      NSColor(red: 0.25, green: 0.24, blue: 0.27, alpha: 1),
    ])
    background?.draw(in: bounds, angle: -90)

    NSColor.black.withAlphaComponent(0.36).setStroke()
    NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)).stroke()
    NSColor.white.withAlphaComponent(0.10).setStroke()
    NSBezierPath(rect: bounds.insetBy(dx: 1.5, dy: 1.5)).stroke()
    super.draw(dirtyRect)

    if isFieldFocused {
      let ring = NSBezierPath(
        roundedRect: bounds.insetBy(dx: 1, dy: 1),
        xRadius: 3,
        yRadius: 3)
      ring.lineWidth = 3
      NSColor.controlAccentColor.setStroke()
      ring.stroke()
    }
  }
}

private final class NetworkOptionsTextFieldCell: NSTextFieldCell {
  override func drawingRect(forBounds rect: NSRect) -> NSRect {
    let horizontalInset: CGFloat = 7
    let availableHeight = max(0, rect.height - 4)
    let textHeight = min(ceil(cellSize(forBounds: rect).height), availableHeight)
    let originY = rect.midY - textHeight / 2
    return NSRect(
      x: rect.minX + horizontalInset,
      y: originY,
      width: max(0, rect.width - horizontalInset * 2),
      height: max(0, textHeight))
  }

  override func edit(
    withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?,
    event: NSEvent?
  ) {
    super.edit(
      withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate,
      event: event)
  }

  override func select(
    withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?,
    start selStart: Int, length selLength: Int
  ) {
    super.select(
      withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate,
      start: selStart, length: selLength)
  }
}

private struct NetworkOptionsCheckbox: NSViewRepresentable {
  var title: String
  @Binding var isOn: Bool
  var identifier: String?

  init(_ title: String, isOn: Binding<Bool>, identifier: String? = nil) {
    self.title = title
    self._isOn = isOn
    self.identifier = identifier
  }

  func makeNSView(context: Context) -> NSButton {
    let button = NSButton(
      checkboxWithTitle: title, target: context.coordinator, action: #selector(Coordinator.toggle))
    button.font = .systemFont(ofSize: 13)
    button.setButtonType(.switch)
    button.isBordered = false
    button.allowsMixedState = false
    button.identifier = identifier.map { NSUserInterfaceItemIdentifier($0) }
    button.setAccessibilityIdentifier(identifier)
    return button
  }

  func updateNSView(_ button: NSButton, context: Context) {
    context.coordinator.parent = self
    if button.title != title {
      button.title = title
    }
    button.state = isOn ? .on : .off
    button.identifier = identifier.map { NSUserInterfaceItemIdentifier($0) }
    button.setAccessibilityIdentifier(identifier)
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  final class Coordinator: NSObject {
    var parent: NetworkOptionsCheckbox

    init(parent: NetworkOptionsCheckbox) {
      self.parent = parent
    }

    @objc @MainActor func toggle(_ sender: NSButton) {
      parent.isOn = sender.state == .on
    }
  }
}

private struct NetworkOptionsButton: NSViewRepresentable {
  var title: String
  var isDefault: Bool
  var isEnabled: Bool
  var identifier: String?
  var action: () -> Void

  init(
    _ title: String,
    isDefault: Bool = false,
    isEnabled: Bool = true,
    identifier: String? = nil,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.isDefault = isDefault
    self.isEnabled = isEnabled
    self.identifier = identifier
    self.action = action
  }

  func makeNSView(context: Context) -> NSButton {
    let button = NSButton(
      title: title, target: context.coordinator, action: #selector(Coordinator.press))
    button.bezelStyle = .rounded
    button.font = .systemFont(ofSize: 13)
    configure(button)
    return button
  }

  func updateNSView(_ button: NSButton, context: Context) {
    context.coordinator.parent = self
    configure(button)
  }

  private func configure(_ button: NSButton) {
    if button.title != title {
      button.title = title
    }
    button.isEnabled = isEnabled
    button.keyEquivalent = isDefault ? "\r" : ""
    button.identifier = identifier.map { NSUserInterfaceItemIdentifier($0) }
    button.setAccessibilityIdentifier(identifier)
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  final class Coordinator: NSObject {
    var parent: NetworkOptionsButton

    init(parent: NetworkOptionsButton) {
      self.parent = parent
    }

    @objc @MainActor func press(_ sender: NSButton) {
      parent.action()
    }
  }
}

private func optionLabel(_ title: String, width: CGFloat) -> some View {
  Text(title)
    .font(.system(size: 13))
    .frame(width: width, height: 20, alignment: .trailing)
}
