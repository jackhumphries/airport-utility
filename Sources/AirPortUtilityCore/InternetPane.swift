import AppKit
import SwiftUI

struct InternetPane: View {
  @EnvironmentObject private var model: AirportAppModel
  @State private var showOptions = false
  @State private var showModemOptions = false

  private var optionsTopPadding: CGFloat {
    model.internet.connectUsing == .pppoe ? 14 : 78
  }

  var body: some View {
    PaneBox {
      VStack(alignment: .leading, spacing: 12) {
        InternetFormRow(title: localized("Connect Using:")) {
          Picker("", selection: $model.internet.connectUsing) {
            ForEach(model.internetConnectUsingOptions) { value in
              Text(value.label).tag(value)
            }
          }
          .pickerStyle(.menu)
          .labelsHidden()
          .accessibilityIdentifier("internet.connect.using")
          .onChange(of: model.internet.connectUsing) { model.handleInternetConnectUsingChanged($0) }
        }
        if model.internet.connectUsing == .pppoe {
          InternetFormRow(title: localized("Account Name:")) {
            AirPortTextField(
              text: $model.internet.pppoeAccount,
              identifier: "internet.pppoe.account")
          }
          .internetEditableRow()
          InternetFormRow(title: localized("Password:")) {
            AirPortSecureField(
              text: $model.internet.pppoePassword,
              identifier: "internet.pppoe.password")
              .frame(height: 24)
          }
          .internetEditableRow()
          InternetFormRow(title: localized("Service Name:")) {
            AirPortTextField(
              text: $model.internet.pppoeService,
              identifier: "internet.pppoe.service")
          }
          .internetEditableRow()
          InternetFormRow(title: localized("Connection:")) {
            Picker("", selection: $model.internet.pppoeConnection) {
              ForEach(PPPoEConnectionOption.allCases) { option in
                Text(option.label).tag(option.value)
              }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityIdentifier("internet.pppoe.connection")
          }
          .internetEditableRow()
          .padding(.bottom, 10)
        }
        if model.internet.connectUsing == .modem && model.showsModemControls {
          InternetFormRow(title: localized("Phone Number:")) {
            AirPortTextField(
              text: $model.internet.modemPhoneNumber,
              identifier: "internet.modem.phone.number")
          }
          .internetEditableRow()
          InternetFormRow(title: localized("Alternate Number:")) {
            AirPortTextField(
              text: $model.internet.modemAlternateNumber,
              identifier: "internet.modem.alternate.number")
          }
          .internetEditableRow()
          if model.showsExtendedModemControls {
            InternetFormRow(title: localized("Account Name:")) {
              AirPortTextField(
                text: $model.internet.modemAccount,
                identifier: "internet.modem.account")
            }
            .internetEditableRow()
            InternetFormRow(title: localized("Password:")) {
              AirPortSecureField(
                text: $model.internet.modemPassword,
                identifier: "internet.modem.password")
                .frame(height: 24)
            }
            .internetEditableRow()
            InternetFormRow(title: localized("Verify Password:")) {
              AirPortSecureField(
                text: $model.internet.modemVerifyPassword,
                identifier: "internet.modem.verify.password")
                .frame(height: 24)
            }
            .internetEditableRow()
          }
          InternetOptionsCheckbox(
            localized("Use AOL"),
            isOn: $model.internet.modemUseAOL,
            identifier: "internet.modem.use.aol")
            .frame(width: AirPortLayout.formControlWidth, alignment: .leading)
            .padding(.leading, AirPortLayout.formControlLeading)
          if model.showsExtendedModemControls {
            HStack {
              Spacer().frame(width: AirPortLayout.formControlLeading)
              InternetPaneButton(
                localized("Modem Options..."), width: 147,
                identifier: "internet.modem.options.open"
              ) { showModemOptions = true }
                .frame(width: 147, height: 22)
            }
            .padding(.top, 18)
          }
        }
        if model.internet.connectUsing != .modem {
        InternetFormRow(title: localized("IPv4 Address:")) {
          if model.internet.connectUsing == .static {
            AirPortTextField(
              text: $model.internet.ipv4Address,
              identifier: "internet.ipv4.address")
          } else {
            HStack {
              Text(model.internet.ipv4Address)
                .frame(maxWidth: .infinity, alignment: .leading)
              if model.internet.connectUsing == .dhcp {
                InternetPaneButton(
                  localized("Renew DHCP Lease"), width: 148,
                  identifier: "internet.renew.dhcp.lease"
                ) {
                  model.renewDHCPLease()
                }
                .frame(minWidth: 148).frame(height: 22)
              }
            }
          }
        }
        .internetEditableRow(enabled: model.internet.connectUsing == .static)
        InternetFormRow(title: localized("Subnet Mask:")) {
          if model.internet.connectUsing == .static {
            AirPortTextField(
              text: $model.internet.subnetMask,
              identifier: "internet.subnet.mask")
          } else {
            Text(model.internet.subnetMask)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .internetEditableRow(enabled: model.internet.connectUsing == .static)
        InternetFormRow(title: localized("Router Address:")) {
          if model.internet.connectUsing == .static {
            AirPortTextField(
              text: $model.internet.routerAddress,
              identifier: "internet.router.address")
          } else {
            Text(model.internet.routerAddress)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .internetEditableRow(enabled: model.internet.connectUsing == .static)
        InternetFormRow(title: localized("DNS Servers:")) {
          DNSServerFields(
            text: $model.internet.dnsServers,
            placeholderText: model.internet.connectUsing == .dhcp
              ? model.internet.dnsServerPreview : "",
            layout: model.internet.connectUsing == .pppoe ? .horizontal : .vertical,
            identifierPrefix: "internet.dns"
          )
        }
        if model.showsIPv6InternetControls {
          InternetFormRow(title: localized("IPv6 DNS Servers:")) {
            DNSServerFields(
              text: $model.internet.ipv6DNSServers,
              placeholderText: model.internet.connectUsing == .dhcp
                ? model.internet.ipv6DNSServerPreview : "",
              identifierPrefix: "internet.ipv6.dns"
            )
          }
        }
        InternetFormRow(title: localized("Domain Name:")) {
          AirPortTextField(
            text: $model.internet.domainName,
            identifier: "internet.domain.name")
        }
        .internetEditableRow()
        if model.showsIPv6InternetControls {
          InternetFormRow(title: localized("IPv6 Address:")) {
            Text(model.internet.ipv6Address)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        if model.showsInternetOptionsControls {
          HStack {
            Spacer().frame(width: AirPortLayout.formControlLeading)
            InternetPaneButton(
              localized("Internet Options..."), width: 147,
              identifier: "internet.options.open"
            ) { showOptions = true }
              .frame(width: 147, height: 22)
          }
          .padding(.top, optionsTopPadding)
        }
        }
      }
    }
    .sheet(isPresented: $showOptions) {
      InternetOptionsSheet()
        .environmentObject(model)
    }
    .sheet(isPresented: $showModemOptions) {
      ModemOptionsSheet()
        .environmentObject(model)
    }
  }
}

private struct InternetPaneButton: NSViewRepresentable {
  var title: String
  var width: CGFloat
  var identifier: String?
  var action: () -> Void

  init(
    _ title: String, width: CGFloat, identifier: String? = nil,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.width = width
    self.identifier = identifier
    self.action = action
  }

  func makeNSView(context: Context) -> NSButton {
    let button = InternetPaneNSButton(
      title: title, target: context.coordinator, action: #selector(Coordinator.press))
    button.bezelStyle = .rounded
    button.controlSize = .small
    button.font = .systemFont(ofSize: 13)
    button.setButtonType(.momentaryPushIn)
    button.alignment = .center
    button.translatesAutoresizingMaskIntoConstraints = false
    // Exact width, but never narrower than the label needs. The constants were
    // measured against English and truncate longer translations; a plain
    // greaterThanOrEqual constraint instead lets the button expand to fill,
    // which changes the English layout.
    button.widthAnchor.constraint(
      equalToConstant: max(width, button.intrinsicContentSize.width)
    ).isActive = true
    button.heightAnchor.constraint(equalToConstant: 22).isActive = true
    button.setAccessibilityTitle(title)
    button.identifier = identifier.map { NSUserInterfaceItemIdentifier($0) }
    button.setAccessibilityIdentifier(identifier)
    return button
  }

  func updateNSView(_ button: NSButton, context: Context) {
    button.title = title
    button.setAccessibilityTitle(title)
    button.identifier = identifier.map { NSUserInterfaceItemIdentifier($0) }
    button.setAccessibilityIdentifier(identifier)
    context.coordinator.action = action
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(action: action)
  }

  @MainActor
  final class Coordinator: NSObject {
    var action: () -> Void

    init(action: @escaping () -> Void) {
      self.action = action
    }

    @objc @MainActor func press(_ sender: NSButton) {
      action()
    }
  }
}

private final class InternetPaneNSButton: NSButton {
  override func accessibilityTitle() -> String? {
    title
  }
}

private struct InternetFormRow<Content: View>: View {
  @Environment(\.isEnabled) private var isEnabled

  var title: String
  @ViewBuilder var content: Content

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: AirPortLayout.formColumnSpacing) {
      Text(title)
        .font(.system(size: 13))
        .frame(width: AirPortLayout.formLabelWidth, alignment: .trailing)
        .foregroundStyle(Color.primary.opacity(isEnabled ? 0.92 : 0.45))
      content
        .frame(width: AirPortLayout.formControlWidth, alignment: .leading)
    }
  }
}

extension View {
  @ViewBuilder
  fileprivate func internetEditableRow(enabled: Bool = true) -> some View {
    if enabled {
      self.padding(.bottom, -6)
    } else {
      self
    }
  }
}

struct DNSServerFields: View {
  enum Layout {
    case vertical
    case horizontal
  }

  @Binding var text: String
  var placeholderText = ""
  var layout: Layout = .vertical
  var identifierPrefix: String?

  var body: some View {
    Group {
      if layout == .horizontal {
        HStack(spacing: 6) {
          serverField(index: 0)
            .frame(width: 137)
          serverField(index: 1)
            .frame(width: 136)
        }
      } else {
        VStack(spacing: 6) {
          serverField(index: 0)
          serverField(index: 1)
        }
      }
    }
  }

  private func serverField(index: Int) -> some View {
    AirPortTextField(
      text: binding(for: index),
      placeholder: placeholder(for: index),
      identifier: identifierPrefix.map { "\($0).\(index + 1)" })
  }

  private func placeholder(for index: Int) -> String {
    let servers = Self.servers(from: placeholderText)
    return index < servers.count ? servers[index] : ""
  }

  func binding(for index: Int) -> Binding<String> {
    Binding {
      let servers = Self.servers(from: text)
      return index < servers.count ? servers[index] : ""
    } set: { value in
      var servers = Self.servers(from: text)
      while servers.count <= index {
        servers.append("")
      }
      servers[index] = value
      text = Self.combined(servers)
    }
  }

  static func servers(from text: String) -> [String] {
    text
      .split { $0 == "," || $0 == "\n" }
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
  }

  static func combined(_ servers: [String]) -> String {
    servers
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: ", ")
  }
}
