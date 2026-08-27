import AppKit
import SwiftUI

struct DisksPane: View {
  @EnvironmentObject private var model: AirportAppModel
  @State private var showErase = false
  @State private var showArchive = false

  var body: some View {
    PaneBox {
      DiskInventoryList(
        records: model.disks.inventory,
        selectedID: $model.disks.selectedDiskID,
        didLoadInventory: model.disks.didLoadInventory,
        isLoading: isLoadingDiskInventory)
      HStack {
        Spacer().frame(width: AirPortLayout.formControlLeading)
        DisksPaneButton(
          localized("Erase Disk…"), width: 107, isEnabled: selectedDisk != nil,
          identifier: "disks.erase.open"
        ) {
          showErase = true
        }
        Spacer()
        DisksPaneButton(
          localized("Archive Disk…"), width: 120, isEnabled: canArchiveDisk,
          identifier: "disks.archive.open"
        ) {
          showArchive = true
        }
      }
      HStack {
        Spacer().frame(width: AirPortLayout.formControlLeading)
        DisksCheckbox(
          localized("Enable file sharing"), isOn: $model.disks.fileSharing,
          identifier: "disks.file.sharing")
      }
      .padding(.top, 11)
      FormRow(title: localized("Secure Shared Disks:")) {
        DiskSecurityPopup(
          selection: $model.disks.secureSharedDisks,
          identifier: "disks.secure.shared.disks")
          .frame(width: 279, height: 20)
      }
      if model.disks.secureSharedDisks == "disk-password" {
        FormRow(title: localized("Disk Password:")) {
          AirPortSecureField(
            text: $model.disks.diskPassword,
            placeholder: localized("Disk password"),
            identifier: "disks.disk.password")
            .frame(height: 24)
        }
        FormRow(title: localized("Verify Password:")) {
          AirPortSecureField(
            text: $model.disks.verifyDiskPassword,
            placeholder: localized("Verify disk password"),
            identifier: "disks.verify.password")
            .frame(height: 24)
        }
      }
      if model.disks.secureSharedDisks == "accounts" {
        FormRow(title: localized("Accounts:")) {
          DiskAccountsEditor(
            accounts: $model.disks.fileSharingAccounts,
            selectedID: $model.disks.selectedFileSharingAccountID,
            isEnabled: model.supportsDiskFileSharingAccountEditing)
        }
        if model.supportsDiskFileSharingAccountEditing,
          let selectedAccount = selectedFileSharingAccountBinding
        {
          FormRow(title: localized("Account Name:")) {
            AirPortTextField(
              text: selectedAccount.name,
              placeholder: localized("Account name"),
              identifier: "disks.account.name")
              .frame(height: 24)
          }
          FormRow(title: localized("Password:")) {
            AirPortSecureField(
              text: selectedAccount.password,
              placeholder: localized("Account password"),
              identifier: "disks.account.password")
              .frame(height: 24)
          }
          FormRow(title: localized("Verify Password:")) {
            AirPortSecureField(
              text: selectedAccount.verifyPassword,
              placeholder: localized("Verify account password"),
              identifier: "disks.account.verify.password")
              .frame(height: 24)
          }
          FormRow(title: localized("File Sharing Access:")) {
            DiskAccountAccessPopup(
              selection: selectedAccount.access,
              identifier: "disks.account.file.sharing.access")
              .frame(width: 279, height: 20)
          }
        }
      } else {
        HStack {
          Spacer().frame(width: AirPortLayout.formControlLeading)
          DisksCheckbox(
            localized("Remember this password in my keychain"),
            isOn: Binding(
              get: { model.remembersCurrentDiskPassword },
              set: { model.updateRememberCurrentDiskPassword($0) }),
            identifier: "disks.remember.password")
        }
      }
    }
    .sheet(isPresented: $showErase) {
      EraseDiskSheet()
        .environmentObject(model)
    }
    .sheet(isPresented: $showArchive) {
      ArchiveDiskSheet()
        .environmentObject(model)
    }
  }

