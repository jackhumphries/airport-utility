import Foundation

extension AirportAppModel {
  private static let identityACPSettings = ["syNm", "sySN", "syVs", "syAP"]
  private static let deviceStatusACPSettings = ["sySt"]
  private static let liveInternetACPSettings = [
    "waCV", "waIP", "waSM", "waRA", "peAC", "peSC", "6cfg", "6aut", "6Wad", "wbEn",
    "waD1", "waD2", "waD3", "waC1", "waC2", "waC3", "6NS1", "6NS2", "waDN",
    "peUN", "pePW", "peSN", "wbHN", "wbHU", "wbHP",
    "moPN", "moAP", "moUN", "moPW", "moID", "moCI", "moMP", "moPD", "moAD", "moDT",
    "moMF",
  ]
  private static let liveWirelessACPSettings = [
    "raSt", "raNm", "raWM", "syRe", "raCl", "raMd", "raCh", "dWDS", "bsWM", "wdLs",
    "raMu", "raPo", "raKT", "raRo",
  ]
  private static let liveAirPlayACPSettings = ["auRR", "auNN", "auNP", "aWan"]
  private static let liveBaseStationACPSettings = [
    "raWB", "waNM", "syCt", "syLo", "ntSV",
  ]
  private static let liveNetworkACPSettings = [
    "laIP", "dhBg", "dhEn", "dhLe", "naFl", "nDMZ", "dhMg", "dh95",
  ]
  private static let liveAdvancedACPSettings = [
    "slCl", "slvl", "snAF", "pdFl", "pdUN", "pdPW", "pdAR", "pdID", "pdMC",
    "acEn", "acTa", "raFl", "raCi", "raI1", "raSe", "raAu", "raI2", "raS2", "raU2",
    "raF2",
  ]
  private static let dnsPreviewIPv4ACPSettingGroups = [
    ["waC1", "waC2", "waC3"],
    ["waD1", "waD2", "waD3"],
  ]
  private static let dnsPreviewIPv6ACPSettingGroups = [
    ["6NS1", "6NS2"]
  ]
  private static let ipv6FeatureACPSettings = [
    "6cfg", "6aut", "6Wad", "6NS1", "6NS2", "6Wgw", "6sfw",
  ]
  private static let dynamicGlobalHostnameFeatureACPSettings = [
    "wbEn", "wbAC", "wbHN", "wbHU", "wbHP",
  ]
  private static let classicWDSFeatureACPSettings = ["bsWM"]
  private static let loggingFeatureACPSettings = ["slCl", "slvl", "snAF"]
  private static let pppDialInFeatureACPSettings = [
    "pdFl", "pdUN", "pdPW", "pdAR", "pdID", "pdMC",
  ]
  private static let baseStationMetadataFeatureACPSettings = ["syCt", "syLo"]
  private static let legacyWirelessOptionsFeatureACPSettings = ["raMu", "raPo", "raKT", "raRo"]
  private static let legacyDHCPOptionsFeatureACPSettings = ["dhMg", "dh95"]
  private static let accessControlFeatureACPSettings = [
    "acEn", "acTa", "raFl", "raCi", "raI1", "raAu",
  ]
  private static let refreshBaseACPSettings =
    identityACPSettings + deviceStatusACPSettings + ["Prof", "MaSt"]
  private static let refreshLiveACPSettings =
    liveInternetACPSettings + liveWirelessACPSettings + liveAirPlayACPSettings
    + liveBaseStationACPSettings + liveNetworkACPSettings + liveAdvancedACPSettings
  private static let refreshACPSettings = refreshBaseACPSettings + refreshLiveACPSettings

  func refreshSettings() async throws {
    if mockMode {
      loadMockState()
      appendLog("Mock refresh completed.")
      return
    }

    let requestConnection = connection
    let requestHost = AirportConnection.normalizedHost(requestConnection.host)
    usesLegacyACP = false
    let batch = try await readSettingsBatch(Self.refreshACPSettings, connection: requestConnection)
    let reader = batch.reader
    let identity = try Self.baseStationIdentity(from: reader)
    guard reader.hasValue(at: "settings.Prof.decoded") || Self.hasDirectProfileSettings(reader)
    else {
      throw AirportServiceReadError.missingSetting("Prof")
    }
    let diskInventory = Self.diskInventoryRefreshResult(from: reader, rawOutput: batch.rawOutput)
    let supportsIPv6 = Self.hasAnySetting(Self.ipv6FeatureACPSettings, in: reader)
    let supportsDynamicGlobalHostname = Self.hasAnySetting(
      Self.dynamicGlobalHostnameFeatureACPSettings, in: reader)
    let supportsClassicWDS = Self.hasAnySetting(Self.classicWDSFeatureACPSettings, in: reader)
    let supportsLogging = Self.hasAnySetting(Self.loggingFeatureACPSettings, in: reader)
    let supportsPPPDialIn = Self.hasAnySetting(Self.pppDialInFeatureACPSettings, in: reader)
    let supportsBaseStationMetadata = Self.hasAnyLiveSetting(
      Self.baseStationMetadataFeatureACPSettings, in: reader)
    let supportsLegacyWirelessOptions = Self.hasAnySetting(
      Self.legacyWirelessOptionsFeatureACPSettings, in: reader)
    let supportsLegacyDHCPOptions = Self.hasAnySetting(
      Self.legacyDHCPOptionsFeatureACPSettings, in: reader)
    let supportsAccessControl = Self.hasAnySetting(
      Self.accessControlFeatureACPSettings, in: reader)

    guard !isEditingDevice else {
      status = "Finish editing before refreshing settings."
      appendLog("Ignored settings refresh while editing.")
      return
    }
    guard connectionStillMatches(requestHost) else {
      appendLog("Ignored settings refresh for stale host \(requestHost).")
      return
    }

    apply(profile: batch.value)
    if usesLegacyACP {
      legacySNMPCommunity = Self.legacySNMPCommunity(
        configured: reader.string("settings.snCS"),
        adminPassword: requestConnection.password)
      legacyACPSettingsValuesJSON = Self.legacySettingsValuesJSON(
        from: batch.value,
        excluding: identity.productID == "3" ? [] : ["acTa"])
    } else {
      legacySNMPCommunity = ""
      legacyACPSettingsValuesJSON = ""
    }
    let liveAirPlaySettings = Self.liveAirPlaySettings(reader: reader)
    apply(liveInternetSettings: Self.liveInternetSettings(reader: reader))
    apply(liveWirelessSettings: Self.liveWirelessSettings(reader: reader))
    apply(liveAirPlaySettings: liveAirPlaySettings)
    apply(liveAdvancedSettings: Self.liveAdvancedSettings(reader: reader))
    applyLiveLegacyDeviceOptions(reader: reader)
    if let allowSetupOverWAN = Self.liveAllowSetupOverWAN(reader: reader) {
      baseStation.allowSetupOverWAN = allowSetupOverWAN
    }
    applyDeviceStatus(
      problemCodes: Self.deviceProblemCodes(
        reader: reader, allowSetupOverWAN: baseStation.allowSetupOverWAN))
    updateCapabilities(
      productID: identity.productID,
      hasAirPlaySupport: Self.hasLiveAirPlaySettings(reader: reader),
      hasDiskSupport: diskInventory != nil,
      supportsIPv6: supportsIPv6,
      supportsDynamicGlobalHostname: supportsDynamicGlobalHostname,
      supportsClassicWDS: supportsClassicWDS,
      supportsLogging: supportsLogging,
      supportsPPPDialIn: supportsPPPDialIn,
      supportsBaseStationMetadata: supportsBaseStationMetadata,
      supportsLegacyWirelessOptions: supportsLegacyWirelessOptions,
      supportsLegacyDHCPOptions: supportsLegacyDHCPOptions,
      supportsAccessControl: supportsAccessControl)
    applyLiveDNSPreviewFallbackIfNeeded(reader: reader, requestHost: requestHost)
    guard connectionStillMatches(requestHost) else {
      ignoreStaleOperation(
        "Ignored settings refresh after DNS fallback for stale host \(requestHost).")
      return
    }
    applyAuthoritativeBaseStationIdentity(
      readName: identity.name,
      serialNumber: identity.serialNumber,
      version: identity.version,
      productID: identity.productID,
      supportsIPv6: supportsIPv6,
      supportsDynamicGlobalHostname: supportsDynamicGlobalHostname,
      supportsClassicWDS: supportsClassicWDS,
      supportsLogging: supportsLogging,
      supportsPPPDialIn: supportsPPPDialIn,
      supportsBaseStationMetadata: supportsBaseStationMetadata,
      supportsLegacyWirelessOptions: supportsLegacyWirelessOptions,
      supportsLegacyDHCPOptions: supportsLegacyDHCPOptions,
      supportsAccessControl: supportsAccessControl)
    applyDiskInventoryRefreshResult(diskInventory)
    loadAuxiliaryPasswordsFromStore()
    markClean()
    hasLoadedSettings = true
    hasTrustedConnectionPassword = true
    status = "Connected to \(connection.host)"
    clearBaseStationUpdate(requestHost: requestHost)
    showConnectionDetails = false
    saveConnectionPasswordIfRequested()
    scheduleAutomaticFirmwareCatalogRefreshIfNeeded(requestHost: requestHost)
    scheduleAutomaticConfigurationBackupIfNeeded(requestHost: requestHost)
    restartWirelessClientPollingIfPossible()
    refreshStorageHealthIfPossible()
    appendLog("Refresh completed.")
  }

  func readBaseStationIdentity(connection: AirportConnection? = nil) async throws -> (
    name: String, serialNumber: String, version: String, productID: String
  ) {
    let connection = connection ?? self.connection
    let reader = try await readSettingsReader(Self.identityACPSettings, connection: connection)
    return try Self.baseStationIdentity(from: reader)
  }

  private static func baseStationIdentity(from reader: ProfileReader) throws -> (
    name: String, serialNumber: String, version: String, productID: String
  ) {
    guard let name = reader.string("settings.syNm") else {
      throw AirportServiceReadError.missingSetting("syNm")
    }
    // The original 802.11g AirPort Extreme (product 3) does not return sySN
    // even though the rest of its identity and profile snapshot are valid.
    let serial = reader.string("settings.sySN") ?? ""
    guard let version = reader.string("settings.syVs") else {
      throw AirportServiceReadError.missingSetting("syVs")
    }
    let productID = reader.string("settings.syAP") ?? ""
    return (name, serial, version, productID)
  }

  func refreshLiveSettingsIfPossible() {
    guard !mockMode, !isBusy, !isEditingDevice, liveCredentialsAvailable, !hasLoadedSettings else {
      return
    }
    refresh()
  }

  func refreshBaseStationIdentityIfNeeded() {
    guard !mockMode, !isBusy, !isEditingDevice, liveCredentialsAvailable, hasLoadedSettings else {
      return
    }
    guard
      baseStation.serialNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || baseStation.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return
    }

