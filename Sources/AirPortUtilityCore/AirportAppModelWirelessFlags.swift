import Foundation

@MainActor
extension AirportAppModel {
  func wirelessFlags(changesOnly: Bool = false) -> [(String, String?)]? {
    var flags: [(String, String?)] = []
    let wirelessMode = normalized(wireless.mode)
    let wirelessSecurity = normalized(wireless.security)
    let wirelessModeChanged = wirelessMode != normalized(cleanSnapshot.wireless.mode)
    let wirelessNameChanged =
      normalized(wireless.networkName) != normalized(cleanSnapshot.wireless.networkName)
    var allowedWirelessModes: Set<String> = ["create", "extend", "off"]
    if showsWirelessClientModeControls {
      allowedWirelessModes.insert("join")
    }
    if showsClassicWDSWirelessControls {
      allowedWirelessModes.insert("wds")
    }
    let allowedWirelessModeText =
      ["create", "join", "wds", "extend", "off"]
      .filter { allowedWirelessModes.contains($0) }
      .joined(separator: ", ")
    guard
      validateOption(
        wireless.mode,
        cleanValue: cleanSnapshot.wireless.mode,
        changesOnly: changesOnly,
        allowed: allowedWirelessModes,
        statusMessage: "Wireless Mode must be \(allowedWirelessModeText)."
      )
    else { return nil }
    appendChanged(
      &flags, "--wireless-mode", wireless.mode, cleanSnapshot.wireless.mode,
      changesOnly: changesOnly)
    if wirelessMode != "off" {
      guard
        validateOption(
          wireless.security,
          cleanValue: cleanSnapshot.wireless.security,
          changesOnly: changesOnly && !wirelessModeChanged,
          allowed: Set(wirelessSecurityOptions.map(\.rawValue)),
          statusMessage: localized("Wireless Security is not supported.")
        )
      else { return nil }
      let shouldValidateWirelessName = !changesOnly || wirelessModeChanged || wirelessNameChanged
      guard !shouldValidateWirelessName || !normalized(wireless.networkName).isEmpty else {
        status = localized("Wireless Network Name cannot be empty.")
        return nil
      }
      appendChanged(
        &flags, "--wireless-name", wireless.networkName, cleanSnapshot.wireless.networkName,
        changesOnly: changesOnly)
      appendChanged(
        &flags, "--wireless-security", wireless.security, cleanSnapshot.wireless.security,
        changesOnly: changesOnly)
      if wirelessMode == "create" {
        appendChangedBoolean(
          &flags,
          trueFlag: "--allow-network-extension",
          falseFlag: "--no-allow-network-extension",
          value: wireless.allowNetworkExtension,
          cleanValue: cleanSnapshot.wireless.allowNetworkExtension,
          changesOnly: changesOnly)
      }
      if wirelessMode == "wds" {
        guard
          validateOption(
            wireless.wdsMode,
            cleanValue: cleanSnapshot.wireless.wdsMode,
            changesOnly: changesOnly,
            allowed: ["main", "relay", "remote", "off"],
            statusMessage: localized("WDS Mode must be main, relay, remote, or off.")
          )
        else { return nil }
        appendChanged(
          &flags, "--wds-mode", wireless.wdsMode,
          cleanSnapshot.wireless.wdsMode, changesOnly: changesOnly)
        guard isValidWDSPeerAirPortIDs(wireless.wdsPeerAirPortIDs) else {
          status = localized("WDS peer AirPort IDs must be one or two MAC addresses.")
          return nil
        }
        appendChanged(
          &flags, "--wds-peer-airport-id", wireless.wdsPeerAirPortIDs,
          cleanSnapshot.wireless.wdsPeerAirPortIDs, changesOnly: changesOnly)
      }
    }
    if wirelessMode != "off", wirelessSecurity != "none" {
      let wirelessPassword = normalized(wireless.password)
      let verifyWirelessPassword = normalized(wireless.verifyPassword)
      let cleanWirelessPassword = normalized(cleanSnapshot.wireless.password)
      let wirelessSecurityChanged =
        wirelessSecurity != normalized(cleanSnapshot.wireless.security)
      let wirelessPasswordChanged = wirelessPassword != cleanWirelessPassword
      let shouldRewriteWirelessPassword =
        wirelessSecurityChanged || wirelessPasswordChanged
        || (wirelessNameChanged && !wirelessPassword.isEmpty)
      if shouldRewriteWirelessPassword {
        guard !normalized(wireless.networkName).isEmpty else {
          status = localized("Wireless Network Name cannot be empty.")
          return nil
        }
        guard !wirelessPassword.isEmpty else {
          status = localized("Wireless Password cannot be empty.")
          return nil
        }
        guard wirelessPassword == verifyWirelessPassword else {
          status = localized("Wireless passwords do not match.")
          return nil
        }
      }
      if shouldRewriteWirelessPassword {
        if !flags.contains(where: { $0.0 == "--wireless-name" }) {
          flags.append(("--wireless-name", normalized(wireless.networkName)))
        }
        flags.append(("--wireless-password", wirelessPassword))
      }
    }
    if wirelessMode != "off" {
      let regionCode = normalized(wireless.regionCode)
      let radioChannel = normalized(wireless.radioChannel)
      guard
        validateOption(
          wireless.radioMode,
          cleanValue: cleanSnapshot.wireless.radioMode,
          changesOnly: changesOnly && !wirelessModeChanged,
          allowed: [
            "80211b", "80211bg", "80211g", "80211a", "80211n-a", "80211n-bg",
            "80211n-only-24", "80211n-only-5",
          ],
          statusMessage: localized("Radio Mode is not supported."),
          allowEmpty: true
        )
      else { return nil }
      if !regionCode.isEmpty
        && (!changesOnly || regionCode != normalized(cleanSnapshot.wireless.regionCode))
      {
        guard let code = Int(regionCode), (0...255).contains(code) else {
          status = localized("Region code must be between 0 and 255.")
          return nil
        }
      }
      if !radioChannel.isEmpty
        && (!changesOnly || radioChannel != normalized(cleanSnapshot.wireless.radioChannel))
      {
        guard
          radioChannel == "automatic"
            || (Int(radioChannel).map { (1...200).contains($0) } ?? false)
        else {
          status = localized("Radio channel must be 'automatic' or a channel number.")
          return nil
        }
      }
      appendChanged(
        &flags, "--region-code", normalizedIntegerText(wireless.regionCode),
        normalizedIntegerText(cleanSnapshot.wireless.regionCode),
        changesOnly: changesOnly)
      appendChangedBoolean(
        &flags,
        trueFlag: "--hidden-network",
        falseFlag: "--no-hidden-network",
        value: wireless.hiddenNetwork,
        cleanValue: cleanSnapshot.wireless.hiddenNetwork,
        changesOnly: changesOnly
      )
      appendChanged(
        &flags, "--radio-mode", wireless.radioMode, cleanSnapshot.wireless.radioMode,
        changesOnly: changesOnly)
      appendChanged(
        &flags, "--radio-channel", normalizedRadioChannel(wireless.radioChannel),
        normalizedRadioChannel(cleanSnapshot.wireless.radioChannel),
        changesOnly: changesOnly)
    }
    if capabilities.supportsLegacyWirelessOptions && wirelessMode != "off" {
      let options = legacyDeviceOptions.wireless
      let cleanOptions = cleanSnapshot.legacyDeviceOptions.wireless
      guard MulticastRateOption.allCases.contains(where: { $0.value == options.multicastRate })
      else {
        status = localized("Multicast Rate is not supported.")
        return nil
      }
      guard TransmitPowerOption.allCases.contains(where: { $0.percent == options.transmitPower })
      else {
        status = localized("Transmit Power is not supported.")
        return nil
      }
      guard (60...86_400).contains(options.groupKeyTimeoutSeconds) else {
        status = localized("WPA Group Key Timeout must be between 60 seconds and 24 hours.")
        return nil
      }
      appendChanged(
        &flags, "--multicast-rate", String(options.multicastRate),
        String(cleanOptions.multicastRate), changesOnly: changesOnly)
      appendChanged(
        &flags, "--transmit-power", String(options.transmitPower),
        String(cleanOptions.transmitPower), changesOnly: changesOnly)
      appendChanged(
        &flags, "--group-key-timeout-seconds", String(options.groupKeyTimeoutSeconds),
        String(cleanOptions.groupKeyTimeoutSeconds), changesOnly: changesOnly)
      appendChangedBoolean(
        &flags,
        trueFlag: "--interference-robustness",
        falseFlag: "--no-interference-robustness",
        value: options.interferenceRobustness,
        cleanValue: cleanOptions.interferenceRobustness,
        changesOnly: changesOnly)
    }
    return flags
  }

  private func isValidWDSPeerAirPortIDs(_ text: String) -> Bool {
    let ids = text
      .split { $0 == "," || $0 == "\n" || $0 == " " || $0 == "\t" }
      .map(String.init)
    guard !ids.isEmpty, ids.count <= 2 else { return false }
    return ids.allSatisfy { id in
      let hex = id.filter { $0.isHexDigit }
      return hex.count == 12
    }
  }

}
