import SwiftUI

struct ModemOptionsSheet: View {
  @EnvironmentObject private var model: AirportAppModel
  @Environment(\.dismiss) private var dismiss
  @State private var draft = InternetState()
  @State private var loaded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(localized("Modem Options"))
        .font(.system(size: 13, weight: .semibold))
      Divider()

      if model.showsModemControls {
        modemRow(localized("Disconnect if Idle:")) {
          Picker("", selection: $draft.modemIdleSeconds) {
            ForEach(ModemIdleOption.allCases) { option in
              Text(option.label).tag(option.seconds)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .accessibilityIdentifier("internet.modem.options.idle")
        }
        modemRow(localized("Country Code:")) {
          Picker("", selection: $draft.modemCountryCode) {
            ForEach(ModemCountryOption.allCases) { option in
              Text(option.name).tag(option.code)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .accessibilityIdentifier("internet.modem.options.country")
        }
        modemRow(localized("Protocol:")) {
          Picker("", selection: $draft.modemProtocol) {
            Text("v.34").tag("v34")
            Text("v.90").tag("v90")
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .accessibilityIdentifier("internet.modem.options.protocol")
        }
        modemRow(localized("Dialing:")) {
          Picker("", selection: $draft.modemPulseDialing) {
            Text(localized("Tone")).tag(false)
            Text(localized("Pulse")).tag(true)
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .accessibilityIdentifier("internet.modem.options.dialing")
        }

        VStack(alignment: .leading, spacing: 10) {
          InternetOptionsCheckbox(
            localized("Automatically Dial"),
            isOn: $draft.modemAutomaticallyDial,
            identifier: "internet.modem.options.automatically.dial")
          InternetOptionsCheckbox(
            localized("Ignore Dial Tone"),
            isOn: $draft.modemIgnoreDialTone,
            identifier: "internet.modem.options.ignore.dial.tone")
        }
        .padding(.leading, 164)
      } else {
        Text(localized("This base station does not support modem options."))
      }

      Spacer()
      HStack {
        Spacer()
        Button(localized("Cancel")) { dismiss() }
          .accessibilityIdentifier("internet.modem.options.cancel")
        Button(localized("Save")) {
          model.internet = draft
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier("internet.modem.options.save")
        .disabled(!model.showsModemControls)
      }
    }
    .padding(20)
    .frame(width: 520, height: 350)
    .onAppear {
      guard !loaded else { return }
      draft = model.internet
      loaded = true
    }
  }

  private func modemRow<Content: View>(
    _ title: String, @ViewBuilder content: () -> Content
  ) -> some View {
    HStack {
      Text(title)
        .frame(width: 145, alignment: .trailing)
      content()
        .frame(width: 280, alignment: .leading)
    }
    .font(.system(size: 13))
  }
}
