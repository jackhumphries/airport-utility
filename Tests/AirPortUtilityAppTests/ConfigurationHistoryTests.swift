// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

import Foundation
import XCTest
@testable import AirPortUtilityCore

final class ConfigurationHistoryTests: XCTestCase {
  func testStoredSnapshotOmitsSecretsAndCanRestoreWithCurrentSecrets() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ConfigurationHistoryStore(directory: directory)
    var before = AirportSettingsSnapshot()
    before.baseStation.name = "Before"
    before.baseStation.newAdminPassword = "admin-secret"
    before.wireless.password = "wifi-secret"
    before.legacyDeviceOptions.accessControl.primarySecret = "radius-secret"

    let record = try store.prepare(title: "Wireless", host: "192.0.2.1", snapshot: before)
    let raw = try String(
      contentsOf: directory.appendingPathComponent(record.snapshotFileName), encoding: .utf8)
    XCTAssertFalse(raw.contains("admin-secret"))
    XCTAssertFalse(raw.contains("wifi-secret"))
    XCTAssertFalse(raw.contains("radius-secret"))

    let stored = try store.loadSnapshot(for: record)
    var current = AirportSettingsSnapshot()
    current.baseStation.newAdminPassword = "current-admin"
    current.wireless.password = "current-wifi"
    current.legacyDeviceOptions.accessControl.primarySecret = "current-radius"
    let rollback = try ConfigurationHistoryStore.mergingSensitiveValues(
      into: stored, from: current)
    XCTAssertEqual(rollback.baseStation.name, "Before")
    XCTAssertEqual(rollback.baseStation.newAdminPassword, "current-admin")
    XCTAssertEqual(rollback.wireless.password, "current-wifi")
    XCTAssertEqual(
      rollback.legacyDeviceOptions.accessControl.primarySecret, "current-radius")
  }

  func testRetentionCountIsConfigurablePerStore() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ConfigurationHistoryStore(directory: directory, maxRecords: 3)

    for index in 0..<5 {
      _ = try store.prepare(
        title: "Automatic backup \(index)", host: "192.0.2.1", snapshot: .init())
    }

    XCTAssertEqual(store.loadRecords().count, 3)
  }

  func testHistoryStatusUpdatesAndIsNewestFirst() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ConfigurationHistoryStore(directory: directory)
    let first = try store.prepare(title: "Internet", host: "192.0.2.1", snapshot: .init())
    let records = try store.update(id: first.id, status: .verifiedReachable)
    XCTAssertEqual(records.first?.status, .verifiedReachable)
    XCTAssertTrue(records.first?.omittedSensitiveValues == true)
  }

  @MainActor
  func testScopedVerificationIgnoresSecretsAndUnrelatedPanes() {
    let model = AirportAppModel()
    model.mockMode = true
    var expected = model.currentSnapshot
    expected.wireless.networkName = "Studio"
    expected.wireless.password = "expected-secret"
    model.wireless.networkName = "Studio"
    model.wireless.password = "returned-or-preserved-secret"
    model.internet.domainName = "unrelated-change.example"

    XCTAssertTrue(model.configurationMatches(expected, scope: .wireless))
  }

  @MainActor
  func testAutomaticConfigurationBackupIsDueUntilAWholeIntervalHasPassed() {
    let model = AirportAppModel()
    let start = Date()

    XCTAssertTrue(model.automaticConfigurationBackupIsDue(host: "192.0.2.1", now: start))

    model.automaticConfigurationBackupHost = "192.0.2.1"
    model.lastAutomaticConfigurationBackupDate = start

    XCTAssertFalse(
      model.automaticConfigurationBackupIsDue(
        host: "192.0.2.1", now: start.addingTimeInterval(60)))
    XCTAssertTrue(
      model.automaticConfigurationBackupIsDue(
        host: "192.0.2.1",
        now: start.addingTimeInterval(model.automaticConfigurationBackupInterval)))
    XCTAssertTrue(
      model.automaticConfigurationBackupIsDue(
        host: "203.0.113.9", now: start.addingTimeInterval(60)))
  }

  @MainActor
  func testWriteFailureSetsRecoveryGuidance() {
    let model = AirportAppModel()
    defer { try? FileManager.default.removeItem(at: ConfigurationHistoryStore.defaultDirectory()) }
    guard let id = model.prepareConfigurationChange(title: "Wireless", host: "192.0.2.1") else {
      return XCTFail("Expected a change ID")
    }

    model.updateConfigurationChange(id, status: .writeFailed)

    XCTAssertEqual(model.recoveryGuidance?.reason, .configurationWriteFailed)
    XCTAssertEqual(
      AirportConnection.normalizedHost(model.recoveryGuidance?.host ?? ""), "192.0.2.1")
  }

  @MainActor
  func testVerificationFailureSetsRecoveryGuidance() {
    let model = AirportAppModel()
    defer { try? FileManager.default.removeItem(at: ConfigurationHistoryStore.defaultDirectory()) }
    guard let id = model.prepareConfigurationChange(title: "Wireless", host: "192.0.2.1") else {
      return XCTFail("Expected a change ID")
    }

    model.updateConfigurationChange(id, status: .verificationFailed)

    XCTAssertEqual(model.recoveryGuidance?.reason, .configurationVerificationFailed)
  }

  @MainActor
  func testVerifiedStatusClearsRecoveryGuidance() {
    let model = AirportAppModel()
    defer { try? FileManager.default.removeItem(at: ConfigurationHistoryStore.defaultDirectory()) }
    guard let id = model.prepareConfigurationChange(title: "Wireless", host: "192.0.2.1") else {
      return XCTFail("Expected a change ID")
    }
    model.recoveryGuidance = RecoveryGuidance(
      reason: .configurationWriteFailed, host: "192.0.2.1", deviceName: "stale",
      date: Date(), detail: "stale guidance")

    model.updateConfigurationChange(id, status: .verifiedExpected)

    XCTAssertNil(model.recoveryGuidance)
  }

  @MainActor
  func testMostRecentKnownGoodConfigurationRecordPrefersNewestAcrossBothStores() {
    let model = AirportAppModel()
    let host = "192.0.2.1"
    model.configurationChangeHistory = [
      ConfigurationChangeRecord(
        id: UUID(), date: Date(timeIntervalSince1970: 1_000), title: "Old verified",
        host: host, status: .verifiedExpected, snapshotFileName: "a.json",
        omittedSensitiveValues: true),
      ConfigurationChangeRecord(
        id: UUID(), date: Date(timeIntervalSince1970: 5_000), title: "Failed write",
        host: host, status: .writeFailed, snapshotFileName: "b.json",
        omittedSensitiveValues: true),
    ]
    model.automaticConfigurationBackups = [
      ConfigurationChangeRecord(
        id: UUID(), date: Date(timeIntervalSince1970: 3_000), title: "Automatic backup",
        host: host, status: .prepared, snapshotFileName: "c.json",
        omittedSensitiveValues: true),
    ]

    let candidate = model.mostRecentKnownGoodConfigurationRecord(forHost: host)

    // The failed write (newest overall) doesn't count as known-good; the
    // automatic backup (newer than the verified history record, and
    // unconditionally "good" since it's never paired with a write to fail)
    // wins.
    XCTAssertEqual(candidate?.record.title, "Automatic backup")
    XCTAssertTrue(candidate?.isAutomaticBackup == true)
  }

  @MainActor
  func testMostRecentKnownGoodConfigurationRecordReturnsNilWhenNoneQualify() {
    let model = AirportAppModel()
    model.configurationChangeHistory = [
      ConfigurationChangeRecord(
        id: UUID(), date: Date(), title: "Failed write", host: "192.0.2.1",
        status: .writeFailed, snapshotFileName: "a.json", omittedSensitiveValues: true)
    ]

    XCTAssertNil(model.mostRecentKnownGoodConfigurationRecord(forHost: "192.0.2.1"))
  }

  @MainActor
  func testScopedVerificationDetectsReturnedDifference() {
    let model = AirportAppModel()
    model.mockMode = true
    model.network.routerMode = .dhcpAndNat
    var expected = model.currentSnapshot
    expected.network.dhcpRangeStart = "192.168.1.10"
    model.network.dhcpRangeStart = "192.168.1.20"

    XCTAssertFalse(model.configurationMatches(expected, scope: .network))
  }
}
