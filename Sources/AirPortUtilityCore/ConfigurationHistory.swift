// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

import Foundation

enum ConfigurationChangeStatus: String, Codable, Sendable {
  case prepared, applied, verifiedReachable, verifiedExpected, writeFailed
  case verificationMismatch, verificationFailed

  var userFacingDescription: String {
    switch self {
    case .prepared: "Snapshot saved"
    case .applied: "Applied; awaiting verification"
    case .verifiedReachable: "Applied; AirPort reachable"
    case .verifiedExpected: "Applied and verified"
    case .writeFailed: "Write failed"
    case .verificationMismatch: "Applied; returned settings differ"
    case .verificationFailed: "Applied; reachability not confirmed"
    }
  }
}

struct ConfigurationChangeRecord: Codable, Equatable, Sendable, Identifiable {
  let id: UUID
  let date: Date
  let title: String
  let host: String
  var status: ConfigurationChangeStatus
  let snapshotFileName: String
  let omittedSensitiveValues: Bool
}

final class ConfigurationHistoryStore: @unchecked Sendable {
  private let directory: URL
  private let fileManager: FileManager
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder
  private let maxRecords: Int

  init(
    directory: URL? = nil, maxRecords: Int = 50, fileManager: FileManager = .default
  ) {
    self.fileManager = fileManager
    self.directory = directory ?? Self.defaultDirectory()
    self.maxRecords = maxRecords
    encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
  }

  func loadRecords() -> [ConfigurationChangeRecord] {
    guard let data = try? Data(contentsOf: indexURL),
      let records = try? decoder.decode([ConfigurationChangeRecord].self, from: data)
    else { return [] }
    return records.sorted { $0.date > $1.date }
  }

  func prepare(title: String, host: String, snapshot: AirportSettingsSnapshot) throws
    -> ConfigurationChangeRecord
  {
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let id = UUID()
    let fileName = "\(id.uuidString).json"
    let data = try Self.sanitizedSnapshotData(snapshot, encoder: encoder)
    try data.write(to: directory.appendingPathComponent(fileName), options: [.atomic])
    let record = ConfigurationChangeRecord(
      id: id, date: Date(), title: title, host: host, status: .prepared,
      snapshotFileName: fileName, omittedSensitiveValues: true)
    var records = loadRecords()
    records.insert(record, at: 0)
    records = Array(records.prefix(maxRecords))
    try save(records)
    removeUnreferencedSnapshots(records: records)
    return record
  }

  func update(id: UUID, status: ConfigurationChangeStatus) throws
    -> [ConfigurationChangeRecord]
  {
    var records = loadRecords()
    guard let index = records.firstIndex(where: { $0.id == id }) else { return records }
    records[index].status = status
    try save(records)
    return records
  }

  func loadSnapshot(for record: ConfigurationChangeRecord) throws -> AirportSettingsSnapshot {
    let data = try Data(contentsOf: directory.appendingPathComponent(record.snapshotFileName))
    return try decoder.decode(AirportSettingsSnapshot.self, from: data)
  }

  static func mergingSensitiveValues(
    into snapshot: AirportSettingsSnapshot, from current: AirportSettingsSnapshot
  ) throws -> AirportSettingsSnapshot {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let snapshotObject = try JSONSerialization.jsonObject(with: encoder.encode(snapshot))
    let currentObject = try JSONSerialization.jsonObject(with: encoder.encode(current))
    let merged = mergeSensitive(snapshotObject, current: currentObject, key: "")
    return try decoder.decode(
      AirportSettingsSnapshot.self, from: JSONSerialization.data(withJSONObject: merged))
  }

  static func omittingSensitiveValues(from snapshot: AirportSettingsSnapshot) throws
    -> AirportSettingsSnapshot
  {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    return try decoder.decode(
      AirportSettingsSnapshot.self,
      from: sanitizedSnapshotData(snapshot, encoder: encoder))
  }

  private static func sanitizedSnapshotData(
    _ snapshot: AirportSettingsSnapshot, encoder: JSONEncoder
  ) throws -> Data {
    let object = try JSONSerialization.jsonObject(with: encoder.encode(snapshot))
    let sanitized = sanitize(object, key: "")
    return try JSONSerialization.data(withJSONObject: sanitized, options: [.prettyPrinted, .sortedKeys])
  }

  private static func isSensitive(_ key: String) -> Bool {
    let key = key.lowercased()
    return key.contains("password") || key.contains("secret")
      || key == "advancedacpsettingsjson"
  }

  private static func sanitize(_ value: Any, key: String) -> Any {
    if isSensitive(key) {
      if value is NSNull { return NSNull() }
      if value is String { return "" }
    }
    if let dictionary = value as? [String: Any] {
      return Dictionary(uniqueKeysWithValues: dictionary.map { childKey, child in
        (childKey, sanitize(child, key: childKey))
      })
    }
    if let array = value as? [Any] { return array.map { sanitize($0, key: key) } }
    return value
  }

