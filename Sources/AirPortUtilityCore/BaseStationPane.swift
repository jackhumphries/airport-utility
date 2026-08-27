import SwiftUI

struct BaseStationPane: View {
  @EnvironmentObject private var model: AirportAppModel

  var body: some View {
    PaneBox {
      FormRow(title: localized("Base Station Name:")) {
        AirPortTextField(
          text: $model.baseStation.name,
          placeholder: localized("Name"),
          selectOnAppear: true,
          identifier: "base.station.name")
      }
      FormRow(title: localized("Base Station Password:")) {
        AirPortSecureField(
          text: $model.baseStation.newAdminPassword,
          placeholder: localized("New password"),
          identifier: "base.station.admin.password")
          .frame(height: 24)
      }
      FormRow(title: localized("Verify Password:")) {
        AirPortSecureField(
          text: $model.baseStation.verifyAdminPassword,
          placeholder: localized("Verify password"),
          identifier: "base.station.admin.verify.password")
          .frame(height: 24)
      }
      HStack {
        Spacer().frame(width: AirPortLayout.formControlLeading)
        BaseStationCheckbox(
          localized("Remember this password in my keychain"),
          isOn: Binding(
            get: { model.rememberConnectionPassword },
            set: { model.updateRememberConnectionPassword($0) }),
          identifier: "base.station.remember.password")
      }
      HStack {
        Spacer().frame(width: AirPortLayout.formControlLeading)
        BaseStationCheckbox(
          localized("Allow setup over Ethernet WAN port"),
          isOn: $model.baseStation.allowSetupOverWAN,
          identifier: "base.station.allow.setup.over.wan")
      }
      if model.capabilities.supportsBaseStationMetadata {
        FormRow(title: localized("Contact:")) {
          AirPortTextField(
            text: $model.legacyDeviceOptions.baseStation.contact,
            identifier: "base.station.contact")
        }
        FormRow(title: localized("Location:")) {
          AirPortTextField(
            text: $model.legacyDeviceOptions.baseStation.location,
            identifier: "base.station.location")
        }
      }
      HStack {
        Spacer().frame(width: AirPortLayout.formControlLeading)
        BaseStationCheckbox(
          localized("Set time automatically"),
          isOn: $model.legacyDeviceOptions.baseStation.setTimeAutomatically,
          identifier: "base.station.set.time.automatically")
      }
      FormRow(title: localized("Time Server:")) {
        AirPortTextField(
          text: $model.legacyDeviceOptions.baseStation.timeServer,
          placeholder: "time.apple.com",
          identifier: "base.station.time.server")
      }
      .disabled(!model.legacyDeviceOptions.baseStation.setTimeAutomatically)
    }
  }
}
