// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

import Foundation
import XCTest
@testable import AirPortUtilityCore

final class HealthHistoryTests: XCTestCase {
  func testSamplesWithinWindowAreCombined() {
    let start = Date(timeIntervalSince1970: 1_000_000)
    let first = sample(date: start, clients: 2)
    let updated = sample(date: start.addingTimeInterval(60), clients: 3)

    let result = HealthHistoryRetention.adding(updated, to: [first], now: updated.date)

    XCTAssertEqual(result, [updated])
  }

  func testSampleAfterWindowIsAppended() {
    let start = Date(timeIntervalSince1970: 1_000_000)
    let first = sample(date: start, clients: 2)
    let later = sample(
      date: start.addingTimeInterval(HealthHistoryRetention.samplingInterval), clients: 3)

    let result = HealthHistoryRetention.adding(later, to: [first], now: later.date)

    XCTAssertEqual(result, [first, later])
  }

  func testExpiredSamplesAreRemoved() {
    let now = Date(timeIntervalSince1970: 10_000_000)
    let expired = sample(
      date: now.addingTimeInterval(-HealthHistoryRetention.maximumAge - 1), clients: 1)
    let current = sample(date: now, clients: 2)

    XCTAssertEqual(
      HealthHistoryRetention.adding(current, to: [expired], now: now),
      [current])
  }

  func testDifferentHostsDoNotShareSamplingWindow() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let first = sample(date: now, host: "192.168.1.1", clients: 1)
    let second = sample(date: now, host: "192.168.1.2", clients: 2)

    XCTAssertEqual(
      HealthHistoryRetention.adding(second, to: [first], now: now),
      [first, second])
  }

  func testOlderHistoryWithoutBackupGrowthFieldsStillDecodes() throws {
    let original = sample(date: Date(timeIntervalSince1970: 1_000_000), clients: 2)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let encoded = try encoder.encode(HealthHistoryArchive(samples: [original]))
    var archive = try XCTUnwrap(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    var samples = try XCTUnwrap(archive["samples"] as? [[String: Any]])
    samples[0].removeValue(forKey: "backupAllocatedBytes")
    samples[0].removeValue(forKey: "recentlyActiveBackupCount")
    archive["samples"] = samples
    let legacyData = try JSONSerialization.data(withJSONObject: archive)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let decoded = try decoder.decode(HealthHistoryArchive.self, from: legacyData)

    XCTAssertEqual(decoded.samples.first?.backupAllocatedBytes, nil)
    XCTAssertEqual(decoded.samples.first?.recentlyActiveBackupCount, nil)
  }

  private func sample(
    date: Date,
    host: String = "192.168.1.1",
    clients: Int
  ) -> HealthHistorySample {
    HealthHistorySample(
      id: UUID(), date: date, host: host, freeBytes: 500, totalBytes: 1_000,
      diskCondition: .healthy, smbAvailability: .reachable,
      backupCount: 2, staleBackupCount: 0, backupAllocatedBytes: 750,
      recentlyActiveBackupCount: 2, wirelessClientCount: clients,
      weakSignalClientCount: 0, warningCount: 0)
  }
}
