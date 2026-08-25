import Foundation

@MainActor
extension AirportAppModel {
  func loadInitialSettingsIfPossible() {
    if !mockMode, hasStartedBonjourDiscovery, discoveredDevices.isEmpty,
      selectedTopologyDeviceID == nil
    {
      status = "Scanning for AirPort base stations…"
      return
    }
    refreshLiveSettingsIfPossible()
  }

  func startBonjourDiscovery() {
    guard !mockMode, !hasStartedBonjourDiscovery else { return }
    hasStartedBonjourDiscovery = true
    let browser = makeBonjourBrowser()
    bonjourBrowser = browser
    browser.start()
  }

  private func makeBonjourBrowser() -> AirPortBonjourBrowser {
    AirPortBonjourBrowser { [weak self] devices in
      self?.updateDiscoveredDevices(devices)
    }
  }

  public var canRefreshNetwork: Bool {
    !isBusy && !isEditingDevice && !isShowingPasswords && !isShowingPreferences
      && !isShowingConfigureOther && !isShowingSites && !isShowingSetup
      && !isShowingRestoreConfirmation
      && !isShowingRestartConfirmation && !isRestorePending && !isRestoringDefaults
      && !isInternetPopoverPresented
      && !isConnectionPopoverPresented
  }

  public func refreshNetwork() {
    guard canRefreshNetwork else { return }
    isDevicePopoverPresented = false
    isInternetPopoverPresented = false
    isConnectionPopoverPresented = false
    isInternetSelected = false
    selectedTopologyDeviceID = nil
    selectedTopologyDeviceIdentifiers = []
    startupConnectionTask?.cancel()
    startupConnectionTask = nil
    hasAttemptedStartupConnection = false
    hasManualTopologySelection = false
    preview = nil
    clearLoadedDeviceDetails(name: "")

    guard !mockMode else {
      appendLog("Mock network scan completed.")
      return
    }
    let browser = bonjourBrowser ?? makeBonjourBrowser()
    bonjourBrowser = browser
    hasStartedBonjourDiscovery = true
    browser.start()
    status = "Scanning for AirPort base stations…"
    appendLog("Rescanning the network for AirPort base stations.")
  }

  func updateDiscoveredDevices(_ devices: [AirportDiscoveredDevice]) {
    reconcileBaseStationRestartTracking(with: devices)
    updateConnectedTopologyDeviceIdentifiers(from: devices)
    discoveredDevices = devices
    updateSiteHostsFromDiscoveredDevices(devices)
    completeRestoreIfResetDeviceAvailable()
    if isShowingSetup, setup.step == .applying,
      !devices.contains(where: {
        $0.sharesStableIdentity(with: updatingBaseStationDeviceIdentifiers)
      })
    {
      didSetupDeviceDisappear = true
    }
    completeSetupIfRestartedDeviceAvailable()
    rememberTopologyDisplaySnapshots(from: deduplicatedTopologyDevices(devices))
    if let selectedTopologyDeviceID,
      !visibleTopologyDevices.contains(where: { $0.id == selectedTopologyDeviceID })
    {
      let selectedHost = AirportConnection.normalizedHost(connection.host)
      let selectedPassword = connection.password
      let selectedRememberPassword = rememberConnectionPassword
      let selectedPasswordTrusted = hasTrustedConnectionPassword
      if let replacementDevice = visibleTopologyDevices.first(where: {
        isReplacementForSelectedTopologyDevice($0, selectedHost: selectedHost)
      }) {
        self.selectedTopologyDeviceID = replacementDevice.id
        rememberSelectedTopologyDeviceIdentity(replacementDevice)
        reuseConnectionPasswordAfterStableIdentityReplacement(
          replacementDevice,
          previousHost: selectedHost,
          previousPassword: selectedPassword,
          previousRememberPassword: selectedRememberPassword,
          previousPasswordTrusted: selectedPasswordTrusted)
        updateConnectionHostAfterStableIdentityReplacement(
          replacementDevice, selectedHost: selectedHost)
        restartWirelessClientPollingIfPossible()
        return
      }
      self.selectedTopologyDeviceID = nil
      selectedTopologyDeviceIdentifiers = []
      isDevicePopoverPresented = false
      isEditingDevice = false
      preview = nil
    }
    scheduleStartupConnectionToMostUpstreamAirPort()
    loadDefaultPasswordForDiscoveredDeviceIfAvailable(devices)
    loadSavedPasswordForDiscoveredDeviceIfAvailable(devices)
  }

