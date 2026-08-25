// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

import XCTest

@testable import AirPortUtilityCore

final class TimeMachineBackupTests: XCTestCase {
  func testBackupFreshnessThresholds() {
    let now = Date(timeIntervalSince1970: 2_000_000)

    XCTAssertEqual(
      TimeMachineBackupAssessment.condition(
        latestActivity: now.addingTimeInterval(-47 * 60 * 60), now: now),
      .current)
    XCTAssertEqual(
      TimeMachineBackupAssessment.condition(
        latestActivity: now.addingTimeInterval(-3 * 24 * 60 * 60), now: now),
      .warning)
    XCTAssertEqual(
      TimeMachineBackupAssessment.condition(
        latestActivity: now.addingTimeInterval(-8 * 24 * 60 * 60), now: now),
      .stale)
    XCTAssertEqual(
      TimeMachineBackupAssessment.condition(latestActivity: nil, now: now),
      .unknown)
  }

  func testScannerReadsSparsebundleNameAndLatestBandActivity() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
      .appendingPathComponent("time-machine-scan-\(UUID().uuidString)", isDirectory: true)
    let bundle = root.appendingPathComponent("fallback-name.sparsebundle", isDirectory: true)
    let bands = bundle.appendingPathComponent("bands", isDirectory: true)
    try fileManager.createDirectory(at: bands, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: root) }

    let plist = try PropertyListSerialization.data(
      fromPropertyList: ["Computer Name": "Graham’s MacBook Air"],
      format: .xml, options: 0)
    try plist.write(to: bundle.appendingPathComponent("Info.plist"))
    let band = bands.appendingPathComponent("0")
    try Data(repeating: 1, count: 4_096).write(to: band)
    let activity = Date(timeIntervalSince1970: 1_900_000)
    try fileManager.setAttributes([.modificationDate: activity], ofItemAtPath: band.path)

    let records = TimeMachineBackupScanner.scan(
      volumeNames: [], roots: [root], now: activity.addingTimeInterval(60 * 60))

    XCTAssertEqual(records.count, 1)
    XCTAssertEqual(records.first?.computerName, "Graham’s MacBook Air")
    XCTAssertEqual(records.first?.latestActivity, activity)
    XCTAssertEqual(records.first?.condition, .current)
    XCTAssertGreaterThan(records.first?.allocatedBytes ?? 0, 0)
  }

  func testScannerIgnoresOrdinaryFolders() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
      .appendingPathComponent("time-machine-scan-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(
      at: root.appendingPathComponent("Documents", isDirectory: true),
      withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: root) }

    XCTAssertTrue(TimeMachineBackupScanner.scan(volumeNames: [], roots: [root]).isEmpty)
  }

  func testTotalAllocatedBytesIgnoresUnknownSizes() {
    let backups = [
      backup(path: "one", bytes: 100),
      backup(path: "two", bytes: nil),
      backup(path: "three", bytes: 250),
    ]

    XCTAssertEqual(TimeMachineBackupAssessment.totalAllocatedBytes(backups), 350)
    XCTAssertNil(TimeMachineBackupAssessment.totalAllocatedBytes([backup(path: "one", bytes: nil)]))
  }

  func testHistoryAnalysisUsesLatestTwoSizedSamples() {
    let first = historySample(date: Date(timeIntervalSince1970: 100), bytes: 1_000)
    let unknown = historySample(date: Date(timeIntervalSince1970: 200), bytes: nil)
    let latest = historySample(date: Date(timeIntervalSince1970: 300), bytes: 1_600)

    let growth = TimeMachineBackupHistoryAnalysis.latestGrowth(in: [latest, first, unknown])

    XCTAssertEqual(growth?.deltaBytes, 600)
    XCTAssertEqual(growth?.interval, 200)
    XCTAssertEqual(growth?.condition, .growing)
  }

  func testHistoryAnalysisReportsUnchangedAndInsufficientData() {
    let first = historySample(date: Date(timeIntervalSince1970: 100), bytes: 1_000)
    let latest = historySample(date: Date(timeIntervalSince1970: 200), bytes: 1_000)

    XCTAssertEqual(
      TimeMachineBackupHistoryAnalysis.latestGrowth(in: [first, latest])?.condition,
      .unchanged)
    XCTAssertNil(TimeMachineBackupHistoryAnalysis.latestGrowth(in: [latest]))
  }

  private func backup(path: String, bytes: Int64?) -> TimeMachineBackupRecord {
    TimeMachineBackupRecord(
      computerName: path,
      bundleURL: URL(fileURLWithPath: "/tmp/\(path).sparsebundle"),
      latestActivity: nil,
      allocatedBytes: bytes,
      condition: .unknown)
  }

  private func historySample(date: Date, bytes: Int64?) -> HealthHistorySample {
    HealthHistorySample(
      id: UUID(), date: date, host: "192.168.1.1", freeBytes: nil, totalBytes: nil,
      diskCondition: .healthy, smbAvailability: .reachable,
      backupCount: 1, staleBackupCount: 0, backupAllocatedBytes: bytes,
      recentlyActiveBackupCount: 1, wirelessClientCount: 0,
      weakSignalClientCount: 0, warningCount: 0)
  }
}
