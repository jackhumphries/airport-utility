import Foundation

@MainActor
extension AirportAppModel {
  func networkFlags(changesOnly: Bool = false) -> [(String, String?)]? {
    var flags: [(String, String?)] = []
    let routerModeChanged = network.routerMode != cleanSnapshot.network.routerMode
    if !changesOnly
      || normalized(network.lanIPAddress) != normalized(cleanSnapshot.network.lanIPAddress)
    {
      let lanIPAddress = normalized(network.lanIPAddress)
      if !lanIPAddress.isEmpty {
        guard isIPv4Address(lanIPAddress) else {
          status = localized("LAN IP Address must be an IPv4 address.")
          return nil
        }
        flags.append(("--lan-ip-address", lanIPAddress))
      }
    }
    appendChanged(
      &flags, "--router-mode", network.routerMode.rawValue,
      cleanSnapshot.network.routerMode.rawValue, changesOnly: changesOnly)
    if network.routerMode == .dhcpAndNat || network.routerMode == .dhcpOnly {
      guard
        validateOption(
          network.dhcpLeaseUnit,
          cleanValue: cleanSnapshot.network.dhcpLeaseUnit,
          changesOnly: changesOnly && !routerModeChanged,
          allowed: [
            "second", "seconds", "minute", "minutes", "hour", "hours", "day", "days", "week",
            "weeks",
          ],
          statusMessage: localized("DHCP Lease unit is not supported.")
        )
      else { return nil }
      let dhcpRangeStartChanged =
        normalized(network.dhcpRangeStart) != normalized(cleanSnapshot.network.dhcpRangeStart)
      let dhcpRangeEndChanged =
        normalized(network.dhcpRangeEnd) != normalized(cleanSnapshot.network.dhcpRangeEnd)
      let dhcpLeaseChanged =
        normalizedDHCPLeaseValue(network.dhcpLease)
        != normalizedDHCPLeaseValue(cleanSnapshot.network.dhcpLease)
      let dhcpLeaseUnitChanged =
        normalizedDHCPLeaseUnit(network.dhcpLeaseUnit)
        != normalizedDHCPLeaseUnit(cleanSnapshot.network.dhcpLeaseUnit)
      let shouldValidateDHCPRange =
        !changesOnly || routerModeChanged || dhcpRangeStartChanged || dhcpRangeEndChanged
      let shouldValidateDHCPLease =
        !changesOnly || routerModeChanged || dhcpLeaseChanged || dhcpLeaseUnitChanged
      guard !shouldValidateDHCPRange || !normalized(network.dhcpRangeStart).isEmpty else {
        status = localized("DHCP Range Beginning cannot be empty.")
        return nil
      }
      guard !shouldValidateDHCPRange || isIPv4Address(network.dhcpRangeStart) else {
        status = localized("DHCP Range Beginning must be an IPv4 address.")
        return nil
      }
      guard !shouldValidateDHCPRange || !normalized(network.dhcpRangeEnd).isEmpty else {
        status = localized("DHCP Range Ending cannot be empty.")
        return nil
      }
      guard !shouldValidateDHCPRange || isIPv4Address(network.dhcpRangeEnd) else {
        status = localized("DHCP Range Ending must be an IPv4 address.")
        return nil
      }
      guard
        !shouldValidateDHCPRange
          || DHCPRangeFields.fields(start: network.dhcpRangeStart, end: network.dhcpRangeEnd) != nil
      else {
        status =
          localized("DHCP Range Beginning and Ending must use the same supported private subnet, with Ending not before Beginning.")
        return nil
      }
      guard !shouldValidateDHCPLease || !normalized(network.dhcpLease).isEmpty else {
        status = localized("DHCP Lease cannot be empty.")
        return nil
      }
      guard !shouldValidateDHCPLease || isPositiveInteger(network.dhcpLease) else {
        status = localized("DHCP Lease must be a positive number.")
        return nil
      }
      guard
        !shouldValidateDHCPLease
          || isSupportedDHCPLeaseDuration(value: network.dhcpLease, unit: network.dhcpLeaseUnit)
      else {
        status = localized("DHCP Lease duration must be between 1 second and 10 years.")
        return nil
      }
      appendChanged(
        &flags, "--dhcp-range-start", network.dhcpRangeStart, cleanSnapshot.network.dhcpRangeStart,
        changesOnly: changesOnly && !routerModeChanged)
      appendChanged(
        &flags, "--dhcp-range-end", network.dhcpRangeEnd, cleanSnapshot.network.dhcpRangeEnd,
        changesOnly: changesOnly && !routerModeChanged)
      appendChanged(
        &flags, "--dhcp-lease", normalizedDHCPLeaseValue(network.dhcpLease),
        normalizedDHCPLeaseValue(cleanSnapshot.network.dhcpLease),
        changesOnly: changesOnly && !routerModeChanged)
      appendChanged(
        &flags, "--dhcp-lease-unit", normalizedDHCPLeaseUnit(network.dhcpLeaseUnit),
        normalizedDHCPLeaseUnit(cleanSnapshot.network.dhcpLeaseUnit),
        changesOnly: changesOnly && !routerModeChanged)
      if capabilities.supportsLegacyDHCPOptions {
        appendChanged(
          &flags, "--dhcp-message", legacyDeviceOptions.dhcp.message,
          cleanSnapshot.legacyDeviceOptions.dhcp.message,
          changesOnly: changesOnly && !routerModeChanged)
        appendChanged(
          &flags, "--ldap-server", legacyDeviceOptions.dhcp.ldapServer,
          cleanSnapshot.legacyDeviceOptions.dhcp.ldapServer,
          changesOnly: changesOnly && !routerModeChanged)
      }
    }
    if network.routerMode == .dhcpAndNat || network.routerMode == .natOnly {
      appendChangedBoolean(
        &flags,
        trueFlag: "--nat-pmp",
        falseFlag: "--no-nat-pmp",
        value: network.natPMP,
        cleanValue: cleanSnapshot.network.natPMP,
        changesOnly: changesOnly
      )
      if !changesOnly
        || normalized(network.defaultHost) != normalized(cleanSnapshot.network.defaultHost)
      {
        let defaultHost = normalized(network.defaultHost)
        if defaultHost.isEmpty {
          flags.append(("--clear-default-host", nil))
        } else {
          guard isIPv4Address(defaultHost) else {
            status = localized("Default Host must be an IPv4 address.")
            return nil
          }
          flags.append(("--default-host", defaultHost))
        }
      }
    }
    return flags
  }

