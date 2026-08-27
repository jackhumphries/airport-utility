import AppKit
import SwiftUI

struct WirelessOptionsSheet: View {
  @EnvironmentObject private var model: AirportAppModel
  @Environment(\.dismiss) private var dismiss
  @State private var draft = WirelessState()
  @State private var legacyDraft = LegacyWirelessOptionsState()
  @State private var loaded = false

  var body: some View {
    ZStack(alignment: .topLeading) {
      Text(localized("Wireless Options"))
        .font(.system(size: 13, weight: .semibold))
        .frame(width: 150, alignment: .leading)
        .offset(x: 18, y: 15)

      Rectangle()
        .fill(Color.primary.opacity(0.14))
        .frame(width: 432, height: 1)
        .offset(x: 24, y: 61)

      optionLabel(localized("Region:"), width: 172)
        .offset(x: 18, y: 84)
      Picker(localized("Region"), selection: $draft.regionCode) {
        ForEach(WirelessRegionOption.allCases) { region in
          Text(region.localizedName).tag(region.code)
        }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .accessibilityIdentifier("wireless.options.region")
      .frame(width: 264, height: 23)
      .offset(x: 195, y: 80)

      WirelessOptionsCheckbox(
        localized("Create hidden network"),
        isOn: $draft.hiddenNetwork,
        identifier: "wireless.options.hidden.network")
        .frame(width: 264, height: 18, alignment: .leading)
        .offset(x: 195, y: 115)

      optionLabel(localized("Radio Mode:"), width: 172)
        .offset(x: 18, y: 140)
      Picker(localized("Radio Mode"), selection: $draft.radioMode) {
        ForEach(Self.radioModeOptions(for: draft.radioMode)) { option in
          Text(option.label).tag(option.value)
        }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .accessibilityIdentifier("wireless.options.radio.mode")
      .frame(width: 264, height: 23)
      .offset(x: 195, y: 136)

      optionLabel(localized("Radio Channel:"), width: 172)
        .offset(x: 18, y: 171)
      Picker(localized("Radio Channel"), selection: $draft.radioChannel) {
        Text(localized("Automatic")).tag("automatic")
        ForEach(Self.radioChannels, id: \.self) { channel in
          Text(channel).tag(channel)
        }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .accessibilityIdentifier("wireless.options.radio.channel")
      .frame(width: 264, height: 23)
      .offset(x: 195, y: 167)

      if model.capabilities.supportsLegacyWirelessOptions {
        optionLabel(localized("Multicast Rate:"), width: 172)
          .offset(x: 18, y: 202)
        Picker(localized("Multicast Rate"), selection: $legacyDraft.multicastRate) {
          ForEach(MulticastRateOption.allCases) { option in
            Text(option.label).tag(option.value)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .accessibilityIdentifier("wireless.options.multicast.rate")
        .frame(width: 264, height: 23)
        .offset(x: 195, y: 198)

        optionLabel(localized("Transmit Power:"), width: 172)
          .offset(x: 18, y: 233)
        Picker(localized("Transmit Power"), selection: $legacyDraft.transmitPower) {
          ForEach(TransmitPowerOption.allCases) { option in
            Text(option.label).tag(option.percent)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .accessibilityIdentifier("wireless.options.transmit.power")
        .frame(width: 264, height: 23)
        .offset(x: 195, y: 229)

        optionLabel(localized("WPA Group Key Timeout:"), width: 172)
          .offset(x: 18, y: 264)
        Picker(localized("WPA Group Key Timeout"), selection: $legacyDraft.groupKeyTimeoutSeconds) {
          ForEach(Self.groupKeyTimeoutOptions, id: \.seconds) { option in
            Text(option.label).tag(option.seconds)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .accessibilityIdentifier("wireless.options.group.key.timeout")
        .frame(width: 264, height: 23)
        .offset(x: 195, y: 260)

        WirelessOptionsCheckbox(
          localized("Use interference robustness"),
          isOn: $legacyDraft.interferenceRobustness,
          identifier: "wireless.options.interference.robustness")
          .frame(width: 264, height: 18, alignment: .leading)
          .offset(x: 195, y: 295)
      }

      // Right-anchored rather than placed at fixed x offsets: a wider translated
      // label ("Abbrechen") would otherwise grow rightward into the Save button.
      // The trailing edge and 12pt gap reproduce the previous English layout
      // exactly (Cancel 308-378, Save 390-460).
      HStack(spacing: 12) {
        WirelessOptionsButton(localized("Cancel"), identifier: "wireless.options.cancel") {
          dismiss()
        }
        WirelessOptionsButton(
          localized("Save"), isDefault: true, isEnabled: hasChanges,
          identifier: "wireless.options.save"
        ) {
          model.wireless = draft
          if model.capabilities.supportsLegacyWirelessOptions {
            model.legacyDeviceOptions.wireless = legacyDraft
          }
          dismiss()
        }
      }
      .frame(width: 460, alignment: .trailing)
      .offset(x: 0, y: actionButtonY)
    }
    .onAppear {
      if !loaded {
        draft = model.wireless
        legacyDraft = model.legacyDeviceOptions.wireless
        loaded = true
      }
    }
    .frame(width: 480, height: sheetHeight, alignment: .topLeading)
    .background(AirPortSheetBackground())
  }

  private static let radioChannels = (1...11).map(String.init)
  private static let groupKeyTimeoutOptions = [
    (seconds: 900, label: localized("15 minutes")),
    (seconds: 1_800, label: localized("30 minutes")),
    (seconds: 3_600, label: localized("1 hour")),
    (seconds: 7_200, label: localized("2 hours")),
    (seconds: 14_400, label: localized("4 hours")),
    (seconds: 28_800, label: localized("8 hours")),
    (seconds: 86_400, label: localized("24 hours")),
  ]

  private var actionButtonY: CGFloat {
    model.capabilities.supportsLegacyWirelessOptions ? 346 : 243
  }

  private var sheetHeight: CGFloat {
    model.capabilities.supportsLegacyWirelessOptions ? 383 : 280
  }

  private var hasChanges: Bool {
    wirelessOptions(draft) != wirelessOptions(model.wireless)
      || (model.capabilities.supportsLegacyWirelessOptions
        && legacyDraft != model.legacyDeviceOptions.wireless)
  }

  static func radioModeOptions(for value: String) -> [WirelessRadioModeOption] {
    WirelessRadioModeOption.options(including: value)
  }

  private func wirelessOptions(_ state: WirelessState) -> WirelessOptionsComparable {
    WirelessOptionsComparable(
      regionCode: AirportValueNormalizer.normalizedIntegerText(state.regionCode),
      hiddenNetwork: state.hiddenNetwork,
      radioMode: AirportValueNormalizer.text(state.radioMode),
      radioChannel: AirportValueNormalizer.normalizedRadioChannel(state.radioChannel)
    )
  }

  /// Right-aligned label ending at the control column. The width extends
  /// leftward to the sheet margin so longer translations have room; English is
  /// unaffected because the text is right-aligned.
  private func optionLabel(_ title: String, width: CGFloat) -> some View {
    Text(title)
      .font(.system(size: 13))
      .frame(width: width, height: 20, alignment: .trailing)
  }
}

private struct WirelessOptionsComparable: Equatable {
  var regionCode: String
  var hiddenNetwork: Bool
  var radioMode: String
  var radioChannel: String
}

private struct WirelessOptionsButton: NSViewRepresentable {
  var title: String
  var isDefault: Bool
  var isEnabled: Bool
  var identifier: String?
  var action: () -> Void

  init(
    _ title: String,
    isDefault: Bool = false,
    isEnabled: Bool = true,
    identifier: String? = nil,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.isDefault = isDefault
    self.isEnabled = isEnabled
    self.identifier = identifier
    self.action = action
  }

  func makeNSView(context: Context) -> NSButton {
    let button = WirelessOptionsNSButton(
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
      equalToConstant: max(70, button.intrinsicContentSize.width)
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
    var parent: WirelessOptionsButton

    init(parent: WirelessOptionsButton) {
      self.parent = parent
    }

    @objc @MainActor func press(_ sender: NSButton) {
      parent.action()
    }
  }
}

private final class WirelessOptionsNSButton: NSButton {
  override func accessibilityTitle() -> String? {
    title
  }
}

private struct WirelessOptionsCheckbox: NSViewRepresentable {
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
    var parent: WirelessOptionsCheckbox

    init(parent: WirelessOptionsCheckbox) {
      self.parent = parent
    }

    @objc @MainActor func toggle(_ sender: NSButton) {
      parent.isOn = sender.state == .on
    }
  }
}
