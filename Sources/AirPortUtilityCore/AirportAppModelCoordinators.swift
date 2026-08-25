import Foundation

@MainActor
final class ConnectionSession {
  var hasTrustedConnectionPassword = false
  var cachedPasswordsByAccount: [String: CachedConnectionPassword] = [:]
}

@MainActor
final class TopologyStore {
  var selectedDeviceID: String?
  var startupConnectionTask: Task<Void, Never>?
  var hasAttemptedStartupConnection = false
  var hasManualTopologySelection = false
  var startupDiscoveryDebounceNanoseconds: UInt64 = 750_000_000
  var updatingBaseStationHost: String?
  var updatingBaseStationDeviceID: String?
  var selectedDeviceIdentifiers: [String] = []
  var connectedDeviceIdentifiers: [String] = []
  var connectedDeviceHost = ""
  var updatingDeviceIdentifiers: [String] = []
  var updatingDisplaySnapshot: TopologyDeviceDisplaySnapshot?
  var displaySnapshotsByName: [String: TopologyDeviceDisplaySnapshot] = [:]
  var displaySnapshotsByIdentifier: [String: TopologyDeviceDisplaySnapshot] = [:]
  var displaySnapshotsByHost: [String: TopologyDeviceDisplaySnapshot] = [:]
  var firmwareBadgeSnapshotsByIdentifier: [String: FirmwareBadgeSnapshot] = [:]
  var pendingConnectionHost: String?
  var restartTrackers: [UUID: BaseStationRestartTracker] = [:]
  var restartTimeoutTasks: [UUID: Task<Void, Never>] = [:]
  var restartRecoveryTasks: [UUID: Task<Void, Never>] = [:]
  var restartTimeoutNanoseconds: UInt64 = 180_000_000_000
  var restartPollIntervalNanoseconds: UInt64 = 1_000_000_000
  var restartProbeTimeout: TimeInterval = 3
  var restartProbeOverride:
    (@MainActor (AirportConnection, Bool, Bool) async -> Bool)?
  var restartStatusTrackerID: UUID?
  var wirelessClientPollTask: Task<Void, Never>?
  var wirelessClientPollGeneration = UUID()
  var wirelessClientPollIntervalNanoseconds: UInt64 = 2_000_000_000
  var wirelessClientIdentityDiscoveryInterval: TimeInterval = 300
  var wirelessClientIdentityDiscoveryHost = ""
  var lastWirelessClientIdentityDiscoveryDate: Date?
  var wirelessClientFetchOverride:
    (@MainActor (AirportConnection, Bool, String) async throws -> [WirelessClient])?
  var legacySNMPCommunity = ""
  var lastWirelessClientError = ""
}

@MainActor
final class FirmwareCoordinator {
  var downloadService = FirmwareDownloadService()
  var installVerificationAttempts = 72
  var installVerificationDelayNanoseconds: UInt64 = 5_000_000_000
  var catalogRefreshTask: Task<Void, Never>?
  var completionMonitorTask: Task<Void, Never>?
  var uploadProgressBuffer = ""
}

@MainActor
final class ConfigurationSession {
  var cleanSnapshot = AirportSettingsSnapshot()
  var cleanCapabilities = DeviceCapabilities()
  var cleanHasDetectedIPv6Support = false
  var cleanHasDetectedDynamicGlobalHostnameSupport = false
  var cleanHasDetectedClassicWDSSupport = false
  var archiveCompletionMonitorTask: Task<Void, Never>?
}
