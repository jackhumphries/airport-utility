import AppKit
import SwiftUI

enum AirPortLayout {
  static let sheetWidth: CGFloat = 520
  static let defaultConfigurationSheetWidth: CGFloat = 566
  static let configurationSheetHeight: CGFloat = 579
  static let configurationSheetInsetHeight: CGFloat = configurationSheetHeight - 42
  static let configurationSheetHorizontalPadding: CGFloat = 13
  static let configurationFooterTopPadding: CGFloat = 12
  static let topTabsHorizontalClearance: CGFloat = 8
  static let crowdedTopTabsHorizontalClearance: CGFloat = 70
  static let formLabelWidth: CGFloat = 190
  static let formColumnSpacing: CGFloat = 18
  static let formControlWidth: CGFloat = 279
  static let formControlLeading: CGFloat = formLabelWidth + formColumnSpacing

  static func configurationSheetWidth(for panes: [Pane]) -> CGFloat {
    let tabsClearance =
      panes.count >= 7 ? crowdedTopTabsHorizontalClearance : topTabsHorizontalClearance
    return max(
      defaultConfigurationSheetWidth,
      topTabsWidth(for: panes)
        + configurationSheetHorizontalPadding * 2
        + tabsClearance)
  }

  static func topTabsWidth(for panes: [Pane]) -> CGFloat {
    panes.reduce(CGFloat(0)) { $0 + topTabWidth(for: $1) }
  }

    static func topTabWidth(for pane: Pane) -> CGFloat {
      switch pane {
      case .baseStation:
        99
      case .internet:
        70
      case .wireless:
        74
      case .network:
        73
      case .airPlay:
        67
      case .disks:
        55
      case .advanced:
        79
      case .firmware:
        82
      case .diagnostics:
        90
    }
  }
}

struct ConfigurationSheet<Content: View>: View {
  @EnvironmentObject private var model: AirportAppModel
  @ViewBuilder var content: Content

  var body: some View {
    VStack(spacing: 0) {
      ZStack(alignment: .top) {
        VStack(spacing: 0) {
          TopTabs()
          content
            .padding(.top, 24)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
      }
      .padding(.horizontal, AirPortLayout.configurationSheetHorizontalPadding)
      .padding(.top, 14)
      .frame(height: 526)
      HStack(spacing: 12) {
        if let status = footerStatus {
          Text(status)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
          Spacer()
        }
        SheetFooterButton("Cancel", width: 70, identifier: "sheet.cancel") {
          model.cancelEditing()
        }
        SheetFooterButton(
          "Update",
          width: 73,
          isDefault: true,
          isEnabled: model.canApplyPendingChanges,
          identifier: "sheet.update"
        ) {
          model.applyPendingChanges()
        }
      }
      .padding(.leading, 20)
      .padding(.trailing, 30)
      .padding(.top, AirPortLayout.configurationFooterTopPadding)
      .padding(.bottom, 20)
    }
    .frame(width: configurationSheetWidth, height: AirPortLayout.configurationSheetHeight)
    .background(AirPortSheetBackground())
    .overlay(alignment: .top) {
      SheetInsetBorder(topGapWidth: configurationSheetWidth - 46)
        .stroke(Color.white.opacity(0.12), lineWidth: 1)
        .frame(
          width: configurationSheetWidth - 40,
          height: AirPortLayout.configurationSheetInsetHeight
        )
        .offset(y: 30)
        .allowsHitTesting(false)
    }
  }

  private var configurationSheetWidth: CGFloat {
    AirPortLayout.configurationSheetWidth(for: model.visiblePanes)
  }

  private var footerStatus: String? {
    let status = model.status.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !status.isEmpty else { return nil }
    guard !status.hasPrefix("Connected"), !status.hasPrefix("Ready to connect"),
      status != "Not connected"
    else {
      return nil
    }
    return status
  }
}

private struct SheetInsetBorder: Shape {
  let topGapWidth: CGFloat