  func airPlayFlags(changesOnly: Bool = false) -> [(String, String?)]? {
    guard supportsPane(.airPlay) else {
      status = localized("This base station does not support AirPlay.")
      return nil
    }

    let speakerName = normalized(airPlay.speakerName)
    let cleanSpeakerName = normalized(cleanSnapshot.airPlay.speakerName)
    let speakerPassword = normalized(airPlay.speakerPassword)
    let verifySpeakerPassword = normalized(airPlay.verifySpeakerPassword)
    let cleanSpeakerPassword = normalized(cleanSnapshot.airPlay.speakerPassword)
    let enabledChanged = airPlay.enabled != cleanSnapshot.airPlay.enabled
    let nameChanged = speakerName != cleanSpeakerName
    let passwordChanged = speakerPassword != cleanSpeakerPassword
    let shouldValidateName = airPlay.enabled && (!changesOnly || enabledChanged || nameChanged)
    let shouldValidatePassword =
      airPlay.enabled && (!changesOnly || enabledChanged || passwordChanged)

    guard !shouldValidateName || !speakerName.isEmpty else {
      status = localized("AirPlay Speaker Name cannot be empty.")
      return nil
    }
    guard !shouldValidatePassword || speakerPassword == verifySpeakerPassword else {
      status = localized("AirPlay passwords do not match.")
      return nil
    }

    var flags: [(String, String?)] = []
    appendChangedBoolean(
      &flags,
      trueFlag: "--airplay-enabled",
      falseFlag: "--no-airplay-enabled",
      value: airPlay.enabled,
      cleanValue: cleanSnapshot.airPlay.enabled,
      changesOnly: changesOnly
    )
    if airPlay.enabled {
      appendChanged(
        &flags,
        "--airplay-speaker-name",
        speakerName,
        cleanSpeakerName,
        changesOnly: changesOnly)
      if !changesOnly || passwordChanged {
        if speakerPassword.isEmpty {
          if changesOnly || !cleanSpeakerPassword.isEmpty {
            flags.append(("--clear-airplay-speaker-password", nil))
          }
        } else {
          flags.append(("--airplay-speaker-password", speakerPassword))
        }
      }
      appendChangedBoolean(
        &flags,
        trueFlag: "--airplay-over-wan",
        falseFlag: "--no-airplay-over-wan",
        value: airPlay.overWAN,
        cleanValue: cleanSnapshot.airPlay.overWAN,
        changesOnly: changesOnly
      )
    }
    return flags
  }