    let requestHost = AirportConnection.normalizedHost(connection.host)
    Task {
      do {
        let identity = try await readBaseStationIdentity()
        applyIdentityIfConnectionStillMatches(
          requestHost: requestHost,
          readName: identity.name,
          serialNumber: identity.serialNumber,
          version: identity.version,
          productID: identity.productID
        )
      } catch {
        appendIdentityRefreshFailureIfConnectionStillMatches(
          requestHost: requestHost,
          errorDescription: error.localizedDescription
        )
      }
    }
  }

  private func readTextSetting(_ setting: String, connection: AirportConnection? = nil) async throws
    -> String
  {
    let connection = connection ?? self.connection
    let result = try await runner.run(
      script: AirportCommand.readScript,
      arguments: AirportCommand.readSetting(setting, connection: connection), connection: connection
    )
    return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func readSettingsBatch(
    _ settings: [String], connection: AirportConnection? = nil
  ) async throws -> AirportSettingsBatch {
    let connection = connection ?? self.connection
    let settings = Self.uniqueACPSettings(settings)
    guard !settings.isEmpty else {
      throw AirportServiceReadError.missingSetting("settings")
    }
    let arguments = AirportCommand.readSettings(settings, connection: connection, json: true)
    let result: CommandResult
    do {
      result = try await runner.run(
        script: AirportCommand.readScript,
        arguments: arguments,
        connection: connection)
    } catch {
      guard Self.shouldRetryWithLegacyACP(error) else { throw error }
      usesLegacyACP = true
      let legacySettings = Self.uniqueACPSettings(
        settings + Self.legacySetupSnapshotSettings + Self.legacyExtremeSnapshotSettings + ["snCS"])
      var legacyArguments = AirportCommand.readSettings(
        legacySettings, connection: connection, json: true
      ).usingAirPortBackendSubcommand("legacy-read")
      if usesLegacyACP17 {
        legacyArguments.append("--acp17")
      }
      result = try await runner.run(
        script: AirportCommand.legacyReadScript,
        arguments: legacyArguments,
        connection: connection)
    }
    let value = try JSONDecoder().decode(JSONValue.self, from: Data(result.stdout.utf8))
    return AirportSettingsBatch(rawOutput: result.stdout, value: value)
  }

  nonisolated static func shouldRetryWithLegacyACP(_ error: Error) -> Bool {
    let description = error.localizedDescription.lowercased()
    return description.contains("srp challenge failed with acp status -16")
      || description.contains("srp challenge failed with acp status -0x10")
  }

  private static func hasDirectProfileSettings(_ reader: ProfileReader) -> Bool {
    ["syNm", "sySN", "syVs", "syAP", "waCV", "waIP", "raNm", "auNN"].contains {
      reader.hasValue(at: "settings.\($0)")
    }
  }

  func readSettingsReader(
    _ settings: [String], connection: AirportConnection? = nil
  ) async throws -> ProfileReader {
    try await readSettingsBatch(settings, connection: connection).reader
  }

  private static func uniqueACPSettings(_ settings: [String]) -> [String] {
    var seen: Set<String> = []
    var unique: [String] = []
    for setting in settings {
      guard setting.utf8.count == 4, !seen.contains(setting) else { continue }
      seen.insert(setting)
      unique.append(setting)
    }
    return unique
  }

  private static func liveInternetSettings(reader: ProfileReader?) -> LiveInternetSettings {
    let connectUsingText = reader?.string("settings.waCV")
    let pppoeActiveText = reader?.string("settings.peAC")
    let pppoeStayConnectedText = reader?.string("settings.peSC")
    let ipv6ConfigText = reader?.string("settings.6cfg")
    let ipv6AutomaticText = reader?.string("settings.6aut")
    let ipv6FirewallText = reader?.string("settings.6sfw")
    let dynamicHostnameText = reader?.string("settings.wbEn")
    let dynamicHostnameAutoConfigText = reader?.string("settings.wbAC")

    return LiveInternetSettings(
      connectUsing: Self.liveSettingReader(connectUsingText)?.connectUsing("value"),
      dnsServers: Self.liveAddressSettings(["waD1", "waD2", "waD3"], reader: reader) {
        $0.ipv4Address("settings.\($1)")
      },
      ipv6DNSServers: Self.liveAddressSettings(["6NS1", "6NS2"], reader: reader) {
        $0.ipv6Address("settings.\($1)")
      },
      domainName: Self.usableLiveSettingText(reader?.string("settings.waDN")),
      pppoeAccount: Self.usableLiveSettingText(reader?.string("settings.peUN")),
      pppoePassword: Self.usableLiveSettingText(reader?.string("settings.pePW")),
      pppoeService: Self.usableLiveSettingText(reader?.string("settings.peSN")),
      pppoeConnection: Self.livePPPoEConnection(
        activeText: pppoeActiveText,
        stayConnectedText: pppoeStayConnectedText),
      configureIPv6: Self.liveConfigureIPv6(
        configText: ipv6ConfigText,
        automaticText: ipv6AutomaticText),
      ipv6Mode: Self.liveIPv6Mode(configText: ipv6ConfigText),
      ipv6DefaultRoute: Self.usableLiveSettingText(reader?.string("settings.6Wgw")),
      ipv6Firewall: Self.liveSettingReader(ipv6FirewallText)?.boolFromInt("value"),
      dynamicGlobalHostname: Self.liveSettingReader(dynamicHostnameText)?.boolFromInt("value"),
      dynamicGlobalHostnameAutoConfig:
        Self.liveSettingReader(dynamicHostnameAutoConfigText)?.boolFromInt("value"),
      globalHostname: Self.usableLiveSettingText(reader?.string("settings.wbHN")),
      globalHostnameUser: Self.usableLiveSettingText(reader?.string("settings.wbHU")),
      globalHostnamePassword: Self.usableLiveSettingText(reader?.string("settings.wbHP")),
      modemPhoneNumber: Self.usableLiveSettingText(reader?.string("settings.moPN")),
      modemAlternateNumber: Self.usableLiveSettingText(reader?.string("settings.moAP")),
      modemAccount: Self.usableLiveSettingText(reader?.string("settings.moUN")),
      modemPassword: Self.usableLiveSettingText(reader?.string("settings.moPW")),
      modemIdleSeconds: Self.liveSettingInt(reader?.string("settings.moID")),
      modemCountryCode: Self.liveSettingInt(reader?.string("settings.moCI")),
      modemProtocol: Self.liveModemProtocol(reader?.string("settings.moMP")),
      modemPulseDialing: Self.liveSettingReader(reader?.string("settings.moPD"))?.boolFromInt("value"),
      modemAutomaticallyDial:
        Self.liveSettingReader(reader?.string("settings.moAD"))?.boolFromInt("value"),
      modemIgnoreDialTone:
        Self.liveSettingReader(reader?.string("settings.moDT"))?.boolFromInt("value"),
      modemUseAOL: Self.liveSettingReader(reader?.string("settings.moMF"))?.boolFromInt("value")
    )
  }

  private static func liveModemProtocol(_ text: String?) -> String? {
    switch liveSettingInt(text) {
    case 1: return "v34"
    case 2: return "v90"
    default: return nil
    }
  }

  private static func liveAddressSettings(
    _ settings: [String],
    reader: ProfileReader?,
    valueForSetting: (ProfileReader, String) -> String?
  ) -> [String?]? {
    guard let reader else { return nil }
    var values: [String?] = []
    var foundValue = false
    for setting in settings {
      let value = valueForSetting(reader, setting)
      if value != nil { foundValue = true }
      values.append(value)
    }
    return foundValue ? values : nil
  }

  private static func livePPPoEConnection(activeText: String?, stayConnectedText: String?)
    -> String?
  {
    let active = liveSettingReader(activeText)?.boolFromInt("value")
    let stayConnected = liveSettingReader(stayConnectedText)?.boolFromInt("value")
    guard active != nil || stayConnected != nil else { return nil }
    if active == true && stayConnected == true { return "always-on" }
    if active == true { return "automatic" }
    return "manual"
  }

  private static func liveConfigureIPv6(configText: String?, automaticText: String?) -> String? {
    if liveSettingInt(configText) == 0 {
      return "link-local"
    }
    guard let automatic = liveSettingReader(automaticText)?.boolFromInt("value") else {
      return nil
    }
    return automatic ? "automatic" : "manual"
  }

  private static func liveIPv6Mode(configText: String?) -> String? {
    switch liveSettingInt(configText) {
    case 1: return "host"
    case 3: return "tunnel"
    case 5: return "router"
    default: return nil
    }
  }

  private static func liveSettingInt(_ text: String?) -> Int? {
    guard let text = usableLiveSettingText(text) else { return nil }
    if let value = Int(text) {
      return value
    }
    return Int(text, radix: 16)
  }

  private static func unsignedInteger(_ data: Data?) -> Int? {
    guard let data, (1...4).contains(data.count) else { return nil }
    return data.reduce(0) { ($0 << 8) | Int($1) }
  }

  private static func accessControlEntries(from data: Data?) -> [AccessControlEntry]? {
    guard let data, data.count >= 16 else { return nil }
    let count = data[8..<16].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    guard count <= UInt64((data.count - 16) / 40) else { return nil }

    return (0..<Int(count)).map { index in
      let offset = 16 + (index * 40)
      let macBytes = data[offset..<(offset + 6)]
      let descriptionBytes = data[(offset + 6)..<(offset + 40)]
      let descriptionData = Data(descriptionBytes.prefix { $0 != 0 })
      return AccessControlEntry(
        macAddress: macBytes.map { String(format: "%02X", $0) }.joined(separator: ":"),
        description: String(data: descriptionData, encoding: .utf8) ?? "")
    }
  }

  private func applyLiveLegacyDeviceOptions(reader: ProfileReader) {
    if reader.hasValue(at: "settings.syCt") {
      legacyDeviceOptions.baseStation.contact = reader.string("settings.syCt") ?? ""
    }
    if reader.hasValue(at: "settings.syLo") {
      legacyDeviceOptions.baseStation.location = reader.string("settings.syLo") ?? ""
    }
    if reader.hasValue(at: "settings.ntSV") {
      let timeServer = reader.string("settings.ntSV") ?? ""
      legacyDeviceOptions.baseStation.timeServer = timeServer
      legacyDeviceOptions.baseStation.setTimeAutomatically = !timeServer.isEmpty
    }

    legacyDeviceOptions.wireless.multicastRate =
      Self.unsignedInteger(reader.data("settings.raMu"))
      ?? Self.liveSettingInt(reader.string("settings.raMu"))
      ?? legacyDeviceOptions.wireless.multicastRate
    legacyDeviceOptions.wireless.transmitPower =
      Self.unsignedInteger(reader.data("settings.raPo"))
      ?? Self.liveSettingInt(reader.string("settings.raPo"))
      ?? legacyDeviceOptions.wireless.transmitPower
    legacyDeviceOptions.wireless.groupKeyTimeoutSeconds =
      Self.unsignedInteger(reader.data("settings.raKT"))
      ?? Self.liveSettingInt(reader.string("settings.raKT"))
      ?? legacyDeviceOptions.wireless.groupKeyTimeoutSeconds
    legacyDeviceOptions.wireless.interferenceRobustness =
      reader.boolFromInt("settings.raRo")
      ?? legacyDeviceOptions.wireless.interferenceRobustness

    if reader.hasValue(at: "settings.dhMg") {
      legacyDeviceOptions.dhcp.message = reader.string("settings.dhMg") ?? ""
    }
    if reader.hasValue(at: "settings.dh95") {
      legacyDeviceOptions.dhcp.ldapServer = reader.string("settings.dh95") ?? ""
    }

    let localEnabled = reader.boolFromInt("settings.acEn") ?? false
    let radiusEnabled = reader.boolFromInt("settings.raFl") ?? false
    legacyDeviceOptions.accessControl.mode =
      radiusEnabled ? "radius" : (localEnabled ? "local" : "not-enabled")
    if let entries = Self.accessControlEntries(from: reader.data("settings.acTa")) {
      legacyDeviceOptions.accessControl.entries = entries
    }
    legacyDeviceOptions.accessControl.radiusType =
      reader.boolFromInt("settings.raCi") == true ? "alternate" : "default"
    legacyDeviceOptions.accessControl.primaryAddress =
      reader.ipv4Address("settings.raI1", allowingZero: true)
      .flatMap { $0 == "0.0.0.0" ? nil : $0 } ?? ""
    if reader.hasValue(at: "settings.raSe") {
      let secret = reader.string("settings.raSe") ?? ""
      legacyDeviceOptions.accessControl.primarySecret = secret
      legacyDeviceOptions.accessControl.primaryVerifySecret = secret
    }
    legacyDeviceOptions.accessControl.primaryPort =
      Self.liveSettingInt(reader.string("settings.raAu"))
      ?? legacyDeviceOptions.accessControl.primaryPort
    legacyDeviceOptions.accessControl.secondaryAddress =
      reader.ipv4Address("settings.raI2", allowingZero: true)
      .flatMap { $0 == "0.0.0.0" ? nil : $0 } ?? ""
    if reader.hasValue(at: "settings.raS2") {
      let secret = reader.string("settings.raS2") ?? ""
      legacyDeviceOptions.accessControl.secondarySecret = secret
      legacyDeviceOptions.accessControl.secondaryVerifySecret = secret
    }
    legacyDeviceOptions.accessControl.secondaryPort =
      Self.liveSettingInt(reader.string("settings.raU2"))
      ?? legacyDeviceOptions.accessControl.secondaryPort
  }

  private func apply(liveInternetSettings settings: LiveInternetSettings) {
    if let reportedConnectUsing = settings.connectUsing {
      let connectUsing =
        reportedConnectUsing == .modem && !capabilities.supportsModem
        ? ConnectUsing.dhcp : reportedConnectUsing
      internet.connectUsing = connectUsing
      if connectUsing == .dhcp {
        internet.dnsServers = ""
        internet.ipv6DNSServers = ""
      } else {
        internet.dnsServerPreview = ""
        internet.ipv6DNSServerPreview = ""
      }
      if connectUsing != .pppoe {
        internet.pppoeAccount = ""
        internet.pppoePassword = ""
        internet.pppoeService = ""
        internet.pppoeConnection = "always-on"
      }
    }

    if let dnsServers = settings.dnsServers {
      let joinedDNSServers = ProfileReader.joinNonZeroIPv4(dnsServers)
      if internet.connectUsing == .dhcp {
        internet.dnsServerPreview = joinedDNSServers
        internet.dnsServers = ""
      } else {
        internet.dnsServers = joinedDNSServers
        internet.dnsServerPreview = ""
      }
    }
    if let ipv6DNSServers = settings.ipv6DNSServers {
      let joinedIPv6DNSServers = ProfileReader.joinNonZeroIPv6(ipv6DNSServers)
      if internet.connectUsing == .dhcp {
        internet.ipv6DNSServerPreview = joinedIPv6DNSServers
        internet.ipv6DNSServers = ""
      } else {
        internet.ipv6DNSServers = joinedIPv6DNSServers
        internet.ipv6DNSServerPreview = ""
      }
    }
    if let domainName = settings.domainName {
      internet.domainName = domainName
    }
    if let pppoeAccount = settings.pppoeAccount {
      internet.pppoeAccount = pppoeAccount
    }
    if let pppoePassword = settings.pppoePassword {
      internet.pppoePassword = pppoePassword
    }
    if let pppoeService = settings.pppoeService {
      internet.pppoeService = pppoeService
    }
    if let pppoeConnection = settings.pppoeConnection {
      internet.pppoeConnection = pppoeConnection
    }
    if let configureIPv6 = settings.configureIPv6 {
      internet.configureIPv6 = configureIPv6
    }
    if let ipv6Mode = settings.ipv6Mode {
      internet.ipv6Mode = ipv6Mode
    }
    if let ipv6DefaultRoute = settings.ipv6DefaultRoute {
      internet.ipv6DefaultRoute = ipv6DefaultRoute
    }
    if let ipv6Firewall = settings.ipv6Firewall {
      internet.ipv6Firewall = ipv6Firewall
    }
    if let dynamicGlobalHostname = settings.dynamicGlobalHostname {
      internet.dynamicGlobalHostname = dynamicGlobalHostname
      if !dynamicGlobalHostname {
        internet.globalHostname = ""
        internet.globalHostnameUser = ""
        internet.globalHostnamePassword = ""
      }
    }
    if let dynamicGlobalHostnameAutoConfig = settings.dynamicGlobalHostnameAutoConfig {
      internet.dynamicGlobalHostnameAutoConfig = dynamicGlobalHostnameAutoConfig
    }
    if let globalHostname = settings.globalHostname {
      internet.globalHostname = globalHostname
    }
    if let globalHostnameUser = settings.globalHostnameUser {
      internet.globalHostnameUser = globalHostnameUser
    }
    if let globalHostnamePassword = settings.globalHostnamePassword {
      internet.globalHostnamePassword = globalHostnamePassword
    }
    if let value = settings.modemPhoneNumber { internet.modemPhoneNumber = value }
    if let value = settings.modemAlternateNumber { internet.modemAlternateNumber = value }
    if let value = settings.modemAccount { internet.modemAccount = value }
    if let value = settings.modemPassword {
      internet.modemPassword = value
      internet.modemVerifyPassword = value
    }
    if let value = settings.modemIdleSeconds { internet.modemIdleSeconds = value }
    if let value = settings.modemCountryCode { internet.modemCountryCode = value }
    if let value = settings.modemProtocol { internet.modemProtocol = value }
    if let value = settings.modemPulseDialing { internet.modemPulseDialing = value }
    if let value = settings.modemAutomaticallyDial { internet.modemAutomaticallyDial = value }
    if let value = settings.modemIgnoreDialTone { internet.modemIgnoreDialTone = value }
    if let value = settings.modemUseAOL { internet.modemUseAOL = value }
  }

  static func liveAdvancedSettings(reader: ProfileReader?) -> LiveAdvancedSettings {
    let destination = reader?.ipv4Address("settings.slCl", allowingZero: true)
    return LiveAdvancedSettings(
      syslogDestinationAddress: destination == "0.0.0.0" ? "" : destination,
      syslogLevel: liveSettingInt(reader?.string("settings.slvl")),
      snmpAccessFlags: liveSettingInt(reader?.string("settings.snAF")),
      pppDialInEnabled:
        liveSettingReader(reader?.string("settings.pdFl"))?.boolFromInt("value"),
      pppDialInAccount: usableLiveSettingText(reader?.string("settings.pdUN")),
      pppDialInPassword: usableLiveSettingText(reader?.string("settings.pdPW")),
      pppDialInAnswerOnRing: liveSettingInt(reader?.string("settings.pdAR")),
      pppDialInIdleSeconds: liveSettingInt(reader?.string("settings.pdID")),
      pppDialInMaximumConnectSeconds: liveSettingInt(reader?.string("settings.pdMC"))
    )
  }

  func apply(liveAdvancedSettings settings: LiveAdvancedSettings) {
    if let value = settings.syslogDestinationAddress {
      advanced.syslogDestinationAddress = value
    }
    if let value = settings.syslogLevel {
      advanced.syslogLevel = value
    }
    if let flags = settings.snmpAccessFlags {
      advanced.allowSNMP = flags & 0x2 == 0
      advanced.allowSNMPOverWAN = flags & 0x1 == 0 && advanced.allowSNMP
    }
    if let value = settings.pppDialInEnabled {
      advanced.pppDialInEnabled = value
    }
    if let value = settings.pppDialInAccount {
      advanced.pppDialInAccount = value
    }
    if let value = settings.pppDialInPassword {
      advanced.pppDialInPassword = value
      advanced.pppDialInVerifyPassword = value
    }
    if let value = settings.pppDialInAnswerOnRing {
      advanced.pppDialInAnswerOnRing = value
    }
    if let value = settings.pppDialInIdleSeconds {
      advanced.pppDialInIdleSeconds = value
    }
    if let value = settings.pppDialInMaximumConnectSeconds {
      advanced.pppDialInMaximumConnectSeconds = value
    }
  }

  private static func liveWirelessSettings(reader: ProfileReader?) -> LiveWirelessSettings {
    let modeText = reader?.string("settings.raSt")
    let nameText = reader?.string("settings.raNm")
    let securityText = reader?.string("settings.raWM")
    let regionCodeText = reader?.string("settings.syRe")
    let hiddenNetworkText = reader?.string("settings.raCl")
    let radioModeText = reader?.string("settings.raMd")
    let radioChannelText = reader?.string("settings.raCh")
    let allowNetworkExtensionText = reader?.string("settings.dWDS")
    let wdsModeText = reader?.string("settings.bsWM")
    let wdsPeerAirPortIDsText = reader?.string("settings.wdLs")

    return Self.liveWirelessSettings(
      modeText: modeText,
      nameText: nameText,
      securityText: securityText,
      regionCodeText: regionCodeText,
      hiddenNetworkText: hiddenNetworkText,
      radioModeText: radioModeText,
      radioChannelText: radioChannelText,
      allowNetworkExtensionText: allowNetworkExtensionText,
      wdsModeText: wdsModeText,
      wdsPeerAirPortIDsText: wdsPeerAirPortIDsText
    )
  }

  static func liveWirelessSettings(
    modeText: String? = nil,
    nameText: String? = nil,
    securityText: String? = nil,
    regionCodeText: String? = nil,
    hiddenNetworkText: String? = nil,
    radioModeText: String? = nil,
    radioChannelText: String? = nil,
    allowNetworkExtensionText: String? = nil,
    wdsModeText: String? = nil,
    wdsPeerAirPortIDsText: String? = nil
  ) -> LiveWirelessSettings {
    let modeReader = liveSettingReader(modeText)
    let securityReader = liveSettingReader(securityText)
    let hiddenNetworkReader = liveSettingReader(hiddenNetworkText)
    let radioModeReader = liveSettingReader(radioModeText)
    let radioChannelReader = liveSettingReader(radioChannelText)
    let allowNetworkExtensionReader = liveSettingReader(allowNetworkExtensionText)
    let wdsModeReader = liveSettingReader(wdsModeText)

    return LiveWirelessSettings(
      mode: modeReader?.wirelessMode("value"),
      networkName: usableLiveSettingText(nameText),
      security: securityReader?.wirelessSecurity("value"),
      regionCode: normalizedLiveIntegerText(regionCodeText),
      hiddenNetwork: hiddenNetworkReader?.boolFromInt("value"),
      radioMode: radioModeReader?.radioMode("value"),
      radioChannel: radioChannelReader?.radioChannel("value"),
      allowNetworkExtension: allowNetworkExtensionReader?.boolFromInt("value"),
      wdsMode: wdsModeReader?.wdsMode("value"),
      wdsPeerAirPortIDs: wdsPeerAirPortIDs(from: wdsPeerAirPortIDsText)
    )
  }

  private static func wdsPeerAirPortIDs(from text: String?) -> String? {
    guard let text = usableLiveSettingText(text) else { return nil }
    let hex = text.filter { $0.isHexDigit }
    guard hex.count >= 12 else { return nil }
    var ids: [String] = []
    var index = hex.startIndex
    while hex.distance(from: index, to: hex.endIndex) >= 16 {
      let end = hex.index(index, offsetBy: 12)
      let raw = String(hex[index..<end])
      if raw != "000000000000" {
        ids.append(Self.formattedAirPortID(raw))
      }
      index = hex.index(index, offsetBy: 16)
    }
    return ids.joined(separator: ", ")
  }

  private static func formattedAirPortID(_ hex: String) -> String {
    stride(from: 0, to: hex.count, by: 2).map { offset in
      let start = hex.index(hex.startIndex, offsetBy: offset)
      let end = hex.index(start, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
      return String(hex[start..<end]).uppercased()
    }.joined(separator: ":")
  }

  private static func liveSettingReader(_ text: String?) -> ProfileReader? {
    guard let text = usableLiveSettingText(text) else { return nil }
    return ProfileReader(.object(["value": .string(text)]))
  }

  private static func usableLiveSettingText(_ text: String?) -> String? {
    guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
      ProfileReader.isUsableSettingText(trimmed)
    else { return nil }
    return trimmed
  }

  private static func normalizedLiveIntegerText(_ text: String?) -> String? {
    guard let text = usableLiveSettingText(text) else { return nil }
    guard let number = Int(text) else { return text }
    return String(number)
  }

  func apply(liveWirelessSettings settings: LiveWirelessSettings) {
    if let mode = settings.mode {
      wireless.mode = mode
    }

    if wireless.mode == "off" {
      wireless.networkName = "Off"
      wireless.security = "none"
      wireless.password = ""
      wireless.verifyPassword = ""
    } else {
      if let networkName = settings.networkName {
        wireless.networkName = networkName
      }
      if let security = settings.security {
        wireless.security = security
      }
      if wireless.security == "none" {
        wireless.password = ""
        wireless.verifyPassword = ""
      }
    }

    if let regionCode = settings.regionCode {
      wireless.regionCode = normalizedIntegerText(regionCode)
    }
    if let hiddenNetwork = settings.hiddenNetwork {
      wireless.hiddenNetwork = hiddenNetwork
    }
    if let radioMode = settings.radioMode {
      wireless.radioMode = radioMode
    }
    if let radioChannel = settings.radioChannel {
      wireless.radioChannel = normalizedRadioChannel(radioChannel)
    }
    if let allowNetworkExtension = settings.allowNetworkExtension {
      wireless.allowNetworkExtension = allowNetworkExtension
    }
    if let wdsMode = settings.wdsMode {
      wireless.wdsMode = wdsMode
    }
    if let wdsPeerAirPortIDs = settings.wdsPeerAirPortIDs {
      wireless.wdsPeerAirPortIDs = wdsPeerAirPortIDs
    }
  }

  private static func liveAirPlaySettings(reader: ProfileReader?) -> LiveAirPlaySettings {
    let enabledText = reader?.string("settings.auRR")
    let overWANText = reader?.string("settings.aWan")
    return LiveAirPlaySettings(
      enabled: Self.liveSettingReader(enabledText)?.boolFromInt("value"),
      speakerName: Self.usableLiveSettingText(reader?.string("settings.auNN")),
      speakerPassword: Self.usableLiveSettingText(reader?.string("settings.auNP")),
      overWAN: Self.liveSettingReader(overWANText)?.boolFromInt("value")
    )
  }

  private static func hasLiveAirPlaySettings(reader: ProfileReader) -> Bool {
    liveAirPlayACPSettings.contains { reader.hasValue(at: "settings.\($0)") }
  }

  private static func hasAnySetting(_ settings: [String], in reader: ProfileReader) -> Bool {
    settings.contains {
      reader.hasUsableSetting(at: "settings.\($0)")
        || reader.hasUsableSetting(at: "restoreProfile.\($0)")
    }
  }

  private static func hasAnyLiveSetting(_ settings: [String], in reader: ProfileReader) -> Bool {
    settings.contains { reader.hasUsableSetting(at: "settings.\($0)") }
  }

  private func apply(liveAirPlaySettings settings: LiveAirPlaySettings) {
    if let enabled = settings.enabled {
      airPlay.enabled = enabled
    }
    if let speakerName = settings.speakerName {
      airPlay.speakerName = speakerName
    }
    if let speakerPassword = settings.speakerPassword {
      airPlay.speakerPassword = speakerPassword
      airPlay.verifySpeakerPassword = speakerPassword
    }
    if let overWAN = settings.overWAN {
      airPlay.overWAN = overWAN
    }
  }

  nonisolated static func deviceStatusText(problemCodes: [String]) -> String {
    DeviceStatusMessage.text(problemCodes: problemCodes)
  }

  nonisolated static func deviceStatusDetail(
    problemCodes: [String],
    routerMode: RouterMode
  ) -> String {
    DeviceStatusMessage.detail(problemCodes: problemCodes, routerMode: routerMode)
  }

  nonisolated static func deviceStatusDetails(
    problemCodes: [String],
    routerMode: RouterMode
  ) -> [String] {
    DeviceStatusMessage.details(problemCodes: problemCodes, routerMode: routerMode)
  }

  func currentDeviceProblemCodes() -> [String] {
    if let device = selectedTopologyDevice() {
      let codes = Self.normalizedProblemCodes(device.problemCodes)
      if !codes.isEmpty {
        return codes
      }
    }
    return baseStation.problemCodes
  }

  nonisolated static func normalizedProblemCodes(_ problemCodes: [String]) -> [String] {
    DeviceStatusMessage.normalizedProblemCodes(problemCodes)
  }

  private static func deviceStatusText(reader: ProfileReader) -> String {
    DeviceStatusMessage.text(reader: reader)
  }

  nonisolated static func liveAllowSetupOverWANForTesting(reader: ProfileReader) -> Bool? {
    liveAllowSetupOverWAN(reader: reader)
  }

  private nonisolated static func liveAllowSetupOverWAN(reader: ProfileReader) -> Bool? {
    DeviceStatusMessage.liveAllowSetupOverWAN(reader: reader)
  }

  nonisolated static func deviceProblemCodesForTesting(
    reader: ProfileReader,
    allowSetupOverWAN: Bool?
  ) -> [String] {
    deviceProblemCodes(reader: reader, allowSetupOverWAN: allowSetupOverWAN)
  }

  private nonisolated static func deviceProblemCodes(
    reader: ProfileReader,
    allowSetupOverWAN: Bool?
  ) -> [String] {
    DeviceStatusMessage.problemCodes(reader: reader, allowSetupOverWAN: allowSetupOverWAN)
  }

  private func applyLiveDNSPreviewFallbackIfNeeded(
    reader: ProfileReader,
    requestHost: String? = nil
  ) {
    guard internet.connectUsing == .dhcp else { return }

    if internet.dnsServerPreview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      let values = Self.firstAvailableIPv4Settings(
        Self.dnsPreviewIPv4ACPSettingGroups,
        reader: reader)
      guard
        applyDNSPreviewFallbackIfConnectionStillMatches(
          requestHost: requestHost,
          ipv4Values: values
        )
      else { return }
    }

    if internet.ipv6DNSServerPreview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      let values = Self.firstAvailableIPv6Settings(
        Self.dnsPreviewIPv6ACPSettingGroups,
        reader: reader)
      guard
        applyDNSPreviewFallbackIfConnectionStillMatches(
          requestHost: requestHost,
          ipv6Values: values
        )
      else { return }
    }
  }

  func applyDNSPreviewFallbackIfConnectionStillMatches(
    requestHost: String?,
    ipv4Values: [String?]? = nil,
    ipv6Values: [String?]? = nil
  ) -> Bool {
    if let requestHost, !connectionStillMatches(requestHost) {
      return false
    }
    if let ipv4Values,
      internet.dnsServerPreview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      let joined = ProfileReader.joinNonZeroIPv4(ipv4Values)
      if !joined.isEmpty {
        internet.dnsServerPreview = joined
      }
    }
    if let ipv6Values,
      internet.ipv6DNSServerPreview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      let joined = ProfileReader.joinNonZeroIPv6(ipv6Values)
      if !joined.isEmpty {
        internet.ipv6DNSServerPreview = joined
      }
    }
    return true
  }

  private static func firstAvailableIPv4Settings(
    _ settingGroups: [[String]],
    reader: ProfileReader
  ) -> [String?] {
    for settings in settingGroups {
      let values = settings.map {
        reader.ipv4Address("settings.\($0)")
      }
      if !ProfileReader.joinNonZeroIPv4(values).isEmpty {
        return values
      }
    }
    return []
  }

  private static func firstAvailableIPv6Settings(
    _ settingGroups: [[String]],
    reader: ProfileReader
  ) -> [String?] {
    for settings in settingGroups {
      let values = settings.map {
        reader.ipv6Address("settings.\($0)")
      }
      if !ProfileReader.joinNonZeroIPv6(values).isEmpty {
        return values
      }
    }
    return []
  }

  private func readProfileText(_ path: String, connection: AirportConnection? = nil) async throws
    -> String
  {
    let connection = connection ?? self.connection
    let result = try await runner.run(
      script: AirportCommand.readScript,
      arguments: AirportCommand.readProfilePath(path, connection: connection),
      connection: connection)
    return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func readProfile(connection: AirportConnection? = nil) async throws -> JSONValue {
    let connection = connection ?? self.connection
    let result = try await runner.run(
      script: AirportCommand.readScript,
      arguments: AirportCommand.readSetting("Prof", connection: connection, json: true),
      connection: connection
    )
    let data = Data(result.stdout.utf8)
    return try JSONDecoder().decode(JSONValue.self, from: data)
  }

  func readSetupProfile(connection: AirportConnection? = nil) async throws -> JSONValue {
    let connection = connection ?? self.connection
    guard usesLegacyACP else {
      let selected = selectedTopologyDevice()
      let selectedProductID = selected?.productID.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let productID = selectedProductID.isEmpty
        ? baseStation.productID.trimmingCharacters(in: .whitespacesAndNewlines)
        : selectedProductID
      var profile = try SetupProfileTemplates.load(
        productID: productID, modelName: selected?.modelName ?? setupDeviceModelName)
      guard case .object(var wrapper) = profile,
        case .object(var restoreProfile)? = wrapper["restoreProfile"]
      else { return profile }
      var settings = restoreProfile.keys.filter {
        $0.count == 4 && $0.unicodeScalars.allSatisfy(\.isASCII)
      }
      settings.append("Prof")
      let result = try await runner.run(
        script: AirportCommand.readScript,
        arguments: AirportCommand.readSettings(
          Array(Set(settings)).sorted(), connection: connection, json: true),
        connection: connection)
      let response = try JSONDecoder().decode(JSONValue.self, from: Data(result.stdout.utf8))
      if case .object(let responseObject) = response,
        case .object(let records)? = responseObject["settings"]
      {
        for (setting, record) in records {
          guard let template = restoreProfile[setting],
            let value = Self.factoryProfileValue(record: record, matching: template)
          else { continue }
          restoreProfile[setting] = value
        }
      }
      wrapper["restoreProfile"] = .object(restoreProfile)
      profile = .object(wrapper)
      return profile
    }
    var arguments = AirportCommand.readSettings(
      capabilities.supportsModem
        ? Self.legacyExtremeSnapshotSettings : Self.legacySetupSnapshotSettings,
      connection: connection, json: true
    ).usingAirPortBackendSubcommand("legacy-read")
    if usesLegacyACP17 {
      arguments.append("--acp17")
    }
    let result = try await runner.run(
      script: AirportCommand.legacyReadScript,
      arguments: arguments,
      connection: connection)
    let live = try JSONDecoder().decode(JSONValue.self, from: Data(result.stdout.utf8))
    guard capabilities.supportsModem,
      case .object(let defaults) = try SetupProfileTemplates.loadLegacyExtreme(),
      case .object(let defaultSettings)? = defaults["settings"],
      case .object(let liveRoot) = live,
      case .object(let liveSettings)? = liveRoot["settings"]
    else { return live }
    var merged = defaultSettings
    for (setting, value) in liveSettings {
      merged[setting] = value
    }
    var root = liveRoot
    root["settings"] = .object(merged)
    return .object(root)
  }

  static let legacySetupSnapshotSettings = """
    6CWp,AAU ,aWan,acEn,acTa,auNN,auNP,auRR,ctim,cver,dh95,dhBg,dhDB,dhDE,dhDL,dhDS,dhEn,dhFl,dhLe,dhMg,dhRo,dhSN,laIP,laSM,lcVs,leAc,nDMZ,naAF,naBg,naEn,naFl,naRo,naSN,ntSV,paFR,peAC,peAO,peID,pePW,peSC,peSN,peUN,pmPI,pmPR,pmPS,pmTa,prnR,ra1C,raAc,raAu,raC2,raCA,raCh,raCi,raCl,raCr,raDS,raEA,raF2,raFl,raI1,raI2,raKT,raMd,raMu,raNA,raNm,raPo,raPx,raR2,raRe,raRo,raS2,raSe,raSk,raSt,raT2,raTm,raTr,raU2,raWB,raWE,raWM,slCl,slvl,snAF,snLL,snLW,snRL,snRW,snWL,snWW,syCt,syDN,syLo,syNm,syPR,syPW,usbF,waCV,waD1,waD2,waD3,waDC,waDN,waDS,waIP,waIn,waNM,waRA,waSD,waSM,wdFl,wdLs
    """.split(separator: ",").map(String.init)

  static let legacyExtremeSnapshotSettings = """
    6CWp,AAU ,acEn,acTa,ctim,cver,dh95,dhBg,dhDB,dhDE,dhDL,dhDS,dhEn,dhFl,dhLe,dhMg,dhRo,dhSN,laIP,laSM,lcVs,moAD,moAP,moCC,moCI,moDT,moID,moMF,moMP,moPD,moPN,moPW,moUN,nDMZ,naAF,naBg,naEn,naFl,naRo,naSN,ntSV,paFR,pdAR,pdFl,pdID,pdMC,pdPW,pdUN,peAC,peAO,peID,pePW,peSC,peSN,peUN,pmPI,pmPR,pmPS,pmTa,prnR,ra1C,raAc,raAu,raC2,raCA,raCh,raCi,raCl,raCr,raDS,raEA,raF2,raFl,raI1,raI2,raKT,raMd,raMu,raNA,raNm,raPo,raPx,raR2,raRe,raRo,raS2,raSe,raSk,raSt,raT2,raTm,raTr,raU2,raWB,raWE,raWM,slCl,slvl,snAF,snLL,snLW,snRL,snRW,snWL,snWW,syCt,syDN,syLo,syNm,syPR,syPW,usbF,waCV,waD1,waD2,waD3,waDC,waDN,waDS,waIP,waIn,waNM,waRA,waSD,waSM,wdFl,wdLs
    """.split(separator: ",").map(String.init)

  static func legacySNMPCommunity(configured: String?, adminPassword: String) -> String {
    let configured = configured?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return configured.isEmpty ? adminPassword : configured
  }

  static func legacySettingsValuesJSON(
    from response: JSONValue, excluding excludedSettings: Set<String> = []
  ) -> String {
    guard case .object(let root) = response,
      case .object(let settings)? = root["settings"]
    else { return "" }
    let allowed = Set(legacySetupSnapshotSettings + legacyExtremeSnapshotSettings)
    var values: [String: JSONValue] = [:]
    for (setting, record) in settings
    where allowed.contains(setting) && !excludedSettings.contains(setting)
    {
      guard case .object(let fields) = record,
        case .string(let hex)? = fields["hex"]
      else { continue }
      values[setting] = .object(["type": .string("bytes"), "hex": .string(hex)])
    }
    guard !values.isEmpty,
      let data = try? JSONEncoder().encode(JSONValue.object(values))
    else { return "" }
    return String(decoding: data, as: UTF8.self)
  }

  static func factoryProfileValue(
    record: JSONValue, matching template: JSONValue
  ) -> JSONValue? {
    guard case .object(let fields) = record else { return nil }
    switch template {
    case .object(let object):
      if case .string("integer")? = object["type"],
        case .string(let text)? = fields["value"]
      {
        var typed = object
        typed["decimal"] = .string(text)
        return .object(typed)
      }
      if case .string("bytes")? = object["type"], let hex = fields["hex"] {
        var typed = object
        typed["hex"] = hex
        return .object(typed)
      }
      if let decoded = fields["decoded"], object["radios"] != nil {
        return mergeFactoryWiFi(decoded, with: template)
      }
      return fields["decoded"]
    case .array:
      return fields["decoded"]
    case .string:
      if case .string(let hex)? = fields["hex"] {
        if hex.count == 8, let value = UInt32(hex, radix: 16) {
          let octets: [UInt32] = [
            (value >> 24) & 0xff, (value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff,
          ]
          return .string(octets.map { String($0) }.joined(separator: "."))
        }
        if hex.count == 32, hex.allSatisfy({ $0 == "0" }) {
          return .string("::")
        }
        if let ipv6 = ProfileReader.ipv6Address(fromHex: hex) {
          return .string(ipv6)
        }
      }
      return fields["value"]
    case .bool:
      guard case .string(let hex)? = fields["hex"] else { return nil }
      return .bool(hex.contains { $0 != "0" })
    case .number:
      guard case .string(let text)? = fields["value"], let number = Double(text) else {
        return nil
      }
      return .number(number)
    case .null:
      return fields["decoded"] ?? fields["value"]
    }
  }

  private static func mergeFactoryWiFi(_ live: JSONValue, with template: JSONValue) -> JSONValue {
    guard case .object(var liveWiFi) = live,
      case .array(let liveRadios)? = liveWiFi["radios"],
      case .object(let templateWiFi) = template,
      case .array(let templateRadios)? = templateWiFi["radios"]
    else { return live }
    let policyKeys: Set<String> = ["pSTA", "raMd", "raMu", "raWC", "vaps"]
    let merged = liveRadios.enumerated().map { index, radio -> JSONValue in
      guard case .object(var liveRadio) = radio,
        index < templateRadios.count,
        case .object(let templateRadio) = templateRadios[index]
      else { return radio }
      for key in policyKeys {
        if let value = templateRadio[key] { liveRadio[key] = value }
      }
      return .object(liveRadio)
    }
    liveWiFi["radios"] = .array(merged)
    return .object(liveWiFi)
  }

  func apply(profile: JSONValue) {
    let reader = ProfileReader.normalized(profile)
    let radio = reader.reader("restoreProfile.WiFi.radios.0")
    applyProfileInternetFeatureSupport(reader, treatsMissingAsUnsupported: false)

    if let value = reader.string("restoreProfile.syNm") {
      baseStation.name = value
    }
    if let value = reader.string("restoreProfile.sySN") {
      baseStation.serialNumber = value
    }
    if let value = reader.string("restoreProfile.syVs") {
      baseStation.version = value
    }
    if let value = reader.string("restoreProfile.syAP") {
      baseStation.productID = value
      updateCapabilities(productID: value)
    }
    if let password = reader.string("restoreProfile.syPW") {
      baseStation.newAdminPassword = password
      baseStation.verifyAdminPassword = password
    } else {
      let password = connection.password.trimmingCharacters(in: .whitespacesAndNewlines)
      if !password.isEmpty {
        baseStation.newAdminPassword = password
        baseStation.verifyAdminPassword = password
      }
    }
    if let value = reader.bool("restoreProfile.raWB") ?? reader.boolFromInt("restoreProfile.raWB")
    {
      baseStation.allowSetupOverWAN = value
    }

    if let reportedValue = reader.connectUsing("restoreProfile.waCV") {
      let value =
        reportedValue == .modem && !capabilities.supportsModem
        ? ConnectUsing.dhcp : reportedValue
      internet.connectUsing = value
      if value == .dhcp {
        internet.dnsServers = ""
        internet.ipv6DNSServers = ""
      } else {
        internet.dnsServerPreview = ""
        internet.ipv6DNSServerPreview = ""
      }
      if value != .pppoe {
        internet.pppoeAccount = ""
        internet.pppoePassword = ""
        internet.pppoeService = ""
        internet.pppoeConnection = "always-on"
      }
    }
    internet.ipv4Address = reader.ipv4Address("restoreProfile.waIP") ?? internet.ipv4Address
    internet.subnetMask = reader.ipv4Address("restoreProfile.waSM") ?? internet.subnetMask
    internet.routerAddress = reader.ipv4Address("restoreProfile.waRA") ?? internet.routerAddress
    if let dnsServers = ipv4DNSServerValues(reader) {
      let joinedDNSServers = ProfileReader.joinNonZeroIPv4(dnsServers)
      if internet.connectUsing == .dhcp {
        internet.dnsServerPreview = joinedDNSServers
      } else {
        internet.dnsServers = joinedDNSServers
        internet.dnsServerPreview = ""
      }
    }
    internet.domainName =
      reader.string("restoreProfile.waDN") ?? reader.string("restoreProfile.waCD")
      ?? internet.domainName
    internet.ipv6Address = reader.ipv6Address("restoreProfile.6Wad") ?? internet.ipv6Address
    if let ipv6DNSServers = ipv6DNSServerValues(reader) {
      let joinedIPv6DNSServers = ProfileReader.joinNonZeroIPv6(ipv6DNSServers)
      if internet.connectUsing == .dhcp {
        internet.ipv6DNSServerPreview = joinedIPv6DNSServers
      } else {
        internet.ipv6DNSServers = joinedIPv6DNSServers
        internet.ipv6DNSServerPreview = ""
      }
    }
    internet.pppoeAccount = reader.string("restoreProfile.peUN") ?? internet.pppoeAccount
    internet.pppoePassword = reader.string("restoreProfile.pePW") ?? internet.pppoePassword
    internet.pppoeService = reader.string("restoreProfile.peSN") ?? internet.pppoeService
    if let value = reader.pppoeConnection() {
      internet.pppoeConnection = value
    }
    if let value = reader.configureIPv6() {
      internet.configureIPv6 = value
    }
    if let value = Self.liveIPv6Mode(configText: reader.string("restoreProfile.6cfg")) {
      internet.ipv6Mode = value
    }
    internet.ipv6DefaultRoute =
      reader.ipv6Address("restoreProfile.6Wgw") ?? internet.ipv6DefaultRoute
    internet.ipv6Firewall =
      reader.bool("restoreProfile.6sfw") ?? reader.boolFromInt("restoreProfile.6sfw")
      ?? internet.ipv6Firewall
    if let value = reader.bool("restoreProfile.wbEn") {
      internet.dynamicGlobalHostname = value
      if !value {
        internet.globalHostname = ""
        internet.globalHostnameUser = ""
        internet.globalHostnamePassword = ""
      }
    }
    internet.dynamicGlobalHostnameAutoConfig =
      reader.bool("restoreProfile.wbAC") ?? reader.boolFromInt("restoreProfile.wbAC")
      ?? internet.dynamicGlobalHostnameAutoConfig
    internet.globalHostname = reader.string("restoreProfile.wbHN") ?? internet.globalHostname
    internet.globalHostnameUser =
      reader.string("restoreProfile.wbHU") ?? reader.string("restoreProfile.wbRU")
      ?? internet.globalHostnameUser
    internet.globalHostnamePassword =
      reader.string("restoreProfile.wbHP") ?? reader.string("restoreProfile.wbRP")
      ?? internet.globalHostnamePassword
    internet.modemPhoneNumber =
      reader.string("restoreProfile.moPN") ?? internet.modemPhoneNumber
    internet.modemAlternateNumber =
      reader.string("restoreProfile.moAP") ?? internet.modemAlternateNumber
    internet.modemAccount = reader.string("restoreProfile.moUN") ?? internet.modemAccount
    if let value = reader.string("restoreProfile.moPW") {
      internet.modemPassword = value
      internet.modemVerifyPassword = value
    }
    internet.modemIdleSeconds =
      Self.liveSettingInt(reader.string("restoreProfile.moID")) ?? internet.modemIdleSeconds
    internet.modemCountryCode =
      Self.liveSettingInt(reader.string("restoreProfile.moCI")) ?? internet.modemCountryCode
    if let value = Self.liveModemProtocol(reader.string("restoreProfile.moMP")) {
      internet.modemProtocol = value
    }
    internet.modemPulseDialing =
      reader.boolFromInt("restoreProfile.moPD") ?? internet.modemPulseDialing
    internet.modemAutomaticallyDial =
      reader.boolFromInt("restoreProfile.moAD") ?? internet.modemAutomaticallyDial
    internet.modemIgnoreDialTone =
      reader.boolFromInt("restoreProfile.moDT") ?? internet.modemIgnoreDialTone
    internet.modemUseAOL =
      reader.boolFromInt("restoreProfile.moMF") ?? internet.modemUseAOL

    if let value =
      reader.wirelessMode("restoreProfile.bsNM") ?? radio?.wirelessMode("raSt")
      ?? reader.wirelessMode("restoreProfile.raSt")
    {
      wireless.mode = value
    }
    wireless.networkName =
      radio?.string("raNm") ?? reader.string("restoreProfile.raNm") ?? wireless.networkName
    if wireless.mode == "off" {
      wireless.networkName = "Off"
    }
    if let value = reader.wirelessSecurity("restoreProfile.bsSM") ?? radio?.wirelessSecurity("raWM")
    {
      wireless.security = value
    }
    if let password =
      reader.string("restoreProfile.bsSK") ?? radio?.string("raCr") ?? radio?.string("raWE")
      ?? reader.string("restoreProfile.raCr") ?? reader.string("restoreProfile.raWE")
    {
      wireless.password = password
      wireless.verifyPassword = password
    } else if wireless.mode == "off" || wireless.security == "none" {
      wireless.password = ""
      wireless.verifyPassword = ""
    }
    wireless.regionCode = reader.string("restoreProfile.syRe") ?? wireless.regionCode
    wireless.hiddenNetwork =
      radio?.bool("raCl") ?? reader.bool("restoreProfile.raCl") ?? wireless.hiddenNetwork
    if let value = radio?.radioMode("raMd") ?? reader.radioMode("restoreProfile.raMd") {
      wireless.radioMode = value
    }
    wireless.radioChannel =
      reader.radioChannel("restoreProfile.bsRC") ?? radio?.radioChannel("raCh")
      ?? reader.radioChannel("restoreProfile.raCh")
      ?? wireless.radioChannel
    if wireless.mode == "off" {
      wireless.security = "none"
      wireless.password = ""
      wireless.verifyPassword = ""
      wireless.regionCode = ""
      wireless.hiddenNetwork = false
      wireless.radioMode = ""
      wireless.radioChannel = ""
    }

    if let value =
      reader.routerMode("restoreProfile.bsRM")
      ?? reader.legacyRouterMode("restoreProfile.raTr")
    {
      network.routerMode = value
    }
    network.lanIPAddress =
      reader.ipv4Address("restoreProfile.laIP") ?? reader.ipv4Address("restoreProfile.waIP")
      ?? network.lanIPAddress
    network.dhcpRangeStart =
      reader.ipv4Address("restoreProfile.dhBg") ?? network.dhcpRangeStart
    network.dhcpRangeEnd =
      reader.ipv4Address("restoreProfile.dhEn") ?? network.dhcpRangeEnd
    if let lease = reader.dhcpLease("restoreProfile.dhLe") {
      network.dhcpLease = lease.value
      network.dhcpLeaseUnit = lease.unit
    }
    network.natPMP = reader.boolFromInt("restoreProfile.naFl") ?? network.natPMP
    if let defaultHost = reader.ipv4Address("restoreProfile.nDMZ", allowingZero: true) {
      network.defaultHost = defaultHost == "0.0.0.0" ? "" : defaultHost
    }

    let rawFileSharing = reader.diagnosticDescription("restoreProfile.bsFS") ?? "<missing>"
    let decodedFileSharing = reader.boolFromInt("restoreProfile.bsFS")
    if let decodedFileSharing {
      disks.fileSharing = decodedFileSharing
      hasReportedDiskFileSharingSetting = true
    }
    appendLog(
      "Storage file-sharing setting: bsFS raw=\(rawFileSharing), decoded=\(decodedFileSharing.map { String($0) } ?? "<unavailable>").")
    disks.shareOverWAN = reader.boolFromInt("restoreProfile.bsRF") ?? disks.shareOverWAN
    if let value = reader.diskSecurity("restoreProfile.bsFM") {
      disks.secureSharedDisks = value
    }
    if let value = reader.guestDiskAccess("restoreProfile.bsGA") {
      disks.guestAccess = value
    }
    if let password = reader.string("restoreProfile.fssp") {
      disks.diskPassword = password
      disks.verifyDiskPassword = password
    } else if disks.secureSharedDisks != "disk-password" {
      disks.diskPassword = ""
      disks.verifyDiskPassword = ""
    }
    disks.winsServer = reader.ipv4Address("restoreProfile.SMBs") ?? disks.winsServer
    disks.windowsWorkgroup = reader.string("restoreProfile.SMBw") ?? disks.windowsWorkgroup

    if let enabled = reader.bool("restoreProfile.auRR") ?? reader.boolFromInt("restoreProfile.auRR")
    {
      airPlay.enabled = enabled
    }
    airPlay.speakerName = reader.string("restoreProfile.auNN") ?? airPlay.speakerName
    if let password = reader.string("restoreProfile.auNP") {
      airPlay.speakerPassword = password
      airPlay.verifySpeakerPassword = password
    }
    if let overWAN = reader.bool("restoreProfile.aWan") ?? reader.boolFromInt("restoreProfile.aWan")
    {
      airPlay.overWAN = overWAN
    }

    let syslogDestination = reader.ipv4Address(
      "restoreProfile.slCl", allowingZero: true)
    if let syslogDestination {
      advanced.syslogDestinationAddress =
        syslogDestination == "0.0.0.0" ? "" : syslogDestination
    }
    advanced.syslogLevel =
      Self.liveSettingInt(reader.string("restoreProfile.slvl")) ?? advanced.syslogLevel
    if let flags = Self.liveSettingInt(reader.string("restoreProfile.snAF")) {
      advanced.allowSNMP = flags & 0x2 == 0
      advanced.allowSNMPOverWAN = flags & 0x1 == 0 && advanced.allowSNMP
    }
    advanced.pppDialInEnabled =
      reader.boolFromInt("restoreProfile.pdFl") ?? advanced.pppDialInEnabled
    advanced.pppDialInAccount =
      reader.string("restoreProfile.pdUN") ?? advanced.pppDialInAccount
    if let password = reader.string("restoreProfile.pdPW") {
      advanced.pppDialInPassword = password
      advanced.pppDialInVerifyPassword = password
    }
    advanced.pppDialInAnswerOnRing =
      Self.liveSettingInt(reader.string("restoreProfile.pdAR"))
      ?? advanced.pppDialInAnswerOnRing
    advanced.pppDialInIdleSeconds =
      Self.liveSettingInt(reader.string("restoreProfile.pdID"))
      ?? advanced.pppDialInIdleSeconds
    advanced.pppDialInMaximumConnectSeconds =
      Self.liveSettingInt(reader.string("restoreProfile.pdMC"))
      ?? advanced.pppDialInMaximumConnectSeconds

    if reader.hasValue(at: "restoreProfile.syCt") {
      legacyDeviceOptions.baseStation.contact = reader.string("restoreProfile.syCt") ?? ""
    }
    if reader.hasValue(at: "restoreProfile.syLo") {
      legacyDeviceOptions.baseStation.location = reader.string("restoreProfile.syLo") ?? ""
    }
    if reader.hasValue(at: "restoreProfile.ntSV") {
      let timeServer = reader.string("restoreProfile.ntSV") ?? ""
      legacyDeviceOptions.baseStation.timeServer = timeServer
      legacyDeviceOptions.baseStation.setTimeAutomatically = !timeServer.isEmpty
    }
    legacyDeviceOptions.wireless.multicastRate =
      Self.unsignedInteger(reader.data("restoreProfile.raMu"))
      ?? Self.liveSettingInt(reader.string("restoreProfile.raMu"))
      ?? legacyDeviceOptions.wireless.multicastRate
    legacyDeviceOptions.wireless.transmitPower =
      Self.unsignedInteger(reader.data("restoreProfile.raPo"))
      ?? Self.liveSettingInt(reader.string("restoreProfile.raPo"))
      ?? legacyDeviceOptions.wireless.transmitPower
    legacyDeviceOptions.wireless.groupKeyTimeoutSeconds =
      Self.unsignedInteger(reader.data("restoreProfile.raKT"))
      ?? Self.liveSettingInt(reader.string("restoreProfile.raKT"))
      ?? legacyDeviceOptions.wireless.groupKeyTimeoutSeconds
    legacyDeviceOptions.wireless.interferenceRobustness =
      reader.boolFromInt("restoreProfile.raRo")
      ?? legacyDeviceOptions.wireless.interferenceRobustness
    if reader.hasValue(at: "restoreProfile.dhMg") {
      legacyDeviceOptions.dhcp.message = reader.string("restoreProfile.dhMg") ?? ""
    }
    if reader.hasValue(at: "restoreProfile.dh95") {
      legacyDeviceOptions.dhcp.ldapServer = reader.string("restoreProfile.dh95") ?? ""
    }
    let localAccessEnabled = reader.boolFromInt("restoreProfile.acEn") ?? false
    let radiusAccessEnabled = reader.boolFromInt("restoreProfile.raFl") ?? false
    legacyDeviceOptions.accessControl.mode =
      radiusAccessEnabled ? "radius" : (localAccessEnabled ? "local" : "not-enabled")
    if let entries = Self.accessControlEntries(from: reader.data("restoreProfile.acTa")) {
      legacyDeviceOptions.accessControl.entries = entries
    }
    legacyDeviceOptions.accessControl.radiusType =
      reader.boolFromInt("restoreProfile.raCi") == true ? "alternate" : "default"
    if reader.hasValue(at: "restoreProfile.raI1") {
      legacyDeviceOptions.accessControl.primaryAddress =
        reader.ipv4Address("restoreProfile.raI1", allowingZero: true)
        .flatMap { $0 == "0.0.0.0" ? nil : $0 } ?? ""
    }
    if reader.hasValue(at: "restoreProfile.raSe") {
      let secret = reader.string("restoreProfile.raSe") ?? ""
      legacyDeviceOptions.accessControl.primarySecret = secret
      legacyDeviceOptions.accessControl.primaryVerifySecret = secret
    }
    legacyDeviceOptions.accessControl.primaryPort =
      Self.liveSettingInt(reader.string("restoreProfile.raAu"))
      ?? legacyDeviceOptions.accessControl.primaryPort
    if reader.hasValue(at: "restoreProfile.raI2") {
      legacyDeviceOptions.accessControl.secondaryAddress =
        reader.ipv4Address("restoreProfile.raI2", allowingZero: true)
        .flatMap { $0 == "0.0.0.0" ? nil : $0 } ?? ""
    }
    if reader.hasValue(at: "restoreProfile.raS2") {
      let secret = reader.string("restoreProfile.raS2") ?? ""
      legacyDeviceOptions.accessControl.secondarySecret = secret
      legacyDeviceOptions.accessControl.secondaryVerifySecret = secret
    }
    legacyDeviceOptions.accessControl.secondaryPort =
      Self.liveSettingInt(reader.string("restoreProfile.raU2"))
      ?? legacyDeviceOptions.accessControl.secondaryPort
  }

  func applyProfileInternetFeatureSupport(
    _ reader: ProfileReader,
    treatsMissingAsUnsupported: Bool
  ) {
    let supportsIPv6 = Self.hasAnySetting(Self.ipv6FeatureACPSettings, in: reader)
    let supportsDynamicGlobalHostname = Self.hasAnySetting(
      Self.dynamicGlobalHostnameFeatureACPSettings, in: reader)
    let supportsLogging = Self.hasAnySetting(Self.loggingFeatureACPSettings, in: reader)
    let supportsPPPDialIn = Self.hasAnySetting(Self.pppDialInFeatureACPSettings, in: reader)
    let profileProductID =
      reader.string("restoreProfile.syAP")
      ?? reader.string("settings.syAP")
      ?? baseStation.productID
    let supportsBaseStationMetadata =
      DeviceCapabilities.forProductID(profileProductID).supportsBaseStationMetadata
    let supportsLegacyWirelessOptions = Self.hasAnySetting(
      Self.legacyWirelessOptionsFeatureACPSettings, in: reader)
    let supportsLegacyDHCPOptions = Self.hasAnySetting(
      Self.legacyDHCPOptionsFeatureACPSettings, in: reader)
    let supportsAccessControl = Self.hasAnySetting(
      Self.accessControlFeatureACPSettings, in: reader)
    if supportsIPv6 || treatsMissingAsUnsupported {
      capabilities.supportsIPv6 = supportsIPv6
      hasDetectedIPv6Support = true
    }
    if supportsDynamicGlobalHostname || treatsMissingAsUnsupported {
      capabilities.supportsDynamicGlobalHostname = supportsDynamicGlobalHostname
      hasDetectedDynamicGlobalHostnameSupport = true
    }
    if supportsLogging || treatsMissingAsUnsupported {
      capabilities.supportsLogging =
        supportsLogging || DeviceCapabilities.forProductID(baseStation.productID).supportsLogging
    }
    if supportsPPPDialIn || treatsMissingAsUnsupported {
      capabilities.supportsPPPDialIn =
        supportsPPPDialIn
        || DeviceCapabilities.forProductID(baseStation.productID).supportsPPPDialIn
    }
    if supportsBaseStationMetadata || treatsMissingAsUnsupported {
      capabilities.supportsBaseStationMetadata =
        supportsBaseStationMetadata
        || DeviceCapabilities.forProductID(baseStation.productID).supportsBaseStationMetadata
    }
    if supportsLegacyWirelessOptions || treatsMissingAsUnsupported {
      capabilities.supportsLegacyWirelessOptions =
        supportsLegacyWirelessOptions
        || DeviceCapabilities.forProductID(baseStation.productID).supportsLegacyWirelessOptions
    }
    if supportsLegacyDHCPOptions || treatsMissingAsUnsupported {
      capabilities.supportsLegacyDHCPOptions =
        supportsLegacyDHCPOptions
        || DeviceCapabilities.forProductID(baseStation.productID).supportsLegacyDHCPOptions
    }
    if supportsAccessControl || treatsMissingAsUnsupported {
      capabilities.supportsAccessControl =
        supportsAccessControl
        || DeviceCapabilities.forProductID(baseStation.productID).supportsAccessControl
    }
  }

  private func ipv4DNSServerValues(_ reader: ProfileReader) -> [String?]? {
    let configuredPaths = [
      "restoreProfile.waD1", "restoreProfile.waD2", "restoreProfile.waD3",
    ]
    let configured = configuredPaths.map {
      reader.ipv4Address($0)
    }
    if !ProfileReader.joinNonZeroIPv4(configured).isEmpty {
      return configured
    }

    if let fallback = firstExistingIPv4Addresses(
      in: [
        ["restoreProfile.waC1", "restoreProfile.waC2", "restoreProfile.waC3"],
        ["restoreProfile.dhcpDNS1", "restoreProfile.dhcpDNS2"],
        ["restoreProfile.currentDNS1", "restoreProfile.currentDNS2", "restoreProfile.currentDNS3"],
        ["restoreProfile.currentPrimaryDNSServer", "restoreProfile.currentSecondaryDNSServer"],
      ],
      reader: reader
    ) {
      return fallback
    }

    return configuredPaths.contains { reader.hasValue(at: $0) } ? configured : nil
  }

  private func ipv6DNSServerValues(_ reader: ProfileReader) -> [String?]? {
    let configuredPaths = [
      "restoreProfile.6NS1", "restoreProfile.6NS2",
    ]
    let configured = configuredPaths.map {
      reader.ipv6Address($0)
    }
    if !ProfileReader.joinNonZeroIPv6(configured).isEmpty {
      return configured
    }

    if let fallback = firstExistingValues(
      in: [
        ["restoreProfile.dhcpIPv6DNS1", "restoreProfile.dhcpIPv6DNS2"],
        [
          "restoreProfile.ipv6CurrentPrimaryDNSAddress",
          "restoreProfile.ipv6CurrentSecondaryDNSAddress",
        ],
      ],
      reader: reader,
      joinedBy: ProfileReader.joinNonZeroIPv6,
      valueForPath: { reader.ipv6Address($0) }
    ) {
      return fallback
    }

    return configuredPaths.contains { reader.hasValue(at: $0) } ? configured : nil
  }

  private func firstExistingIPv4Addresses(in pathGroups: [[String]], reader: ProfileReader)
    -> [String?]?
  {
    firstExistingValues(in: pathGroups, reader: reader, joinedBy: ProfileReader.joinNonZeroIPv4) {
      reader.ipv4Address($0)
    }
  }

  private func firstExistingValues(
    in pathGroups: [[String]], reader: ProfileReader, joinedBy join: ([String?]) -> String,
    valueForPath: (String) -> String?
  ) -> [String?]? {
    var firstPresentValues: [String?]?
    for paths in pathGroups {
      let values = paths.map(valueForPath)
      if !join(values).isEmpty {
        return values
      }
      if firstPresentValues == nil && paths.contains(where: { reader.hasValue(at: $0) }) {
        firstPresentValues = values
      }
    }
    return firstPresentValues
  }

  func connectionStillMatches(_ requestHost: String) -> Bool {
    AirportConnection.normalizedHost(requestHost)
      == AirportConnection.normalizedHost(connection.host)
  }

  func applyIdentityIfConnectionStillMatches(
    requestHost: String, readName: String, serialNumber: String, version: String,
    productID: String = ""
  ) {
    guard !isEditingDevice else {
      appendLog("Ignored identity refresh while editing.")
      return
    }
    guard connectionStillMatches(requestHost) else {
      appendLog("Ignored identity refresh for stale host \(requestHost).")
      return
    }
    applyAuthoritativeBaseStationIdentity(
      readName: readName,
      serialNumber: serialNumber,
      version: version,
      productID: productID
    )
  }

  func appendIdentityRefreshFailureIfConnectionStillMatches(
    requestHost: String, errorDescription: String
  ) {
    guard connectionStillMatches(requestHost) else {
      appendLog("Ignored identity refresh failure for stale host \(requestHost).")
      return
    }
    appendLog("Identity refresh failed: \(Self.userFacingErrorDescription(errorDescription))")
  }

  func applyAuthoritativeBaseStationIdentity(
    readName: String,
    serialNumber: String,
    version: String,
    productID: String = "",
    supportsIPv6: Bool? = nil,
    supportsDynamicGlobalHostname: Bool? = nil,
    supportsClassicWDS: Bool? = nil,
    supportsLogging: Bool? = nil,
    supportsPPPDialIn: Bool? = nil,
    supportsBaseStationMetadata: Bool? = nil,
    supportsLegacyWirelessOptions: Bool? = nil,
    supportsLegacyDHCPOptions: Bool? = nil,
    supportsAccessControl: Bool? = nil
  ) {
    let selectedDeviceName =
      selectedTopologyDeviceID.flatMap { selectedID in
        visibleTopologyDevices.first { $0.id == selectedID }?.displayName
      }?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let directName = readName.trimmingCharacters(in: .whitespacesAndNewlines)

    if let selectedDeviceName, !selectedDeviceName.isEmpty {
      baseStation.name = selectedDeviceName
    } else if !directName.isEmpty {
      baseStation.name = directName
    }
    if let serialNumber = Self.usableIdentityText(serialNumber) {
      baseStation.serialNumber = serialNumber
    }
    if let version = Self.usableIdentityText(version) {
      baseStation.version = version
      firmware.currentVersion = version
    }
    if let productID = Self.usableIdentityText(productID) {
      let previousProductID = baseStation.productID.trimmingCharacters(in: .whitespacesAndNewlines)
      if productID != previousProductID {
        if supportsIPv6 == nil {
          hasDetectedIPv6Support = false
        }
        if supportsDynamicGlobalHostname == nil {
          hasDetectedDynamicGlobalHostnameSupport = false
        }
        if supportsClassicWDS == nil {
          hasDetectedClassicWDSSupport = false
        }
      }
      baseStation.productID = productID
      updateCapabilities(
        productID: productID,
        supportsIPv6: supportsIPv6,
        supportsDynamicGlobalHostname: supportsDynamicGlobalHostname,
        supportsClassicWDS: supportsClassicWDS,
        supportsLogging: supportsLogging,
        supportsPPPDialIn: supportsPPPDialIn,
        supportsBaseStationMetadata: supportsBaseStationMetadata,
        supportsLegacyWirelessOptions: supportsLegacyWirelessOptions,
        supportsLegacyDHCPOptions: supportsLegacyDHCPOptions,
        supportsAccessControl: supportsAccessControl)
    }
    updateConnectedFirmwareBadgeSnapshot()
  }

  private func updateCapabilities(
    productID: String = "",
    hasAirPlaySupport: Bool? = nil,
    hasDiskSupport: Bool? = nil,
    supportsIPv6: Bool? = nil,
    supportsDynamicGlobalHostname: Bool? = nil,
    supportsClassicWDS: Bool? = nil,
    supportsLogging: Bool? = nil,
    supportsPPPDialIn: Bool? = nil,
    supportsBaseStationMetadata: Bool? = nil,
    supportsLegacyWirelessOptions: Bool? = nil,
    supportsLegacyDHCPOptions: Bool? = nil,
    supportsAccessControl: Bool? = nil
  ) {
    let trimmedProductID = productID.trimmingCharacters(in: .whitespacesAndNewlines)
    let previousProductID = baseStation.productID.trimmingCharacters(in: .whitespacesAndNewlines)
    let productIDChanged = !trimmedProductID.isEmpty && trimmedProductID != previousProductID
    let effectiveProductID =
      trimmedProductID.isEmpty
      ? previousProductID
      : trimmedProductID
    if !trimmedProductID.isEmpty {
      baseStation.productID = trimmedProductID
    }

    var detected = DeviceCapabilities.forProductID(effectiveProductID)
    // Some early AirPort Extreme firmware returns placeholder values for the
    // audio property names even though the hardware has no audio output.
    // A known product ID is authoritative; runtime detection is only a
    // fallback for devices whose product has not been identified.
    if hasAirPlaySupport == true
      && (effectiveProductID.isEmpty
        || DeviceCapabilities.forProductID(effectiveProductID).supportsAirPlay)
    {
      detected.supportsAirPlay = true
    }
    if hasDiskSupport == true {
      detected.supportsDisks = true
    }
    if let supportsIPv6 {
      detected.supportsIPv6 = supportsIPv6
      hasDetectedIPv6Support = true
    } else if productIDChanged {
      hasDetectedIPv6Support = false
    } else {
      detected.supportsIPv6 = capabilities.supportsIPv6
    }
    if let supportsDynamicGlobalHostname {
      detected.supportsDynamicGlobalHostname = supportsDynamicGlobalHostname
      hasDetectedDynamicGlobalHostnameSupport = true
    } else if productIDChanged {
      hasDetectedDynamicGlobalHostnameSupport = false
    } else {
      detected.supportsDynamicGlobalHostname = capabilities.supportsDynamicGlobalHostname
    }
    if let supportsClassicWDS {
      detected.supportsClassicWDS = supportsClassicWDS
      hasDetectedClassicWDSSupport = true
    } else if productIDChanged {
      hasDetectedClassicWDSSupport = false
    } else {
      detected.supportsClassicWDS = capabilities.supportsClassicWDS
    }
    if let supportsLogging {
      detected.supportsLogging =
        supportsLogging || DeviceCapabilities.forProductID(effectiveProductID).supportsLogging
    } else if !productIDChanged {
      detected.supportsLogging =
        detected.supportsLogging || capabilities.supportsLogging
    }
    if let supportsPPPDialIn {
      detected.supportsPPPDialIn =
        supportsPPPDialIn || DeviceCapabilities.forProductID(effectiveProductID).supportsPPPDialIn
    } else if !productIDChanged {
      detected.supportsPPPDialIn =
        detected.supportsPPPDialIn || capabilities.supportsPPPDialIn
    }
    if let supportsBaseStationMetadata {
      detected.supportsBaseStationMetadata =
        supportsBaseStationMetadata
        || DeviceCapabilities.forProductID(effectiveProductID).supportsBaseStationMetadata
    } else if !productIDChanged {
      detected.supportsBaseStationMetadata =
        detected.supportsBaseStationMetadata || capabilities.supportsBaseStationMetadata
    }
    if let supportsLegacyWirelessOptions {
      detected.supportsLegacyWirelessOptions =
        supportsLegacyWirelessOptions
        || DeviceCapabilities.forProductID(effectiveProductID).supportsLegacyWirelessOptions
    } else if !productIDChanged {
      detected.supportsLegacyWirelessOptions =
        detected.supportsLegacyWirelessOptions || capabilities.supportsLegacyWirelessOptions
    }
    if let supportsLegacyDHCPOptions {
      detected.supportsLegacyDHCPOptions =
        supportsLegacyDHCPOptions
        || DeviceCapabilities.forProductID(effectiveProductID).supportsLegacyDHCPOptions
    } else if !productIDChanged {
      detected.supportsLegacyDHCPOptions =
        detected.supportsLegacyDHCPOptions || capabilities.supportsLegacyDHCPOptions
    }
    if let supportsAccessControl {
      detected.supportsAccessControl =
        supportsAccessControl
        || DeviceCapabilities.forProductID(effectiveProductID).supportsAccessControl
    } else if !productIDChanged {
      detected.supportsAccessControl =
        detected.supportsAccessControl || capabilities.supportsAccessControl
    }
    capabilities = detected
    firmware.productID = effectiveProductID
    if firmware.productID.isEmpty {
      firmware.images = []
      firmware.selectedImageID = ""
      firmware.hasLoadedImages = false
    }
    if !capabilities.supportsAirPlay {
      airPlay = AirPlayState()
      if wireless.mode == "join" {
        wireless.mode = "create"
      }
    }
    if !capabilities.supportsDisks {
      disks = DisksState()
    }
    if !capabilities.supportsIPv6 {
      internet.configureIPv6 = ""
      internet.ipv6DNSServers = ""
      internet.ipv6DNSServerPreview = ""
      internet.ipv6Address = ""
    }
    if !capabilities.supportsDynamicGlobalHostname {
      internet.dynamicGlobalHostname = false
      internet.globalHostname = ""
      internet.globalHostnameUser = ""
      internet.globalHostnamePassword = ""
    }
    if !capabilities.supportsClassicWDS {
      if wireless.mode == "wds" {
        wireless.mode = "create"
      }
      wireless.wdsMode = "remote"
      wireless.wdsPeerAirPortIDs = ""
    }
    if !capabilities.supportsLogging {
      advanced.syslogDestinationAddress = ""
      advanced.syslogLevel = AdvancedState().syslogLevel
      advanced.allowSNMP = AdvancedState().allowSNMP
      advanced.allowSNMPOverWAN = AdvancedState().allowSNMPOverWAN
    }
    if !capabilities.supportsPPPDialIn {
      let defaults = AdvancedState()
      advanced.pppDialInEnabled = defaults.pppDialInEnabled
      advanced.pppDialInAccount = defaults.pppDialInAccount
      advanced.pppDialInPassword = defaults.pppDialInPassword
      advanced.pppDialInVerifyPassword = defaults.pppDialInVerifyPassword
      advanced.pppDialInAnswerOnRing = defaults.pppDialInAnswerOnRing
      advanced.pppDialInIdleSeconds = defaults.pppDialInIdleSeconds
      advanced.pppDialInMaximumConnectSeconds = defaults.pppDialInMaximumConnectSeconds
    }
    if !capabilities.supportsBaseStationMetadata {
      legacyDeviceOptions.baseStation.contact = ""
      legacyDeviceOptions.baseStation.location = ""
    }
    if !capabilities.supportsLegacyWirelessOptions {
      legacyDeviceOptions.wireless = LegacyWirelessOptionsState()
    }
    if !capabilities.supportsLegacyDHCPOptions {
      legacyDeviceOptions.dhcp = LegacyDHCPOptionsState()
    }
    if !capabilities.supportsAccessControl {
      legacyDeviceOptions.accessControl = LegacyAccessControlState()
    }
    reconcileSelectedPaneWithCapabilities()
    if mockMode {
      loadMockFirmwareImagesIfNeeded()
    }
  }

  func markClean() {
    cleanSnapshot = currentSnapshot
    cleanCapabilities = capabilities
    cleanHasDetectedIPv6Support = hasDetectedIPv6Support
    cleanHasDetectedDynamicGlobalHostnameSupport = hasDetectedDynamicGlobalHostnameSupport
    cleanHasDetectedClassicWDSSupport = hasDetectedClassicWDSSupport
    clearAppliedAdvancedACPSettings(from: currentSnapshot)
  }

}
