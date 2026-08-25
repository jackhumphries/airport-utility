// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

import Foundation

struct HealthHistorySample: Codable, Identifiable, Equatable, Sendable {
  let id: UUID
  let date: Date
  let host: String
  let freeBytes: Int64?
  let totalBytes: Int64?
  let diskCondition: StorageDiskCondition
  let smbAvailability: StorageServiceAvailability
  let backupCount: Int
  let staleBackupCount: Int
  let backupAllocatedBytes: Int64?
  let recentlyActiveBackupCount: Int?
  let wirelessClientCount: Int
  let weakSignalClientCount: Int
  let warningCount: Int
}

struct HealthHistoryArchive: Codable, Equatable, Sendable {
  var version = 1
  var samples: [HealthHistorySample]
}

enum HealthHistoryRetention {
  static let samplingInterval: TimeInterval = 15 * 60
  static let maximumAge: TimeInterval = 90 * 24 * 60 * 60
  static let maximumSamples = 2_000

  static func adding(
    _ sample: HealthHistorySample,
    to existing: [HealthHistorySample],
    now: Date
  ) -> [HealthHistorySample] {
    let cutoff = now.addingTimeInterval(-maximumAge)
    var retained = existing.filter { $0.date >= cutoff }
    if let index = retained.lastIndex(where: { $0.host == sample.host }),
      sample.date.timeIntervalSince(retained[index].date) < samplingInterval
    {
      retained[index] = sample
    } else {
      retained.append(sample)
    }
    retained.sort { $0.date < $1.date }
    return Array(retained.suffix(maximumSamples))
  }
}

@MainActor
final class HealthHistoryStore {
  private let fileURL: URL

  init(fileURL: URL = HealthHistoryStore.defaultFileURL()) {
    self.fileURL = fileURL
  }

  func load() -> [HealthHistorySample] {
    guard let data = try? Data(contentsOf: fileURL) else { return [] }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return (try? decoder.decode(HealthHistoryArchive.self, from: data))?.samples ?? []
  }

  func save(_ samples: [HealthHistorySample]) {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(HealthHistoryArchive(samples: samples)) else { return }
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true)
      try data.write(to: fileURL, options: .atomic)
    } catch {
      AppLogger.shared.error("Could not save health history: \(error.localizedDescription)", category: .app)
    }
  }

  func clear() {
    try? FileManager.default.removeItem(at: fileURL)
  }

  nonisolated static func defaultFileURL() -> URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("AirPort Utility Powerhouse", isDirectory: true)
      .appendingPathComponent("Health", isDirectory: true)
      .appendingPathComponent("health-history.json")
  }
}

@MainActor
extension AirportAppModel {
  func recordHealthHistorySample(at date: Date = Date()) {
    guard !mockMode else { return }
    let host = AirportConnection.normalizedHost(connection.host)
    guard !host.isEmpty, hasLoadedSettings else { return }
    let clients = wirelessClients
    let weakClients = clients.filter { client in
      guard let rssi = client.rssi else { return false }
      return (rssi > 0 ? rssi - 100 : rssi) < -82
    }.count
    let warnings = DashboardNetworkSummary(
      internet: internet, hostInternet: hostInternet, network: network, wireless: wireless,
      statusText: selectedDeviceStatusText(), statusDetails: selectedDeviceStatusDetails()
    ).warnings.count
    let sample = HealthHistorySample(
      id: UUID(), date: date, host: host,
      freeBytes: storageHealth.freeBytes, totalBytes: storageHealth.totalBytes,
      diskCondition: storageHealth.diskCondition,
      smbAvailability: storageHealth.smbAvailability,
      backupCount: timeMachineBackups.backups.count,
      staleBackupCount: timeMachineBackups.backups.filter { $0.condition == .stale }.count,
      backupAllocatedBytes: TimeMachineBackupAssessment.totalAllocatedBytes(
        timeMachineBackups.backups),
      recentlyActiveBackupCount: timeMachineBackups.backups.filter {
        $0.condition == .current
      }.count,
      wirelessClientCount: clients.count, weakSignalClientCount: weakClients,
      warningCount: warnings)
    healthHistory = HealthHistoryRetention.adding(sample, to: healthHistory, now: date)
    healthHistoryStore.save(healthHistory)
  }

  func clearHealthHistory() {
    healthHistory = []
    healthHistoryStore.clear()
    appendLog("Health history cleared.")
  }
}