  func diskSharingFlags(changesOnly: Bool = false) -> [(String, String?)]? {
    let diskSecurity = normalized(disks.secureSharedDisks)
    let cleanDiskSecurity = normalized(cleanSnapshot.disks.secureSharedDisks)
    guard
      validateOption(
        disks.secureSharedDisks,
        cleanValue: cleanSnapshot.disks.secureSharedDisks,
        changesOnly: changesOnly,
        allowed: ["accounts", "disk-password", "device-password"],
        statusMessage: localized("Secure Shared Disks mode is not supported.")
      )
    else { return nil }
    guard
      validateOption(
        disks.guestAccess,
        cleanValue: cleanSnapshot.disks.guestAccess,
        changesOnly: changesOnly,
        allowed: ["not-allowed", "read-only", "read-write"],
        statusMessage: localized("Guest Disk Access is not supported.")
      )
    else { return nil }
    if diskSecurity == "disk-password" {
      let diskPassword = normalized(disks.diskPassword)
      let verifyDiskPassword = normalized(disks.verifyDiskPassword)
      let cleanDiskPassword = normalized(cleanSnapshot.disks.diskPassword)
      let diskSecurityChanged = diskSecurity != cleanDiskSecurity
      let diskPasswordChanged = diskPassword != cleanDiskPassword
      guard !(diskSecurityChanged || diskPasswordChanged) || !diskPassword.isEmpty else {
        status = localized("Disk Password cannot be empty.")
        return nil
      }
      guard diskPassword.isEmpty || diskPassword == verifyDiskPassword else {
        status = localized("Disk passwords do not match.")
        return nil
      }
    }
    var flags: [(String, String?)] = []
    if diskSecurity == "accounts" {
      guard appendDiskAccountFlags(&flags, changesOnly: changesOnly) else { return nil }
    } else {
      if !changesOnly || disks.fileSharing != cleanSnapshot.disks.fileSharing {
        flags.append(("--usb-file-sharing-flags", disks.fileSharing ? "1104" : "1044"))
      }
      appendChanged(
        &flags, "--disk-security", disks.secureSharedDisks, cleanSnapshot.disks.secureSharedDisks,
        changesOnly: changesOnly)
    }
    appendChanged(
      &flags, "--guest-disk-access", disks.guestAccess, cleanSnapshot.disks.guestAccess,
      changesOnly: changesOnly)
    appendChangedBoolean(
      &flags,
      trueFlag: "--share-disks-over-wan",
      falseFlag: "--no-share-disks-over-wan",
      value: disks.shareOverWAN,
      cleanValue: cleanSnapshot.disks.shareOverWAN,
      changesOnly: changesOnly
    )
    if diskSecurity == "disk-password",
      normalized(disks.diskPassword) != normalized(cleanSnapshot.disks.diskPassword)
    {
      flags.append(("--disk-password", normalized(disks.diskPassword)))
    }
    if (!changesOnly || normalized(disks.winsServer) != normalized(cleanSnapshot.disks.winsServer))
      && !normalized(disks.winsServer).isEmpty
      && !isIPv4Address(disks.winsServer)
    {
      status = localized("WINS Server must be an IPv4 address.")
      return nil
    }
    appendChanged(
      &flags, "--wins-server", disks.winsServer, cleanSnapshot.disks.winsServer,
      changesOnly: changesOnly)
    appendChanged(
      &flags, "--windows-workgroup", disks.windowsWorkgroup, cleanSnapshot.disks.windowsWorkgroup,
      changesOnly: changesOnly)
    return flags
  }

