// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

import Foundation

struct DiagnosticsSnapshot: Codable, Equatable, Sendable {
  struct AppMetadata: Codable, Equatable, Sendable {
    let appVersion: String
    let build: String
    let operatingSystem: String
    let architecture: String
    let backendAvailable: Bool
  }

  struct NetworkSummary: Codable, Equatable, Sendable {
    let connectionStatus: String
    let baseStationName: String
    let model: String
    let firmware: String
    let address: String
    let routerMode: String
    let internetStatus: String
    let upstreamRouter: String
    let dnsServers: String
    let wirelessNetwork: String
    let wirelessMode: String
    let wirelessSecurity: String
    let wirelessClientCount: Int
    let discoveryStarted: Bool
  }

  struct HealthSummary: Codable, Equatable, Sendable {
    let diskCondition: String
    let diskDetail: String
    let smartStatus: String
    let totalBytes: Int64?
    let freeBytes: Int64?
    let smbAvailability: String
    let smbDetail: String
    let backupCount: Int
    let staleBackupCount: Int
    let backupDetail: String
    let currentWarnings: [String]
  }

  let generatedAt: Date
  let metadata: AppMetadata
  let network: NetworkSummary
  let health: HealthSummary
  let connectivity: NetworkDiagnosticsState?
  let wifiCongestion: WiFiCongestionState?
  let compatibility: HardwareCompatibilityAssessment?
}

struct DiagnosticsSupportBundle: Codable, Equatable, Sendable {
  let formatVersion: Int
  let snapshot: DiagnosticsSnapshot
  let logs: [LogEntry]
}

enum DiagnosticsBundleBuilder {
  nonisolated static func build(
    snapshot: DiagnosticsSnapshot,
    logs: [LogEntry]
  ) throws -> String {
    let sanitizedLogs = logs.map {
      LogEntry(
        id: $0.id, timestamp: $0.timestamp, level: $0.level, category: $0.category,
        message: redactForSupport($0.message))
    }
    let bundle = DiagnosticsSupportBundle(
      formatVersion: 1, snapshot: sanitized(snapshot), logs: sanitizedLogs)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(bundle)
    guard let text = String(data: data, encoding: .utf8) else {
      throw CocoaError(.fileWriteInapplicableStringEncoding)
    }
    return text
  }

