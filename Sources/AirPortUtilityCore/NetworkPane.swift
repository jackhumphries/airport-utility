import AppKit
import SwiftUI

struct NetworkPane: View {
  @EnvironmentObject private var model: AirportAppModel
  @State private var showOptions = false

  var body: some View {
    PaneBox {
      FormRow(title: localized("Router Mode:")) {
        Picker("", selection: $model.network.routerMode) {
          ForEach(RouterMode.allCases) { mode in
            Text(mode.label).tag(mode)
          }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .accessibilityIdentifier("network.router.mode")
      }
      if model.network.routerMode == .bridge {
        Spacer().frame(height: 42)
      } else {
        FormRow(title: localized("LAN IP Address:")) {
          AirPortTextField(
            text: $model.network.lanIPAddress,
            placeholder: localized("LAN IP address"),
            identifier: "network.lan.ip.address")
        }
        FormRow(title: localized("DHCP Range:")) {
          DHCPRangeSummary(network: $model.network)
        }
      }
      NetworkTableSection(
        title: localized("DHCP Reservations:"),
        columns: (localized("Description"), localized("IP Address")),
        tableIdentifier: "dhcpTable",
        disabled: model.network.routerMode == .bridge
      )
      NetworkTableSection(
        title: localized("Port Settings:"),
        columns: (localized("Description"), localized("Type")),
        tableIdentifier: "natTable",
        disabled: model.network.routerMode != .dhcpAndNat
      )
      Spacer().frame(height: 28)
      HStack {
        Spacer().frame(width: AirPortLayout.formControlLeading)
        NetworkPaneButton(
          localized("Network Options..."), identifier: "network.options.open"
        ) { showOptions = true }
          .frame(width: 147, height: 22)
          .disabled(model.network.routerMode == .bridge)
      }
    }
    .sheet(isPresented: $showOptions) {
      NetworkOptionsSheet()
        .environmentObject(model)
    }
  }
}

private struct NetworkPaneButton: NSViewRepresentable {
  @Environment(\.isEnabled) private var isEnabled

  var title: String
  var identifier: String?
  var action: () -> Void

  init(_ title: String, identifier: String? = nil, action: @escaping () -> Void) {
    self.title = title
    self.identifier = identifier
    self.action = action
  }

