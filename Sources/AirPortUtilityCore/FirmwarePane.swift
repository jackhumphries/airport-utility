import SwiftUI
import UniformTypeIdentifiers

struct FirmwarePane: View {
  @EnvironmentObject private var model: AirportAppModel
  @State private var isChoosingFirmwareImage = false
  private static let firmwareContentTypes = [
    UTType(filenameExtension: "basebinary") ?? .data,
    .data,
  ]

  var body: some View {
    PaneBox {
      FormRow(title: localized("Version:")) {
        Text(currentVersionText)
          .frame(width: 279, alignment: .leading)
          .accessibilityIdentifier("firmware.current.version")
      }
      FormRow(title: localized("Available Firmware:")) {
        Picker("", selection: $model.firmware.selectedImageID) {
          if model.firmware.images.isEmpty {
            Text(localized("No firmware images loaded")).tag("")
          } else {
            ForEach(model.firmware.images) { image in
              Text(image.displayName).tag(image.id)
            }
          }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .accessibilityIdentifier("firmware.available")
        .disabled(model.firmware.images.isEmpty || model.isBusy)
      }
      HStack {
        Spacer().frame(width: AirPortLayout.formControlLeading)
        DisksPaneButton(
          localized("Check for Updates"), width: 126, isEnabled: !model.isBusy,
          identifier: "firmware.check.for.updates"
        ) {
          model.refreshFirmwareImages()
        }
        DisksPaneButton(
          localized("Choose..."), width: 72, isEnabled: !model.isBusy,
          identifier: "firmware.choose.image"
        ) {
          isChoosingFirmwareImage = true
        }
        Spacer()
        DisksPaneButton(
          installButtonTitle, width: 74, isEnabled: canInstall,
          identifier: "firmware.install"
        ) {
          model.installSelectedFirmware()
        }
      }
      .frame(width: 485)
      if !model.firmware.lastError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        HStack {
          Spacer().frame(width: AirPortLayout.formControlLeading)
          Text(model.firmware.lastError)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .frame(width: 279, alignment: .leading)
            .accessibilityIdentifier("firmware.last.error")
        }
      }
      if !model.firmware.installStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        HStack {
          Spacer().frame(width: AirPortLayout.formControlLeading)
          Text(model.firmware.installStatus)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .frame(width: 279, alignment: .leading)
            .accessibilityIdentifier("firmware.install.status")
        }
      }
      if model.firmware.transferProgress.isVisible {
        FormRow(title: localized("Progress:")) {
          VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
              Text(model.firmware.transferProgress.phase.label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityIdentifier("firmware.transfer.phase")
              Spacer()
              if !model.firmware.transferProgress.percentText.isEmpty {
                Text(model.firmware.transferProgress.percentText)
                  .font(.system(size: 11))
                  .foregroundStyle(.secondary)
                  .monospacedDigit()
                  .accessibilityIdentifier("firmware.transfer.percent")
              }
            }
            .frame(width: 279)
            firmwareProgressView
              .frame(width: 279)
            if !model.firmware.transferProgress.detail.isEmpty {
              Text(model.firmware.transferProgress.detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 279, alignment: .leading)
                .accessibilityIdentifier("firmware.transfer.detail")
            }
          }
        }
      }
    }
    .fileImporter(
      isPresented: $isChoosingFirmwareImage,
      allowedContentTypes: Self.firmwareContentTypes,
      allowsMultipleSelection: false
    ) { result in
      switch result {
      case .success(let urls):
        guard let url = urls.first else { return }
        model.chooseFirmwareImage(at: url)
      case .failure(let error):
        model.chooseFirmwareImageFailed(error)
      }
    }
    .onAppear {
      if !model.firmware.hasLoadedImages && !model.isBusy {
        model.refreshFirmwareImages()
      }
    }
  }

  private var currentVersionText: String {
    let version = model.firmware.currentVersion.trimmingCharacters(in: .whitespacesAndNewlines)
    return version.isEmpty ? localized("Unknown") : version
  }

  private var canInstall: Bool {
    !model.isBusy && model.firmware.selectedImage != nil
  }

  private var installButtonTitle: String {
    guard let image = model.firmware.selectedImage else { return localized("Install") }
    return image.version == model.firmware.currentVersion ? localized("Reinstall") : localized("Install")
  }

  @ViewBuilder
  private var firmwareProgressView: some View {
    if let fraction = model.firmware.transferProgress.fraction {
      ProgressView(value: fraction, total: 1)
        .progressViewStyle(.linear)
    } else {
      ProgressView()
        .progressViewStyle(.linear)
    }
  }
}
