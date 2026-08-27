import AppKit
import SwiftUI

struct EraseDiskSheet: View {
  @EnvironmentObject private var model: AirportAppModel
  @Environment(\.dismiss) private var dismiss
  @State private var diskName = ""
  @State private var method: EraseMethod = .quick

  var body: some View {
    ZStack(alignment: .topLeading) {
      diskIcon
        .offset(x: 14, y: 19)

      Text(localized("Are you sure you want to erase the AirPort Time Capsule disk?"))
        .font(.system(size: 13, weight: .semibold))
        .frame(width: 401, height: 36, alignment: .topLeading)
        .offset(x: 101, y: 19)

      Text(localized("Erasing the AirPort Time Capsule disk deletes all files from the disk."))
        .font(.system(size: 13))
        .frame(width: 430, height: 36, alignment: .topLeading)
        .offset(x: 101, y: 64)

      sheetLabel(localized("Name:"))
        .offset(x: 126, y: 101)
      AirPortTextField(
        text: $diskName,
        identifier: "erase.disk.name")
        .frame(width: 262, height: 24)
        .offset(x: 239, y: 99)

      sheetLabel(localized("Security Method:"))
        .offset(x: 126, y: 127)
      Picker(localized("Security Method"), selection: $method) {
        ForEach(EraseMethod.allCases) { method in
          Text(method.eraseSheetLabel).tag(method)
        }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .accessibilityIdentifier("erase.disk.security.method")
      .frame(width: 261, height: 23)
      .offset(x: 239, y: 125)

      Text(method.eraseSheetDescription)
        .font(.system(size: 11))
        .foregroundStyle(Color.primary.opacity(0.92))
        .frame(width: 401, height: 60, alignment: .topLeading)
        .disabled(true)
        .offset(x: 101, y: 166)

      // Right-anchored: a wider translated label would otherwise grow into the
      // neighbouring button. Trailing edge (500) and 12pt gap match the English
      // layout exactly (Cancel 356-426, Erase 438-500).
      HStack(spacing: 12) {
        DiskSheetButton(
          localized("Cancel"), width: 70, isDefault: true,
          identifier: "erase.disk.cancel"
        ) { dismiss() }
        DiskSheetButton(localized("Erase"), width: 62, identifier: "erase.disk.confirm") {
          model.applyErase(method: method, volumeName: diskName)
          dismiss()
        }
      }
      .frame(width: 500, alignment: .trailing)
      .offset(x: 0, y: 245)
    }
    .onAppear {
      if diskName.isEmpty {
        diskName = Self.initialDiskName(disks: model.disks)
      }
    }
    .frame(width: 520, height: 286, alignment: .topLeading)
    .background(AirPortSheetBackground())
  }

  nonisolated static func initialDiskName(disks: DisksState) -> String {
    DisksPane.selectedDisk(in: disks)?.name
      ?? disks.inventory.first?.name
      ?? localized("AirPort Time Capsule Disk")
  }
}

struct ArchiveDiskSheet: View {
  @EnvironmentObject private var model: AirportAppModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    ZStack(alignment: .topLeading) {
      diskIcon
        .offset(x: 14, y: 19)

      Text(
        localized(
          "Are you sure you want to archive the AirPort Time Capsule disk to a disk connected using USB?"
        )
      )
      .font(.system(size: 13, weight: .semibold))
      .frame(width: 402, height: 44, alignment: .topLeading)
      .offset(x: 101, y: 19)

      Text(localized("Archive the AirPort Time Capsule disk to back up your data."))
        .font(.system(size: 13))
        .frame(width: 401, height: 36, alignment: .topLeading)
        .offset(x: 101, y: 69)

      sheetLabel(localized("Destination:"))
        .offset(x: 126, y: 108)
      Picker(localized("Destination"), selection: .constant(destinationName ?? localized("No AirPort disks available"))) {
        Text(destinationName ?? localized("No AirPort disks available"))
          .tag(destinationName ?? localized("No AirPort disks available"))
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .accessibilityIdentifier("archive.disk.destination")
      .frame(width: 262, height: 23)
      .disabled(destinationName == nil)
      .offset(x: 239, y: 106)

      Text(
        localized("Make sure the storage device has enough space for the archive before connecting it to the base station’s USB Port.")
      )
      .font(.system(size: 13))
      .foregroundStyle(Color.primary.opacity(0.82))
      .frame(width: 402, height: 52, alignment: .topLeading)
      .disabled(true)
      .offset(x: 101, y: 148)

      // Right-anchored: a wider translated label would otherwise grow into the
      // neighbouring button. Trailing edge (500) and 12pt gap match the English
      // layout exactly (Cancel 343-413, Archive 425-500).
      HStack(spacing: 12) {
        if destinationName == nil {
          DiskSheetButton(
            localized("Cancel"), width: 70, isDefault: true,
            identifier: "archive.disk.cancel"
          ) { dismiss() }
          DiskSheetButton(
            localized("Archive"), width: 75, isEnabled: false,
            identifier: "archive.disk.confirm"
          ) {}
        } else {
          DiskSheetButton(localized("Cancel"), width: 70, identifier: "archive.disk.cancel") {
            dismiss()
          }
          DiskSheetButton(
            localized("Archive"), width: 75, isDefault: true,
            identifier: "archive.disk.confirm"
          ) {
            if destinationName != nil {
              model.applyArchive(name: "")
              dismiss()
            }
          }
        }
      }
      .frame(width: 500, alignment: .trailing)
      .offset(x: 0, y: 203)
    }
    .frame(width: 521, height: 244, alignment: .topLeading)
    .background(AirPortSheetBackground())
  }

