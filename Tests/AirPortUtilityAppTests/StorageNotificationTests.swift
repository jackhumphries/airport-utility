// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

import XCTest

@testable import AirPortUtilityCore

final class StorageNotificationTests: XCTestCase {
  func testDisabledPreferencesProduceNoAlerts() {
    let alerts = HealthAlertAssessment.candidates(
      host: "time-capsule.local",
      storage: StorageHealthState(
        diskCondition: .warning, diskDetail: "Warning",
        totalBytes: 100_000_000_000, freeBytes: 1_000_000_000,
        smartStatus: "failing", smbAvailability: .unreachable),
      backups: staleBackupState(),
      preferences: HealthNotificationPreferences())

    XCTAssertTrue(alerts.isEmpty)
  }

  func testEnabledPreferencesProduceSpecificHealthAlerts() {
    let preferences = HealthNotificationPreferences(
      smartStatus: true, lowDiskSpace: true, smbOutage: true, staleBackups: true)
    let alerts = HealthAlertAssessment.candidates(
      host: "time-capsule.local",
      storage: StorageHealthState(
        diskCondition: .warning, diskDetail: "Warning",
        totalBytes: 100_000_000_000, freeBytes: 1_000_000_000,
        smartStatus: "failing", smbAvailability: .unreachable,
        smbDetail: "SMB is unavailable"),
      backups: staleBackupState(),
      preferences: preferences)

    XCTAssertEqual(Set(alerts.map(\.kind)), [
      .smartStatus, .lowDiskSpace, .smbOutage, .staleBackup,
    ])
  }

  func testBackupAlertSignatureEscalatesFromWarningToStale() {
    let preferences = HealthNotificationPreferences(staleBackups: true)
    let warning = backupState(condition: .warning)
    let stale = backupState(condition: .stale)

    let warningAlert = HealthAlertAssessment.candidates(
      host: "time-capsule.local", storage: StorageHealthState(),
      backups: warning, preferences: preferences).first
    let staleAlert = HealthAlertAssessment.candidates(
      host: "time-capsule.local", storage: StorageHealthState(),
      backups: stale, preferences: preferences).first

    XCTAssertEqual(warningAlert?.signature, "warning")
    XCTAssertEqual(staleAlert?.signature, "stale")
  }

  private func staleBackupState() -> TimeMachineBackupState {
    backupState(condition: .stale)
  }

  private func backupState(condition: TimeMachineBackupCondition) -> TimeMachineBackupState {
    TimeMachineBackupState(backups: [
      TimeMachineBackupRecord(
        computerName: "Test Mac",
        bundleURL: URL(fileURLWithPath: "/Volumes/Data/Test.sparsebundle"),
        latestActivity: Date(timeIntervalSince1970: 1_000_000),
        allocatedBytes: 10_000,
        condition: condition)
    ])
  }
}
