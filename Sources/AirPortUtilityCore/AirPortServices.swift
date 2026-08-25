import Foundation
import SwiftUI

@MainActor
public final class AirportAppModel: ObservableObject {
  @Published var connection = AirportConnection()
  @Published var selectedPane: Pane = .baseStation
  @Published var status = "Not connected"
  @Published var isBusy = false
  @Published var logs: [String] = []
  @Published var preview: CommandPreview?
  @Published var mockMode = false
  @Published var showConnectionDetails = true
  @Published var rememberConnectionPassword = false
  @Published var isEditingDevice = false
  @Published var isShowingPasswords = false
  @Published var isShowingPreferences = false
  @Published var isShowingConfigureOther = false
  @Published var isShowingSites = false
  @Published var isShowingSetup = false
  @Published var isWaitingForSetupRestart = false
  @Published var didSetupDeviceDisappear = false
  var setupPreRestartServiceID = ""
  var setupPreRestartBonjourSeed = ""
  @Published var isShowingRestartConfirmation = false
  @Published var isShowingRestoreConfirmation = false
  @Published var isRestorePending = false
  @Published var isWaitingForRestoreRestart = false
  var pendingRestoreConnection: AirportConnection?
  var pendingRestoreDeviceIdentifiers: [String] = []
  @Published var setup = AirPortSetupState()
  var setupSessionID = UUID()
  @Published var isRestoringDefaults = false
  @Published var isDevicePopoverPresented = false {
    didSet {
      guard isDevicePopoverPresented != oldValue else { return }
      devicePopoverPresentationDidChange()
    }
  }
  @Published var isInternetPopoverPresented = false
  @Published var isConnectionPopoverPresented = false
  @Published var isInternetSelected = false
  @Published var isDashboardVisible = false
  private let connectionSession = ConnectionSession()
  private let topologyStore = TopologyStore()
  private let firmwareCoordinator = FirmwareCoordinator()
  private let configurationSession = ConfigurationSession()
  @Published var discoveredDevices: [AirportDiscoveredDevice] = []
  @Published var baseStation = BaseStationState()
  @Published var internet = InternetState()
  @Published var hostInternet = HostInternetState()
  @Published var networkDiagnostics = NetworkDiagnosticsState()
  @Published var wifiCongestion = WiFiCongestionState()
  @Published var wireless = WirelessState()
  @Published var airPlay = AirPlayState()
  @Published var wirelessScanNetworkNames: [String] = []
  @Published var network = NetworkState()
  @Published var disks = DisksState()
  @Published var storageHealth = StorageHealthState()
  @Published var storageHealthHistory: [StorageHealthEvent] = []
  @Published var timeMachineBackups = TimeMachineBackupState()
  @Published var healthNotificationPreferences = HealthNotificationPreferences()
  @Published var healthAlertHistory: [HealthAlertEvent] = []
  @Published var healthHistory: [HealthHistorySample] = []
  @Published var configurationChangeHistory: [ConfigurationChangeRecord] = []
  @Published var automaticConfigurationBackups: [ConfigurationChangeRecord] = []
  @Published var recoveryGuidance: RecoveryGuidance?
  @Published var settingsComparison: SettingsComparison?
  @Published var clientCustomNames: [String: String] = [:]
  @Published var sites: [Site] = []
  let healthHistoryStore: HealthHistoryStore
  let configurationHistoryStore: ConfigurationHistoryStore
  let automaticConfigurationBackupStore: ConfigurationHistoryStore
  let clientIdentityStore: ClientIdentityStore
  let siteStore: SiteStore
  var activeHealthAlertSignatures: [String: String] = [:]
  var automaticConfigurationBackupInterval: TimeInterval = 86_400
  var automaticConfigurationBackupHost = ""
  var lastAutomaticConfigurationBackupDate: Date?
  var healthNotificationDeliveryOverride:
    (@MainActor (HealthAlertEvent) async -> Bool)?
  var storageSMARTStatuses: [String] = []
  var hasReportedDiskFileSharingSetting = false
  @Published var advanced = AdvancedState()
  @Published var legacyDeviceOptions = LegacyDeviceOptionsState()
  @Published var capabilities = DeviceCapabilities()
  @Published var hasDetectedIPv6Support = false
  @Published var hasDetectedDynamicGlobalHostnameSupport = false
  @Published var hasDetectedClassicWDSSupport = false
  @Published var usesLegacyACP = false
  var legacyACPSettingsValuesJSON = ""
  @Published var wirelessClients: [WirelessClient] = []
  @Published var wirelessClientDiscoveryNote: String?
  var wifiCongestionTask: Task<Void, Never>?
  @Published var hasLoadedWirelessClients = false
  @Published var firmware = FirmwareState()
  var hasLoadedSettings = false
  var hasStartedBonjourDiscovery = false
  var shouldRefreshAfterBusySelection = false
  var bonjourBrowser: AirPortBonjourBrowser?
  static let stableIdentifierPasswordAccountPrefix = "airport-device-id:"
  static let healthNotificationPreferencesKey = "health-notification-preferences"
  static let healthAlertHistoryKey = "health-alert-history"
  static let activeHealthAlertSignaturesKey = "active-health-alert-signatures"

