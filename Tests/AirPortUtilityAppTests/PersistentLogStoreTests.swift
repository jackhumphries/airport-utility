// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

//
//  PersistentLogStoreTests.swift
//  AirPortUtility
//
//  Created by Graham Barber on 05/08/2026.
//


import Foundation
import XCTest
@testable import AirPortUtilityCore

final class PersistentLogStoreTests: XCTestCase {
  private var temporaryDirectory: URL!

  override func setUpWithError() throws {
    temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)

    try FileManager.default.createDirectory(
      at: temporaryDirectory,
      withIntermediateDirectories: true
    )
  }

  override func tearDownWithError() throws {
    if FileManager.default.fileExists(
      atPath: temporaryDirectory.path
    ) {
      try FileManager.default.removeItem(
        at: temporaryDirectory
      )
    }
  }

  func testAppendAndReadEntry() async throws {
    let logURL = temporaryDirectory
      .appendingPathComponent("test.log")

    let store = PersistentLogStore(
      logFileURL: logURL
    )

    let entry = LogEntry(
      level: .info,
      category: .discovery,
      message: "Discovered AirPort"
    )

    try await store.append(entry)

    let entries = try await store.readEntries()

    XCTAssertEqual(entries.count, 1)
    XCTAssertEqual(entries.first?.id, entry.id)
    XCTAssertEqual(entries.first?.level, .info)
    XCTAssertEqual(entries.first?.category, .discovery)
    XCTAssertEqual(
      entries.first?.message,
      "Discovered AirPort"
    )
  }

  func testClearRemovesEntries() async throws {
    let logURL = temporaryDirectory
      .appendingPathComponent("test.log")

    let store = PersistentLogStore(
      logFileURL: logURL
    )

    try await store.append(
      LogEntry(
        level: .warning,
        category: .network,
        message: "Network unavailable"
      )
    )

    try await store.clear()

    let entries = try await store.readEntries()

    XCTAssertTrue(entries.isEmpty)
  }

  func testRotationMovesExistingLog() async throws {
    let logURL = temporaryDirectory
      .appendingPathComponent("test.log")

    let store = PersistentLogStore(
      logFileURL: logURL,
      maximumFileSize: 1
    )

    try await store.append(
      LogEntry(
        level: .info,
        category: .app,
        message: "First entry"
      )
    )

    try await store.append(
      LogEntry(
        level: .info,
        category: .app,
        message: "Second entry"
      )
    )

    let rotatedURL = logURL
      .deletingPathExtension()
      .appendingPathExtension("previous.log")

    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: rotatedURL.path
      )
    )

    let entries = try await store.readEntries()

    XCTAssertEqual(entries.count, 1)
    XCTAssertEqual(entries.first?.message, "Second entry")
  }
}