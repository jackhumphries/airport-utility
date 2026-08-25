import Foundation

@MainActor
extension AirportAppModel {
  private static let airPlayPasswordAccountPrefix = "airport-airplay:"
  private static let diskPasswordAccountPrefix = "airport-disk:"

  var liveCredentialsAvailable: Bool {
    !connection.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !connection.password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  func presentSelectedDeviceConnectionPrompt() {
    isShowingRestartConfirmation = false
    isShowingRestoreConfirmation = false
    isDevicePopoverPresented = true
    isInternetPopoverPresented = false
    clearAuxiliarySheets()
    if connection.password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      hasTrustedConnectionPassword = false
    }
    updateIdleConnectionStatus()
  }

  func loadSavedPasswordForConnectionHost() {
    loadSavedPasswordForConnectionHost(device: selectedTopologyDevice(), fallbackHosts: [])
  }

  func loadSavedPasswordForConnectionHost(
    device: AirportDiscoveredDevice?, fallbackHosts: [String]
  ) {
    normalizeConnectionHost()
    guard !mockMode, connection.password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return
    }
    let accounts = passwordStoreAccounts(
      for: device,
      fallbackHosts: [connection.host] + fallbackHosts,
      includeCurrentIdentityAccounts: true)
    guard let cachedPassword = savedPassword(for: accounts) else { return }
    connection.password = cachedPassword.password
    rememberConnectionPassword = cachedPassword.rememberPassword
    hasTrustedConnectionPassword = cachedPassword.trusted
    if let device, cachedPassword.rememberPassword {
      savePassword(
        cachedPassword.password,
        for: passwordStoreAccounts(for: device, fallbackHosts: [connection.host]))
    }
  }

  func loadSavedPasswordForDiscoveredDeviceIfAvailable(_ devices: [AirportDiscoveredDevice]) {
    guard !mockMode, !hasLoadedSettings, !isBusy,
      connection.password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return
    }
    let preferredDevices = preferredDiscoveredDevices(devices)
    if let primary = preferredDevices.first,
      isPrimaryAirPortCandidate(primary),
      primary.connectionHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return
    }
    for device in preferredDevices {
      let host = device.connectionHost
      guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
      guard let cachedPassword = savedPassword(for: passwordStoreAccounts(for: device)) else {
        continue
      }
      connection.host = AirportConnection.normalizedHost(host)
      connection.password = cachedPassword.password
      rememberConnectionPassword = cachedPassword.rememberPassword
      hasTrustedConnectionPassword = cachedPassword.trusted
      updateConnectedTopologyDeviceIdentifiers(from: devices)
      if cachedPassword.rememberPassword {
        savePassword(
          cachedPassword.password, for: passwordStoreAccounts(for: device, fallbackHosts: [host]))
      }
      // Startup discovery may still be collecting topology candidates. In
      // that case retain the credential now, but let the debounced upstream
      // selection issue the single initial refresh.
      if startupConnectionTask == nil || hasAttemptedStartupConnection {
        refreshLiveSettingsIfPossible()
      }
      return
    }
  }

  private func preferredDiscoveredDevices(_ devices: [AirportDiscoveredDevice])
    -> [AirportDiscoveredDevice]
  {
    let currentHost = AirportConnection.normalizedHost(connection.host)
    return devices.sorted { left, right in
      let leftMatches = left.matchesConnectionHost(currentHost)
      let rightMatches = right.matchesConnectionHost(currentHost)
      if leftMatches != rightMatches { return leftMatches }
      let leftIsTimeCapsule = isPrimaryAirPortCandidate(left)
      let rightIsTimeCapsule = isPrimaryAirPortCandidate(right)
      if leftIsTimeCapsule != rightIsTimeCapsule { return leftIsTimeCapsule }
      return left.displayName.localizedCaseInsensitiveCompare(right.displayName)
        == .orderedAscending
    }
  }

  private func isPrimaryAirPortCandidate(_ device: AirportDiscoveredDevice) -> Bool {
    device.displayModelName.localizedCaseInsensitiveContains("Time Capsule")
      || device.displayName.localizedCaseInsensitiveContains("Time Capsule")
  }

  func loadDefaultPasswordForDiscoveredDeviceIfAvailable(
    _ devices: [AirportDiscoveredDevice]
  ) {
    guard !mockMode, !hasLoadedSettings, !isBusy else {
      return
    }
    guard let device = preferredDiscoveredDevices(devices).first,
      device.usesDefaultAdminPassword,
      !device.connectionHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      shouldUseDefaultPasswordForDiscoveredDevice(device)
    else {
      return
    }
    useDefaultPasswordForDevice(device)
    if startupConnectionTask == nil || hasAttemptedStartupConnection {
      refreshLiveSettingsIfPossible()
    }
  }

  private func shouldUseDefaultPasswordForDiscoveredDevice(
    _ device: AirportDiscoveredDevice
  ) -> Bool {
    if connection.password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return true
    }
    let host = AirportConnection.normalizedHost(connection.host)
    return device.matchesConnectionHost(host)
      || device.sharesStableIdentity(with: selectedTopologyDeviceIdentifiers)
      || device.sharesStableIdentity(with: connectedTopologyDeviceIdentifiers)
  }

  @discardableResult
  func useDefaultPasswordForDevice(_ device: AirportDiscoveredDevice) -> Bool {
    guard device.usesDefaultAdminPassword else { return false }
    let host = AirportConnection.normalizedHost(device.connectionHost)
    guard !host.isEmpty else { return false }
    connection.host = host
    connection.password = "public"
    rememberConnectionPassword = false
    hasTrustedConnectionPassword = true
    saveSessionPassword(
      CachedConnectionPassword(password: "public", rememberPassword: false, trusted: true),
      for: passwordStoreAccounts(for: device, fallbackHosts: [host]))
    appendLog("Using default base station password for \(device.displayName).")
    return true
  }

  func saveConnectionPasswordIfRequested() {
    saveConnectionPasswordIfRequested(for: selectedTopologyDevice())
  }

  func saveConnectionPasswordIfRequested(for device: AirportDiscoveredDevice?) {
    cacheCurrentConnectionPasswordForSession(for: device)
    guard rememberConnectionPassword else { return }
    normalizeConnectionHost()
    let password = connection.password.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !password.isEmpty else { return }
    savePassword(
      password,
      for: passwordStoreAccounts(
        for: device, fallbackHosts: [connection.host], includeCurrentIdentityAccounts: true))
  }

  func updateRememberConnectionPassword(_ remember: Bool) {
    rememberConnectionPassword = remember
    cacheCurrentConnectionPasswordForSession()
    if remember {
      saveConnectionPasswordIfRequested()
    } else {
      deletePasswords(
        for: passwordStoreAccounts(
          for: selectedTopologyDevice(),
          fallbackHosts: [connection.host],
          includeCurrentIdentityAccounts: true))
    }
  }

  func loadAuxiliaryPasswordsFromStore() {
    guard !mockMode else { return }

    if capabilities.supportsAirPlay {
      let password = savedAuxiliaryPassword(prefix: Self.airPlayPasswordAccountPrefix)
      airPlay.rememberPassword = password != nil
      if normalized(airPlay.speakerPassword).isEmpty, let password {
        airPlay.speakerPassword = password
        airPlay.verifySpeakerPassword = password
      }
    } else {
      airPlay.rememberPassword = false
    }

    if capabilities.supportsDisks {
      let password = savedAuxiliaryPassword(prefix: Self.diskPasswordAccountPrefix)
      disks.rememberPassword = password != nil
      if disks.secureSharedDisks == "disk-password",
        normalized(disks.diskPassword).isEmpty,
        let password
      {
        disks.diskPassword = password
        disks.verifyDiskPassword = password
      }
    } else {
      disks.rememberPassword = false
    }
  }

  func updateRememberAirPlayPassword(_ remember: Bool) {
    airPlay.rememberPassword = remember
    let password = normalized(airPlay.speakerPassword)
    let isAppliedPassword =
      password == normalized(cleanSnapshot.airPlay.speakerPassword)
    updateAuxiliaryPassword(
      password,
      remember: remember,
      shouldSaveNow: isAppliedPassword,
      prefix: Self.airPlayPasswordAccountPrefix)
  }

  var remembersCurrentDiskPassword: Bool {
    disks.secureSharedDisks == "device-password"
      ? rememberConnectionPassword : disks.rememberPassword
  }

  func updateRememberCurrentDiskPassword(_ remember: Bool) {
    if disks.secureSharedDisks == "device-password" {
      updateRememberConnectionPassword(remember)
      return
    }
    disks.rememberPassword = remember
    let password = normalized(disks.diskPassword)
    let isAppliedPassword =
      disks.secureSharedDisks == "disk-password"
      && normalized(cleanSnapshot.disks.secureSharedDisks) == "disk-password"
      && password == normalized(cleanSnapshot.disks.diskPassword)
    updateAuxiliaryPassword(
      password,
      remember: remember,
      shouldSaveNow: isAppliedPassword,
      prefix: Self.diskPasswordAccountPrefix)
  }

  func persistAuxiliaryPasswordPreferences(from snapshot: AirportSettingsSnapshot) {
    if capabilities.supportsAirPlay {
      updateAuxiliaryPassword(
        normalized(snapshot.airPlay.speakerPassword),
        remember: snapshot.airPlay.rememberPassword,
        shouldSaveNow: true,
        prefix: Self.airPlayPasswordAccountPrefix)
    }
    if capabilities.supportsDisks, snapshot.disks.secureSharedDisks == "disk-password" {
      updateAuxiliaryPassword(
        normalized(snapshot.disks.diskPassword),
        remember: snapshot.disks.rememberPassword,
        shouldSaveNow: true,
        prefix: Self.diskPasswordAccountPrefix)
    }
  }

  func selectedTopologyDevice() -> AirportDiscoveredDevice? {
    guard let selectedTopologyDeviceID else { return nil }
    return visibleTopologyDevices.first { $0.id == selectedTopologyDeviceID }
  }

  private func savedPassword(for accounts: [String]) -> CachedConnectionPassword? {
    for account in accounts {
      let account = AirportConnection.normalizedHost(account)
      if let password = sessionConnectionPasswords[account] {
        return password
      }
      if let password = passwordStore.password(for: account) {
        return CachedConnectionPassword(password: password, rememberPassword: true, trusted: true)
      }
    }
    return nil
  }

  func cacheCurrentConnectionPasswordForSession(
    for device: AirportDiscoveredDevice? = nil
  ) {
    normalizeConnectionHost()
    let password = connection.password.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !password.isEmpty else { return }
    let accounts = passwordStoreAccounts(
      for: device ?? selectedTopologyDevice(),
      fallbackHosts: [connection.host],
      includeCurrentIdentityAccounts: true)
    saveSessionPassword(
      CachedConnectionPassword(
        password: password,
        rememberPassword: rememberConnectionPassword,
        trusted: hasTrustedConnectionPassword),
      for: accounts)
  }

  private func saveSessionPassword(_ password: CachedConnectionPassword, for accounts: [String]) {
    for account in accounts {
      sessionConnectionPasswords[AirportConnection.normalizedHost(account)] = password
    }
  }

  private func savePassword(_ password: String, for accounts: [String]) {
    for account in accounts {
      passwordStore.savePassword(password, for: account)
    }
  }

  private func deletePasswords(for accounts: [String]) {
    for account in accounts {
      passwordStore.deletePassword(for: account)
    }
  }

  private func savedAuxiliaryPassword(prefix: String) -> String? {
    for account in auxiliaryPasswordStoreAccounts(prefix: prefix) {
      if let password = passwordStore.password(for: account) {
        return password
      }
    }
    return nil
  }

  private func updateAuxiliaryPassword(
    _ password: String,
    remember: Bool,
    shouldSaveNow: Bool,
    prefix: String
  ) {
    let accounts = auxiliaryPasswordStoreAccounts(prefix: prefix)
    if remember, shouldSaveNow, !password.isEmpty {
      savePassword(password, for: accounts)
    } else if !remember || password.isEmpty {
      deletePasswords(for: accounts)
    }
  }

  private func auxiliaryPasswordStoreAccounts(prefix: String) -> [String] {
    passwordStoreAccounts(
      for: selectedTopologyDevice(),
      fallbackHosts: [connection.host],
      includeCurrentIdentityAccounts: true
    ).map { prefix + $0 }
  }

  private func passwordStoreAccounts(
    for device: AirportDiscoveredDevice? = nil, fallbackHosts: [String] = [],
    includeCurrentIdentityAccounts: Bool = false
  ) -> [String] {
    var accounts = fallbackHosts
    if let device {
      accounts += device.normalizedStableIdentifiers.compactMap(Self.passwordStoreAccount)
      accounts.append(device.connectionHost)
      accounts += device.normalizedConnectionHosts
    }
    if includeCurrentIdentityAccounts {
      accounts += selectedTopologyDeviceIdentifiers.compactMap(Self.passwordStoreAccount)
      accounts += connectedTopologyDeviceIdentifiers.compactMap(Self.passwordStoreAccount)
      accounts += updatingBaseStationDeviceIdentifiers.compactMap(Self.passwordStoreAccount)
    }
    return Self.uniquePasswordStoreAccounts(accounts)
  }

  private static func passwordStoreAccount(for stableIdentifier: String) -> String? {
    let stableIdentifier = stableIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    guard !stableIdentifier.isEmpty else { return nil }
    return stableIdentifierPasswordAccountPrefix + stableIdentifier
  }

  private static func uniquePasswordStoreAccounts(_ accounts: [String]) -> [String] {
    var seen: Set<String> = []
    var unique: [String] = []
    for account in accounts {
      let account = AirportConnection.normalizedHost(account)
      guard !account.isEmpty, !seen.contains(account) else { continue }
      seen.insert(account)
      unique.append(account)
    }
    return unique
  }

  func updateConnectionPasswordAfterAdminChange(_ password: String) {
    connection.password = password.trimmingCharacters(in: .whitespacesAndNewlines)
    hasTrustedConnectionPassword = !connection.password.isEmpty
    saveConnectionPasswordIfRequested()
  }

  static func environmentValue(_ key: String) -> String? {
    guard
      let value = ProcessInfo.processInfo.environment[key]?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty
    else { return nil }
    return value
  }

  func normalizeConnectionHost() {
    connection.host = AirportConnection.normalizedHost(connection.host)
  }

  static func defaultPasswordStore() -> AirportPasswordStore {
    if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
      || Bundle.main.bundleURL.pathExtension == "xctest"
      || ProcessInfo.processInfo.arguments.contains(where: { $0.contains(".xctest") })
    {
      return NoopAirportPasswordStore()
    }
    return KeychainAirportPasswordStore.shared
  }

}