  func path(in rect: CGRect) -> Path {
    let gapStart = rect.midX - topGapWidth / 2
    let gapEnd = rect.midX + topGapWidth / 2
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    path.addLine(to: CGPoint(x: gapStart, y: rect.minY))
    path.move(to: CGPoint(x: gapEnd, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
    return path
  }
}

private struct SheetFooterButton: NSViewRepresentable {
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
    let button = SheetFooterNSButton(
      title: title, target: context.coordinator, action: #selector(Coordinator.press))
    button.bezelStyle = .rounded
    button.controlSize = .regular
    button.font = .systemFont(ofSize: 13)
    button.setButtonType(.momentaryPushIn)
    button.alignment = .center
    button.translatesAutoresizingMaskIntoConstraints = false
    button.widthAnchor.constraint(equalToConstant: width).isActive = true
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
    var parent: SheetFooterButton

    init(parent: SheetFooterButton) {
      self.parent = parent
    }

    @objc @MainActor func press(_ sender: NSButton) {
      parent.action()
    }
  }
}

private final class SheetFooterNSButton: NSButton {
  override func accessibilityTitle() -> String? {
    title
  }
}

struct AirPortSheetBackground: View {
  var body: some View {
    ZStack {
      LinearGradient(
        colors: [
          Color(red: 0.25, green: 0.23, blue: 0.27),
          Color(red: 0.19, green: 0.17, blue: 0.21),
          Color(red: 0.14, green: 0.13, blue: 0.16),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
      LinearGradient(
        colors: [
          Color.white.opacity(0.07),
          Color.clear,
          Color.black.opacity(0.16),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
    }
  }
}

struct TopTabs: View {
  @EnvironmentObject private var model: AirportAppModel

  var body: some View {
    TopTabsControl(selectedPane: $model.selectedPane, panes: model.visiblePanes)
      .frame(width: TopTabsNSView.totalWidth(for: model.visiblePanes), height: 24)
      .padding(.top, 5)
      .onChange(of: model.visiblePanes) { _ in
        model.reconcileSelectedPaneWithCapabilities()
      }
  }
}

private struct TopTabsControl: NSViewRepresentable {
  @Binding var selectedPane: Pane
  var panes: [Pane]

  func makeNSView(context: Context) -> TopTabsNSView {
    let view = TopTabsNSView(action: context.coordinator)
    configure(view)
    return view
  }

  func updateNSView(_ view: TopTabsNSView, context: Context) {
    context.coordinator.selectedPane = $selectedPane
    context.coordinator.panes = panes
    configure(view)
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(selectedPane: $selectedPane, panes: panes)
  }

  private func configure(_ view: TopTabsNSView) {
    view.panes = panes
    view.selectedPane = selectedPane
  }

  @MainActor
  final class Coordinator: NSObject {
    var selectedPane: Binding<Pane>
    var panes: [Pane]

    init(selectedPane: Binding<Pane>, panes: [Pane]) {
      self.selectedPane = selectedPane
      self.panes = panes
    }

    @objc @MainActor func selectPane(_ sender: NSSegmentedControl) {
      guard panes.indices.contains(sender.selectedSegment) else { return }
      selectedPane.wrappedValue = panes[sender.selectedSegment]
    }
  }
}

private final class TopTabsNSView: NSView {
  private let control: NSSegmentedControl
  private var tabElements: [TopTabAccessibilityElement] = []
  var panes: [Pane] = Pane.allCases {
    didSet {
      guard panes != oldValue else { return }
      configureSegments()
    }
  }

  var selectedPane: Pane = .baseStation {
    didSet {
      control.selectedSegment = panes.firstIndex(of: selectedPane) ?? 0
      tabElements.forEach { $0.selectedPane = selectedPane }
    }
  }

  init(action: TopTabsControl.Coordinator) {
    self.control = NSSegmentedControl(
      labels: Pane.allCases.map(\.rawValue),
      trackingMode: .selectOne,
      target: action,
      action: #selector(TopTabsControl.Coordinator.selectPane(_:)))
    super.init(frame: NSRect(x: 0, y: 0, width: 371, height: 24))

    control.segmentStyle = .texturedRounded
    control.controlSize = .small
    control.font = .systemFont(ofSize: 13)
    control.translatesAutoresizingMaskIntoConstraints = false
    control.setAccessibilityElement(false)
    addSubview(control)

    NSLayoutConstraint.activate([
      control.leadingAnchor.constraint(equalTo: leadingAnchor),
      control.trailingAnchor.constraint(equalTo: trailingAnchor),
      control.topAnchor.constraint(equalTo: topAnchor),
      control.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])

    configureSegments()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var intrinsicContentSize: NSSize {
    NSSize(width: Self.totalWidth(for: panes), height: 24)
  }

  override func isAccessibilityElement() -> Bool {
    false
  }

  override func accessibilityChildren() -> [Any]? {
    tabElements
  }

  fileprivate func select(_ pane: Pane) {
    selectedPane = pane
    control.selectedSegment = panes.firstIndex(of: pane) ?? 0
    _ = control.target?.perform(control.action, with: control)
  }

  fileprivate func accessibilityFrame(for pane: Pane) -> NSRect {
    let index = panes.firstIndex(of: pane) ?? 0
    let originX = panes.prefix(index).reduce(CGFloat(0)) { partialResult, pane in
      partialResult + Self.width(for: pane)
    }
    let rect = NSRect(x: originX, y: 0, width: Self.width(for: pane), height: bounds.height)
    guard let window else { return rect }
    return window.convertToScreen(convert(rect, to: nil))
  }

  private func configureSegments() {
    control.segmentCount = panes.count
    tabElements = []
    for (index, pane) in panes.enumerated() {
      control.setLabel(pane.rawValue, forSegment: index)
      control.setWidth(Self.width(for: pane), forSegment: index)
      let element = TopTabAccessibilityElement(owner: self, pane: pane)
      element.setAccessibilityParent(self)
      tabElements.append(element)
    }
    control.selectedSegment = panes.firstIndex(of: selectedPane) ?? 0
    tabElements.forEach { $0.selectedPane = selectedPane }
    invalidateIntrinsicContentSize()
  }

  static func totalWidth(for panes: [Pane]) -> CGFloat {
    AirPortLayout.topTabsWidth(for: panes)
  }

  private static func width(for pane: Pane) -> CGFloat {
    AirPortLayout.topTabWidth(for: pane)
  }
}

private final class TopTabAccessibilityElement: NSAccessibilityElement {
  nonisolated(unsafe) private weak var owner: TopTabsNSView?
  private let pane: Pane

  nonisolated(unsafe) var selectedPane: Pane = .baseStation

  init(owner: TopTabsNSView, pane: Pane) {
    self.owner = owner
    self.pane = pane
    super.init()
  }

  override func accessibilityRole() -> NSAccessibility.Role? {
    .radioButton
  }

  override func accessibilitySubrole() -> NSAccessibility.Subrole? {
    NSAccessibility.Subrole(rawValue: "AXTabButton")
  }

  override func accessibilityTitle() -> String? {
    pane.rawValue
  }

  override func accessibilityIdentifier() -> String? {
    "sheet.tab.\(pane.rawValue.lowercased().replacingOccurrences(of: " ", with: "."))"
  }

  override func accessibilityValue() -> Any? {
    pane == selectedPane ? 1 : 0
  }

  override func accessibilityFrame() -> NSRect {
    MainActor.assumeIsolated { [owner, pane] in
      owner?.accessibilityFrame(for: pane) ?? .zero
    }
  }

  override func accessibilityActionNames() -> [NSAccessibility.Action] {
    [.press]
  }

  override func accessibilityPerformPress() -> Bool {
    MainActor.assumeIsolated { [owner, pane] in
      owner?.select(pane)
    }
    return true
  }
}

struct PaneBox<Content: View>: View {
  var title: String?
  @ViewBuilder var content: Content

  init(title: String? = nil, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if let title {
        Text(title)
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(.white.opacity(0.9))
      }
      VStack(alignment: .leading, spacing: 12) {
        content
      }
    }
    .frame(width: AirPortLayout.sheetWidth, alignment: .leading)
  }
}

struct FormRow<Content: View>: View {
  @Environment(\.isEnabled) private var isEnabled

  var title: String
  @ViewBuilder var content: Content

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: AirPortLayout.formColumnSpacing) {
      Text(title)
        .font(.system(size: 13))
        .frame(width: AirPortLayout.formLabelWidth, alignment: .trailing)
        .foregroundStyle(Color.primary.opacity(isEnabled ? 0.92 : 0.45))
      content
        .frame(width: AirPortLayout.formControlWidth, alignment: .leading)
    }
  }
}

struct PaneActions: View {
  var preview: () -> Void
  var apply: () -> Void

  var body: some View {
    HStack {
      Spacer()
      Button("Preview") { preview() }
        .accessibilityIdentifier("pane.actions.preview")
      Button("Apply") { apply() }
        .accessibilityIdentifier("pane.actions.apply")
    }
    .buttonStyle(AirPortButtonStyle(width: 96))
    .padding(.top, 8)
  }
}

struct CommandPreviewView: View {
  @EnvironmentObject private var model: AirportAppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(model.preview?.title ?? "Command Log")
          .font(.subheadline.weight(.semibold))
        Spacer()
        if model.isBusy {
          ProgressView()
            .scaleEffect(0.7)
        }
      }
      if let preview = model.preview {
        Text(AirportCommand.display(AirportCommand.writeScript, preview.redactedArguments))
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
        Text(preview.output.isEmpty ? "Dry-run completed without output." : preview.output)
          .font(.system(.caption, design: .monospaced))
          .foregroundStyle(.secondary)
          .lineLimit(4)
          .textSelection(.enabled)
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(model.logs.enumerated()), id: \.offset) { _, entry in
              Text(entry)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
          }
        }
      }
    }
    .frame(height: 130)
    .padding(12)
    .frame(width: 760)
    .background(Color.black.opacity(0.30))
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.10), lineWidth: 1))
  }
}

