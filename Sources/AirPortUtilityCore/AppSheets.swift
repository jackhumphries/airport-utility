import SwiftUI

struct PasswordsSheet: View {
  @EnvironmentObject private var model: AirportAppModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(localized("Passwords"))
        .font(.system(size: 13, weight: .semibold))
        .padding(.bottom, 13)

      VStack(alignment: .leading, spacing: 8) {
        passwordRow(
          localized("Base Station Password:"), value: baseStationPassword,
          identifier: "passwords.base.station.value")
        if shouldShowDiskPassword {
          passwordRow(
            localized("Disk Password:"), value: diskPassword,
            identifier: "passwords.disk.value")
        }
      }
      .padding(.bottom, 20)

      HStack {
        Spacer()
        Button("OK") {
          dismiss()
        }
        .accessibilityIdentifier("passwords.ok")
        .keyboardShortcut(.defaultAction)
        .frame(width: 70)
      }
    }
    .padding(EdgeInsets(top: 18, leading: 20, bottom: 16, trailing: 20))
    .frame(width: 360, alignment: .leading)
  }

  /// The accessibility identifier is passed in rather than derived from the
  /// label. Deriving it meant matching the English word "Disk", which stops
  /// matching as soon as the label is translated.
  private func passwordRow(
    _ label: String, value: String, identifier: String
  ) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(label)
        .font(.system(size: 13))
        .frame(width: 145, alignment: .trailing)
      Text(value.isEmpty ? localized("Not available") : value)
        .font(.system(size: 13))
        .textSelection(.enabled)
        .accessibilityIdentifier(identifier)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var baseStationPassword: String {
    let configuredPassword = model.baseStation.newAdminPassword
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if !configuredPassword.isEmpty {
      return configuredPassword
    }
    return model.connection.password.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var shouldShowDiskPassword: Bool {
    model.disks.secureSharedDisks == "disk-password"
  }

  private var diskPassword: String {
    model.disks.diskPassword.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

struct PreferencesSheet: View {
  @EnvironmentObject private var model: AirportAppModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(localized("Preferences"))
        .font(.system(size: 13, weight: .semibold))

      Toggle(
        localized("Show connection details in the Other Wi-Fi Devices menu"),
        isOn: $model.showConnectionDetails
      )
      .toggleStyle(.checkbox)
      .font(.system(size: 13))
      .accessibilityIdentifier("preferences.show.connection.details")

      HStack {
        Spacer()
        Button("OK") {
          dismiss()
        }
        .accessibilityIdentifier("preferences.ok")
        .keyboardShortcut(.defaultAction)
        .frame(width: 70)
      }
    }
    .padding(EdgeInsets(top: 18, leading: 20, bottom: 16, trailing: 20))
    .frame(width: 430, alignment: .leading)
  }
}

struct ConfigureOtherSheet: View {
  @EnvironmentObject private var model: AirportAppModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(localized("Configure Other"))
        .font(.system(size: 13, weight: .semibold))

      VStack(alignment: .leading, spacing: 10) {
        labeledField(localized("Host:")) {
          AirPortTextField(
            text: $model.connection.host,
            placeholder: "Host",
            identifier: "configure.other.host")
            .frame(width: 240, height: 24)
        }
        labeledField(localized("Password:")) {
          AirPortSecureField(
            text: $model.connection.password,
            placeholder: localized("Password"),
            identifier: "configure.other.password",
            onSubmit: submitConnection)
            .frame(width: 240, height: 24)
        }
        if !model.mockMode {
          labeledField(localized("Repository:")) {
            AirPortTextField(
              text: $model.connection.repoPath,
              placeholder: localized("Repository"),
              identifier: "configure.other.repository")
              .frame(width: 240, height: 24)
          }
        }
        Toggle(
          localized("Remember this password in my keychain"),
          isOn: Binding(
            get: { model.rememberConnectionPassword },
            set: { model.updateRememberConnectionPassword($0) }))
          .toggleStyle(.checkbox)
          .font(.system(size: 12))
          .accessibilityIdentifier("configure.other.remember.password")
          .padding(.leading, 94)
      }

      if !model.status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Text(model.status)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      HStack {
        Spacer()
        Button(localized("Cancel")) {
          dismiss()
        }
        .accessibilityIdentifier("configure.other.cancel")
        .frame(width: 70)
        Button(model.isBusy ? localized("Working") : localized("Connect")) {
          submitConnection()
        }
        .accessibilityIdentifier("configure.other.connect")
        .keyboardShortcut(.defaultAction)
        .disabled(!model.canAttemptConnection)
        .frame(width: 82)
      }
    }
    .padding(EdgeInsets(top: 18, leading: 20, bottom: 16, trailing: 20))
    .frame(width: 420, alignment: .leading)
  }

  private func submitConnection() {
    guard model.canAttemptConnection else { return }
    model.refresh()
  }

  private func labeledField<Content: View>(
    _ label: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(label)
        .font(.system(size: 13))
        .frame(width: 86, alignment: .trailing)
      content()
    }
  }
}