  let runner = AirportCommandRunner()
  let passwordStore: AirportPasswordStore
  var selectedTopologyDeviceID: String? {
    get { topologyStore.selectedDeviceID }
    set {
      let didChange = topologyStore.selectedDeviceID != newValue
      objectWillChange.send()
      topologyStore.selectedDeviceID = newValue
      if didChange {
        selectedDeviceForWirelessClientsDidChange()
      }
    }
  }
  var startupConnectionTask: Task<Void, Never>? {
    get { topologyStore.startupConnectionTask }
    set { topologyStore.startupConnectionTask = newValue }
  }
  var hasAttemptedStartupConnection: Bool {
    get { topologyStore.hasAttemptedStartupConnection }
    set { topologyStore.hasAttemptedStartupConnection = newValue }
  }
  var hasManualTopologySelection: Bool {
    get { topologyStore.hasManualTopologySelection }
    set { topologyStore.hasManualTopologySelection = newValue }
  }
  var startupDiscoveryDebounceNanoseconds: UInt64 {
    get { topologyStore.startupDiscoveryDebounceNanoseconds }
    set { topologyStore.startupDiscoveryDebounceNanoseconds = newValue }
  }
  var updatingBaseStationHost: String? {
    get { topologyStore.updatingBaseStationHost }
    set {
      objectWillChange.send()
      topologyStore.updatingBaseStationHost = newValue
    }
  }
  var updatingBaseStationDeviceID: String? {
    get { topologyStore.updatingBaseStationDeviceID }
    set {
      objectWillChange.send()
      topologyStore.updatingBaseStationDeviceID = newValue
    }
  }
  var selectedTopologyDeviceIdentifiers: [String] {
    get { topologyStore.selectedDeviceIdentifiers }
    set { topologyStore.selectedDeviceIdentifiers = newValue }
  }
  var connectedTopologyDeviceIdentifiers: [String] {
    get { topologyStore.connectedDeviceIdentifiers }
    set { topologyStore.connectedDeviceIdentifiers = newValue }
  }
  var connectedTopologyDeviceHost: String {
    get { topologyStore.connectedDeviceHost }
    set { topologyStore.connectedDeviceHost = newValue }
  }
  var updatingBaseStationDeviceIdentifiers: [String] {
    get { topologyStore.updatingDeviceIdentifiers }
    set { topologyStore.updatingDeviceIdentifiers = newValue }
  }
  var updatingBaseStationDisplaySnapshot: TopologyDeviceDisplaySnapshot? {
    get { topologyStore.updatingDisplaySnapshot }
    set { topologyStore.updatingDisplaySnapshot = newValue }
  }
  var topologyDisplaySnapshotsByName: [String: TopologyDeviceDisplaySnapshot] {
    get { topologyStore.displaySnapshotsByName }
    set { topologyStore.displaySnapshotsByName = newValue }
  }
  var topologyDisplaySnapshotsByIdentifier: [String: TopologyDeviceDisplaySnapshot] {
    get { topologyStore.displaySnapshotsByIdentifier }
    set { topologyStore.displaySnapshotsByIdentifier = newValue }
  }
  var topologyDisplaySnapshotsByHost: [String: TopologyDeviceDisplaySnapshot] {
    get { topologyStore.displaySnapshotsByHost }
    set { topologyStore.displaySnapshotsByHost = newValue }
  }
  var firmwareBadgeSnapshotsByIdentifier: [String: FirmwareBadgeSnapshot] {
    get { topologyStore.firmwareBadgeSnapshotsByIdentifier }
    set { topologyStore.firmwareBadgeSnapshotsByIdentifier = newValue }
  }
  var pendingTopologyConnectionHost: String? {
    get { topologyStore.pendingConnectionHost }
    set { topologyStore.pendingConnectionHost = newValue }
  }
  var baseStationRestartTrackers: [UUID: BaseStationRestartTracker] {
    get { topologyStore.restartTrackers }
    set {
      objectWillChange.send()
      topologyStore.restartTrackers = newValue
    }
  }
  var baseStationRestartTimeoutTasks: [UUID: Task<Void, Never>] {
    get { topologyStore.restartTimeoutTasks }
    set { topologyStore.restartTimeoutTasks = newValue }
  }
  var baseStationRestartRecoveryTasks: [UUID: Task<Void, Never>] {
    get { topologyStore.restartRecoveryTasks }
    set { topologyStore.restartRecoveryTasks = newValue }
  }
  var baseStationRestartTimeoutNanoseconds: UInt64 {
    get { topologyStore.restartTimeoutNanoseconds }
    set { topologyStore.restartTimeoutNanoseconds = newValue }
  }
  var baseStationRestartPollIntervalNanoseconds: UInt64 {
    get { topologyStore.restartPollIntervalNanoseconds }
    set { topologyStore.restartPollIntervalNanoseconds = newValue }
  }
  var baseStationRestartProbeTimeout: TimeInterval {
    get { topologyStore.restartProbeTimeout }
    set { topologyStore.restartProbeTimeout = newValue }
  }
  var baseStationRestartProbeOverride: (@MainActor (AirportConnection, Bool, Bool) async -> Bool)?
  {
    get { topologyStore.restartProbeOverride }
    set { topologyStore.restartProbeOverride = newValue }
  }
  var baseStationRestartStatusTrackerID: UUID? {
    get { topologyStore.restartStatusTrackerID }
    set { topologyStore.restartStatusTrackerID = newValue }
  }
  var wirelessClientPollTask: Task<Void, Never>? {
    get { topologyStore.wirelessClientPollTask }
    set { topologyStore.wirelessClientPollTask = newValue }
  }
  var wirelessClientPollGeneration: UUID {
    get { topologyStore.wirelessClientPollGeneration }
    set { topologyStore.wirelessClientPollGeneration = newValue }
  }
  var wirelessClientPollIntervalNanoseconds: UInt64 {
    get { topologyStore.wirelessClientPollIntervalNanoseconds }
    set { topologyStore.wirelessClientPollIntervalNanoseconds = newValue }
  }
  var wirelessClientIdentityDiscoveryInterval: TimeInterval {
    get { topologyStore.wirelessClientIdentityDiscoveryInterval }
    set { topologyStore.wirelessClientIdentityDiscoveryInterval = newValue }
  }
  var wirelessClientIdentityDiscoveryHost: String {
    get { topologyStore.wirelessClientIdentityDiscoveryHost }
    set { topologyStore.wirelessClientIdentityDiscoveryHost = newValue }
  }
  var lastWirelessClientIdentityDiscoveryDate: Date? {
    get { topologyStore.lastWirelessClientIdentityDiscoveryDate }
    set { topologyStore.lastWirelessClientIdentityDiscoveryDate = newValue }
  }
  var wirelessClientFetchOverride:
    (@MainActor (AirportConnection, Bool, String) async throws -> [WirelessClient])?
  {
    get { topologyStore.wirelessClientFetchOverride }
    set { topologyStore.wirelessClientFetchOverride = newValue }
  }
  var legacySNMPCommunity: String {
    get { topologyStore.legacySNMPCommunity }
    set { topologyStore.legacySNMPCommunity = newValue }
  }
  var lastWirelessClientError: String {
    get { topologyStore.lastWirelessClientError }
    set { topologyStore.lastWirelessClientError = newValue }
  }
  var storageHealthRefreshTask: Task<Void, Never>?
  var networkDiagnosticsTask: Task<Void, Never>?
  var storageInventoryHealthRefreshTask: Task<Void, Never>?
  var storageHealthProbeOverride: (@MainActor (String, UInt16, TimeInterval) async -> Bool)?
  var storageInventoryRefreshOverride:
    (@MainActor (AirportConnection) async -> (raw: String, records: [DiskRecord])?)?
  var timeMachineBackupScanTask: Task<Void, Never>?
  var timeMachineBackupScanOverride:
    (@MainActor ([String]) async -> [TimeMachineBackupRecord])?
  var archiveCompletionMonitorTask: Task<Void, Never>? {
    get { configurationSession.archiveCompletionMonitorTask }
    set { configurationSession.archiveCompletionMonitorTask = newValue }
  }
  var hasTrustedConnectionPassword: Bool {
    get { connectionSession.hasTrustedConnectionPassword }
    set { connectionSession.hasTrustedConnectionPassword = newValue }
  }
  var firmwareDownloadService: FirmwareDownloadService {
    get { firmwareCoordinator.downloadService }
    set { firmwareCoordinator.downloadService = newValue }
  }
  var firmwareInstallVerificationAttempts: Int {
    get { firmwareCoordinator.installVerificationAttempts }
    set { firmwareCoordinator.installVerificationAttempts = newValue }
  }
  var firmwareInstallVerificationDelayNanoseconds: UInt64 {
    get { firmwareCoordinator.installVerificationDelayNanoseconds }
    set { firmwareCoordinator.installVerificationDelayNanoseconds = newValue }
  }
  var cleanSnapshot: AirportSettingsSnapshot {
    get { configurationSession.cleanSnapshot }
    set { configurationSession.cleanSnapshot = newValue }
  }
  var cleanCapabilities: DeviceCapabilities {
    get { configurationSession.cleanCapabilities }
    set { configurationSession.cleanCapabilities = newValue }
  }
  var cleanHasDetectedIPv6Support: Bool {
    get { configurationSession.cleanHasDetectedIPv6Support }
    set { configurationSession.cleanHasDetectedIPv6Support = newValue }
  }
  var cleanHasDetectedDynamicGlobalHostnameSupport: Bool {
    get { configurationSession.cleanHasDetectedDynamicGlobalHostnameSupport }
    set { configurationSession.cleanHasDetectedDynamicGlobalHostnameSupport = newValue }
  }
  var cleanHasDetectedClassicWDSSupport: Bool {
    get { configurationSession.cleanHasDetectedClassicWDSSupport }
    set { configurationSession.cleanHasDetectedClassicWDSSupport = newValue }
  }
  var firmwareCatalogRefreshTask: Task<Void, Never>? {
    get { firmwareCoordinator.catalogRefreshTask }
    set { firmwareCoordinator.catalogRefreshTask = newValue }
  }
  var firmwareCompletionMonitorTask: Task<Void, Never>? {
    get { firmwareCoordinator.completionMonitorTask }
    set { firmwareCoordinator.completionMonitorTask = newValue }
  }
  var firmwareUploadProgressBuffer: String {
    get { firmwareCoordinator.uploadProgressBuffer }
    set { firmwareCoordinator.uploadProgressBuffer = newValue }
  }
  var sessionConnectionPasswords: [String: CachedConnectionPassword] {
    get { connectionSession.cachedPasswordsByAccount }
    set { connectionSession.cachedPasswordsByAccount = newValue }
  }

