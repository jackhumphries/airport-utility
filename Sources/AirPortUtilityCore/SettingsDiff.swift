// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

import Foundation

struct SettingsDifference: Identifiable, Equatable {
  var id: String { path }
  var path: String
  var sectionLabel: String
  var fieldLabel: String
  var before: String
  var after: String
}

struct SettingsComparison: Identifiable, Equatable {
  let id = UUID()
  var beforeLabel: String
  var afterLabel: String
  var differences: [SettingsDifference]
}

/// Identifies one entry from either Configuration History or Automatic
/// Backups, so the two stores can be referenced interchangeably when
/// comparing two arbitrary entries to each other.
struct HistoryEntryReference: Identifiable, Equatable {
  var record: ConfigurationChangeRecord
  var isAutomaticBackup: Bool
  var id: UUID { record.id }
}

enum SettingsDiff {
  /// Field-level differences between two snapshots, secrets excluded from
  /// both sides identically first so a redacted stored value never appears
  /// to "differ" from a real current one.
  static func differences(
    from storedSnapshot: AirportSettingsSnapshot,
    to currentSnapshot: AirportSettingsSnapshot
  ) -> [SettingsDifference] {
    guard let before = try? ConfigurationHistoryStore.omittingSensitiveValues(from: storedSnapshot),
      let after = try? ConfigurationHistoryStore.omittingSensitiveValues(from: currentSnapshot)
    else { return [] }
    let encoder = JSONEncoder()
    guard let beforeData = try? encoder.encode(before),
      let afterData = try? encoder.encode(after),
      let beforeObject = try? JSONSerialization.jsonObject(with: beforeData) as? [String: Any],
      let afterObject = try? JSONSerialization.jsonObject(with: afterData) as? [String: Any]
    else { return [] }
    var results: [SettingsDifference] = []
    walk(beforeObject, afterObject, path: [], into: &results)
    return results.sorted { $0.path < $1.path }
  }

  private static func walk(_ before: Any, _ after: Any, path: [String], into results: inout [SettingsDifference]) {
    if let beforeDict = before as? [String: Any], let afterDict = after as? [String: Any] {
      for key in Set(beforeDict.keys).union(afterDict.keys).sorted() {
        walk(beforeDict[key] ?? NSNull(), afterDict[key] ?? NSNull(), path: path + [key], into: &results)
      }
      return
    }
    let beforeText = stringValue(before)
    let afterText = stringValue(after)
    guard beforeText != afterText, !path.isEmpty else { return }
    let sectionKey = path[0]
    let fieldPath = path.dropFirst()
    let fieldLabel =
      fieldPath.isEmpty
      ? humanizedKey(sectionKey)
      : fieldPath.map(humanizedKey).joined(separator: " > ")
    results.append(
      SettingsDifference(
        path: path.joined(separator: "."),
        sectionLabel: sectionLabel(for: sectionKey),
        fieldLabel: fieldLabel,
        before: beforeText.isEmpty ? "(empty)" : beforeText,
        after: afterText.isEmpty ? "(empty)" : afterText))
  }

  private static func stringValue(_ value: Any) -> String {
    if value is NSNull { return "" }
    if let string = value as? String { return string }
    if let number = value as? NSNumber {
      // NSNumber from JSONSerialization doesn't distinguish Bool from 0/1
      // without checking the objCType, but Codable bools decode through
      // JSONSerialization as actual Bool-typed NSNumbers we can detect here.
      if CFGetTypeID(number) == CFBooleanGetTypeID() {
        return number.boolValue ? "true" : "false"
      }
      return number.stringValue
    }
    if let array = value as? [Any] {
      return "[" + array.map(stringValue).joined(separator: ", ") + "]"
    }
    return String(describing: value)
  }

  private static func sectionLabel(for key: String) -> String {
    switch key {
    case "baseStation": "Base Station"
    case "internet": "Internet"
    case "wireless": "Wireless"
    case "network": "Network"
    case "airPlay": "AirPlay"
    case "disks": "Disks"
    case "advanced": "Advanced"
    case "legacyDeviceOptions": "Legacy Device Options"
    default: humanizedKey(key)
    }
  }

  private static func humanizedKey(_ key: String) -> String {
    guard let first = key.first else { return key }
    var result = String(first).uppercased()
    for character in key.dropFirst() {
      if character.isUppercase {
        result.append(" ")
      }
      result.append(character)
    }
    return result
  }
}

@MainActor
extension AirportAppModel {
  func compareToCurrentSettings(_ record: ConfigurationChangeRecord) {
    compareToCurrentSettings(HistoryEntryReference(record: record, isAutomaticBackup: false))
  }

  func compareToCurrentSettings(fromAutomaticBackup record: ConfigurationChangeRecord) {
    compareToCurrentSettings(HistoryEntryReference(record: record, isAutomaticBackup: true))
  }

  func compareToCurrentSettings(_ entry: HistoryEntryReference) {
    do {
      let stored = try historySnapshot(for: entry)
      let differences = SettingsDiff.differences(from: stored, to: cleanSnapshot)
      settingsComparison = SettingsComparison(
        beforeLabel: historyEntryLabel(entry), afterLabel: "Current", differences: differences)
    } catch {
      status = "Could not load the snapshot for comparison: \(error.localizedDescription)"
    }
  }

  /// Compares two arbitrary Configuration History/Automatic Backup entries
  /// to each other, rather than either against the current live settings.
  func compareEntries(_ first: HistoryEntryReference, _ second: HistoryEntryReference) {
    do {
      let firstSnapshot = try historySnapshot(for: first)
      let secondSnapshot = try historySnapshot(for: second)
      let differences = SettingsDiff.differences(from: firstSnapshot, to: secondSnapshot)
      settingsComparison = SettingsComparison(
        beforeLabel: historyEntryLabel(first), afterLabel: historyEntryLabel(second),
        differences: differences)
    } catch {
      status = "Could not load a snapshot for comparison: \(error.localizedDescription)"
    }
  }

  private func historySnapshot(for entry: HistoryEntryReference) throws -> AirportSettingsSnapshot {
    let store = entry.isAutomaticBackup ? automaticConfigurationBackupStore : configurationHistoryStore
    return try store.loadSnapshot(for: entry.record)
  }

  private func historyEntryLabel(_ entry: HistoryEntryReference) -> String {
    let title = entry.isAutomaticBackup ? "Automatic backup" : entry.record.title
    return "\(title) (\(entry.record.date.formatted(date: .abbreviated, time: .shortened)))"
  }
}
