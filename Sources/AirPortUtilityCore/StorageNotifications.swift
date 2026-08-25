// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

import Foundation
import UserNotifications

struct HealthNotificationPreferences: Codable, Equatable, Sendable {
  var smartStatus = false
  var lowDiskSpace = false
  var smbOutage = false
  var staleBackups = false

  var hasEnabledAlerts: Bool {
    smartStatus || lowDiskSpace || smbOutage || staleBackups
  }
}

enum HealthAlertKind: String, Codable, Sendable {
  case smartStatus
  case lowDiskSpace
  case smbOutage
  case staleBackup
}

struct HealthAlertEvent: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let date: Date
  let kind: HealthAlertKind
  let title: String
  let detail: String
  let host: String
}

public enum HealthNotificationCenter {
  public nonisolated static var isAvailableForCurrentProcess: Bool {
    Bundle.main.bundleURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame
      && Bundle.main.bundleIdentifier != nil
  }

  nonisolated static func deliver(_ event: HealthAlertEvent) async -> Bool {
    guard isAvailableForCurrentProcess else { return false }
    let center = UNUserNotificationCenter.current()
    do {
      let settings = await center.notificationSettings()
      if settings.authorizationStatus == .notDetermined {
        guard try await center.requestAuthorization(options: [.alert, .sound]) else {
          return false
        }
      } else if settings.authorizationStatus != .authorized
        && settings.authorizationStatus != .provisional
      {
        return false
      }
      let content = UNMutableNotificationContent()
      content.title = event.title
      content.body = event.detail
      content.sound = .default
      try await center.add(
        UNNotificationRequest(
          identifier: "airport-health-\(event.id.uuidString)",
          content: content,
          trigger: nil))
      return true
    } catch {
      return false
    }
  }
}

struct HealthAlertCandidate: Equatable, Sendable {
  let key: String
  let signature: String
  let kind: HealthAlertKind
  let title: String
  let detail: String
}

enum HealthAlertAssessment {
  private static let lowFreeFraction = 0.10
  private static let lowFreeBytes: Int64 = 20 * 1_024 * 1_024 * 1_024

  nonisolated static func candidates(
    host: String,
    storage: StorageHealthState,
    backups: TimeMachineBackupState,
    preferences: HealthNotificationPreferences
  ) -> [HealthAlertCandidate] {
    var alerts: [HealthAlertCandidate] = []
    let hostKey = AirportConnection.normalizedHost(host)
    let smart = storage.smartStatus.trimmingCharacters(in: .whitespacesAndNewlines)
    if preferences.smartStatus, !smart.isEmpty,
      smart.caseInsensitiveCompare("verified") != .orderedSame
    {
      alerts.append(HealthAlertCandidate(
        key: "\(hostKey):smart", signature: smart.lowercased(), kind: .smartStatus,
        title: "Time Capsule disk needs attention",
        detail: "SMART status: \(smart)"))
    }
    if preferences.lowDiskSpace, let total = storage.totalBytes, let free = storage.freeBytes,
      total > 0,
      free < min(lowFreeBytes, Int64(Double(total) * lowFreeFraction))
    {
      alerts.append(HealthAlertCandidate(
        key: "\(hostKey):capacity", signature: "low", kind: .lowDiskSpace,
        title: "Time Capsule storage is low",
        detail: "\(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)) remains free."))
    }
    if preferences.smbOutage, storage.smbAvailability == .unreachable {
      alerts.append(HealthAlertCandidate(
        key: "\(hostKey):smb", signature: "unreachable", kind: .smbOutage,
        title: "Time Capsule file sharing is unavailable",
        detail: storage.smbDetail))
    }
    if preferences.staleBackups {
      for backup in backups.backups where backup.condition == .warning || backup.condition == .stale {
        let severity = backup.condition.rawValue
        let age = backup.latestActivity.map {
          "Latest activity was \($0.formatted(date: .abbreviated, time: .shortened))."
        } ?? "Latest backup activity is unknown."
        alerts.append(HealthAlertCandidate(
          key: "\(hostKey):backup:\(backup.id)", signature: severity,
          kind: .staleBackup,
          title: backup.condition == .stale ? "Time Machine backup is stale" : "Time Machine backup may be overdue",
          detail: "\(backup.computerName): \(age)"))
      }
    }
    return alerts
  }
}
