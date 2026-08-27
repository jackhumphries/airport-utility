import SwiftUI

private enum AdvancedPaneSection: String, CaseIterable, Identifiable {
  case logging = "Logging & Statistics"
  case pppDialIn = "PPP Dial-in"
  case accessControl = "Access Control"

  var id: String { rawValue }

  /// Localized section title. `rawValue` stays English because it is the
  /// enum's identity, and a raw value must be a compile-time literal.
  var displayName: String { localized(rawValue) }
}

struct AdvancedPane: View {
  @EnvironmentObject private var model: AirportAppModel
  @State private var selectedSection: AdvancedPaneSection = .logging

  private var visibleSections: [AdvancedPaneSection] {
    AdvancedPaneSection.allCases.filter { section in
      switch section {
      case .logging:
        model.showsLoggingControls
      case .pppDialIn:
        model.showsPPPDialInControls
      case .accessControl:
        model.showsAccessControlControls
      }
    }
  }

  var body: some View {
    PaneBox {
      if visibleSections.count > 1 {
        Picker("", selection: $selectedSection) {
          ForEach(visibleSections) { section in
            Text(section.displayName).tag(section)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityIdentifier("advanced.section")
        .frame(maxWidth: 330)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.bottom, 8)
      }

      switch selectedSection {
      case .logging:
        if model.showsLoggingControls {
          loggingSettings
        }
      case .pppDialIn:
        if model.showsPPPDialInControls {
          pppDialInSettings
        }
      case .accessControl:
        if model.showsAccessControlControls {
          accessControlSettings
        }
      }
    }
    .onAppear(perform: reconcileSelectedSection)
    .onChange(of: visibleSections) { _ in reconcileSelectedSection() }
  }

  @ViewBuilder
  private var loggingSettings: some View {
    Text(localized("This AirPort wireless device supports log messages that may help diagnose a problem."))
      .font(.system(size: 13))
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 12)

    FormRow(title: localized("Syslog Destination Address:")) {
      AirPortTextField(
        text: $model.advanced.syslogDestinationAddress,
        identifier: "advanced.logging.syslog.destination")
    }

    FormRow(title: localized("Syslog Level:")) {
      Picker("", selection: $model.advanced.syslogLevel) {
        ForEach(SyslogLevelOption.allCases) { option in
          Text(option.label).tag(option.level)
        }
      }
      .pickerStyle(.menu)
      .labelsHidden()
      .accessibilityIdentifier("advanced.logging.syslog.level")
    }

    Text(
      localized("Simple Network Management Protocol (SNMP) allows you to query this device for statistics, including the number of wireless clients.")
    )
    .font(.system(size: 13))
    .foregroundStyle(.secondary)
    .fixedSize(horizontal: false, vertical: true)
    .padding(.horizontal, 12)
    .padding(.top, 8)

    AdvancedCheckbox(
      localized("Allow SNMP"),
      isOn: $model.advanced.allowSNMP,
      identifier: "advanced.logging.allow.snmp")
      .padding(.leading, AirPortLayout.formControlLeading)
      .onChange(of: model.advanced.allowSNMP) { enabled in
        if !enabled {
          model.advanced.allowSNMPOverWAN = false
        }
      }

    AdvancedCheckbox(
      localized("Allow SNMP over WAN"),
      isOn: $model.advanced.allowSNMPOverWAN,
      identifier: "advanced.logging.allow.snmp.over.wan")
      .padding(.leading, AirPortLayout.formControlLeading + 20)
      .disabled(!model.advanced.allowSNMP)
  }