  private var isLoadingDiskInventory: Bool {
    model.isBusy && !model.disks.didLoadInventory
  }

  private var selectedDisk: DiskRecord? {
    Self.selectedDisk(in: model.disks)
  }

  private var canArchiveDisk: Bool {
    Self.canArchiveDisk(in: model.disks)
  }

  private var selectedFileSharingAccountBinding: (
    name: Binding<String>,
    password: Binding<String>,
    verifyPassword: Binding<String>,
    access: Binding<String>
  )? {
    guard
      let index = model.disks.fileSharingAccounts.firstIndex(where: {
        $0.id == model.disks.selectedFileSharingAccountID
      })
    else { return nil }
    return (
      name: Binding(
        get: { model.disks.fileSharingAccounts[index].name },
        set: { model.disks.fileSharingAccounts[index].name = $0 }),
      password: Binding(
        get: { model.disks.fileSharingAccounts[index].password },
        set: { model.disks.fileSharingAccounts[index].password = $0 }),
      verifyPassword: Binding(
        get: { model.disks.fileSharingAccounts[index].verifyPassword },
        set: { model.disks.fileSharingAccounts[index].verifyPassword = $0 }),
      access: Binding(
        get: { model.disks.fileSharingAccounts[index].access },
        set: { model.disks.fileSharingAccounts[index].access = $0 })
    )
  }

  nonisolated static func selectedDisk(in disks: DisksState) -> DiskRecord? {
    disks.inventory.first { $0.id == disks.selectedDiskID }
  }

  nonisolated static func canArchiveDisk(in disks: DisksState) -> Bool {
    disks.inventory.contains { $0.builtIn } && disks.inventory.contains { !$0.builtIn }
  }
}

struct DisksPaneButton: NSViewRepresentable {
  var title: String
  var width: CGFloat
  var isEnabled: Bool
  var identifier: String?
  var action: () -> Void

  init(
    _ title: String, width: CGFloat, isEnabled: Bool = true, identifier: String? = nil,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.width = width
    self.isEnabled = isEnabled
    self.identifier = identifier
    self.action = action
  }