  private func appendDiskAccountFlags(
    _ flags: inout [(String, String?)], changesOnly: Bool
  ) -> Bool {
    let accounts = normalizedDiskAccounts(disks.fileSharingAccounts)
    let cleanAccounts = normalizedDiskAccounts(cleanSnapshot.disks.fileSharingAccounts)
    let accountsChanged = accounts != cleanAccounts
    let diskModeChanged =
      normalized(disks.secureSharedDisks) != normalized(cleanSnapshot.disks.secureSharedDisks)
    let fileSharingChanged = disks.fileSharing != cleanSnapshot.disks.fileSharing
    guard !changesOnly || accountsChanged || diskModeChanged || fileSharingChanged else {
      return true
    }
    for account in accounts {
      guard !account.password.isEmpty else {
        status = localized("Account Password cannot be empty.")
        return false
      }
      guard account.password == account.verifyPassword else {
        status = localized("Account passwords do not match.")
        return false
      }
      guard diskAccountAccessValue(account.access) != nil else {
        status = localized("File Sharing Access must be read-write, read-only, or not-allowed.")
        return false
      }
    }
    flags.append(("--usb-file-sharing-flags", disks.fileSharing ? "1040" : "1044"))
    if !changesOnly || accountsChanged || diskModeChanged {
      for account in accounts {
        guard let json = diskAccountJSONString(account) else { return false }
        flags.append(("--disk-account-json", json))
      }
    }
    return true
  }

  private func normalizedDiskAccounts(_ accounts: [DiskAccount]) -> [DiskAccount] {
    accounts.compactMap { account in
      let name = normalized(account.name)
      guard !name.isEmpty else { return nil }
      return DiskAccount(
        id: account.id,
        name: name,
        password: normalized(account.password),
        verifyPassword: normalized(account.verifyPassword),
        access: normalized(account.access)
      )
    }
  }

  private func diskAccountAccessValue(_ access: String) -> Int? {
    switch normalized(access) {
    case "read-write":
      return 0
    case "read-only":
      return 1
    case "not-allowed":
      return 2
    default:
      return nil
    }
  }

  private func diskAccountJSONString(_ account: DiskAccount) -> String? {
    guard let access = diskAccountAccessValue(account.access) else { return nil }
    let object: [String: Any] = [
      "fileSharingAccess": access,
      "name": account.name,
      "password": account.password,
    ]
    guard JSONSerialization.isValidJSONObject(object),
      let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
      let text = String(data: data, encoding: .utf8)
    else {
      status = localized("Could not encode disk account settings.")
      return nil
    }
    return text
  }