  nonisolated static func redactForSupport(_ value: String) -> String {
    var result = LogRedactor.redact(value)
    let homePath = FileManager.default.homeDirectoryForCurrentUser.path
    if !homePath.isEmpty {
      result = result.replacingOccurrences(of: homePath, with: "~")
    }
    if let hardwareAddress = try? NSRegularExpression(
      pattern: #"(?i)\b(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}\b"#)
    {
      result = hardwareAddress.stringByReplacingMatches(
        in: result, range: NSRange(result.startIndex..., in: result),
        withTemplate: "<hardware-address-redacted>")
    }
    if let backupPath = try? NSRegularExpression(
      pattern: #"(?i)/Volumes/[^\r\n"]+?\.sparsebundle"#)
    {
      result = backupPath.stringByReplacingMatches(
        in: result, range: NSRange(result.startIndex..., in: result),
        withTemplate: "<backup-path-redacted>")
    }
    return result
  }

  private nonisolated static func sanitized(_ snapshot: DiagnosticsSnapshot)
    -> DiagnosticsSnapshot
  {
    let redact = redactForSupport
    return DiagnosticsSnapshot(
      generatedAt: snapshot.generatedAt,
      metadata: snapshot.metadata,
      network: DiagnosticsSnapshot.NetworkSummary(
        connectionStatus: redact(snapshot.network.connectionStatus),
        baseStationName: redact(snapshot.network.baseStationName),
        model: redact(snapshot.network.model),
        firmware: redact(snapshot.network.firmware),
        address: redact(snapshot.network.address),
        routerMode: redact(snapshot.network.routerMode),
        internetStatus: redact(snapshot.network.internetStatus),
        upstreamRouter: redact(snapshot.network.upstreamRouter),
        dnsServers: redact(snapshot.network.dnsServers),
        wirelessNetwork: redact(snapshot.network.wirelessNetwork),
        wirelessMode: redact(snapshot.network.wirelessMode),
        wirelessSecurity: redact(snapshot.network.wirelessSecurity),
        wirelessClientCount: snapshot.network.wirelessClientCount,
        discoveryStarted: snapshot.network.discoveryStarted),
      health: DiagnosticsSnapshot.HealthSummary(
        diskCondition: redact(snapshot.health.diskCondition),
        diskDetail: redact(snapshot.health.diskDetail),
        smartStatus: redact(snapshot.health.smartStatus),
        totalBytes: snapshot.health.totalBytes,
        freeBytes: snapshot.health.freeBytes,
        smbAvailability: redact(snapshot.health.smbAvailability),
        smbDetail: redact(snapshot.health.smbDetail),
        backupCount: snapshot.health.backupCount,
        staleBackupCount: snapshot.health.staleBackupCount,
        backupDetail: redact(snapshot.health.backupDetail),
        currentWarnings: snapshot.health.currentWarnings.map(redact)),
      connectivity: snapshot.connectivity,
      wifiCongestion: snapshot.wifiCongestion,
      compatibility: snapshot.compatibility)
  }
}

@MainActor
extension AirportAppModel {
  func diagnosticsSnapshot() -> DiagnosticsSnapshot {
    let bundle = Bundle.main
    let appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "development"
    let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development"
    let backendURL = URL(fileURLWithPath: connection.repoPath)
      .appendingPathComponent("backend/airport_backend.py")
    let selectedDevice = selectedTopologyDevice()
    let networkSummary = DashboardNetworkSummary(
      internet: internet, hostInternet: hostInternet, network: network, wireless: wireless,
      statusText: selectedDeviceStatusText(), statusDetails: selectedDeviceStatusDetails())
    return DiagnosticsSnapshot(
      generatedAt: Date(),
      metadata: DiagnosticsSnapshot.AppMetadata(
        appVersion: appVersion,
        build: build,
        operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
        architecture: Self.diagnosticsArchitecture,
        backendAvailable: FileManager.default.fileExists(atPath: backendURL.path)),
      network: DiagnosticsSnapshot.NetworkSummary(
        connectionStatus: status,
        baseStationName: baseStation.name,
        model: selectedDevice?.displayModelName ?? "AirPort Base Station",
        firmware: baseStation.version,
        address: AirportConnection.normalizedHost(connection.host),
        routerMode: network.routerMode.label,
        internetStatus: networkSummary.internetStatus,
        upstreamRouter: networkSummary.upstreamRouter,
        dnsServers: networkSummary.dnsServers,
        wirelessNetwork: wireless.networkName,
        wirelessMode: networkSummary.wirelessMode,
        wirelessSecurity: networkSummary.wirelessSecurity,
        wirelessClientCount: wirelessClients.count,
        discoveryStarted: hasStartedBonjourDiscovery),
      health: DiagnosticsSnapshot.HealthSummary(
        diskCondition: storageHealth.diskCondition.rawValue,
        diskDetail: storageHealth.diskDetail,
        smartStatus: storageHealth.smartStatus,
        totalBytes: storageHealth.totalBytes,
        freeBytes: storageHealth.freeBytes,
        smbAvailability: storageHealth.smbAvailability.rawValue,
        smbDetail: storageHealth.smbDetail,
        backupCount: timeMachineBackups.backups.count,
        staleBackupCount: timeMachineBackups.backups.filter { $0.condition == .stale }.count,
        backupDetail: timeMachineBackups.detail,
        currentWarnings: networkSummary.warnings),
      connectivity: networkDiagnostics,
      wifiCongestion: wifiCongestion,
      compatibility: hardwareCompatibilityAssessment())
  }

  private static var diagnosticsArchitecture: String {
    #if arch(arm64)
      "arm64"
    #elseif arch(x86_64)
      "x86_64"
    #else
      "unknown"
    #endif
  }
}