struct AirPortButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  var width: CGFloat?
  var emphasized = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13))
      .foregroundStyle(
        emphasized && isEnabled ? Color.white : Color.primary.opacity(isEnabled ? 1 : 0.45)
      )
      .frame(width: width, height: 22)
      .background(backgroundColor)
      .clipShape(RoundedRectangle(cornerRadius: 5))
      .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.black.opacity(0.20), lineWidth: 1))
      .opacity(configuration.isPressed && isEnabled ? 0.7 : 1)
  }

  private var backgroundColor: Color {
    if emphasized && isEnabled {
      return Color.accentColor
    }
    if isEnabled {
      return Color(red: 0.48, green: 0.48, blue: 0.50)
    }
    if emphasized {
      return Color(red: 0.08, green: 0.08, blue: 0.09)
    }
    return Color(red: 0.43, green: 0.43, blue: 0.45).opacity(0.62)
  }
}

extension View {
  func airPortField(isFocused: Bool = false) -> some View {
    modifier(AirPortFieldModifier(isExternallyFocused: isFocused))
  }
}

private struct AirPortFieldModifier: ViewModifier {
  @Environment(\.isEnabled) private var isEnabled
  var isExternallyFocused: Bool
  @FocusState private var isFocused: Bool

  func body(content: Content) -> some View {
    content
      .focused($isFocused)
      .padding(.horizontal, 7)
      .frame(height: 24)
      .background(
        LinearGradient(
          colors: [
            Color(red: 0.32, green: 0.30, blue: 0.33),
            Color(red: 0.25, green: 0.24, blue: 0.27),
          ],
          startPoint: .top,
          endPoint: .bottom
        )
      )
      .clipShape(RoundedRectangle(cornerRadius: 4))
      .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.34), lineWidth: 1))
      .overlay(
        RoundedRectangle(cornerRadius: 3)
          .stroke(Color.white.opacity(isEnabled ? 0.12 : 0.05), lineWidth: 1)
          .padding(1)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 3)
          .stroke(
            Color.accentColor.opacity(0.9),
            lineWidth: isExternallyFocused || isFocused ? 2 : 0)
          .padding(-1)
      )
      .opacity(isEnabled ? 1 : 0.58)
  }
}