  func makeNSView(context: Context) -> NSButton {
    let button = DisksPaneNSButton(
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
    button.isEnabled = isEnabled
    button.setAccessibilityTitle(title)
    button.identifier = identifier.map { NSUserInterfaceItemIdentifier($0) }
    button.setAccessibilityIdentifier(identifier)
    return button
  }

  func updateNSView(_ button: NSButton, context: Context) {
    button.title = title
    button.isEnabled = isEnabled
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

private final class DisksPaneNSButton: NSButton {
  override func accessibilityTitle() -> String? {
    title
  }
}

private struct DiskSecurityPopup: NSViewRepresentable {
  @Binding var selection: String
  var identifier: String

  private let options = [
    (localized("With accounts"), "accounts"),
    (localized("With a disk password"), "disk-password"),
    (localized("With device password"), "device-password"),
  ]

  func makeNSView(context: Context) -> NSPopUpButton {
    let button = BindingNSPopUpButton(frame: .zero, pullsDown: false)
    button.onSelectionValueChanged = { [weak coordinator = context.coordinator] value in
      Task { @MainActor in
        coordinator?.setSelection(value)
      }
    }
    button.controlSize = .small
    button.font = .systemFont(ofSize: 13)
    button.target = context.coordinator
    button.action = #selector(Coordinator.changed(_:))
    configure(button)
    return button
  }

  func updateNSView(_ button: NSPopUpButton, context: Context) {
    context.coordinator.parent = self
    if let button = button as? BindingNSPopUpButton {
      button.onSelectionValueChanged = { [weak coordinator = context.coordinator] value in
        Task { @MainActor in
          coordinator?.setSelection(value)
        }
      }
    }
    configure(button)
    if let index = options.firstIndex(where: { $0.1 == selection }) {
      button.selectItem(at: index)
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  private func configure(_ button: NSPopUpButton) {
    if button.numberOfItems != options.count {
      button.removeAllItems()
      for option in options {
        button.addItem(withTitle: option.0)
        button.item(withTitle: option.0)?.representedObject = option.1
      }
    }
    button.identifier = NSUserInterfaceItemIdentifier(identifier)
    button.setAccessibilityIdentifier(identifier)
  }

  final class Coordinator: NSObject {
    var parent: DiskSecurityPopup

    init(parent: DiskSecurityPopup) {
      self.parent = parent
    }

    @objc @MainActor func changed(_ sender: NSPopUpButton) {
      guard let value = sender.selectedItem?.representedObject as? String else { return }
      setSelection(value)
    }

    @MainActor func setSelection(_ value: String) {
      parent.selection = value
    }
  }
}

private struct DiskAccountAccessPopup: NSViewRepresentable {
  @Binding var selection: String
  var identifier: String

  private let options = [
    (localized("Read and Write"), "read-write"),
    (localized("Read Only"), "read-only"),
    (localized("Not Allowed"), "not-allowed"),
  ]

  func makeNSView(context: Context) -> NSPopUpButton {
    let button = BindingNSPopUpButton(frame: .zero, pullsDown: false)
    button.onSelectionValueChanged = { [weak coordinator = context.coordinator] value in
      Task { @MainActor in
        coordinator?.setSelection(value)
      }
    }
    button.controlSize = .small
    button.font = .systemFont(ofSize: 13)
    button.target = context.coordinator
    button.action = #selector(Coordinator.changed(_:))
    configure(button)
    return button
  }

  func updateNSView(_ button: NSPopUpButton, context: Context) {
    context.coordinator.parent = self
    if let button = button as? BindingNSPopUpButton {
      button.onSelectionValueChanged = { [weak coordinator = context.coordinator] value in
        Task { @MainActor in
          coordinator?.setSelection(value)
        }
      }
    }
    configure(button)
    if let index = options.firstIndex(where: { $0.1 == selection }) {
      button.selectItem(at: index)
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  private func configure(_ button: NSPopUpButton) {
    if button.numberOfItems != options.count {
      button.removeAllItems()
      for option in options {
        button.addItem(withTitle: option.0)
        button.item(withTitle: option.0)?.representedObject = option.1
      }
    }
    button.identifier = NSUserInterfaceItemIdentifier(identifier)
    button.setAccessibilityIdentifier(identifier)
  }

  final class Coordinator: NSObject {
    var parent: DiskAccountAccessPopup

    init(parent: DiskAccountAccessPopup) {
      self.parent = parent
    }

    @objc @MainActor func changed(_ sender: NSPopUpButton) {
      guard let value = sender.selectedItem?.representedObject as? String else { return }
      setSelection(value)
    }

    @MainActor func setSelection(_ value: String) {
      parent.selection = value
    }
  }
}

private final class BindingNSPopUpButton: NSPopUpButton {
  var onSelectionValueChanged: ((String) -> Void)?

  override func setAccessibilityValue(_ accessibilityValue: Any?) {
    guard let rawValue = accessibilityValue as? String else { return }
    let selectedItem =
      item(withTitle: rawValue)
      ?? itemArray.first { ($0.representedObject as? String) == rawValue }
    guard let selectedItem else { return }
    select(selectedItem)
    guard let value = selectedItem.representedObject as? String else { return }
    onSelectionValueChanged?(value)
  }
}

private struct DisksCheckbox: NSViewRepresentable {
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
    button.identifier = identifier.map { NSUserInterfaceItemIdentifier($0) }
    button.setAccessibilityIdentifier(identifier)
    button.state = isOn ? .on : .off
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  final class Coordinator: NSObject {
    var parent: DisksCheckbox

    init(parent: DisksCheckbox) {
      self.parent = parent
    }

    @objc @MainActor func toggle(_ sender: NSButton) {
      parent.isOn = sender.state == .on
    }
  }
}

private struct DiskAccountsEditor: View {
  @Binding var accounts: [DiskAccount]
  @Binding var selectedID: String
  var isEnabled: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      VStack(spacing: 0) {
        HStack {
          Text(localized("Account Name"))
            .font(.system(size: 12))
            .foregroundStyle(Color.white.opacity(0.78))
          Spacer()
        }
        .padding(.horizontal, 8)
        .frame(width: 277, height: 22)
        .background(Color(red: 0.23, green: 0.21, blue: 0.24))
        .overlay(Rectangle().stroke(Color(red: 0.14, green: 0.13, blue: 0.16), lineWidth: 1))

        if accounts.isEmpty {
          HStack {
            Spacer()
          }
          .frame(width: 277, height: 50)
          .background(Color(red: 0.18, green: 0.14, blue: 0.18))
          .overlay(Rectangle().stroke(Color(red: 0.15, green: 0.13, blue: 0.16), lineWidth: 1))
        } else {
          VStack(spacing: 0) {
            ForEach(accounts.indices, id: \.self) { index in
              DiskAccountRow(
                name: accountNameBinding(for: index),
                isSelected: accounts[index].id == selectedID,
                isEnabled: isEnabled,
                identifier: "disks.accounts.row.\(index).name"
              ) {
                if isEnabled {
                  selectedID = accounts[index].id
                }
              }
            }
            Spacer(minLength: accounts.count < 2 ? 25 : 0)
          }
          .frame(width: 277, height: 50)
          .background(Color(red: 0.18, green: 0.14, blue: 0.18))
          .overlay(Rectangle().stroke(Color(red: 0.15, green: 0.13, blue: 0.16), lineWidth: 1))
        }
      }

      HStack(spacing: 6) {
        DisksPaneButton(
          "+", width: 28, isEnabled: isEnabled,
          identifier: "disks.accounts.add"
        ) {
          addAccount()
        }
        DisksPaneButton(
          "-", width: 28, isEnabled: isEnabled && selectedAccountIndex != nil,
          identifier: "disks.accounts.remove"
        ) {
          deleteSelectedAccount()
        }
      }
    }
    .onAppear(perform: reconcileSelection)
    .onChange(of: accounts) { _ in
      reconcileSelection()
    }
  }

  private var selectedAccountIndex: Int? {
    accounts.firstIndex { $0.id == selectedID }
  }

  private func accountNameBinding(for index: Int) -> Binding<String> {
    Binding(
      get: {
        guard accounts.indices.contains(index) else { return "" }
        return accounts[index].name
      },
      set: { newValue in
        guard accounts.indices.contains(index) else { return }
        accounts[index].name = newValue
      })
  }

  private func addAccount() {
    let account = DiskAccount(name: nextAccountName())
    accounts.append(account)
    selectedID = account.id
  }

  private func deleteSelectedAccount() {
    guard let index = selectedAccountIndex else { return }
    accounts.remove(at: index)
    reconcileSelection()
  }

  private func reconcileSelection() {
    guard let firstAccount = accounts.first else {
      selectedID = ""
      return
    }
    if !accounts.contains(where: { $0.id == selectedID }) {
      selectedID = firstAccount.id
    }
  }

  private func nextAccountName() -> String {
    let existingNames = Set(accounts.map(\.name))
    var index = accounts.count + 1
    while existingNames.contains("Account \(index)") {
      index += 1
    }
    return "Account \(index)"
  }
}

private struct DiskAccountRow: View {
  @Binding var name: String
  var isSelected: Bool
  var isEnabled: Bool
  var identifier: String?
  var select: () -> Void

  var body: some View {
    TextField("", text: $name)
      .textFieldStyle(.plain)
      .font(.system(size: 12))
      .foregroundStyle(Color.white.opacity(isEnabled ? 0.9 : 0.45))
      .padding(.horizontal, 8)
      .frame(width: 277, height: 25)
      .background(isSelected ? Color(red: 0.22, green: 0.39, blue: 0.64) : Color.clear)
      .disabled(!isEnabled)
      .contentShape(Rectangle())
      .onTapGesture(perform: select)
      .accessibilityLabel(name.isEmpty ? localized("File sharing account") : name)
      .accessibilityValue(isSelected ? "selected" : "")
      .accessibilityIdentifier(identifier ?? "")
  }
}

struct DiskInventoryList: View {
  var records: [DiskRecord]
  @Binding var selectedID: String
  var didLoadInventory = false
  var isLoading = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if records.isEmpty {
        partitionsRow {
          Text(emptyStateText)
            .foregroundStyle(.secondary)
        }
      } else {
        partitionsRow {
          VStack(spacing: 0) {
            ForEach(records) { record in
              Button {
                selectedID = record.id
              } label: {
                DiskInventoryRow(record: record, isSelected: selectedID == record.id)
              }
              .buttonStyle(.plain)
              .accessibilityLabel(record.name)
              .accessibilityValue(selectedID == record.id ? "selected" : "")
              .accessibilityIdentifier("disks.partition.\(record.id)")
            }
            Spacer(minLength: records.count < 2 ? 56 : 0)
          }
          .frame(width: 277, height: 114)
          .background(Color(red: 0.18, green: 0.14, blue: 0.18))
          .overlay(Rectangle().stroke(Color(red: 0.15, green: 0.13, blue: 0.16), lineWidth: 1))
        }
      }
    }
    .onAppear(perform: reconcileSelection)
    .onChange(of: records) { _ in
      reconcileSelection()
    }
  }

  private func partitionsRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    HStack(alignment: .top, spacing: AirPortLayout.formColumnSpacing) {
      Text(localized("Partitions:"))
        .font(.system(size: 13))
        .frame(width: AirPortLayout.formLabelWidth, alignment: .trailing)
        .padding(.top, 8)
      content()
        .frame(width: AirPortLayout.formControlWidth, alignment: .leading)
    }
  }

  private var emptyStateText: String {
    Self.emptyStateText(didLoadInventory: didLoadInventory, isLoading: isLoading)
  }

  private func reconcileSelection() {
    guard let firstRecord = records.first else {
      selectedID = ""
      return
    }
    if !records.contains(where: { $0.id == selectedID }) {
      selectedID = firstRecord.id
    }
  }

  nonisolated static func emptyStateText(didLoadInventory: Bool, isLoading: Bool) -> String {
    if isLoading {
      return localized("Loading disk information...")
    }
    if didLoadInventory {
      return localized("No disk partitions found.")
    }
    return localized("No disk information loaded.")
  }
}

struct DiskInventoryRow: View {
  var record: DiskRecord
  var isSelected: Bool

  /// The drive behind this volume: vendor and model, then firmware revision.
  static func hardwareLine(for record: DiskRecord) -> String? {
    let parts = [record.vendor, record.revision]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  /// Capacity and health: total, how much is used, and the SMART status.
  ///
  /// Shown beside the volume rather than behind a button: the device publishes
  /// all of it with the disk inventory, so there is nothing to run. The SMART
  /// value passes through `localized`, so a known term is translated and
  /// anything unfamiliar appears verbatim rather than being guessed at.
  static func capacityLine(for record: DiskRecord) -> String? {
    var parts: [String] = []
    let byteCount = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
    // "1.34 TB used / 2 TB" rather than a bare "1.34 TB / 2 TB": without the
    // word there is nothing to say which number is which. The row only has
    // about 205pt of text width, which a full-precision pair overruns even
    // without the word, so the line is allowed to scale down slightly (see
    // `body`) instead of being kept short at the cost of being ambiguous.
    switch (record.sizeUsed, record.size, record.sizeFree) {
    case let (used?, total?, _):
      parts.append(localizedFormat("%1$@ used / %2$@", byteCount(used), byteCount(total)))
    case let (nil, total?, free?):
      parts.append(
        localizedFormat("%1$@ used / %2$@", byteCount(total - free), byteCount(total)))
    case let (used?, nil, _):
      parts.append(localizedFormat("%@ used", byteCount(used)))
    case let (nil, nil, free?):
      parts.append(localizedFormat("%@ free", byteCount(free)))
    case let (nil, total?, nil):
      parts.append(byteCount(total))
    default:
      break
    }
    let smartStatus = record.smartStatus.trimmingCharacters(in: .whitespacesAndNewlines)
    if !smartStatus.isEmpty {
      parts.append(localizedFormat("SMART: %@", localized(smartStatus)))
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  /// Long vendor strings and full-precision capacity pairs ("502.15 GB used /
  /// 931.32 GB · SMART: verified" is 244pt in Spanish against 205pt of room)
  /// overrun the row. Shrinking to 8pt keeps the whole line readable, where
  /// truncation would drop the SMART status — the part worth reading — off the
  /// end. Ordinary values render at the full 10pt.
  static let detailMinimumScale: CGFloat = 0.8

  var body: some View {
    HStack(spacing: 6) {
      airPortResourceImage(named: iconResourceName, fallbackSystemName: iconFallbackSystemName)
        .resizable()
        .scaledToFit()
        .frame(width: 50, height: 50)
        .accessibilityLabel(iconAccessibilityLabel)

      VStack(alignment: .leading, spacing: 3) {
        DiskNameTextField(record.name)
          .frame(height: 19)
        if let hardware = Self.hardwareLine(for: record) {
          Text(hardware)
            .font(.system(size: 10))
            .lineLimit(1)
            .minimumScaleFactor(Self.detailMinimumScale)
            .foregroundStyle(Color.white.opacity(isSelected ? 0.7 : 0.38))
        }
        if let capacity = Self.capacityLine(for: record) {
          Text(capacity)
            .font(.system(size: 10))
            .lineLimit(1)
            .minimumScaleFactor(Self.detailMinimumScale)
            .foregroundStyle(Color.white.opacity(isSelected ? 0.7 : 0.38))
        }
      }
      Spacer()
    }
    .padding(.horizontal, 8)
    .frame(width: 277, height: 56)
    .foregroundStyle(Color.white.opacity(0.88))
    .background(rowBackground)
    .contentShape(Rectangle())
  }

  private var rowBackground: Color {
    if isSelected {
      return Color(red: 0.22, green: 0.39, blue: 0.64)
    }
    return Color(red: 0.33, green: 0.34, blue: 0.33)
  }

  private var iconResourceName: String {
    record.builtIn ? "AirDisk.icns" : "Drives.icns"
  }

  private var iconFallbackSystemName: String {
    record.builtIn ? "internaldrive" : "externaldrive"
  }

  private var iconAccessibilityLabel: String {
    record.builtIn ? "AirDisk" : "Drives"
  }
}

private struct DiskNameTextField: NSViewRepresentable {
  var text: String

  init(_ text: String) {
    self.text = text
  }

  func makeNSView(context: Context) -> NSTextField {
    let textField = DiskNameNSTextField(frame: .zero)
    textField.isEditable = false
    textField.isSelectable = false
    textField.isBordered = false
    textField.drawsBackground = false
    textField.font = .systemFont(ofSize: 13, weight: .semibold)
    textField.textColor = NSColor.white.withAlphaComponent(0.88)
    textField.lineBreakMode = .byTruncatingTail
    textField.cell?.truncatesLastVisibleLine = true
    textField.cell?.usesSingleLineMode = true
    textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
    return textField
  }

  func updateNSView(_ textField: NSTextField, context: Context) {
    textField.stringValue = text
  }
}

private final class DiskNameNSTextField: NSTextField {
  override func accessibilityRole() -> NSAccessibility.Role? {
    .textField
  }
}
