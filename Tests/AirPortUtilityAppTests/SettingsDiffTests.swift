// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

import XCTest
@testable import AirPortUtilityCore

final class SettingsDiffTests: XCTestCase {
  func testNoDifferencesForIdenticalSnapshots() {
    let snapshot = AirportSettingsSnapshot()

    XCTAssertEqual(SettingsDiff.differences(from: snapshot, to: snapshot), [])
  }

  func testDetectsChangedFieldsWithHumanReadableLabels() {
    var before = AirportSettingsSnapshot()
    before.wireless.networkName = "Old-WiFi"
    before.network.routerMode = .dhcpAndNat
    var after = before
    after.wireless.networkName = "Home-WiFi"
    after.network.routerMode = .bridge

    let differences = SettingsDiff.differences(from: before, to: after)

    XCTAssertTrue(
      differences.contains {
        $0.sectionLabel == "Wireless" && $0.fieldLabel == "Network Name"
          && $0.before == "Old-WiFi" && $0.after == "Home-WiFi"
      })
    XCTAssertTrue(
      differences.contains {
        $0.sectionLabel == "Network" && $0.fieldLabel == "Router Mode"
          && $0.before == "dhcp-and-nat" && $0.after == "bridge"
      })
  }

  func testSensitiveFieldsNeverAppearAsDifferencesEvenWhenActuallyDifferent() {
    var before = AirportSettingsSnapshot()
    before.wireless.password = "old-secret"
    before.baseStation.newAdminPassword = "old-admin-secret"
    var after = AirportSettingsSnapshot()
    after.wireless.password = "new-secret"
    after.baseStation.newAdminPassword = "new-admin-secret"

    let differences = SettingsDiff.differences(from: before, to: after)

    XCTAssertTrue(differences.allSatisfy { !$0.path.lowercased().contains("password") })
  }

  func testEmptyValuesAreLabeledRatherThanShownBlank() {
    var before = AirportSettingsSnapshot()
    before.network.dhcpRangeStart = "192.168.1.10"
    var after = before
    after.network.dhcpRangeStart = ""

    let differences = SettingsDiff.differences(from: before, to: after)

    let match = differences.first { $0.fieldLabel == "Dhcp Range Start" }
    XCTAssertEqual(match?.before, "192.168.1.10")
    XCTAssertEqual(match?.after, "(empty)")
  }

  @MainActor
  func testCompareToCurrentSettingsPopulatesComparisonFromStoredSnapshot() throws {
    let model = AirportAppModel()
    defer { try? FileManager.default.removeItem(at: ConfigurationHistoryStore.defaultDirectory()) }
    var stored = AirportSettingsSnapshot()
    stored.wireless.networkName = "Old-WiFi"
    let record = try model.configurationHistoryStore.prepare(
      title: "Wireless", host: "192.0.2.1", snapshot: stored)
    model.wireless.networkName = "Home-WiFi"
    model.markClean(.all, from: model.currentSnapshot, appliedAdminPassword: "")

    model.compareToCurrentSettings(record)

    let comparison = try XCTUnwrap(model.settingsComparison)
    XCTAssertEqual(comparison.beforeLabel.hasPrefix("Wireless"), true)
    XCTAssertEqual(comparison.afterLabel, "Current")
    XCTAssertTrue(
      comparison.differences.contains {
        $0.fieldLabel == "Network Name" && $0.before == "Old-WiFi" && $0.after == "Home-WiFi"
      })
  }

  @MainActor
  func testCompareEntriesComparesTwoArbitrarySnapshotsAcrossBothStores() throws {
    let model = AirportAppModel()
    defer { try? FileManager.default.removeItem(at: ConfigurationHistoryStore.defaultDirectory()) }
    let automaticBackupsDirectory = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    )[0].appendingPathComponent("AirPort Utility Powerhouse/Automatic Backups", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: automaticBackupsDirectory) }

    var first = AirportSettingsSnapshot()
    first.wireless.networkName = "Old-WiFi"
    let historyRecord = try model.configurationHistoryStore.prepare(
      title: "Wireless", host: "192.0.2.1", snapshot: first)
    var second = AirportSettingsSnapshot()
    second.wireless.networkName = "Home-WiFi"
    let backupRecord = try model.automaticConfigurationBackupStore.prepare(
      title: "Automatic backup", host: "192.0.2.1", snapshot: second)

    model.compareEntries(
      HistoryEntryReference(record: historyRecord, isAutomaticBackup: false),
      HistoryEntryReference(record: backupRecord, isAutomaticBackup: true))

    let comparison = try XCTUnwrap(model.settingsComparison)
    XCTAssertTrue(comparison.beforeLabel.hasPrefix("Wireless"))
    XCTAssertTrue(comparison.afterLabel.hasPrefix("Automatic backup"))
    XCTAssertTrue(
      comparison.differences.contains {
        $0.fieldLabel == "Network Name" && $0.before == "Old-WiFi" && $0.after == "Home-WiFi"
      })
  }
}