  func makeNSView(context: Context) -> NSButton {
    let button = NetworkPaneNSButton(
      title: title, target: context.coordinator, action: #selector(Coordinator.press))
    button.bezelStyle = .rounded
    button.controlSize = .regular
    button.font = .systemFont(ofSize: 13)
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
    button.setAccessibilityTitle(title)
    button.identifier = identifier.map { NSUserInterfaceItemIdentifier($0) }
    button.setAccessibilityIdentifier(identifier)
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  final class Coordinator: NSObject {
    var parent: NetworkPaneButton

    init(parent: NetworkPaneButton) {
      self.parent = parent
    }

    @objc @MainActor func press(_ sender: NSButton) {
      parent.action()
    }
  }
}

private final class NetworkPaneNSButton: NSButton {
  override func accessibilityTitle() -> String? {
    title
  }
}

struct DHCPRangeSummary: View {
  @Binding var network: NetworkState

  var body: some View {
    Group {
      if network.routerMode == .dhcpOnly {
        HStack(spacing: 4) {
          NetworkOptionsTextField(
            text: $network.dhcpRangeStart,
            identifier: "network.dhcp.range.start")
            .frame(width: 129, height: 24)
          Text("to")
            .frame(width: 18)
          NetworkOptionsTextField(
            text: $network.dhcpRangeEnd,
            identifier: "network.dhcp.range.end")
            .frame(width: 129, height: 24)
        }
      } else {
        Text("\(network.dhcpRangeStart) to \(network.dhcpRangeEnd)")
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .onChange(of: network.routerMode) { newMode in
      if newMode == .dhcpOnly,
        network.dhcpRangeStart == "10.0.1.2",
        network.dhcpRangeEnd == "10.0.1.200"
      {
        network.dhcpRangeStart = "192.168.4.2"
        network.dhcpRangeEnd = "192.168.4.200"
      }
    }
  }
}

struct NetworkTableSection: View {
  var title: String
  var columns: (String, String)
  var tableIdentifier: String
  var disabled: Bool

  var body: some View {
    HStack(alignment: .top, spacing: AirPortLayout.formColumnSpacing) {
      Text(title)
        .font(.system(size: 13))
        .frame(width: AirPortLayout.formLabelWidth, alignment: .trailing)
        .foregroundStyle(Color.primary.opacity(disabled ? 0.45 : 1))
      VStack(alignment: .leading, spacing: 6) {
        TwoColumnEmptyTable(columns: columns, tableIdentifier: tableIdentifier, disabled: disabled)
        HStack(spacing: 0) {
          NetworkTableAddRemoveButtons(tableIdentifier: tableIdentifier, addEnabled: false)
            .frame(width: 47, height: 23)
          Spacer()
          NetworkTableEditButton(tableIdentifier: tableIdentifier)
            .frame(width: 44, height: 22)
        }
        .frame(width: 277)
      }
      .frame(width: AirPortLayout.formControlWidth, alignment: .leading)
    }
  }
}

private struct NetworkTableAddRemoveButtons: NSViewRepresentable {
  var tableIdentifier: String
  var addEnabled: Bool

  func makeNSView(context: Context) -> NSView {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 47, height: 23))
    view.addSubview(
      makeButton(
        symbolName: "plus", actionName: "add", accessibilityDescription: "add"))
    let removeButton = makeButton(
      symbolName: "minus", actionName: "remove", accessibilityDescription: "remove")
    removeButton.frame.origin.x = 22
    removeButton.isEnabled = false
    view.addSubview(removeButton)
    updateButtons(in: view)
    return view
  }

  func updateNSView(_ view: NSView, context: Context) {
    updateButtons(in: view)
  }

  private func makeButton(
    symbolName: String, actionName: String, accessibilityDescription: String
  ) -> NSButton {
    let button = NetworkTableControlNSButton(frame: NSRect(x: 0, y: 0, width: 25, height: 23))
    button.bezelStyle = .smallSquare
    button.controlSize = .small
    button.font = .systemFont(ofSize: 11, weight: .semibold)
    button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
    button.imagePosition = .imageOnly
    button.imageScaling = .scaleNone
    button.isBordered = true
    button.title = ""
    button.axDescription = accessibilityDescription
    let identifier = "\(tableIdentifier).\(actionName)"
    button.identifier = NSUserInterfaceItemIdentifier(identifier)
    button.setAccessibilityIdentifier(identifier)
    return button
  }

  private func updateButtons(in view: NSView) {
    guard view.subviews.count == 2,
      let addButton = view.subviews[0] as? NSButton,
      let removeButton = view.subviews[1] as? NSButton
    else { return }
    addButton.isEnabled = addEnabled
    removeButton.isEnabled = false
  }
}

private final class NetworkTableControlNSButton: NSButton {
  var axDescription = ""

  override func accessibilityTitle() -> String? {
    ""
  }

  override func accessibilityLabel() -> String? {
    axDescription
  }
}

private struct NetworkTableEditButton: NSViewRepresentable {
  var tableIdentifier: String

  func makeNSView(context: Context) -> NSButton {
    let button = NetworkTableEditNSButton(title: localized("Edit"), target: nil, action: nil)
    button.bezelStyle = .rounded
    button.controlSize = .regular
    button.font = .systemFont(ofSize: 13)
    button.identifier = NSUserInterfaceItemIdentifier("_NS:ID")
    configure(button)
    return button
  }

  func updateNSView(_ button: NSButton, context: Context) {
    configure(button)
  }

  private func configure(_ button: NSButton) {
    button.title = localized("Edit")
    button.target = nil
    button.action = nil
    button.isEnabled = false
    let identifier = "\(tableIdentifier).edit"
    button.identifier = NSUserInterfaceItemIdentifier(identifier)
    button.setAccessibilityIdentifier(identifier)
  }
}

private final class NetworkTableEditNSButton: NSButton {
  override func isAccessibilityEnabled() -> Bool {
    false
  }

  override func accessibilityPerformPress() -> Bool {
    false
  }
}

struct TwoColumnEmptyTable: View {
  var columns: (String, String)
  var tableIdentifier: String
  var disabled = false

  var body: some View {
    EmptyNetworkTable(columns: columns, tableIdentifier: tableIdentifier, disabled: disabled)
      .frame(width: 277, height: 94)
      .opacity(disabled ? 0.82 : 1)
  }
}

private struct EmptyNetworkTable: NSViewRepresentable {
  var columns: (String, String)
  var tableIdentifier: String
  var disabled: Bool

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 277, height: 94))
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = false
    scrollView.hasHorizontalScroller = false
    scrollView.borderType = .lineBorder
    scrollView.autohidesScrollers = true