  private func scheduleStartupConnectionToMostUpstreamAirPort() {
    guard !mockMode, !hasAttemptedStartupConnection,
      !hasManualTopologySelection, !hasLoadedSettings, !discoveredDevices.isEmpty
    else { return }
    startupConnectionTask?.cancel()
    let delay = startupDiscoveryDebounceNanoseconds
    startupConnectionTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: delay)
      guard !Task.isCancelled else { return }
      self?.connectToMostUpstreamAirPortOnLaunch()
    }
  }

  func connectToMostUpstreamAirPortOnLaunch() {
    startupConnectionTask = nil
    guard !mockMode, !hasAttemptedStartupConnection,
      !hasManualTopologySelection, !hasLoadedSettings, !isBusy,
      let device = mostUpstreamAirPort(from: visibleTopologyDevices)
    else { return }
    hasAttemptedStartupConnection = true
    selectTopologyDevice(device, isAutomaticStartupSelection: true)
    appendLog("Connecting on launch to upstream AirPort \(device.displayName).")
    refreshLiveSettingsIfPossible()
  }

  func mostUpstreamAirPort(
    from devices: [AirportDiscoveredDevice]
  ) -> AirportDiscoveredDevice? {
    let roots = Self.topologyTrees(from: devices).map(\.device)
    let currentHost = AirportConnection.normalizedHost(connection.host)
    return roots.sorted { left, right in
      let leftMatches = left.matchesConnectionHost(currentHost)
      let rightMatches = right.matchesConnectionHost(currentHost)
      if leftMatches != rightMatches { return leftMatches }
      let leftIsTimeCapsule = left.displayModelName.localizedCaseInsensitiveContains("Time Capsule")
        || left.displayName.localizedCaseInsensitiveContains("Time Capsule")
      let rightIsTimeCapsule = right.displayModelName.localizedCaseInsensitiveContains("Time Capsule")
        || right.displayName.localizedCaseInsensitiveContains("Time Capsule")
      if leftIsTimeCapsule != rightIsTimeCapsule { return leftIsTimeCapsule }
      return left.displayName.localizedCaseInsensitiveCompare(right.displayName) == .orderedAscending
    }.first
  }

  func completeSetupIfRestartedDeviceAvailable() {
    guard isWaitingForSetupRestart else { return }
    let configuredName = setup.deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      let restartedDevice = discoveredDevices.first(where: {
        !$0.requiresSetup
          && $0.sharesStableIdentity(with: updatingBaseStationDeviceIdentifiers)
          && !configuredName.isEmpty
          && $0.displayName.compare(
            configuredName, options: [.caseInsensitive, .diacriticInsensitive])
            == .orderedSame
      })
    else { return }
    setupRestartDidComplete(with: restartedDevice)
  }

  func completeRestoreIfResetDeviceAvailable() {
    guard isRestoringDefaults, isWaitingForRestoreRestart else { return }
    guard
      let resetDevice = discoveredDevices.first(where: {
        $0.requiresSetup
          && $0.sharesStableIdentity(with: updatingBaseStationDeviceIdentifiers)
      })
    else { return }
    isRestoringDefaults = false
    isWaitingForRestoreRestart = false
    clearBaseStationUpdate()
    beginSetup(for: resetDevice)
  }

  func presentDevicePopover() {
    isDevicePopoverPresented.toggle()
    if isDevicePopoverPresented {
      refreshLiveSettingsIfPossible()
      refreshBaseStationIdentityIfNeeded()
    }
  }

  func refreshHostInternetSettings() {
    if mockMode {
      hostInternet = HostInternetState(
        connectionStatus: "Connected",
        routerAddress: internet.routerAddress,
        dnsServers: "192.168.1.1")
      return
    }

    hostInternet.isLoading = true
    Task {
      hostInternet = await Self.readHostInternetSettingsAsync()
    }
  }

  var needsConnectionDetailsBeforeLoadingDevice: Bool {
    !mockMode && !hasDevicePopoverDetails && !liveCredentialsAvailable
  }

  var shouldShowDeviceConnectionPrompt: Bool {
    !mockMode && !isBusy
      && (!liveCredentialsAvailable
        || (!hasDevicePopoverDetails && !hasTrustedConnectionPassword))
  }

  var shouldShowDeviceLoading: Bool {
    guard !mockMode, liveCredentialsAvailable else { return false }
    let isLoadingDeviceDetails = !hasCompleteDevicePopoverDetails && isBusy
    let isLoadingInitialWirelessClients = hasLoadedSettings && !hasLoadedWirelessClients
    return isLoadingDeviceDetails || isLoadingInitialWirelessClients
  }

  var shouldShowInternetLoading: Bool {
    !mockMode && hostInternet.isLoading && !hasInternetPopoverDetails
  }

  var canAttemptConnection: Bool {
    !isBusy
      && !AirportConnection.normalizedHost(connection.host).isEmpty
      && !connection.password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var hasDevicePopoverDetails: Bool {
    devicePopoverDetailValues.contains {
      !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  var hasCompleteDevicePopoverDetails: Bool {
    devicePopoverDetailValues.allSatisfy {
      !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  private var devicePopoverDetailValues: [String] {
    [
      wireless.networkName,
      internet.ipv4Address,
      network.lanIPAddress,
      baseStation.serialNumber,
      baseStation.version,
    ]
  }

  var extendableWirelessNetworkNames: [String] {
    let currentName = wireless.networkName.trimmingCharacters(in: .whitespacesAndNewlines)
    let names =
      wirelessScanNetworkNames
      + (["extend", "wds"].contains(wireless.mode)
        && !Self.isPlaceholderWirelessNetworkName(currentName)
        ? [currentName] : [])
    return Self.uniqueWirelessNetworkNames(names)
  }

  static func uniqueWirelessNetworkNames(_ names: [String]) -> [String] {
    var seen: Set<String> = []
    var unique: [String] = []
    for name in names {
      let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !isPlaceholderWirelessNetworkName(trimmed) else { continue }
      let key = trimmed.folding(
        options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      guard !seen.contains(key) else { continue }
      seen.insert(key)
      unique.append(trimmed)
    }
    return unique
  }

  private static func isPlaceholderWirelessNetworkName(_ name: String) -> Bool {
    name.isEmpty || name.localizedCaseInsensitiveCompare("Off") == .orderedSame
  }

  var hasInternetPopoverDetails: Bool {
    hostInternetPopoverDetailValues.contains {
      !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  var hasCompleteInternetPopoverDetails: Bool {
    hostInternetPopoverDetailValues.allSatisfy {
      !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  var internetPopoverConnectionStatus: String {
    let status = hostInternet.connectionStatus.trimmingCharacters(in: .whitespacesAndNewlines)
    return status.isEmpty ? "Unknown" : status
  }

  var isHostInternetConnected: Bool {
    hostInternet.connectionStatus.trimmingCharacters(in: .whitespacesAndNewlines) == "Connected"
  }

  var internetTopologyAccessibilityTitle: String {
    isHostInternetConnected ? "Internet working normally" : "Internet inactive"
  }

  func deviceStatusText(for device: AirportDiscoveredDevice? = nil) -> String {
    if let device, isTopologyDeviceRestoring(device) {
      return "Restoring"
    }
    if let device, isTopologyDeviceUpdating(device) {
      return "Restarting"
    }
    if let device, device.requiresSetup {
      return "New AirPort base station"
    }
    if let device {
      let status = device.statusText.trimmingCharacters(in: .whitespacesAndNewlines)
      if !status.isEmpty {
        return status
      }
      if !device.problemCodes.isEmpty {
        return Self.deviceStatusText(problemCodes: device.problemCodes)
      }
    }
    let status = baseStation.statusText.trimmingCharacters(in: .whitespacesAndNewlines)
    return status.isEmpty ? "Working normally" : status
  }

  func selectedDeviceStatusText() -> String {
    deviceStatusText(for: selectedTopologyDevice())
  }

  func selectedDeviceStatusDetails() -> [String] {
    let codes = currentDeviceProblemCodes()
    guard !codes.isEmpty else { return [] }
    return Self.deviceStatusDetails(problemCodes: codes, routerMode: network.routerMode)
  }

  func selectedDeviceStatusDetail() -> String {
    selectedDeviceStatusDetails().first ?? ""
  }

  func applyDeviceStatus(problemCodes: [String]) {
    baseStation.problemCodes = Self.normalizedProblemCodes(problemCodes)
    baseStation.statusText = Self.deviceStatusText(problemCodes: problemCodes)
    if problemCodes.contains("pubP") {
      baseStation.newAdminPassword = "public"
      baseStation.verifyAdminPassword = "public"
    }
  }

  var selectedDeviceFirmwareUpdateBadgeCount: Int {
    guard let device = selectedTopologyDevice() else { return 0 }
    return firmwareUpdateBadgeCount(for: device)
  }

  var selectedDeviceFirmwareUpdateDetail: String {
    guard let device = selectedTopologyDevice() else { return "" }
    let connectionHost = AirportConnection.normalizedHost(connection.host)
    guard let snapshot = firmwareBadgeSnapshot(for: device, connectionHost: connectionHost),
      hasAvailableAppleFirmwareUpdate(for: device, snapshot: snapshot)
    else {
      return ""
    }
    guard let image = availableAppleFirmwareUpdateImage(for: device, snapshot: snapshot) else {
      return "Firmware update available"
    }
    return "Firmware \(image.version) available"
  }

  private func availableAppleFirmwareUpdateImage(
    for device: AirportDiscoveredDevice,
    snapshot: FirmwareBadgeSnapshot
  ) -> FirmwareImage? {
    let currentVersion = Self.normalizedFirmwareVersion(snapshot.currentVersion)
    guard !currentVersion.isEmpty else { return nil }
    let firmwareProductID = snapshot.productID.trimmingCharacters(in: .whitespacesAndNewlines)
    let deviceProductID = device.productID.trimmingCharacters(in: .whitespacesAndNewlines)
    return snapshot.images.first { image in
      guard image.newest, !image.isLocalFile else { return false }
      let imageProductID = image.productID.trimmingCharacters(in: .whitespacesAndNewlines)
      if !deviceProductID.isEmpty, !imageProductID.isEmpty, imageProductID != deviceProductID {
        return false
      }
      if !firmwareProductID.isEmpty, !imageProductID.isEmpty, imageProductID != firmwareProductID {
        return false
      }
      return Self.normalizedFirmwareVersion(image.version).compare(
        currentVersion, options: .numeric) == .orderedDescending
    }
  }

  var visiblePanes: [Pane] {
    Pane.allCases.filter { supportsPane($0) }
  }

  var hasDetectedInternetFeatureSupport: Bool {
    hasDetectedIPv6Support || hasDetectedDynamicGlobalHostnameSupport
  }

  var showsIPv6InternetControls: Bool {
    hasDetectedIPv6Support && capabilities.supportsIPv6
  }

  var showsDynamicGlobalHostnameControls: Bool {
    hasDetectedDynamicGlobalHostnameSupport && capabilities.supportsDynamicGlobalHostname
  }

  var showsInternetOptionsControls: Bool {
    showsIPv6InternetControls || showsDynamicGlobalHostnameControls
  }

  var internetConnectUsingOptions: [ConnectUsing] {
    ConnectUsing.allCases.filter { $0 != .modem || capabilities.supportsModem }
  }

  var showsModemControls: Bool {
    capabilities.supportsModem
  }

  var showsExtendedModemControls: Bool {
    showsModemControls && internet.connectUsing == .modem && !internet.modemUseAOL
  }

  var showsLoggingControls: Bool {
    capabilities.supportsLogging
  }

  var showsPPPDialInControls: Bool {
    capabilities.supportsPPPDialIn
  }

  var showsAccessControlControls: Bool {
    capabilities.supportsAccessControl
  }

  var showsClassicWDSWirelessControls: Bool {
    hasDetectedClassicWDSSupport && capabilities.supportsClassicWDS
  }

  var showsWirelessClientModeControls: Bool {
    capabilities.supportsAirPlay
  }

  var usesLegacyWirelessClientSecurity: Bool {
    baseStation.productID.trimmingCharacters(in: .whitespacesAndNewlines) == "102"
      && normalized(wireless.mode) == "join"
  }

  var wirelessSecurityOptions: [WirelessSecurityOption] {
    if usesLegacyWirelessClientSecurity {
      return [.none, .wep40, .wepTransitional, .wpaPersonal, .wpaWPA2Personal]
    }
    return WirelessSecurityOption.allCases
  }

  func supportsPane(_ pane: Pane) -> Bool {
    switch pane {
    case .baseStation, .internet, .wireless, .network, .diagnostics:
      return true
    case .airPlay:
      return capabilities.supportsAirPlay
    case .disks:
      return capabilities.supportsDisks
    case .advanced:
      return showsLoggingControls || showsPPPDialInControls || showsAccessControlControls
    case .firmware:
      return capabilities.supportsFirmware
    }
  }

  func reconcileSelectedPaneWithCapabilities() {
    if !supportsPane(selectedPane) {
      selectedPane = .baseStation
    }
  }

  private var hostInternetPopoverDetailValues: [String] {
    [
      hostInternet.connectionStatus,
      hostInternet.routerAddress,
      hostInternet.dnsServers,
    ]
  }

  var visibleTopologyDevices: [AirportDiscoveredDevice] {
    if mockMode {
      return discoveredDevices
    }

    let visibleDeviceResult = topologyDevicesAfterHidingTransientGenericRecords(
      deduplicatedTopologyDevices(discoveredDevices))
    var devices = visibleDeviceResult.devices
    appendMissingRestartingTopologyDevices(to: &devices)
    restorePreservedTopologyDevicePlacement(in: &devices)
    devices = devices.map(topologyDeviceWithPreservedDisplay)
    let host = AirportConnection.normalizedHost(connection.host)
    if !visibleDeviceResult.hidTransientGenericDevice, hasDevicePopoverDetails, !host.isEmpty,
      !devices.contains(where: { isKnownConnectedTopologyDevice($0, connectionHost: host) })
    {
      let connectedDevice =
        AirportDiscoveredDevice(
          id: "connected-\(host)",
          name: baseStation.name.isEmpty ? host : baseStation.name,
          hostName: host
        )
      devices.append(topologyDeviceWithPreservedDisplay(connectedDevice))
    }
    return devices
  }

  private func appendMissingRestartingTopologyDevices(
    to devices: inout [AirportDiscoveredDevice]
  ) {
    let trackers = baseStationRestartTrackers.values.sorted {
      ($0.displaySnapshot.rootIndex ?? Int.max) < ($1.displaySnapshot.rootIndex ?? Int.max)
    }
    for tracker in trackers {
      guard
        !devices.contains(where: {
          baseStationRestartTracker(tracker, matches: $0)
        })
      else {
        continue
      }
      let snapshot = tracker.displaySnapshot
      let host = tracker.connectionHosts.first ?? ""
      let placeholder = AirportDiscoveredDevice(
        id: "restarting-\(tracker.id.uuidString.lowercased())",
        name: snapshot.displayName,
        hostName: host,
        identifiers: tracker.stableIdentifiers,
        modelName: snapshot.modelName,
        productID: snapshot.productID)
      if let targetIndex = snapshot.rootIndex {
        devices.insert(placeholder, at: min(targetIndex, devices.count))
      } else {
        devices.append(placeholder)
      }
    }
  }

  private func topologyDevicesAfterHidingTransientGenericRecords(
    _ devices: [AirportDiscoveredDevice]
  ) -> (devices: [AirportDiscoveredDevice], hidTransientGenericDevice: Bool) {
    var visibleDevices: [AirportDiscoveredDevice] = []
    var hidTransientGenericDevice = false
    for device in devices {
      if shouldHideTransientGenericTopologyDevice(device) {
        hidTransientGenericDevice = true
      } else {
        visibleDevices.append(device)
      }
    }
    return (visibleDevices, hidTransientGenericDevice)
  }

  private func shouldHideTransientGenericTopologyDevice(_ device: AirportDiscoveredDevice) -> Bool {
    guard isGenericRestartTopologyDevice(device) else { return false }
    guard preservedTopologyDisplaySnapshot(for: device) == nil else { return false }
    return hasRecentTopologyDisplaySnapshot
      || updatingBaseStationDisplaySnapshot != nil
      || updatingBaseStationHost != nil
      || !baseStationRestartTrackers.isEmpty
  }

  private var hasRecentTopologyDisplaySnapshot: Bool {
    topologyDisplaySnapshotsByName.values.contains { !Self.isExpiredTopologyDisplaySnapshot($0) }
      || topologyDisplaySnapshotsByIdentifier.values.contains {
        !Self.isExpiredTopologyDisplaySnapshot($0)
      }
      || topologyDisplaySnapshotsByHost.values.contains {
        !Self.isExpiredTopologyDisplaySnapshot($0)
      }
  }

  private func isGenericRestartTopologyDevice(_ device: AirportDiscoveredDevice) -> Bool {
    guard !device.requiresSetup else { return false }
    guard Self.shouldReplaceUpdatingTopologyModelName(device.modelName),
      Self.shouldReplaceUpdatingTopologyProductID(device.productID)
    else {
      return false
    }
    let name = Self.normalizedTopologyDeviceName(device.displayName)
    return name.isEmpty
      || name == "airport base station"
      || !device.problemCodes.isEmpty
  }

  private func topologyDeviceWithPreservedDisplay(
    _ device: AirportDiscoveredDevice
  ) -> AirportDiscoveredDevice {
    guard let snapshot = preservedTopologyDisplaySnapshot(for: device) else {
      return device
    }
    var device = device
    let preservesActiveUpdateIdentity =
      (updatingBaseStationDisplaySnapshot != nil || isTopologyDeviceRestarting(device))
      && isTopologyDeviceUpdating(device)
    if (preservesActiveUpdateIdentity
      && !Self.shouldReplaceUpdatingTopologyModelName(snapshot.modelName))
      || Self.shouldReplaceUpdatingTopologyModelName(device.modelName)
    {
      device.modelName = snapshot.modelName
    }
    if (preservesActiveUpdateIdentity
      && !Self.shouldReplaceUpdatingTopologyProductID(snapshot.productID))
      || Self.shouldReplaceUpdatingTopologyProductID(device.productID)
    {
      device.productID = snapshot.productID
    }
    return device
  }

  private func preservedTopologyDisplaySnapshot(
    for device: AirportDiscoveredDevice
  ) -> TopologyDeviceDisplaySnapshot? {
    if let tracker = baseStationRestartTracker(matching: device) {
      return tracker.displaySnapshot
    }
    if let snapshot = updatingBaseStationDisplaySnapshot,
      isTopologyDeviceUpdateDisplayCandidate(device, snapshot: snapshot)
    {
      return snapshot
    }
    for identifier in device.normalizedStableIdentifiers {
      if let snapshot = topologyDisplaySnapshotsByIdentifier[identifier],
        !Self.isExpiredTopologyDisplaySnapshot(snapshot),
        isTopologyDeviceUpdateDisplayCandidate(device, snapshot: snapshot)
      {
        return snapshot
      }
    }
    for host in device.normalizedConnectionHosts {
      if let snapshot = topologyDisplaySnapshotsByHost[host],
        !Self.isExpiredTopologyDisplaySnapshot(snapshot),
        isTopologyDeviceUpdateDisplayCandidate(device, snapshot: snapshot)
      {
        return snapshot
      }
    }
    let name = Self.normalizedTopologyDeviceName(device.displayName)
    if let snapshot = topologyDisplaySnapshotsByName[name],
      !Self.isExpiredTopologyDisplaySnapshot(snapshot),
      isTopologyDeviceUpdateDisplayCandidate(device, snapshot: snapshot)
    {
      return snapshot
    }
    return nil
  }

  private func isTopologyDeviceUpdateDisplayCandidate(
    _ device: AirportDiscoveredDevice,
    snapshot: TopologyDeviceDisplaySnapshot
  ) -> Bool {
    if isTopologyDeviceUpdating(device) {
      return true
    }
    if device.sharesStableIdentity(with: snapshot.stableIdentifiers) {
      return true
    }
    let snapshotHosts = Set(snapshot.connectionHosts.map(AirportConnection.normalizedHost))
    if !snapshotHosts.isEmpty,
      !Set(device.normalizedConnectionHosts).isDisjoint(with: snapshotHosts)
    {
      return true
    }
    let snapshotName = Self.normalizedTopologyDeviceName(snapshot.displayName)
    guard !snapshotName.isEmpty,
      Self.normalizedTopologyDeviceName(device.displayName) == snapshotName
    else {
      return false
    }
    let productID = device.productID.trimmingCharacters(in: .whitespacesAndNewlines)
    let snapshotProductID = snapshot.productID.trimmingCharacters(in: .whitespacesAndNewlines)
    return Self.shouldReplaceUpdatingTopologyModelName(device.modelName)
      || Self.shouldReplaceUpdatingTopologyProductID(productID)
      || (!snapshotProductID.isEmpty && productID == snapshotProductID)
  }

  private nonisolated static func shouldReplaceUpdatingTopologyModelName(_ modelName: String)
    -> Bool
  {
    let modelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return modelName.isEmpty || modelName == "airport base station"
  }

  private nonisolated static func shouldReplaceUpdatingTopologyProductID(_ productID: String)
    -> Bool
  {
    let productID = productID.trimmingCharacters(in: .whitespacesAndNewlines)
    return productID.isEmpty || productID == "0"
  }

  private nonisolated static func isExpiredTopologyDisplaySnapshot(
    _ snapshot: TopologyDeviceDisplaySnapshot
  ) -> Bool {
    guard let expiresAt = snapshot.expiresAt else { return false }
    return expiresAt <= Date()
  }

  private func rememberTopologyDisplaySnapshots(from devices: [AirportDiscoveredDevice]) {
    let now = Date()
    pruneExpiredTopologyDisplaySnapshots(now: now)
    for (index, device) in devices.enumerated() {
      let name = Self.normalizedTopologyDeviceName(device.displayName)
      let identifiers = device.normalizedStableIdentifiers
      let hosts = device.normalizedConnectionHosts
      guard !name.isEmpty || !identifiers.isEmpty || !hosts.isEmpty else { continue }
      guard
        !Self.shouldReplaceUpdatingTopologyModelName(device.modelName)
          || !Self.shouldReplaceUpdatingTopologyProductID(device.productID)
      else {
        continue
      }
      let snapshot = TopologyDeviceDisplaySnapshot(
        displayName: device.displayName,
        stableIdentifiers: identifiers,
        connectionHosts: hosts,
        modelName: device.modelName,
        productID: device.productID,
        rootIndex: index,
        expiresAt: now.addingTimeInterval(10 * 60))
      if !name.isEmpty {
        topologyDisplaySnapshotsByName[name] = snapshot
      }
      for identifier in identifiers {
        topologyDisplaySnapshotsByIdentifier[identifier] = snapshot
      }
      for host in hosts {
        topologyDisplaySnapshotsByHost[host] = snapshot
      }
    }
  }

  private func pruneExpiredTopologyDisplaySnapshots(now: Date = Date()) {
    topologyDisplaySnapshotsByName = Self.prunedTopologyDisplaySnapshots(
      topologyDisplaySnapshotsByName, now: now)
    topologyDisplaySnapshotsByIdentifier = Self.prunedTopologyDisplaySnapshots(
      topologyDisplaySnapshotsByIdentifier, now: now)
    topologyDisplaySnapshotsByHost = Self.prunedTopologyDisplaySnapshots(
      topologyDisplaySnapshotsByHost, now: now)
  }

  private static func prunedTopologyDisplaySnapshots(
    _ snapshots: [String: TopologyDeviceDisplaySnapshot], now: Date
  ) -> [String: TopologyDeviceDisplaySnapshot] {
    snapshots.filter { _, snapshot in
      guard let expiresAt = snapshot.expiresAt else { return true }
      return expiresAt > now
    }
  }

  private func restorePreservedTopologyDevicePlacement(in devices: inout [AirportDiscoveredDevice])
  {
    for index in devices.indices {
      guard let snapshot = preservedTopologyDisplaySnapshot(for: devices[index]),
        let targetIndex = snapshot.rootIndex,
        index != targetIndex
      else {
        continue
      }
      let device = devices.remove(at: index)
      devices.insert(device, at: min(targetIndex, devices.count))
      return
    }
  }

  var topologyTrees: [AirportTopologyTree] {
    Self.topologyTrees(from: devicesWithInferredPrimaryRelationships())
  }

  private func devicesWithInferredPrimaryRelationships() -> [AirportDiscoveredDevice] {
    var devices = visibleTopologyDevices
    guard devices.count > 1 else { return devices }
    let connectionHost = AirportConnection.normalizedHost(connection.host)
    guard let primary = devices.first(where: { $0.matchesConnectionHost(connectionHost) }) else {
      return devices
    }
    let clientMACs = Set(wirelessClients.map { Self.normalizedHardwareAddress($0.macAddress) })
    let primaryNetworkName = wireless.networkName.trimmingCharacters(in: .whitespacesAndNewlines)

    for index in devices.indices where devices[index].id != primary.id {
      guard devices[index].extendsDeviceID == nil else { continue }
      let deviceMACs = devices[index].identifiers.compactMap(Self.hardwareAddressIdentifier)
      let isWirelessClient = deviceMACs.contains(where: clientMACs.contains)
      let advertisedNetwork =
        devices[index].txtFields["ranm"]?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let sharesPrimaryNetwork =
        !primaryNetworkName.isEmpty
        && advertisedNetwork.compare(
          primaryNetworkName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
      if isWirelessClient || sharesPrimaryNetwork {
        devices[index].extendsDeviceID = primary.id
      }
    }
    return devices
  }

  func isWirelessTopologyConnection(
    from child: AirportDiscoveredDevice,
    to parent: AirportDiscoveredDevice
  ) -> Bool {
    guard
      child.extendsDeviceID == parent.id
        || parent.matchesConnectionHost(AirportConnection.normalizedHost(connection.host))
    else { return false }
    let clientMACs = Set(wirelessClients.map { Self.normalizedHardwareAddress($0.macAddress) })
    return child.identifiers.compactMap(Self.hardwareAddressIdentifier)
      .contains(where: clientMACs.contains)
  }

  private static func hardwareAddressIdentifier(_ identifier: String) -> String? {
    guard let separator = identifier.firstIndex(of: ":") else { return nil }
    let key = identifier[..<separator].lowercased()
    guard key == "wama" || key == "rama" else { return nil }
    let value = String(identifier[identifier.index(after: separator)...])
    let normalized = normalizedHardwareAddress(value)
    return normalized.isEmpty ? nil : normalized
  }

  private static func normalizedHardwareAddress(_ value: String) -> String {
    value.lowercased().filter { $0.isHexDigit }
  }

  var topologyDevicePlacements: [TopologyDevicePlacement] {
    var placements: [TopologyDevicePlacement] = []
    for (column, tree) in topologyTrees.enumerated() {
      appendTopologyPlacements(tree, row: 0, column: column, placements: &placements)
    }
    return placements
  }

  private func appendTopologyPlacements(
    _ tree: AirportTopologyTree,
    row: Int,
    column: Int,
    placements: inout [TopologyDevicePlacement]
  ) {
    placements.append(
      TopologyDevicePlacement(
        deviceID: tree.device.id,
        row: row,
        column: column,
        parentID: tree.device.extendsDeviceID))
    for child in tree.children {
      appendTopologyPlacements(child, row: row + 1, column: column, placements: &placements)
    }
  }

  static func topologyTrees(from devices: [AirportDiscoveredDevice]) -> [AirportTopologyTree] {
    let devicesByID = Dictionary(uniqueKeysWithValues: devices.map { ($0.id, $0) })
    let childrenByParent = Dictionary(
      grouping: devices.filter { device in
        guard let parentID = device.extendsDeviceID else { return false }
        return devicesByID[parentID] != nil
      }
    ) { $0.extendsDeviceID ?? "" }
    let roots = devices.filter { device in
      guard let parentID = device.extendsDeviceID else { return true }
      return devicesByID[parentID] == nil
    }

    func build(_ device: AirportDiscoveredDevice, ancestry: Set<String>) -> AirportTopologyTree {
      let children = (childrenByParent[device.id] ?? [])
        .filter { !ancestry.contains($0.id) }
        .map { build($0, ancestry: ancestry.union([device.id])) }
      return AirportTopologyTree(device: device, children: children)
    }

    return roots.map { build($0, ancestry: []) }
  }

  func firmwareUpdateBadgeCount(for device: AirportDiscoveredDevice) -> Int {
    let connectionHost = AirportConnection.normalizedHost(connection.host)
    let snapshot = firmwareBadgeSnapshot(for: device, connectionHost: connectionHost)
    guard hasAvailableAppleFirmwareUpdate(for: device, snapshot: snapshot) else { return 0 }
    return 1
  }

  private func firmwareBadgeSnapshot(
    for device: AirportDiscoveredDevice,
    connectionHost: String
  ) -> FirmwareBadgeSnapshot? {
    if isKnownConnectedTopologyDevice(device, connectionHost: connectionHost) {
      let currentSnapshot = FirmwareBadgeSnapshot(
        currentVersion: firmware.currentVersion,
        productID: firmware.productID,
        images: firmware.images)
      if hasAvailableAppleFirmwareUpdate(for: device, snapshot: currentSnapshot) {
        return currentSnapshot
      }
      if firmware.hasLoadedImages || !firmware.images.isEmpty {
        return nil
      }
    }
    for identifier in firmwareBadgeIdentifiers(for: device, fallbackHosts: [device.hostName]) {
      if let snapshot = firmwareBadgeSnapshotsByIdentifier[identifier] {
        return snapshot
      }
    }
    return nil
  }

  private func hasAvailableAppleFirmwareUpdate(
    for device: AirportDiscoveredDevice,
    snapshot: FirmwareBadgeSnapshot?
  ) -> Bool {
    guard let snapshot else { return false }
    let currentVersion = Self.normalizedFirmwareVersion(snapshot.currentVersion)
    guard !currentVersion.isEmpty else { return false }
    let firmwareProductID = snapshot.productID.trimmingCharacters(in: .whitespacesAndNewlines)
    let deviceProductID = device.productID.trimmingCharacters(in: .whitespacesAndNewlines)
    if !deviceProductID.isEmpty, !firmwareProductID.isEmpty, deviceProductID != firmwareProductID {
      return false
    }

    return snapshot.images.contains { image in
      guard image.newest, !image.isLocalFile else { return false }
      return Self.normalizedFirmwareVersion(image.version).compare(
        currentVersion, options: .numeric) == .orderedDescending
    }
  }

  func updateConnectedFirmwareBadgeSnapshot() {
    let snapshot = FirmwareBadgeSnapshot(
      currentVersion: firmware.currentVersion,
      productID: firmware.productID,
      images: firmware.images)
    let identifiers = firmwareBadgeIdentifiersForConnectedDevice()
    guard !identifiers.isEmpty else { return }

    if let device = selectedTopologyDevice(),
      hasAvailableAppleFirmwareUpdate(for: device, snapshot: snapshot)
    {
      for identifier in identifiers {
        firmwareBadgeSnapshotsByIdentifier[identifier] = snapshot
      }
    } else if firmware.hasLoadedImages || !firmware.images.isEmpty {
      for identifier in identifiers {
        firmwareBadgeSnapshotsByIdentifier.removeValue(forKey: identifier)
      }
    }
  }

  private func firmwareBadgeIdentifiersForConnectedDevice() -> [String] {
    var identifiers = selectedTopologyDeviceIdentifiers + connectedTopologyDeviceIdentifiers
    if let device = selectedTopologyDevice() {
      identifiers += firmwareBadgeIdentifiers(for: device, fallbackHosts: [connection.host])
    }
    identifiers += [connection.host, connectedTopologyDeviceHost].map(
      AirportConnection.normalizedHost)
    return Self.uniqueNonEmptyValues(identifiers)
  }

  private func firmwareBadgeIdentifiers(
    for device: AirportDiscoveredDevice,
    fallbackHosts: [String] = []
  ) -> [String] {
    Self.uniqueNonEmptyValues(
      [device.id, device.hostName]
        + device.normalizedStableIdentifiers
        + fallbackHosts
    )
  }

  var supportsDiskFileSharingAccountEditing: Bool {
    true
  }

  var otherWiFiDevicesMenuDevices: [AirportDiscoveredDevice] {
    guard !mockMode else { return [] }
    return deduplicatedTopologyDevices(discoveredDevices)
  }

  func presentOtherWiFiDeviceFromMenu(id: String) {
    guard let device = otherWiFiDevicesMenuDevices.first(where: { $0.id == id }) else { return }
    selectTopologyDevice(device)
    if device.requiresSetup {
      beginSetup(for: device)
      return
    }
    loadInitialSettingsIfPossible()
    isDevicePopoverPresented = true
  }

  func prefillConnectionPasswordFromEnvironmentIfNeeded() {
    guard connection.password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      let password = Self.environmentValue("AIRPORT_UTILITY_PASSWORD"),
      !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return }
    connection.password = password
    hasTrustedConnectionPassword = true
  }

  public func topologyDisplayLogSnapshot() -> String {
    let host = AirportConnection.normalizedHost(connection.host)
    let discovered = discoveredDevices
    let deduplicated = deduplicatedTopologyDevices(discovered)
    let visible = visibleTopologyDevices
    let root: [String: Any] = [
      "timestamp": Self.diagnosticTimestamp(),
      "connection": [
        "host": connection.host,
        "normalizedHost": host,
        "passwordSet": !connection.password.trimmingCharacters(in: .whitespacesAndNewlines)
          .isEmpty,
        "rememberPassword": rememberConnectionPassword,
      ],
      "baseStation": [
        "name": baseStation.name,
        "serialNumber": baseStation.serialNumber,
        "version": baseStation.version,
      ],
      "state": [
        "mockMode": mockMode,
        "showConnectionDetails": showConnectionDetails,
        "hasDevicePopoverDetails": hasDevicePopoverDetails,
        "hasCompleteDevicePopoverDetails": hasCompleteDevicePopoverDetails,
        "hasLoadedSettings": hasLoadedSettings,
        "hasStartedBonjourDiscovery": hasStartedBonjourDiscovery,
        "isBusy": isBusy,
        "isEditingDevice": isEditingDevice,
        "isDevicePopoverPresented": isDevicePopoverPresented,
        "selectedPane": "\(selectedPane)",
        "selectedTopologyDeviceID": selectedTopologyDeviceID ?? "",
        "status": status,
      ],
      "identityState": [
        "selectedTopologyDeviceIdentifiers": selectedTopologyDeviceIdentifiers,
        "connectedTopologyDeviceIdentifiers": connectedTopologyDeviceIdentifiers,
        "updatingBaseStationHost": updatingBaseStationHost ?? "",
        "updatingBaseStationDeviceID": updatingBaseStationDeviceID ?? "",
        "updatingBaseStationDeviceIdentifiers": updatingBaseStationDeviceIdentifiers,
        "pendingTopologyConnectionHost": pendingTopologyConnectionHost ?? "",
      ],
      "displayedTopologyDevices": visible.enumerated().map {
        diagnosticDevice($0.element, index: $0.offset, connectionHost: host)
      },
      "deduplicatedDiscoveredDevices": deduplicated.enumerated().map {
        diagnosticDevice($0.element, index: $0.offset, connectionHost: host)
      },
      "rawDiscoveredDevices": discovered.enumerated().map {
        diagnosticDevice($0.element, index: $0.offset, connectionHost: host)
      },
    ]
    guard JSONSerialization.isValidJSONObject(root),
      let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]),
      let output = String(data: data, encoding: .utf8)
    else {
      return #"{"error":"failed to encode topology display log snapshot"}"#
    }
    return output
  }

  private func diagnosticDevice(
    _ device: AirportDiscoveredDevice, index: Int, connectionHost: String
  ) -> [String: Any] {
    [
      "index": index,
      "id": device.id,
      "bonjourName": device.name,
      "displayName": device.displayName,
      "dnsName": device.hostName,
      "connectionHost": device.connectionHost,
      "ipAddresses": device.addresses,
      "normalizedConnectionHosts": device.normalizedConnectionHosts,
      "rawIdentifiers": device.identifiers,
      "normalizedStableIdentifiers": device.normalizedStableIdentifiers,
      "isSyntheticConnectedDevice": device.id.hasPrefix("connected-"),
      "isSelected": selectedTopologyDeviceID == device.id,
      "isUpdating": isTopologyDeviceUpdating(device),
      "matchesCurrentConnectionHost": device.matchesConnectionHost(connectionHost),
      "sharesSelectedStableIdentity": device.sharesStableIdentity(
        with: selectedTopologyDeviceIdentifiers),
      "sharesConnectedStableIdentity": device.sharesStableIdentity(
        with: connectedTopologyDeviceIdentifiers),
      "sharesUpdatingStableIdentity": device.sharesStableIdentity(
        with: updatingBaseStationDeviceIdentifiers),
    ]
  }

  private static func diagnosticTimestamp() -> String {
    exportTimestamp()
  }

  nonisolated static func exportTimestamp() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date())
  }

  private func deduplicatedTopologyDevices(_ devices: [AirportDiscoveredDevice])
    -> [AirportDiscoveredDevice]
  {
    var deduplicated: [AirportDiscoveredDevice] = []
    for device in devices {
      let hasDiscoveryIdentity =
        !device.normalizedConnectionHosts.isEmpty
        || !device.normalizedStableIdentifiers.isEmpty
      guard hasDiscoveryIdentity else { continue }
      if let index = deduplicated.firstIndex(where: {
        $0.sharesConnectionIdentity(with: device)
          || shouldCollapseConnectedRenameCandidate($0, device)
      }) {
        let existing = deduplicated[index]
        if topologyDevicePreferenceScore(for: device) > topologyDevicePreferenceScore(for: existing)
        {
          deduplicated[index] = device
        }
      } else {
        deduplicated.append(device)
      }
    }
    return deduplicated
  }

  private func shouldCollapseConnectedRenameCandidate(
    _ first: AirportDiscoveredDevice,
    _ second: AirportDiscoveredDevice
  ) -> Bool {
    let currentName = Self.normalizedTopologyDeviceName(baseStation.name)
    guard !currentName.isEmpty else { return false }
    let firstProductID = first.productID.trimmingCharacters(in: .whitespacesAndNewlines)
    let secondProductID = second.productID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !firstProductID.isEmpty, firstProductID == secondProductID else { return false }

    return isConnectedRenamePair(connected: first, renamed: second, currentName: currentName)
      || isConnectedRenamePair(connected: second, renamed: first, currentName: currentName)
  }

  private func isConnectedRenamePair(
    connected: AirportDiscoveredDevice,
    renamed: AirportDiscoveredDevice,
    currentName: String
  ) -> Bool {
    Self.normalizedTopologyDeviceName(renamed.displayName) == currentName
      && isKnownConnectedTopologyDevice(
        connected, connectionHost: AirportConnection.normalizedHost(connection.host))
  }

  private func topologyDevicePreferenceScore(for device: AirportDiscoveredDevice) -> Int {
    var score = 0
    let currentName = Self.normalizedTopologyDeviceName(baseStation.name)
    if !currentName.isEmpty && Self.normalizedTopologyDeviceName(device.displayName) == currentName
    {
      score += 8
    }
    if selectedTopologyDeviceID == device.id {
      score += 4
    }
    if device.sharesStableIdentity(with: selectedTopologyDeviceIdentifiers) {
      score += 4
    }
    if updatingBaseStationDeviceID == device.id {
      score += 2
    }
    if device.sharesStableIdentity(with: updatingBaseStationDeviceIdentifiers) {
      score += 2
    }
    if isTopologyDeviceRestarting(device) {
      score += 2
    }
    if !AirportConnection.normalizedHost(device.hostName).isEmpty {
      score += 1
    }
    return score
  }

  private static func normalizedTopologyDeviceName(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  func updateConnectedTopologyDeviceIdentifiers(from devices: [AirportDiscoveredDevice]) {
    let host = AirportConnection.normalizedHost(connection.host)
    guard !host.isEmpty else {
      connectedTopologyDeviceIdentifiers = []
      connectedTopologyDeviceHost = ""
      return
    }
    if let device = devices.first(where: { $0.matchesConnectionHost(host) }),
      !device.normalizedStableIdentifiers.isEmpty
    {
      connectedTopologyDeviceIdentifiers = device.normalizedStableIdentifiers
      connectedTopologyDeviceHost = host
      return
    }
    if host == connectedTopologyDeviceHost,
      devices.contains(where: { $0.sharesStableIdentity(with: connectedTopologyDeviceIdentifiers) })
    {
      return
    }
    connectedTopologyDeviceIdentifiers = []
    connectedTopologyDeviceHost = ""
  }

  func rememberSelectedTopologyDeviceIdentity(_ device: AirportDiscoveredDevice) {
    selectedTopologyDeviceIdentifiers = device.normalizedStableIdentifiers
    if !device.normalizedStableIdentifiers.isEmpty {
      connectedTopologyDeviceIdentifiers = device.normalizedStableIdentifiers
      connectedTopologyDeviceHost = AirportConnection.normalizedHost(connection.host)
    }
  }

  private func isReplacementForSelectedTopologyDevice(
    _ device: AirportDiscoveredDevice, selectedHost: String
  ) -> Bool {
    if !selectedHost.isEmpty && device.matchesConnectionHost(selectedHost) {
      return true
    }
    return device.sharesStableIdentity(with: selectedTopologyDeviceIdentifiers)
  }

  private func updateConnectionHostAfterStableIdentityReplacement(
    _ device: AirportDiscoveredDevice, selectedHost: String
  ) {
    guard !selectedTopologyDeviceIdentifiers.isEmpty else { return }
    guard selectedHost.isEmpty || !device.matchesConnectionHost(selectedHost) else { return }
    let replacementHost = AirportConnection.normalizedHost(device.connectionHost)
    guard !replacementHost.isEmpty else { return }
    if isBusy {
      pendingTopologyConnectionHost = replacementHost
    } else {
      connection.host = replacementHost
    }
  }

  private func reuseConnectionPasswordAfterStableIdentityReplacement(
    _ device: AirportDiscoveredDevice,
    previousHost: String,
    previousPassword: String,
    previousRememberPassword: Bool,
    previousPasswordTrusted: Bool
  ) {
    if !previousPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      connection.password = previousPassword
      rememberConnectionPassword = previousRememberPassword
      hasTrustedConnectionPassword = previousPasswordTrusted
      if previousPasswordTrusted {
        saveConnectionPasswordIfRequested(for: device)
      }
    } else {
      loadSavedPasswordForConnectionHost(device: device, fallbackHosts: [previousHost])
    }
  }

  func isKnownConnectedTopologyDevice(
    _ device: AirportDiscoveredDevice, connectionHost: String
  ) -> Bool {
    device.matchesConnectionHost(connectionHost)
      || device.sharesStableIdentity(with: selectedTopologyDeviceIdentifiers)
      || device.sharesStableIdentity(with: connectedTopologyDeviceIdentifiers)
      || device.sharesStableIdentity(with: updatingBaseStationDeviceIdentifiers)
  }

  func selectTopologyDevice(
    _ device: AirportDiscoveredDevice,
    isAutomaticStartupSelection: Bool = false
  ) {
    if !isAutomaticStartupSelection {
      hasManualTopologySelection = true
      startupConnectionTask?.cancel()
      startupConnectionTask = nil
    }
    isInternetPopoverPresented = false
    isInternetSelected = false
    cacheCurrentConnectionPasswordForSession()
    let matchesCurrentDeviceIdentity = isKnownConnectedTopologyDevice(
      device, connectionHost: AirportConnection.normalizedHost(connection.host))
    let existingPassword = connection.password
    let existingRememberPassword = rememberConnectionPassword
    let existingPasswordTrusted = hasTrustedConnectionPassword
    selectedTopologyDeviceID = device.id
    rememberSelectedTopologyDeviceIdentity(device)
    let host = AirportConnection.normalizedHost(device.connectionHost)
    let oldHost = AirportConnection.normalizedHost(connection.host)
    if !host.isEmpty, host != oldHost {
      isEditingDevice = false
      preview = nil
      connection.host = host
      if !useDefaultPasswordForDevice(device) {
        if matchesCurrentDeviceIdentity,
          !existingPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
          connection.password = existingPassword
          rememberConnectionPassword = existingRememberPassword
          hasTrustedConnectionPassword = existingPasswordTrusted
          if existingPasswordTrusted {
            saveConnectionPasswordIfRequested(for: device)
          }
        } else {
          connection.password = ""
          rememberConnectionPassword = false
          hasTrustedConnectionPassword = false
          loadSavedPasswordForConnectionHost(
            device: device,
            fallbackHosts: matchesCurrentDeviceIdentity ? [oldHost] : [])
          prefillConnectionPasswordFromEnvironmentIfNeeded()
        }
      }
      if !matchesCurrentDeviceIdentity {
        clearLoadedDeviceDetails(name: device.displayName)
      } else if baseStation.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        baseStation.name = device.displayName
      }
      if isBusy, liveCredentialsAvailable {
        shouldRefreshAfterBusySelection = true
      }
    } else {
      if !host.isEmpty {
        connection.host = host
      }
      if useDefaultPasswordForDevice(device) {
        clearLoadedDeviceDetails(name: device.displayName)
      } else if connection.password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        loadSavedPasswordForConnectionHost(device: device, fallbackHosts: [oldHost])
        prefillConnectionPasswordFromEnvironmentIfNeeded()
      }
      if baseStation.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        baseStation.name = device.displayName
      }
    }
    restartWirelessClientPollingIfPossible()
  }

  func deselectTopologyDevice(_ device: AirportDiscoveredDevice) {
    // Restart and restore confirmations replace the device popover with a
    // sheet. Preserve the selected target across that presentation handoff.
    guard !isShowingRestartConfirmation, !isShowingRestoreConfirmation else { return }
    if selectedTopologyDeviceID == device.id {
      selectedTopologyDeviceID = nil
      selectedTopologyDeviceIdentifiers = []
    }
  }

  func isTopologyDeviceUpdating(_ device: AirportDiscoveredDevice) -> Bool {
    if isTopologyDeviceRestarting(device) {
      return true
    }
    if let updatingBaseStationDeviceID, updatingBaseStationDeviceID == device.id {
      return true
    }
    if device.sharesStableIdentity(with: updatingBaseStationDeviceIdentifiers) {
      return true
    }
    guard let updatingBaseStationHost else { return false }
    return device.matchesConnectionHost(updatingBaseStationHost)
  }

  func isTopologyDeviceRestoring(_ device: AirportDiscoveredDevice) -> Bool {
    guard isRestoringDefaults else { return false }
    if selectedTopologyDeviceID == device.id {
      return true
    }
    if device.sharesStableIdentity(with: selectedTopologyDeviceIdentifiers) {
      return true
    }
    return device.matchesConnectionHost(AirportConnection.normalizedHost(connection.host))
  }

  func selectInternetNode() {
    selectedTopologyDeviceID = nil
    selectedTopologyDeviceIdentifiers = []
    isDevicePopoverPresented = false
    if isEditingDevice {
      cancelEditing()
    } else {
      preview = nil
    }
    isInternetSelected = true
  }

  func deselectInternetNode() {
    isInternetSelected = false
  }

}