  private static func mergeSensitive(_ value: Any, current: Any, key: String) -> Any {
    if isSensitive(key), value is String || value is NSNull { return current }
    if let dictionary = value as? [String: Any], let current = current as? [String: Any] {
      return Dictionary(uniqueKeysWithValues: dictionary.map { childKey, child in
        (
          childKey,
          mergeSensitive(child, current: current[childKey] ?? child, key: childKey)
        )
      })
    }
    if let array = value as? [Any], let current = current as? [Any] {
      return array.enumerated().map { index, child in
        mergeSensitive(child, current: index < current.count ? current[index] : child, key: key)
      }
    }
    return value
  }

  private var indexURL: URL { directory.appendingPathComponent("history.json") }

  nonisolated static func defaultDirectory() -> URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("AirPort Utility Powerhouse/Configuration History", isDirectory: true)
  }

  private func save(_ records: [ConfigurationChangeRecord]) throws {
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    try encoder.encode(records).write(to: indexURL, options: [.atomic])
  }

  private func removeUnreferencedSnapshots(records: [ConfigurationChangeRecord]) {
    let retained = Set(records.map(\.snapshotFileName)).union(["history.json"])
    guard let files = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return }
    for file in files where !retained.contains(file) {
      try? fileManager.removeItem(at: directory.appendingPathComponent(file))
    }
  }
}

@MainActor
extension AirportAppModel {
  func prepareConfigurationChange(title: String, host: String) -> UUID? {
    do {
      let record = try configurationHistoryStore.prepare(
        title: title, host: host, snapshot: cleanSnapshot)
      configurationChangeHistory = configurationHistoryStore.loadRecords()
      appendLog("Saved credential-free pre-change snapshot for \(title).")
      return record.id
    } catch {
      status = "Could not save a pre-change snapshot; no settings were changed."
      appendLog("Configuration apply blocked because its pre-change snapshot failed: \(error.localizedDescription)")
      return nil
    }
  }

  func updateConfigurationChange(_ id: UUID?, status: ConfigurationChangeStatus) {
    guard let id else { return }
    do {
      configurationChangeHistory = try configurationHistoryStore.update(id: id, status: status)
    } catch {
      appendLog("Could not update configuration history: \(error.localizedDescription)")
      return
    }
    guard let record = configurationChangeHistory.first(where: { $0.id == id }) else { return }
    switch record.status {
    case .writeFailed:
      recoveryGuidance = RecoveryGuidance(
        reason: .configurationWriteFailed,
        host: record.host,
        deviceName: postApplyDeviceNameForStatus,
        date: Date(),
        detail: "\(record.title) - \(record.status.userFacingDescription).")
    case .verificationMismatch, .verificationFailed:
      recoveryGuidance = RecoveryGuidance(
        reason: .configurationVerificationFailed,
        host: record.host,
        deviceName: postApplyDeviceNameForStatus,
        date: Date(),
        detail: "\(record.title) - \(record.status.userFacingDescription).")
    case .verifiedReachable, .verifiedExpected:
      clearRecoveryGuidance(forHost: record.host)
    case .prepared, .applied:
      break
    }
  }

  func prepareRollback(_ record: ConfigurationChangeRecord) {
    prepareRollback(record, from: configurationHistoryStore)
  }

  func prepareRollback(fromAutomaticBackup record: ConfigurationChangeRecord) {
    prepareRollback(record, from: automaticConfigurationBackupStore)
  }

  private func prepareRollback(
    _ record: ConfigurationChangeRecord, from store: ConfigurationHistoryStore
  ) {
    let currentHost = AirportConnection.normalizedHost(connection.host)
    guard currentHost == AirportConnection.normalizedHost(record.host) else {
      status = "Connect to \(record.host) before preparing this rollback."
      return
    }
    do {
      let stored = try store.loadSnapshot(for: record)
      let restored = try ConfigurationHistoryStore.mergingSensitiveValues(
        into: stored, from: cleanSnapshot)
      restore(
        snapshot: restored,
        capabilities: capabilities,
        hasDetectedIPv6Support: hasDetectedIPv6Support,
        hasDetectedDynamicGlobalHostnameSupport: hasDetectedDynamicGlobalHostnameSupport,
        hasDetectedClassicWDSSupport: hasDetectedClassicWDSSupport)
      beginEditing()
      status = "Rollback snapshot loaded for review. Preview changes before applying."
      appendLog("Loaded credential-free configuration snapshot for reviewed rollback.")
    } catch {
      status = "Could not load the rollback snapshot: \(error.localizedDescription)"
    }
  }
}
