import Foundation

@MainActor
extension AirportAppModel {
  var hasPendingChanges: Bool {
    comparable(currentSnapshot) != comparable(cleanSnapshot)
  }

  var canApplyPendingChanges: Bool {
    !isBusy && selectedPane != .firmware && hasPendingChanges
  }

  func cancelEditing() {
    preview = nil
    restore(
      snapshot: cleanSnapshot,
      capabilities: cleanCapabilities,
      hasDetectedIPv6Support: cleanHasDetectedIPv6Support,
      hasDetectedDynamicGlobalHostnameSupport: cleanHasDetectedDynamicGlobalHostnameSupport,
      hasDetectedClassicWDSSupport: cleanHasDetectedClassicWDSSupport)
    isEditingDevice = false
    selectedPane = .baseStation
  }

  public func beginEditing() {
    preview = nil
    isDevicePopoverPresented = false
    isInternetPopoverPresented = false
    clearAuxiliarySheets()
    selectedPane = .baseStation
    isEditingDevice = true
  }

  func handleInternetConnectUsingChanged(_ newValue: ConnectUsing) {
    guard newValue != .dhcp else { return }
    if internet.dnsServers.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !internet.dnsServerPreview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      internet.dnsServers = internet.dnsServerPreview
      internet.dnsServerPreview = ""
    }
    if internet.ipv6DNSServers.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !internet.ipv6DNSServerPreview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      internet.ipv6DNSServers = internet.ipv6DNSServerPreview
      internet.ipv6DNSServerPreview = ""
    }
  }

  func beginEditingFirmware() {
    beginEditing()
    if supportsPane(.firmware) {
      selectedPane = .firmware
    }
  }

  public func showPasswords() {
    guard canShowPasswords else { return }
    prepareAuxiliarySheetPresentation()
    isShowingPasswords = true
  }

  public var canShowPasswords: Bool {
    selectedTopologyDevice() != nil
  }

  public func showPreferences() {
    prepareAuxiliarySheetPresentation()
    isShowingPreferences = true
  }

  public func showConfigureOther() {
    prepareAuxiliarySheetPresentation()
    isShowingConfigureOther = true
  }

  public func showSites() {
    prepareAuxiliarySheetPresentation()
    isShowingSites = true
  }

  func prepareAuxiliarySheetPresentation() {
    isEditingDevice = false
    isDevicePopoverPresented = false
    isInternetPopoverPresented = false
    isShowingRestartConfirmation = false
    isShowingRestoreConfirmation = false
    clearAuxiliarySheets()
  }

  func clearAuxiliarySheets() {
    isShowingPasswords = false
    isShowingPreferences = false
    isShowingConfigureOther = false
    isShowingSites = false
  }

  public var defaultConfigurationFileName: String {
    let name = baseStation.name.trimmingCharacters(in: .whitespacesAndNewlines)
    let baseName = name.isEmpty ? "AirPort Configuration" : name
    let invalidCharacters = CharacterSet(charactersIn: "/:")
      .union(.newlines)
      .union(.controlCharacters)
    let sanitized =
      baseName
      .components(separatedBy: invalidCharacters)
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return (sanitized.isEmpty ? "AirPort Configuration" : sanitized) + ".baseconfig"
  }

  public func exportConfiguration(to url: URL) throws {
    let data: Data
    if url.pathExtension.lowercased() == "json" {
      let configuration = AirportConfigurationFile(settings: currentSnapshot)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      data = try encoder.encode(configuration)
    } else {
      data = try AirportBaseConfigurationFile.data(
        from: currentSnapshot,
        capabilities: capabilities)
    }
    try data.write(to: url, options: [.atomic])
    status = "Exported configuration to \(url.lastPathComponent)."
    appendLog("Exported configuration file: \(url.path)")
  }

  public func importConfiguration(from url: URL) throws {
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    if url.pathExtension.lowercased() == "baseconfig"
      || url.pathExtension.lowercased() == "basebinary"
    {
      let profile = try AirportBaseConfigurationFile.profileValue(from: data)
      applyImportedProfile(profile)
    } else if let configuration = try? decoder.decode(AirportConfigurationFile.self, from: data) {
      restore(snapshot: configuration.settings)
    } else if let profile = try? AirportBaseConfigurationFile.profileValue(from: data) {
      applyImportedProfile(profile)
    } else {
      let profile = try decoder.decode(JSONValue.self, from: data)
      applyImportedProfile(profile)
    }
    preview = nil
    isDevicePopoverPresented = false
    isInternetPopoverPresented = false
    clearAuxiliarySheets()
    isEditingDevice = true
    selectedPane = .baseStation
    status =
      "Imported configuration from \(url.lastPathComponent). Review and click Update to apply."
    appendLog("Imported configuration file: \(url.path)")
  }

  func applyImportedProfile(_ profile: JSONValue) {
    let reader = ProfileReader.normalized(profile)
    apply(profile: profile)
    applyProfileInternetFeatureSupport(reader, treatsMissingAsUnsupported: true)
  }

  var currentSnapshot: AirportSettingsSnapshot {
    AirportSettingsSnapshot(
      baseStation: baseStation,
      internet: internet,
      wireless: wireless,
      network: network,
      airPlay: airPlay,
      disks: disks,
      advanced: advanced,
      legacyDeviceOptions: legacyDeviceOptions
    )
  }

  func restore(
    snapshot: AirportSettingsSnapshot,
    capabilities restoredCapabilities: DeviceCapabilities? = nil,
    hasDetectedIPv6Support restoredHasDetectedIPv6Support: Bool? = nil,
    hasDetectedDynamicGlobalHostnameSupport restoredHasDetectedDynamicGlobalHostnameSupport:
      Bool? = nil,
    hasDetectedClassicWDSSupport restoredHasDetectedClassicWDSSupport: Bool? = nil
  ) {
    baseStation = snapshot.baseStation
    internet = snapshot.internet
    wireless = snapshot.wireless
    network = snapshot.network
    airPlay = snapshot.airPlay
    disks = snapshot.disks
    advanced = snapshot.advanced
    legacyDeviceOptions = snapshot.legacyDeviceOptions
    if let restoredCapabilities {
      capabilities = restoredCapabilities
      firmware.productID = baseStation.productID.trimmingCharacters(in: .whitespacesAndNewlines)
      hasDetectedIPv6Support = restoredHasDetectedIPv6Support ?? false
      hasDetectedDynamicGlobalHostnameSupport =
        restoredHasDetectedDynamicGlobalHostnameSupport ?? false
      hasDetectedClassicWDSSupport = restoredHasDetectedClassicWDSSupport ?? false
    } else {
      var restoredCapabilities = DeviceCapabilities.forProductID(baseStation.productID)
      let supportsIPv6 = hasImportedIPv6Settings(snapshot.internet)
      let supportsDynamicGlobalHostname = hasImportedDynamicGlobalHostnameSettings(
        snapshot.internet)
      restoredCapabilities.supportsIPv6 = supportsIPv6
      restoredCapabilities.supportsDynamicGlobalHostname = supportsDynamicGlobalHostname
      capabilities = restoredCapabilities
      firmware.productID = baseStation.productID.trimmingCharacters(in: .whitespacesAndNewlines)
      hasDetectedIPv6Support = supportsIPv6
      hasDetectedDynamicGlobalHostnameSupport = supportsDynamicGlobalHostname
      hasDetectedClassicWDSSupport = false
    }
    reconcileSelectedPaneWithCapabilities()
  }

  func hasImportedIPv6Settings(_ internet: InternetState) -> Bool {
    !AirportValueNormalizer.text(internet.ipv6DNSServers).isEmpty
      || !AirportValueNormalizer.normalizedIPv6Address(internet.ipv6Address).isEmpty
      || internet.configureIPv6.trimmingCharacters(in: .whitespacesAndNewlines) != "link-local"
  }

  func hasImportedDynamicGlobalHostnameSettings(_ internet: InternetState) -> Bool {
    internet.dynamicGlobalHostname
      || !AirportValueNormalizer.text(internet.globalHostname).isEmpty
      || !AirportValueNormalizer.text(internet.globalHostnameUser).isEmpty
      || !AirportValueNormalizer.text(internet.globalHostnamePassword).isEmpty
  }
}