  func baseStationCommands(dryRun: Bool, changesOnly: Bool = false) -> [(String, [String])]? {
    let name = baseStation.name.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanName = cleanSnapshot.baseStation.name.trimmingCharacters(in: .whitespacesAndNewlines)
    let nameChanged = name != cleanName
    guard changesOnly && !nameChanged || !name.isEmpty else {
      status = localized("Base Station Name cannot be empty.")
      return nil
    }
    let newPassword = baseStation.newAdminPassword.trimmingCharacters(in: .whitespacesAndNewlines)
    let verifyPassword = baseStation.verifyAdminPassword.trimmingCharacters(
      in: .whitespacesAndNewlines)
    guard newPassword.isEmpty || newPassword == verifyPassword else {
      status = localized("Admin passwords do not match.")
      return nil
    }
    let adminPasswordChanged = newPassword != normalized(cleanSnapshot.baseStation.newAdminPassword)
    let advancedJSON = baseStation.advancedACPSettingsJSON.trimmingCharacters(
      in: .whitespacesAndNewlines)
    let cleanAdvancedJSON = cleanSnapshot.baseStation.advancedACPSettingsJSON.trimmingCharacters(
      in: .whitespacesAndNewlines)
    let includesLegacyAdvancedACPWrite =
      usesLegacyACP && adminPasswordChanged && !advancedJSON.isEmpty
      && (!changesOnly || advancedJSON != cleanAdvancedJSON)

    var commands: [(String, [String])] = []
    if !changesOnly || nameChanged || includesLegacyAdvancedACPWrite {
      commands.append(
        (
          localized("Base Station Name"),
          AirportCommand.rawWrite(
            setting: "syNm", value: name, connection: connection, dryRun: dryRun)
        ))
    }
    if adminPasswordChanged {
      commands.append(
        (
          localized("Admin Password"),
          AirportCommand.rawWrite(
            setting: "syPW", value: newPassword, connection: connection, dryRun: dryRun)
        ))
    }
    if baseStation.allowSetupOverWAN != cleanSnapshot.baseStation.allowSetupOverWAN {
      let flag =
        baseStation.allowSetupOverWAN ? "--allow-setup-over-wan" : "--no-allow-setup-over-wan"
      commands.append(
        (
          localized("Setup Over Ethernet WAN"),
          AirportCommand.friendlyWrite(
            connection: connection, flags: [(flag, nil)], dryRun: dryRun)
        ))
    }
    let options = legacyDeviceOptions.baseStation
    let cleanOptions = cleanSnapshot.legacyDeviceOptions.baseStation
    let timeServer = normalized(options.timeServer)
    let cleanTimeServer =
      cleanOptions.setTimeAutomatically ? normalized(cleanOptions.timeServer) : ""
    let effectiveTimeServer = options.setTimeAutomatically ? timeServer : ""
    guard !options.setTimeAutomatically || !timeServer.isEmpty else {
      status = localized("Time Server cannot be empty when automatic time is enabled.")
      return nil
    }
    var flags: [(String, String?)] = []
    if capabilities.supportsBaseStationMetadata {
      appendChanged(
        &flags, "--base-station-contact", options.contact, cleanOptions.contact,
        changesOnly: changesOnly)
      appendChanged(
        &flags, "--base-station-location", options.location, cleanOptions.location,
        changesOnly: changesOnly)
    }
    appendChanged(
      &flags, "--time-server", effectiveTimeServer, cleanTimeServer,
      changesOnly: changesOnly)
    if !flags.isEmpty {
      commands.append(
        (
          localized("Base Station Options"),
          AirportCommand.friendlyWrite(
            connection: connection, flags: flags, dryRun: dryRun)
        ))
    }
    if !advancedJSON.isEmpty && (!changesOnly || advancedJSON != cleanAdvancedJSON) {
      guard let settings = advancedACPSettings(from: advancedJSON) else { return nil }
      for setting in settings.keys.sorted() {
        guard let value = settings[setting] else { continue }
        commands.append(
          (
            "Advanced ACP \(setting)",
            AirportCommand.rawWriteJSON(
              setting: setting, valueJSON: value, connection: connection, dryRun: dryRun)
          ))
      }
    }
    return commands
  }

