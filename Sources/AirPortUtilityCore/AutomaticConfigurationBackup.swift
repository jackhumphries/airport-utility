// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

import Foundation

@MainActor
extension AirportAppModel {
  /// Whether enough time has passed since the last automatic backup for
  /// `host` to make another one worthwhile. Switching to a different host
  /// always counts as due, matching the identity-discovery due-check above.
  func automaticConfigurationBackupIsDue(
    host: String,
    now: Date = Date()
  ) -> Bool {
    guard automaticConfigurationBackupHost == host,
      let lastAutomaticConfigurationBackupDate
    else {
      return true
    }
    return now.timeIntervalSince(lastAutomaticConfigurationBackupDate)
      >= automaticConfigurationBackupInterval
  }

  /// Saves a credential-free settings snapshot independent of any user
  /// edit, so a recent backup exists even if settings are never changed
  /// through the app. Distinct from Configuration History, which only
  /// snapshots immediately before a write.
  func scheduleAutomaticConfigurationBackupIfNeeded(requestHost: String) {
    guard !mockMode, liveCredentialsAvailable else { return }
    guard automaticConfigurationBackupIsDue(host: requestHost) else { return }
    do {
      _ = try automaticConfigurationBackupStore.prepare(
        title: "Automatic backup", host: requestHost, snapshot: cleanSnapshot)
      automaticConfigurationBackups = automaticConfigurationBackupStore.loadRecords()
      automaticConfigurationBackupHost = requestHost
      lastAutomaticConfigurationBackupDate = Date()
      appendLog("Saved an automatic configuration backup for \(requestHost).")
    } catch {
      appendLog(
        "Automatic configuration backup failed: \(error.localizedDescription)")
    }
  }
}