  public convenience init() {
    self.init(passwordStore: AirportAppModel.defaultPasswordStore())
  }

  init(passwordStore: AirportPasswordStore) {
    self.passwordStore = passwordStore
    self.healthHistoryStore = HealthHistoryStore()
    self.configurationHistoryStore = ConfigurationHistoryStore()
    self.automaticConfigurationBackupStore = ConfigurationHistoryStore(
      directory: FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
      )[0].appendingPathComponent(
        "AirPort Utility Powerhouse/Automatic Backups", isDirectory: true),
      maxRecords: 14)
    self.clientIdentityStore = ClientIdentityStore()
    self.siteStore = SiteStore()
    self.healthHistory = healthHistoryStore.load()
    self.configurationChangeHistory = configurationHistoryStore.loadRecords()
    self.automaticConfigurationBackups = automaticConfigurationBackupStore.loadRecords()
    self.clientCustomNames = clientIdentityStore.load()
    self.sites = siteStore.loadSites()
    loadHealthNotificationState()
    if let host = Self.environmentValue("AIRPORT_UTILITY_HOST") {
      connection.host = AirportConnection.normalizedHost(host)
    }
    if let password = Self.environmentValue("AIRPORT_UTILITY_PASSWORD") {
      connection.password = password
      hasTrustedConnectionPassword = true
    }
    if let repoPath = Self.environmentValue("AIRPORT_UTILITY_REPO") {
      connection.repoPath = repoPath
    }
    mockMode = ProcessInfo.processInfo.environment["AIRPORT_UTILITY_MOCK"] == "1"
    if !mockMode, connection.password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      loadSavedPasswordForConnectionHost()
    }
    if mockMode {
      loadMockState()
    } else if liveCredentialsAvailable {
      status = "Ready to connect to \(connection.host)"
    } else {
      status = "Enter base station password to load settings."
    }
    AppLogger.shared.notice(

      "AirportAppModel initialised. Mock mode: \(mockMode).",

      category: .app

    )
  }

  func refresh() {
    normalizeConnectionHost()
    guard !isBusy else { return }
    guard mockMode || canAttemptConnection else {
      clearPreviewAfterValidationFailure()
      updateIdleConnectionStatus()
      return
    }
    if !mockMode {
      hasTrustedConnectionPassword = true
    }
    let requestHost = AirportConnection.normalizedHost(connection.host)
    runTask("Refreshing settings", requestHost: requestHost) {
      try await self.refreshSettings()
    }
  }

  func previewBaseStationName() {
    let connection = connection
    let name = baseStation.name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else {
      status = "Base Station Name cannot be empty."
      clearPreviewAfterValidationFailure()
      return
    }
    let args = AirportCommand.rawWrite(
      setting: "syNm", value: name, connection: connection, dryRun: true)
    dryRun(title: "Base Station Name", args: args, connection: connection)
  }

  func applyBaseStationName() {
    let connection = connection
    let name = baseStation.name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else {
      status = "Base Station Name cannot be empty."
      clearPreviewAfterValidationFailure()
      return
    }
    let args = appliedWriteArguments(
      AirportCommand.rawWrite(setting: "syNm", value: name, connection: connection, dryRun: false))
    apply(
      title: "Base Station Name", args: args, connection: connection,
      cleanScope: .baseStationName)
  }

  func previewAdminPassword() {
    let connection = connection
    let newPassword = baseStation.newAdminPassword.trimmingCharacters(in: .whitespacesAndNewlines)
    let verifyPassword = baseStation.verifyAdminPassword.trimmingCharacters(
      in: .whitespacesAndNewlines)
    guard !newPassword.isEmpty,
      newPassword == verifyPassword
    else {
      status = "Admin passwords do not match."
      clearPreviewAfterValidationFailure()
      return
    }
    let args = AirportCommand.rawWrite(
      setting: "syPW", value: newPassword, connection: connection, dryRun: true)
    dryRun(title: "Admin Password", args: args, connection: connection)
  }

  func applyAdminPassword() {
    let connection = connection
    let newPassword = baseStation.newAdminPassword.trimmingCharacters(in: .whitespacesAndNewlines)
    let verifyPassword = baseStation.verifyAdminPassword.trimmingCharacters(
      in: .whitespacesAndNewlines)
    guard !newPassword.isEmpty,
      newPassword == verifyPassword
    else {
      status = "Admin passwords do not match."
      clearPreviewAfterValidationFailure()
      return
    }
    let args = appliedWriteArguments(
      AirportCommand.rawWrite(
        setting: "syPW", value: newPassword, connection: connection, dryRun: false))
    apply(
      title: "Admin Password", args: args, connection: connection, cleanScope: .adminPassword,
      appliedAdminPassword: newPassword
    ) {
      self.updateConnectionPasswordAfterAdminChange(newPassword)
      self.clearAppliedAdminPasswordFieldsIfUnchanged(newPassword)
    }
  }

  func previewBaseStation() {
    let connection = connection
    guard let commands = baseStationCommands(dryRun: true, changesOnly: true) else {
      clearPreviewAfterValidationFailure()
      return
    }
    guard !commands.isEmpty else {
      preview = nil
      status = "No pending Base Station changes to preview."
      return
    }
    dryRunSequence(title: "Base Station", commands: commands, connection: connection)
  }

  func applyBaseStation() {
    let connection = connection
    guard let commands = baseStationCommands(dryRun: false, changesOnly: true) else {
      clearPreviewAfterValidationFailure()
      return
    }
    guard !commands.isEmpty else {
      preview = nil
      status = "No pending Base Station changes to apply."
      return
    }
    let newPassword = baseStation.newAdminPassword.trimmingCharacters(in: .whitespacesAndNewlines)
    applySequence(
      title: "Base Station", commands: appliedFinalCommand(commands), connection: connection,
      cleanScope: .baseStation,
      appliedAdminPassword: newPassword
    ) {
      if !newPassword.isEmpty {
        self.updateConnectionPasswordAfterAdminChange(newPassword)
        self.clearAppliedAdminPasswordFieldsIfUnchanged(newPassword)
      }
    }
  }

  func previewInternet() {
    previewFriendlySettings(
      title: "Internet",
      noChangesStatus: "No pending Internet changes to preview."
    ) {
      internetFlags(changesOnly: true)
    }
  }

  func applyInternet() {
    applyFriendlySettings(
      title: "Internet",
      noChangesStatus: "No pending Internet changes to apply.",
      cleanScope: .internet
    ) {
      internetFlags(changesOnly: true)
    }
  }

  func renewDHCPLease() {
    refresh()
  }

  func previewFriendlySettings(
    title: String,
    noChangesStatus: String,
    flags: () -> [(String, String?)]?
  ) {
    let connection = connection
    guard let flags = flags() else {
      clearPreviewAfterValidationFailure()
      return
    }
    guard !flags.isEmpty else {
      preview = nil
      status = noChangesStatus
      return
    }
    dryRun(
      title: title,
      args: AirportCommand.friendlyWrite(connection: connection, flags: flags, dryRun: true),
      connection: connection)
  }

  func applyFriendlySettings(
    title: String,
    noChangesStatus: String,
    cleanScope: CleanScope,
    completion: @escaping (AirportSettingsSnapshot) -> Void = { _ in },
    flags: () -> [(String, String?)]?
  ) {
    let connection = connection
    let appliedSnapshot = currentSnapshot
    guard let flags = flags() else {
      clearPreviewAfterValidationFailure()
      return
    }
    guard !flags.isEmpty else {
      preview = nil
      status = noChangesStatus
      return
    }
    apply(
      title: title,
      args: appliedWriteArguments(
        AirportCommand.friendlyWrite(connection: connection, flags: flags, dryRun: false)),
      connection: connection,
      cleanScope: cleanScope,
      appliedSnapshot: appliedSnapshot
    ) {
      completion(appliedSnapshot)
    }
  }

  func previewWireless() {
    previewFriendlySettings(
      title: "Wireless",
      noChangesStatus: "No pending Wireless changes to preview."
    ) {
      wirelessFlags(changesOnly: true)
    }
  }

  func applyWireless() {
    applyFriendlySettings(
      title: "Wireless",
      noChangesStatus: "No pending Wireless changes to apply.",
      cleanScope: .wireless
    ) {
      wirelessFlags(changesOnly: true)
    }
  }

  func previewNetwork() {
    previewFriendlySettings(
      title: "Network",
      noChangesStatus: "No pending Network changes to preview."
    ) {
      networkFlags(changesOnly: true)
    }
  }

  func applyNetwork() {
    applyFriendlySettings(
      title: "Network",
      noChangesStatus: "No pending Network changes to apply.",
      cleanScope: .network
    ) {
      networkFlags(changesOnly: true)
    }
  }

  func previewAirPlay() {
    guard supportsPane(.airPlay) else {
      status = "This base station does not support AirPlay."
      clearPreviewAfterValidationFailure()
      return
    }
    previewFriendlySettings(
      title: "AirPlay",
      noChangesStatus: "No pending AirPlay changes to preview."
    ) {
      airPlayFlags(changesOnly: true)
    }
  }

  func applyAirPlay() {
    guard supportsPane(.airPlay) else {
      status = "This base station does not support AirPlay."
      clearPreviewAfterValidationFailure()
      return
    }
    applyFriendlySettings(
      title: "AirPlay",
      noChangesStatus: "No pending AirPlay changes to apply.",
      cleanScope: .airPlay,
      completion: { self.persistAuxiliaryPasswordPreferences(from: $0) }
    ) {
      airPlayFlags(changesOnly: true)
    }
  }

  func applyCurrentPane() {
    switch selectedPane {
    case .baseStation:
      applyBaseStation()
    case .internet:
      applyInternet()
    case .wireless:
      applyWireless()
    case .network:
      applyNetwork()
    case .airPlay:
      applyAirPlay()
    case .disks:
      applyDiskSharing()
    case .advanced:
      applyAdvanced()
    case .firmware:
      installSelectedFirmware()
    case .diagnostics:
      return
    }
  }

  func applyPendingChanges() {
    let connection = connection
    let snapshot = currentSnapshot
    guard comparable(snapshot) != comparable(cleanSnapshot) else {
      preview = nil
      status = "No pending changes to apply."
      return
    }
    var commands: [(String, [String])] = []
    var finalCommands: [(String, [String])] = []
    var adminPassword = ""

    if comparable(snapshot.baseStation) != comparable(cleanSnapshot.baseStation)
      || comparable(snapshot.legacyDeviceOptions).baseStation
        != comparable(cleanSnapshot.legacyDeviceOptions).baseStation
    {
      guard let baseCommands = baseStationCommands(dryRun: false, changesOnly: true) else {
        clearPreviewAfterValidationFailure()
        return
      }
      for command in baseCommands {
        if command.0 == "Admin Password" {
          finalCommands.append(command)
        } else {
          commands.append(command)
        }
      }
      adminPassword = baseStation.newAdminPassword.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if comparable(snapshot.internet) != comparable(cleanSnapshot.internet) {
      guard let flags = internetFlags(changesOnly: true) else {
        clearPreviewAfterValidationFailure()
        return
      }
      if !flags.isEmpty {
        commands.append(
          (
            "Internet",
            AirportCommand.friendlyWrite(connection: connection, flags: flags, dryRun: false)
          ))
      }
    }
    if comparable(snapshot.wireless) != comparable(cleanSnapshot.wireless)
      || comparable(snapshot.legacyDeviceOptions).wireless
        != comparable(cleanSnapshot.legacyDeviceOptions).wireless
    {
      guard let flags = wirelessFlags(changesOnly: true) else {
        clearPreviewAfterValidationFailure()
        return
      }
      if !flags.isEmpty {
        commands.append(
          (
            "Wireless",
            AirportCommand.friendlyWrite(connection: connection, flags: flags, dryRun: false)
          ))
      }
    }
    if comparable(snapshot.network) != comparable(cleanSnapshot.network)
      || comparable(snapshot.legacyDeviceOptions).dhcp
        != comparable(cleanSnapshot.legacyDeviceOptions).dhcp
    {
      guard let flags = networkFlags(changesOnly: true) else {
        clearPreviewAfterValidationFailure()
        return
      }
      if !flags.isEmpty {
        commands.append(
          (
            "Network",
            AirportCommand.friendlyWrite(connection: connection, flags: flags, dryRun: false)
          ))
      }
    }
    if supportsPane(.airPlay), comparable(snapshot.airPlay) != comparable(cleanSnapshot.airPlay) {
      guard let flags = airPlayFlags(changesOnly: true) else {
        clearPreviewAfterValidationFailure()
        return
      }
      if !flags.isEmpty {
        commands.append(
          (
            "AirPlay",
            AirportCommand.friendlyWrite(connection: connection, flags: flags, dryRun: false)
          ))
      }
    }
    if supportsPane(.disks), comparable(snapshot.disks) != comparable(cleanSnapshot.disks) {
      guard let flags = diskSharingFlags(changesOnly: true) else {
        clearPreviewAfterValidationFailure()
        return
      }
      if !flags.isEmpty {
        commands.append(
          (
            "Disk Sharing",
            AirportCommand.friendlyWrite(connection: connection, flags: flags, dryRun: false)
          ))
      }
    }
    if supportsPane(.advanced),
      snapshot.advanced != cleanSnapshot.advanced
        || comparable(snapshot.legacyDeviceOptions).accessControl
          != comparable(cleanSnapshot.legacyDeviceOptions).accessControl
    {
      guard let flags = advancedFlags(changesOnly: true) else {
        clearPreviewAfterValidationFailure()
        return
      }
      if !flags.isEmpty {
        commands.append(
          (
            "Advanced",
            AirportCommand.friendlyWrite(connection: connection, flags: flags, dryRun: false)
          ))
      }
    }

    let pendingCommands = commands + finalCommands
    let commandsForApply: [(String, [String])]
    if usesLegacyFullSnapshotWrites {
      guard let combined = combinedLegacySnapshotCommand(pendingCommands, connection: connection)
      else {
        clearPreviewAfterValidationFailure()
        return
      }
      commandsForApply = [("Settings", combined)]
    } else {
      commandsForApply = pendingCommands
    }
    let orderedCommands = appliedFinalCommand(commandsForApply)
    guard !orderedCommands.isEmpty else {
      preview = nil
      status = "No pending changes to apply."
      return
    }
    guard mockMode || liveCredentialsAvailable else {
      clearPreviewAfterValidationFailure()
      updateIdleConnectionStatus()
      showConnectionDetails = true
      return
    }
    applySequence(
      title: "Settings", commands: orderedCommands, connection: connection, cleanScope: .all,
      appliedSnapshot: snapshot,
      appliedAdminPassword: adminPassword
    ) {
      if !adminPassword.isEmpty {
        self.updateConnectionPasswordAfterAdminChange(adminPassword)
        self.clearAppliedAdminPasswordFieldsIfUnchanged(adminPassword)
      }
      self.persistAuxiliaryPasswordPreferences(from: snapshot)
      self.isEditingDevice = false
      self.selectedPane = .baseStation
    }
  }

  private func combinedLegacySnapshotCommand(
    _ commands: [(String, [String])], connection: AirportConnection
  ) -> [String]? {
    var flags: [String] = []
    var values: [String: Any] = [:]

    for (_, arguments) in commands {
      guard let passwordFlag = arguments.firstIndex(of: "--password"),
        arguments.indices.contains(passwordFlag + 1)
      else {
        status = "Could not combine legacy settings into one update."
        return nil
      }
      let payloadStart = passwordFlag + 2
      if let settingFlag = arguments.firstIndex(of: "--setting"),
        arguments.indices.contains(settingFlag + 1)
      {
        let setting = arguments[settingFlag + 1]
        if let valueJSONFlag = arguments.firstIndex(of: "--value-json"),
          arguments.indices.contains(valueJSONFlag + 1),
          let data = arguments[valueJSONFlag + 1].data(using: .utf8),
          let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        {
          values[setting] = value
        } else if let valueFlag = arguments.firstIndex(of: "--value"),
          arguments.indices.contains(valueFlag + 1)
        {
          values[setting] = arguments[valueFlag + 1]
        } else {
          status = "Could not combine legacy setting \(setting) into one update."
          return nil
        }
      } else if payloadStart < arguments.count {
        flags.append(contentsOf: arguments[payloadStart...])
      }
    }

    var arguments = AirportCommand.friendlyWrite(
      connection: connection, flags: [(String, String?)](), dryRun: false)
    if !values.isEmpty {
      guard JSONSerialization.isValidJSONObject(values),
        let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]),
        let json = String(data: data, encoding: .utf8)
      else {
        status = "Could not encode the combined legacy settings update."
        return nil
      }
      arguments += ["--values-json", json]
    }
    arguments += flags
    return arguments
  }

  func previewCurrentPane() {
    switch selectedPane {
    case .baseStation:
      previewBaseStation()
    case .internet:
      previewInternet()
    case .wireless:
      previewWireless()
    case .network:
      previewNetwork()
    case .airPlay:
      previewAirPlay()
    case .disks:
      previewDiskSharing()
    case .advanced:
      previewAdvanced()
    case .firmware:
      previewSelectedFirmwareInstall()
    case .diagnostics:
      return
    }
  }

  enum CleanScope {
    case all
    case none
    case baseStation
    case baseStationName
    case adminPassword
    case internet
    case wireless
    case network
    case airPlay
    case disks
    case advanced
  }

  func markClean(_ scope: CleanScope) {
    markClean(scope, from: currentSnapshot, appliedAdminPassword: "")
  }

  func markClean(
    _ scope: CleanScope,
    from appliedSnapshot: AirportSettingsSnapshot,
    appliedAdminPassword: String
  ) {
    switch scope {
    case .all:
      cleanSnapshot = appliedSnapshot
      cleanCapabilities = capabilities
      cleanHasDetectedIPv6Support = hasDetectedIPv6Support
      cleanHasDetectedDynamicGlobalHostnameSupport = hasDetectedDynamicGlobalHostnameSupport
      cleanHasDetectedClassicWDSSupport = hasDetectedClassicWDSSupport
      cleanSnapshot.baseStation.newAdminPassword = baseStation.newAdminPassword
      cleanSnapshot.baseStation.verifyAdminPassword = baseStation.verifyAdminPassword
      clearCleanAdminPasswordIfApplied(appliedAdminPassword)
      clearAppliedAdvancedACPSettings(from: appliedSnapshot)
    case .none:
      break
    case .baseStation:
      cleanSnapshot.baseStation = appliedSnapshot.baseStation
      cleanSnapshot.legacyDeviceOptions.baseStation =
        appliedSnapshot.legacyDeviceOptions.baseStation
      cleanSnapshot.baseStation.newAdminPassword = baseStation.newAdminPassword
      cleanSnapshot.baseStation.verifyAdminPassword = baseStation.verifyAdminPassword
      clearCleanAdminPasswordIfApplied(appliedAdminPassword)
      clearAppliedAdvancedACPSettings(from: appliedSnapshot)
    case .baseStationName:
      cleanSnapshot.baseStation.name = appliedSnapshot.baseStation.name
    case .adminPassword:
      if normalized(appliedAdminPassword).isEmpty {
        cleanSnapshot.baseStation.newAdminPassword = baseStation.newAdminPassword
        cleanSnapshot.baseStation.verifyAdminPassword = baseStation.verifyAdminPassword
      } else {
        clearCleanAdminPasswordIfApplied(appliedAdminPassword)
      }
    case .internet:
      cleanSnapshot.internet = appliedSnapshot.internet
    case .wireless:
      cleanSnapshot.wireless = appliedSnapshot.wireless
      cleanSnapshot.legacyDeviceOptions.wireless =
        appliedSnapshot.legacyDeviceOptions.wireless
    case .network:
      cleanSnapshot.network = appliedSnapshot.network
      cleanSnapshot.legacyDeviceOptions.dhcp = appliedSnapshot.legacyDeviceOptions.dhcp
    case .airPlay:
      cleanSnapshot.airPlay = appliedSnapshot.airPlay
    case .disks:
      cleanSnapshot.disks = appliedSnapshot.disks
    case .advanced:
      cleanSnapshot.advanced = appliedSnapshot.advanced
      cleanSnapshot.legacyDeviceOptions.accessControl =
        appliedSnapshot.legacyDeviceOptions.accessControl
    }
  }

  private func clearCleanAdminPasswordIfApplied(_ appliedAdminPassword: String) {
    guard !normalized(appliedAdminPassword).isEmpty else { return }
    cleanSnapshot.baseStation.newAdminPassword = ""
    cleanSnapshot.baseStation.verifyAdminPassword = ""
  }

  func clearAppliedAdvancedACPSettings(from appliedSnapshot: AirportSettingsSnapshot) {
    let appliedJSON = appliedSnapshot.baseStation.advancedACPSettingsJSON
    cleanSnapshot.baseStation.advancedACPSettingsJSON = ""
    guard !normalized(appliedJSON).isEmpty else { return }
    if baseStation.advancedACPSettingsJSON == appliedJSON {
      baseStation.advancedACPSettingsJSON = ""
    }
  }

  private func clearAppliedAdminPasswordFieldsIfUnchanged(_ appliedPassword: String) {
    let appliedPassword = normalized(appliedPassword)
    guard !appliedPassword.isEmpty else { return }
    if normalized(baseStation.newAdminPassword) == appliedPassword {
      baseStation.newAdminPassword = ""
    }
    if normalized(baseStation.verifyAdminPassword) == appliedPassword {
      baseStation.verifyAdminPassword = ""
    }
  }

  func clearLoadedDeviceDetails(name: String) {
    stopWirelessClientPolling(clearClients: true)
    legacySNMPCommunity = ""
    firmwareCatalogRefreshTask?.cancel()
    firmwareCatalogRefreshTask = nil
    firmwareCompletionMonitorTask?.cancel()
    firmwareCompletionMonitorTask = nil
    firmwareUploadProgressBuffer = ""
    baseStation = BaseStationState(name: name)
    internet = InternetState()
    wireless = WirelessState()
    airPlay = AirPlayState()
    network = NetworkState()
    disks = DisksState()
    advanced = AdvancedState()
    legacyDeviceOptions = LegacyDeviceOptionsState()
    capabilities = DeviceCapabilities()
    hasDetectedIPv6Support = false
    hasDetectedDynamicGlobalHostnameSupport = false
    hasDetectedClassicWDSSupport = false
    firmware = FirmwareState()
    cleanSnapshot = currentSnapshot
    cleanCapabilities = capabilities
    cleanHasDetectedIPv6Support = hasDetectedIPv6Support
    cleanHasDetectedDynamicGlobalHostnameSupport = hasDetectedDynamicGlobalHostnameSupport
    cleanHasDetectedClassicWDSSupport = hasDetectedClassicWDSSupport
    hasLoadedSettings = false
    if !liveCredentialsAvailable {
      hasTrustedConnectionPassword = false
    }
    updateIdleConnectionStatus()
  }

  func updateIdleConnectionStatus() {
    if mockMode {
      status = "Connected to \(connection.host). Mock mode."
      return
    }
    status =
      liveCredentialsAvailable
      ? "Ready to connect to \(connection.host)"
      : "Enter base station password to load settings."
  }

  nonisolated static func uniqueNonEmptyValues(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    var unique: [String] = []
    for value in values {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
      seen.insert(trimmed)
      unique.append(trimmed)
    }
    return unique
  }

  nonisolated static func readHostInternetSettingsAsync() async -> HostInternetState {
    await HostInternetReader.readAsync()
  }

  nonisolated static func hostInternetSettings(routeOutput: String, dnsOutput: String)
    -> HostInternetState
  {
    HostInternetReader.hostInternetSettings(routeOutput: routeOutput, dnsOutput: dnsOutput)
  }

  nonisolated static func hostDNSServers(from output: String, preferredInterface: String?)
    -> String
  {
    HostInternetReader.hostDNSServers(from: output, preferredInterface: preferredInterface)
  }

  func beginBaseStationUpdate(requestHost: String) {
    let updatingDevice = selectedTopologyDevice()
    let updatingRootIndex = updatingDevice.flatMap { device in
      visibleTopologyDevices.firstIndex { $0.id == device.id }
    }
    updatingBaseStationHost = requestHost.isEmpty ? nil : requestHost
    updatingBaseStationDeviceID = selectedTopologyDeviceID
    updatingBaseStationDeviceIdentifiers = selectedTopologyDeviceIdentifiers
    if let updatingDevice {
      updatingBaseStationDisplaySnapshot = TopologyDeviceDisplaySnapshot(
        displayName: updatingDevice.displayName,
        stableIdentifiers: updatingDevice.normalizedStableIdentifiers,
        connectionHosts: updatingDevice.normalizedConnectionHosts,
        modelName: updatingDevice.modelName,
        productID: updatingDevice.productID,
        rootIndex: updatingRootIndex,
        expiresAt: nil)
    } else {
      updatingBaseStationDisplaySnapshot = nil
    }
    isDevicePopoverPresented = false
    if isEditingDevice {
      isEditingDevice = false
      selectedPane = .baseStation
    }
  }

  func clearBaseStationUpdate(requestHost: String? = nil) {
    if let requestHost, let updatingBaseStationHost,
      updatingBaseStationHost != requestHost
    {
      return
    }
    updatingBaseStationHost = nil
    updatingBaseStationDeviceID = nil
    updatingBaseStationDeviceIdentifiers = []
    updatingBaseStationDisplaySnapshot = nil
  }

  func loadMockState() {
    connection.host = "time-capsule.local"
    connection.password = "mock-password"
    rememberConnectionPassword = true
    let mockProductID = AirportMockBackend.productID(environmentValue: Self.environmentValue)
    let mockStatusText = AirportMockBackend.statusText(environmentValue: Self.environmentValue)
    baseStation = BaseStationState(
      name: "time capsule 4",
      serialNumber: "6F8412DG32D",
      version: "7.8.1",
      productID: mockProductID,
      statusText: mockStatusText,
      newAdminPassword: "password",
      verifyAdminPassword: "password",
      rememberPassword: true
    )
    internet = InternetState(
      connectUsing: .dhcp,
      ipv4Address: "192.168.4.45",
      subnetMask: "255.255.252.0",
      routerAddress: "192.168.4.1",
      dnsServers: "",
      domainName: "",
      ipv6Address: "",
      ipv6DNSServers: "",
      pppoeAccount: "",
      pppoePassword: "",
      pppoeService: "",
      pppoeConnection: "always-on",
      configureIPv6: "link-local",
      dynamicGlobalHostname: false,
      globalHostname: "",
      globalHostnameUser: "",
      globalHostnamePassword: ""
    )
    hostInternet = HostInternetState(
      connectionStatus: "Connected",
      routerAddress: "192.168.4.1",
      dnsServers: "192.168.1.1")
    wirelessScanNetworkNames = [
      "Jack's Network",
      "Studio Wi-Fi",
      "Airport Guest",
    ]
    wireless = WirelessState(
      mode: "off",
      networkName: "Off",
      security: "none",
      password: "",
      verifyPassword: "",
      regionCode: "",
      hiddenNetwork: false,
      radioMode: "",
      radioChannel: ""
    )
    airPlay = AirPlayState(
      enabled: false,
      speakerName: "time capsule 4",
      speakerPassword: "",
      verifySpeakerPassword: "",
      rememberPassword: true,
      overWAN: false
    )
    network = NetworkState(
      lanIPAddress: "192.168.4.45",
      routerMode: .bridge,
      dhcpRangeStart: "10.0.1.2",
      dhcpRangeEnd: "10.0.1.200",
      natPMP: true,
      dhcpLease: "1",
      dhcpLeaseUnit: "days",
      defaultHost: ""
    )
    disks = DisksState(
      fileSharing: true,
      secureSharedDisks: "device-password",
      guestAccess: "not-allowed",
      shareOverWAN: false,
      diskPassword: "",
      verifyDiskPassword: "",
      rememberPassword: true,
      windowsWorkgroup: "WORKGROUP",
      winsServer: "",
      inventory: [
        DiskRecord(
          deviceName: "dk2",
          name: "Jack's Time Capsule Home",
          format: "HFS",
          uuid: "adabbc6e09e0579081f8444e687f35b9",
          size: 1_000_000_000_000,
          sizeFree: 497_850_000_000,
          builtIn: true
        ),
        DiskRecord(
          deviceName: "dk3",
          name: "USB Archive Disk",
          format: "HFS",
          uuid: "22222222222222222222222222222222",
          size: 2_000_000_000_000,
          sizeFree: 1_500_000_000_000,
          builtIn: false
        ),
      ],
      rawInventory: AirportMockBackend.maStJSON,
      didLoadInventory: true
    )
    capabilities = DeviceCapabilities.forProductID(mockProductID)
    capabilities.supportsIPv6 = true
    capabilities.supportsDynamicGlobalHostname = true
    hasDetectedIPv6Support = true
    hasDetectedDynamicGlobalHostnameSupport = true
    if !capabilities.supportsAirPlay {
      airPlay = AirPlayState()
    }
    if !capabilities.supportsDisks {
      disks = DisksState()
    }
    firmware = FirmwareState()
    firmware.currentVersion = baseStation.version
    firmware.productID = mockProductID
    loadMockFirmwareImagesIfNeeded(force: true)
    status = "Connected to \(connection.host). Mock mode."
    showConnectionDetails = false
    logs = ["Mock backend enabled with fixture Time Capsule settings."]
    discoveredDevices = AirportMockBackend.discoveredDevices(
      statusText: mockStatusText,
      environmentValue: Self.environmentValue)
    markClean()
    hasLoadedSettings = true
  }
}