  private func advancedACPSettings(from text: String) -> [String: String]? {
    guard let data = text.data(using: .utf8) else {
      status = localized("Advanced ACP JSON must be valid UTF-8.")
      return nil
    }
    let object: Any
    do {
      object = try JSONSerialization.jsonObject(with: data)
    } catch {
      status = localized("Advanced ACP JSON is not valid JSON.")
      return nil
    }
    guard let dictionary = object as? [String: Any] else {
      status = localized("Advanced ACP JSON must be an object keyed by setting name.")
      return nil
    }
    var settings: [String: String] = [:]
    for (setting, value) in dictionary {
      guard setting.count == 4 else {
        status = localized("Advanced ACP setting names must be four characters.")
        return nil
      }
      guard JSONSerialization.isValidJSONObject(value),
        let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
        let valueJSON = String(data: data, encoding: .utf8)
      else {
        status = "Could not encode Advanced ACP setting \(setting)."
        return nil
      }
      settings[setting] = valueJSON
    }
    return settings
  }

  private func appendOptional(_ flags: inout [(String, String?)], _ flag: String, _ value: String) {
    if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      flags.append((flag, value))
    }
  }

  func appendChanged(
    _ flags: inout [(String, String?)],
    _ flag: String,
    _ value: String,
    _ cleanValue: String,
    changesOnly: Bool
  ) {
    let value = normalized(value)
    let cleanValue = normalized(cleanValue)
    let isEmpty = value.isEmpty
    guard !changesOnly || value != cleanValue else { return }
    if changesOnly || !isEmpty {
      flags.append((flag, value))
    }
  }

  func appendChangedBoolean(
    _ flags: inout [(String, String?)],
    trueFlag: String,
    falseFlag: String,
    value: Bool,
    cleanValue: Bool,
    changesOnly: Bool
  ) {
    guard !changesOnly || value != cleanValue else { return }
    flags.append((value ? trueFlag : falseFlag, nil))
  }

  func appendAddressList(
    _ flags: inout [(String, String?)],
    valueFlag: String,
    clearFlag: String,
    value: String,
    cleanValue: String,
    changesOnly: Bool,
    maxCount: Int,
    countError: String,
    emptyValueError: String,
    validator: (String) -> Bool,
    validationError: String,
    normalizer: (String) -> String = { $0 },
    slotValueFlags: [String]? = nil
  ) -> Bool {
    let values = splitList(value).map(normalizer)
    let cleanValues = splitList(cleanValue).map(normalizer)
    guard !changesOnly || values != cleanValues else { return true }
    guard !containsEmptyCommaSeparatedValue(value) else {
      status = emptyValueError
      return false
    }
    if values.isEmpty {
      if changesOnly || !cleanValues.isEmpty {
        flags.append((clearFlag, nil))
      }
      return true
    }
    guard values.count <= maxCount else {
      status = countError
      return false
    }
    for item in values {
      guard validator(item) else {
        status = validationError
        return false
      }
    }
    if changesOnly, let slotValueFlags {
      for index in values.indices {
        guard index < slotValueFlags.count else { break }
        let cleanValue = cleanValues.indices.contains(index) ? cleanValues[index] : ""
        if values[index] != cleanValue {
          flags.append((slotValueFlags[index], values[index]))
        }
      }
      return true
    }
    for item in values {
      flags.append((valueFlag, item))
    }
    return true
  }

  private func containsEmptyCommaSeparatedValue(_ text: String) -> Bool {
    AirportValueNormalizer.containsEmptyCommaSeparatedValue(text)
  }

  func validateOption(
    _ value: String,
    cleanValue: String,
    changesOnly: Bool,
    allowed: Set<String>,
    statusMessage: String,
    allowEmpty: Bool = false
  ) -> Bool {
    let value = normalized(value)
    guard !changesOnly || value != normalized(cleanValue) else { return true }
    if allowEmpty && value.isEmpty { return true }
    guard allowed.contains(value) else {
      status = statusMessage
      return false
    }
    return true
  }

  func normalized(_ value: String) -> String {
    AirportValueNormalizer.text(value)
  }

  func isIPv4Address(_ value: String) -> Bool {
    AirportValueNormalizer.isIPv4Address(value)
  }

  func subnetMaskValidationError(_ value: String) -> String? {
    AirportValueNormalizer.subnetMaskValidationError(value)
  }

  func isIPv6Address(_ value: String) -> Bool {
    AirportValueNormalizer.isIPv6Address(value)
  }

  func normalizedIPv6Address(_ value: String) -> String {
    AirportValueNormalizer.normalizedIPv6Address(value)
  }

  private func isPositiveInteger(_ value: String) -> Bool {
    AirportValueNormalizer.isPositiveInteger(value)
  }

  private func normalizedDHCPLeaseValue(_ value: String) -> String {
    AirportValueNormalizer.normalizedDHCPLeaseValue(value)
  }

  private func normalizedDHCPLeaseUnit(_ value: String) -> String {
    AirportValueNormalizer.normalizedDHCPLeaseUnit(value)
  }

  private func isSupportedDHCPLeaseDuration(value: String, unit: String) -> Bool {
    AirportValueNormalizer.isSupportedDHCPLeaseDuration(value: value, unit: unit)
  }

  func normalizedIntegerText(_ value: String) -> String {
    AirportValueNormalizer.normalizedIntegerText(value)
  }

  func normalizedRadioChannel(_ value: String) -> String {
    AirportValueNormalizer.normalizedRadioChannel(value)
  }

  func comparable(_ snapshot: AirportSettingsSnapshot) -> AirportSettingsSnapshot {
    let capabilitiesAreKnown =
      hasLoadedSettings || mockMode
      || !baseStation.productID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    return AirportSettingsComparable.snapshot(
      snapshot,
      capabilitiesAreKnown: capabilitiesAreKnown,
      supportsAirPlay: supportsPane(.airPlay),
      supportsDisks: supportsPane(.disks),
      supportsLogging: capabilities.supportsLogging,
      supportsPPPDialIn: capabilities.supportsPPPDialIn,
      supportsBaseStationMetadata: capabilities.supportsBaseStationMetadata,
      supportsLegacyWirelessOptions: capabilities.supportsLegacyWirelessOptions,
      supportsLegacyDHCPOptions: capabilities.supportsLegacyDHCPOptions,
      supportsAccessControl: capabilities.supportsAccessControl,
      showsIPv6InternetControls: showsIPv6InternetControls,
      showsDynamicGlobalHostnameControls: showsDynamicGlobalHostnameControls)
  }

  func comparable(_ state: BaseStationState) -> BaseStationState {
    AirportSettingsComparable.baseStation(state)
  }

  func comparable(_ state: AirPlayState) -> AirPlayState {
    AirportSettingsComparable.airPlay(state)
  }

  func comparable(_ state: InternetState) -> InternetState {
    AirportSettingsComparable.internet(state)
  }

  func comparable(_ state: LegacyDeviceOptionsState) -> LegacyDeviceOptionsState {
    AirportSettingsComparable.legacyDeviceOptions(state)
  }

  func comparable(_ state: WirelessState) -> WirelessState {
    AirportSettingsComparable.wireless(state)
  }

  func comparable(_ state: NetworkState) -> NetworkState {
    AirportSettingsComparable.network(state)
  }

  func comparable(_ state: DisksState) -> DisksState {
    AirportSettingsComparable.disks(state)
  }

  private func splitList(_ text: String) -> [String] {
    AirportValueNormalizer.splitList(text)
  }

  private func normalizedList(_ text: String, normalizer: (String) -> String = { $0 }) -> String {
    AirportValueNormalizer.normalizedList(text, normalizer: normalizer)
  }

}