    let tableView = EmptyNetworkNSTableView(frame: scrollView.bounds)
    tableView.dataSource = context.coordinator
    tableView.delegate = context.coordinator
    tableView.headerView = NSTableHeaderView()
    tableView.allowsColumnReordering = false
    tableView.allowsColumnResizing = false
    tableView.allowsColumnSelection = false
    tableView.allowsMultipleSelection = false
    tableView.allowsEmptySelection = true
    tableView.columnAutoresizingStyle = .noColumnAutoresizing
    tableView.focusRingType = .none
    tableView.gridStyleMask = []
    tableView.intercellSpacing = NSSize(width: 0, height: 0)
    tableView.rowHeight = 22
    tableView.selectionHighlightStyle = .none
    tableView.style = .plain
    tableView.usesAlternatingRowBackgroundColors = false
    tableView.backgroundColor = .clear
    tableView.setAccessibilityIdentifier(tableIdentifier)

    scrollView.documentView = tableView
    configure(tableView)
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard let tableView = scrollView.documentView as? NSTableView else { return }
    configure(tableView)
    tableView.reloadData()
  }

  private func configure(_ tableView: NSTableView) {
    tableView.tableColumns.forEach { tableView.removeTableColumn($0) }

    let firstWidth: CGFloat = columns.1 == localized("Type") ? 228 : 156.5
    let secondWidth: CGFloat = columns.1 == localized("Type") ? 47 : 118.5
    for (index, columnTitle) in [columns.0, columns.1].enumerated() {
      let tableColumn = NSTableColumn(
        identifier: NSUserInterfaceItemIdentifier("AutomaticTableColumnIdentifier.\(index)")
      )
      tableColumn.title = columnTitle
      tableColumn.width = index == 0 ? firstWidth : secondWidth
      tableColumn.minWidth = tableColumn.width
      tableColumn.maxWidth = tableColumn.width
      tableColumn.isEditable = false
      tableView.addTableColumn(tableColumn)
    }

    tableView.isEnabled = !disabled
    if let emptyTable = tableView as? EmptyNetworkNSTableView {
      emptyTable.isInactive = disabled
    }
    tableView.headerView?.needsDisplay = true
    tableView.needsDisplay = true
  }

  final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
      0
    }
  }
}

private final class EmptyNetworkNSTableView: NSTableView {
  var isInactive = false

  override func drawBackground(inClipRect clipRect: NSRect) {
    NSColor(red: 0.20, green: 0.16, blue: 0.21, alpha: isInactive ? 0.82 : 1).setFill()
    clipRect.fill()

    let bodyMinY = bounds.minY
    let stripeHeight: CGFloat = 19
    let colors = [
      NSColor.black.withAlphaComponent(isInactive ? 0.54 : 0.78),
      NSColor(red: 0.29, green: 0.24, blue: 0.30, alpha: isInactive ? 0.78 : 1),
      NSColor.black.withAlphaComponent(isInactive ? 0.54 : 0.78),
    ]

    for (index, color) in colors.enumerated() {
      color.setFill()
      NSRect(
        x: bounds.minX,
        y: bodyMinY + CGFloat(index) * stripeHeight,
        width: bounds.width,
        height: stripeHeight
      )
      .fill()
    }
  }
}