  @ViewBuilder
  private var pppDialInSettings: some View {
    AdvancedCheckbox(
      localized("PPP Dial-in"),
      isOn: $model.advanced.pppDialInEnabled,
      identifier: "advanced.ppp.dial.in.enabled")
      .padding(.leading, AirPortLayout.formControlLeading)

    Group {
      FormRow(title: localized("Account Name:")) {
        AirPortTextField(
          text: $model.advanced.pppDialInAccount,
          identifier: "advanced.ppp.dial.in.account")
      }
      FormRow(title: localized("Password:")) {
        AirPortSecureField(
          text: $model.advanced.pppDialInPassword,
          identifier: "advanced.ppp.dial.in.password")
          .frame(height: 24)
      }
      FormRow(title: localized("Verify Password:")) {
        AirPortSecureField(
          text: $model.advanced.pppDialInVerifyPassword,
          identifier: "advanced.ppp.dial.in.verify.password")
          .frame(height: 24)
      }
      FormRow(title: localized("Answer on ring:")) {
        TextField("", value: $model.advanced.pppDialInAnswerOnRing, format: .number)
          .textFieldStyle(.plain)
          .airPortField()
          .accessibilityIdentifier("advanced.ppp.dial.in.answer.on.ring")
      }
      FormRow(title: localized("Idle Disconnect After:")) {
        Picker("", selection: $model.advanced.pppDialInIdleSeconds) {
          ForEach(ModemIdleOption.allCases) { option in
            Text(option.label).tag(option.seconds)
          }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .accessibilityIdentifier("advanced.ppp.dial.in.idle.disconnect")
      }
      FormRow(title: localized("Maximum Connect Time:")) {
        Picker("", selection: $model.advanced.pppDialInMaximumConnectSeconds) {
          ForEach(PPPDialInMaximumConnectOption.allCases) { option in
            Text(option.label).tag(option.seconds)
          }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .accessibilityIdentifier("advanced.ppp.dial.in.maximum.connect")
      }
    }
    .disabled(!model.advanced.pppDialInEnabled)
  }

  @ViewBuilder
  private var accessControlSettings: some View {
    FormRow(title: localized("Access Control:")) {
      Picker("", selection: $model.legacyDeviceOptions.accessControl.mode) {
        Text(localized("Not enabled")).tag("not-enabled")
        Text(localized("Local")).tag("local")
        Text("RADIUS").tag("radius")
      }
      .pickerStyle(.menu)
      .labelsHidden()
      .accessibilityIdentifier("advanced.access.control.mode")
    }

    switch model.legacyDeviceOptions.accessControl.mode {
    case "local":
      localAccessControlSettings
    case "radius":
      radiusAccessControlSettings
    default:
      Text(localized("All wireless clients are allowed to join this network."))
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 24)
    }
  }

  @ViewBuilder
  private var localAccessControlSettings: some View {
    Text(localized("Allow only the wireless clients listed below."))
      .font(.system(size: 13))
      .foregroundStyle(.secondary)
      .padding(.leading, 12)

    ScrollView {
      VStack(spacing: 10) {
        ForEach($model.legacyDeviceOptions.accessControl.entries) { $entry in
          VStack(spacing: 8) {
            HStack(spacing: 8) {
              Text(localized("AirPort ID:"))
                .font(.system(size: 12))
                .frame(width: 74, alignment: .trailing)
              AirPortTextField(
                text: $entry.macAddress,
                placeholder: "00:11:22:33:44:55",
                identifier: "advanced.access.control.entry.\(entry.id).mac")
              Button {
                model.legacyDeviceOptions.accessControl.entries.removeAll {
                  $0.id == entry.id
                }
              } label: {
                Image(systemName: "minus.circle")
              }
              .buttonStyle(.plain)
              .accessibilityLabel(localized("Remove access-control entry"))
            }
            HStack(spacing: 8) {
              Text(localized("Description:"))
                .font(.system(size: 12))
                .frame(width: 74, alignment: .trailing)
              AirPortTextField(
                text: $entry.description,
                identifier: "advanced.access.control.entry.\(entry.id).description")
              Spacer().frame(width: 18)
            }
          }
          .padding(8)
          .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        }
      }
      .padding(.horizontal, 12)
    }
    .frame(maxHeight: 260)

    Button(localized("Add Client")) {
      model.legacyDeviceOptions.accessControl.entries.append(AccessControlEntry())
    }
    .accessibilityIdentifier("advanced.access.control.add.client")
    .frame(maxWidth: .infinity, alignment: .trailing)
    .padding(.trailing, 12)
  }

  @ViewBuilder
  private var radiusAccessControlSettings: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        FormRow(title: localized("RADIUS Type:")) {
          Picker("", selection: $model.legacyDeviceOptions.accessControl.radiusType) {
            Text(localized("Default")).tag("default")
            Text(localized("Alternate")).tag("alternate")
          }
          .pickerStyle(.menu)
          .labelsHidden()
          .accessibilityIdentifier("advanced.access.control.radius.type")
        }
        FormRow(title: localized("Primary Server:")) {
          AirPortTextField(
            text: $model.legacyDeviceOptions.accessControl.primaryAddress,
            identifier: "advanced.access.control.radius.primary.address")
        }
        FormRow(title: localized("Shared Secret:")) {
          AirPortSecureField(
            text: $model.legacyDeviceOptions.accessControl.primarySecret,
            identifier: "advanced.access.control.radius.primary.secret")
            .frame(height: 24)
        }
        FormRow(title: localized("Verify Secret:")) {
          AirPortSecureField(
            text: $model.legacyDeviceOptions.accessControl.primaryVerifySecret,
            identifier: "advanced.access.control.radius.primary.verify.secret")
            .frame(height: 24)
        }
        FormRow(title: localized("Primary Port:")) {
          TextField(
            "", value: $model.legacyDeviceOptions.accessControl.primaryPort, format: .number
          )
          .textFieldStyle(.plain)
          .airPortField()
          .accessibilityIdentifier("advanced.access.control.radius.primary.port")
        }
        FormRow(title: localized("Secondary Server:")) {
          AirPortTextField(
            text: $model.legacyDeviceOptions.accessControl.secondaryAddress,
            identifier: "advanced.access.control.radius.secondary.address")
        }
        FormRow(title: localized("Shared Secret:")) {
          AirPortSecureField(
            text: $model.legacyDeviceOptions.accessControl.secondarySecret,
            identifier: "advanced.access.control.radius.secondary.secret")
            .frame(height: 24)
        }
        FormRow(title: localized("Verify Secret:")) {
          AirPortSecureField(
            text: $model.legacyDeviceOptions.accessControl.secondaryVerifySecret,
            identifier: "advanced.access.control.radius.secondary.verify.secret")
            .frame(height: 24)
        }
        FormRow(title: localized("Secondary Port:")) {
          TextField(
            "", value: $model.legacyDeviceOptions.accessControl.secondaryPort, format: .number
          )
          .textFieldStyle(.plain)
          .airPortField()
          .accessibilityIdentifier("advanced.access.control.radius.secondary.port")
        }
      }
    }
    .frame(maxHeight: 340)
  }

  private func reconcileSelectedSection() {
    guard !visibleSections.contains(selectedSection), let first = visibleSections.first else {
      return
    }
    selectedSection = first
  }
}

private struct AdvancedCheckbox: View {
  var title: String
  @Binding var isOn: Bool
  var identifier: String

  init(_ title: String, isOn: Binding<Bool>, identifier: String) {
    self.title = title
    _isOn = isOn
    self.identifier = identifier
  }

  var body: some View {
    Toggle(title, isOn: $isOn)
      .toggleStyle(.checkbox)
      .font(.system(size: 13))
      .accessibilityIdentifier(identifier)
  }
}