  private var destinationName: String? {
    model.disks.inventory.first { !$0.builtIn }?.name
  }
}

private struct DiskSheetButton: NSViewRepresentable {
  var title: String
  var width: CGFloat
  var isDefault: Bool
  var isEnabled: Bool
  var identifier: String?
  var action: () -> Void

  init(
    _ title: String,
    width: CGFloat,
    isDefault: Bool = false,
    isEnabled: Bool = true,
    identifier: String? = nil,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.width = width
    self.isDefault = isDefault
    self.isEnabled = isEnabled
    self.identifier = identifier
    self.action = action
  }

  func makeNSView(context: Context) -> NSButton {
    let button = NSButton(
      title: title, target: context.coordinator, action: #selector(Coordinator.press))
    button.bezelStyle = .rounded
    button.controlSize = .regular
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
    button.setAccessibilityTitle(title)
    button.identifier = identifier.map { NSUserInterfaceItemIdentifier($0) }
    button.setAccessibilityIdentifier(identifier)
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  final class Coordinator: NSObject {
    var parent: DiskSheetButton

    init(parent: DiskSheetButton) {
      self.parent = parent
    }

    @objc @MainActor func press(_ sender: NSButton) {
      parent.action()
    }
  }
}

private var diskIcon: some View {
  airPortResourceImage(named: "AirDisk.icns", fallbackSystemName: "internaldrive")
    .resizable()
    .scaledToFit()
    .frame(width: 82, height: 82)
    .accessibilityLabel("AirDisk")
}

private func sheetLabel(_ title: String) -> some View {
  Text(title)
    .font(.system(size: 13))
    .frame(width: 108, height: 20, alignment: .trailing)
}

extension EraseMethod {
  fileprivate var eraseSheetLabel: String {
    switch self {
    case .quick:
      return localized("Quick Erase (non-secure)")
    case .zero:
      return localized("Zero Out Data")
    case .sevenPass:
      return localized("7-Pass Erase")
    case .thirtyFivePass:
      return localized("35-Pass Erase")
    }
  }

  fileprivate var eraseSheetDescription: String {
    switch self {
    case .quick:
      return
        localized("Erases directory information so that data is no longer accessible. The data is left unchanged on disk until its disk space is required and it is written over. Data is potentially recoverable until then. This option is the quickest, but least secure.")
    case .zero:
      return
        localized("Writes zeros over all data on the disk. This option provides better security than a quick erase, but takes longer.")
    case .sevenPass:
      return
        localized("Writes over disk data seven times. This option is more secure and takes significantly longer.")
    case .thirtyFivePass:
      return
        localized("Writes over disk data thirty-five times. This option is the most secure and takes the longest.")
    }
  }
}

