import SwiftUI

struct AirPlayPane: View {
  @EnvironmentObject private var model: AirportAppModel

  var body: some View {
    PaneBox {
      HStack {
        Spacer().frame(width: AirPortLayout.formControlLeading)
        BaseStationCheckbox(
          localized("Enable AirPlay"), isOn: $model.airPlay.enabled,
          identifier: "airplay.enabled")
      }
      FormRow(title: localized("AirPlay Speaker Name:")) {
        AirPortTextField(
          text: $model.airPlay.speakerName,
          placeholder: localized("Speaker name"),
          identifier: "airplay.speaker.name")
      }
      .disabled(!model.airPlay.enabled)
      FormRow(title: localized("AirPlay Speaker Password:")) {
        AirPortSecureField(
          text: $model.airPlay.speakerPassword,
          placeholder: localized("Speaker password"),
          identifier: "airplay.speaker.password")
          .frame(height: 24)
      }
      .disabled(!model.airPlay.enabled)
      FormRow(title: localized("Verify Password:")) {
        AirPortSecureField(
          text: $model.airPlay.verifySpeakerPassword,
          placeholder: localized("Verify speaker password"),
          identifier: "airplay.speaker.verify.password")
          .frame(height: 24)
      }
      .disabled(!model.airPlay.enabled)
      HStack {
        Spacer().frame(width: AirPortLayout.formControlLeading)
        BaseStationCheckbox(
          localized("Remember this password in my keychain"),
          isOn: Binding(
            get: { model.airPlay.rememberPassword },
            set: { model.updateRememberAirPlayPassword($0) }),
          identifier: "airplay.remember.password")
      }
      .disabled(!model.airPlay.enabled)
      HStack {
        Spacer().frame(width: AirPortLayout.formControlLeading)
        BaseStationCheckbox(
          localized("Enable AirPlay over WAN"), isOn: $model.airPlay.overWAN,
          identifier: "airplay.over.wan")
      }
      .disabled(!model.airPlay.enabled)
    }
  }
}
