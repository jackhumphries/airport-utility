import AppKit
import SwiftUI

struct WirelessPane: View {
  @EnvironmentObject private var model: AirportAppModel
  @State private var showOptions = false

  var body: some View {
    PaneBox {
      FormRow(title: localized("Network Mode:")) {
        Picker("", selection: wirelessMode) {
          Text(localized("Create a wireless network")).tag("create")
          if model.showsWirelessClientModeControls || model.wireless.mode == "join" {
            Text(localized("Join a wireless network")).tag("join")
          }
          if model.showsClassicWDSWirelessControls || model.wireless.mode == "wds" {
            Text(localized("Participate in a WDS network")).tag("wds")
          }
          Text(localized("Extend a wireless network")).tag("extend")
          Text(localized("Off")).tag("off")
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .accessibilityIdentifier("wireless.network.mode")
      }
      if model.wireless.mode != "off" {
        VStack(alignment: .leading, spacing: 12) {
          FormRow(title: localized("Wireless Network Name:")) {
            if model.wireless.mode == "extend" || model.wireless.mode == "wds" {
              WirelessNetworkNameComboBox(
                text: $model.wireless.networkName,
                items: model.extendableWirelessNetworkNames
              )
            } else {
              AirPortTextField(
                text: $model.wireless.networkName,
                placeholder: localized("Network name"),
                identifier: "wireless.network.name")
            }
          }
          FormRow(title: localized("Wireless Security:")) {
            Picker("", selection: $model.wireless.security) {
              ForEach(model.wirelessSecurityOptions) { option in
                Text(option.label).tag(option.rawValue)
              }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityIdentifier("wireless.security")
          }
          if model.wireless.mode == "create" {
            FormRow(title: "") {
              Toggle(localized("Allow this network to be extended"), isOn: $model.wireless.allowNetworkExtension)
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("wireless.allow.network.extension")
            }
          }
          if model.wireless.mode == "wds" {
            FormRow(title: localized("WDS Mode:")) {
              Picker("", selection: $model.wireless.wdsMode) {
                Text(localized("WDS main")).tag("main")
                Text(localized("WDS relay")).tag("relay")
                Text(localized("WDS remote")).tag("remote")
              }
              .pickerStyle(.menu)
              .labelsHidden()
              .accessibilityIdentifier("wireless.wds.mode")
            }
            FormRow(title: localized("WDS Peers:")) {
              AirPortTextField(
                text: $model.wireless.wdsPeerAirPortIDs,
                placeholder: localized("AirPort ID"),
                identifier: "wireless.wds.peers")
            }
          }
          if model.wireless.security != "none" {
            FormRow(title: localized("Wireless Password:")) {
              AirPortSecureField(
                text: $model.wireless.password,
                placeholder: localized("New wireless password"),
                identifier: "wireless.password")
                .frame(height: 24)
            }
            FormRow(title: "Verify Password:") {
              AirPortSecureField(
                text: $model.wireless.verifyPassword,
                placeholder: localized("Verify wireless password"),
                identifier: "wireless.verify.password")
                .frame(height: 24)
            }
          }
          Spacer(minLength: 0)
          HStack {
            Spacer().frame(width: AirPortLayout.formControlLeading)
            WirelessPaneButton(
              localized("Wireless Options..."), identifier: "wireless.options.open"
            ) { showOptions = true }
              .frame(width: 147, height: 22)
          }
        }
        .frame(height: 387, alignment: .topLeading)
      }
    }
    .sheet(isPresented: $showOptions) {
      WirelessOptionsSheet()
        .environmentObject(model)
    }
  }

  private var wirelessMode: Binding<String> {
    Binding {
      model.wireless.mode
    } set: { newMode in
      let previousMode = model.wireless.mode
      model.wireless.mode = newMode
      restoreWirelessDefaultsIfNeeded(from: previousMode, to: newMode)
      restoreLegacyClientSecurityIfNeeded()
    }
  }

  private func restoreWirelessDefaultsIfNeeded(from previousMode: String, to newMode: String) {
    WirelessModeDefaults.restoreIfNeeded(
      wireless: &model.wireless,
      previousMode: previousMode,
      newMode: newMode
    )
  }

  private func restoreLegacyClientSecurityIfNeeded() {
    guard model.usesLegacyWirelessClientSecurity else { return }
    let allowed = Set(model.wirelessSecurityOptions.map(\.rawValue))
    if !allowed.contains(model.wireless.security) {
      model.wireless.security = WirelessSecurityOption.wpaWPA2Personal.rawValue
    }
  }
}

private struct WirelessNetworkNameComboBox: NSViewRepresentable {
  @Binding var text: String
  var items: [String]

  func makeNSView(context: Context) -> NSComboBox {
    let comboBox = NSComboBox(frame: .zero)
    comboBox.isEditable = true
    comboBox.completes = true
    comboBox.usesDataSource = false
    comboBox.hasVerticalScroller = true
    comboBox.numberOfVisibleItems = 8
    comboBox.font = .systemFont(ofSize: 13)
    comboBox.controlSize = .regular
    comboBox.focusRingType = .none
    comboBox.delegate = context.coordinator
    comboBox.setAccessibilityTitle(localized("Wireless Network Name"))
    comboBox.setAccessibilityIdentifier("wireless.network.name")
    updateItems(on: comboBox, items: items)
    comboBox.stringValue = text
    return comboBox
  }

  func updateNSView(_ comboBox: NSComboBox, context: Context) {
    context.coordinator.parent = self
    updateItems(on: comboBox, items: items)
    if comboBox.stringValue != text {
      comboBox.stringValue = text
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  private func updateItems(on comboBox: NSComboBox, items: [String]) {
    let uniqueItems = AirportAppModel.uniqueWirelessNetworkNames(items)
    let currentItems = (0..<comboBox.numberOfItems).compactMap {
      comboBox.itemObjectValue(at: $0) as? String
    }
    guard currentItems != uniqueItems else { return }
    comboBox.removeAllItems()
    comboBox.addItems(withObjectValues: uniqueItems)
    comboBox.numberOfVisibleItems = min(max(uniqueItems.count, 1), 8)
  }

  final class Coordinator: NSObject, NSComboBoxDelegate {
    var parent: WirelessNetworkNameComboBox

    init(parent: WirelessNetworkNameComboBox) {
      self.parent = parent
    }

    func controlTextDidChange(_ notification: Notification) {
      guard let comboBox = notification.object as? NSComboBox else { return }
      parent.text = comboBox.stringValue
    }

    func controlTextDidEndEditing(_ notification: Notification) {
      guard let comboBox = notification.object as? NSComboBox else { return }
      parent.text = comboBox.stringValue
    }

    func comboBoxSelectionDidChange(_ notification: Notification) {
      guard let comboBox = notification.object as? NSComboBox else { return }
      parent.text = (comboBox.objectValueOfSelectedItem as? String) ?? comboBox.stringValue
    }
  }
}

private struct WirelessPaneButton: NSViewRepresentable {
  var title: String
  var identifier: String?
  var action: () -> Void

  init(_ title: String, identifier: String? = nil, action: @escaping () -> Void) {
    self.title = title
    self.identifier = identifier
    self.action = action
  }

  func makeNSView(context: Context) -> NSButton {
    let button = WirelessPaneNSButton(
      title: title, target: context.coordinator, action: #selector(Coordinator.press))
    button.bezelStyle = .rounded
    button.controlSize = .regular
    button.font = .systemFont(ofSize: 13)
    button.setButtonType(.momentaryPushIn)
    button.alignment = .center
    button.setAccessibilityTitle(title)
    button.identifier = identifier.map { NSUserInterfaceItemIdentifier($0) }
    button.setAccessibilityIdentifier(identifier)
    return button
  }

  func updateNSView(_ button: NSButton, context: Context) {
    context.coordinator.parent = self
    button.title = title
    button.setAccessibilityTitle(title)
    button.identifier = identifier.map { NSUserInterfaceItemIdentifier($0) }
    button.setAccessibilityIdentifier(identifier)
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  final class Coordinator: NSObject {
    var parent: WirelessPaneButton

    init(parent: WirelessPaneButton) {
      self.parent = parent
    }

    @objc @MainActor func press(_ sender: NSButton) {
      parent.action()
    }
  }
}

private final class WirelessPaneNSButton: NSButton {
  override func accessibilityTitle() -> String? {
    title
  }
}

enum WirelessModeDefaults {
  static func restoreIfNeeded(wireless: inout WirelessState, previousMode: String, newMode: String)
  {
    guard newMode != "off" else { return }
    let hasOffNetworkName =
      wireless.networkName.localizedCaseInsensitiveCompare("Off") == .orderedSame
    guard previousMode == "off" || wireless.networkName.isEmpty || hasOffNetworkName else {
      return
    }

    if hasOffNetworkName || wireless.networkName.isEmpty {
      wireless.networkName = newMode == "create" ? "Apple Network b92ec3" : ""
    }
    wireless.security = "none"
    wireless.password = ""
    wireless.verifyPassword = ""
  }
}
