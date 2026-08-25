// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

//
//  LogRedactorTests.swift
//  AirPortUtility
//
//  Created by Graham Barber on 05/08/2026.
//


import XCTest
@testable import AirPortUtilityCore

final class LogRedactorTests: XCTestCase {
  func testRedactsPasswordAssignment() {
    let input = "password=super-secret"
    let output = LogRedactor.redact(input)

    XCTAssertEqual(output, "password=<redacted>")
  }

  func testRedactsQuotedJSONPassword() {
    let input = #"{"adminPassword":"secret-value"}"#
    let output = LogRedactor.redact(input)

    XCTAssertEqual(output, #"{"adminPassword":<redacted>}"#)
  }

  func testRedactsAuthorizationHeader() {
    let input = "Authorization: Bearer abc123"
    let output = LogRedactor.redact(input)

    XCTAssertEqual(output, "Authorization: <redacted>")
  }

  func testRedactsURLCredentials() {
    let input = "smb://graham:secret@192.168.1.1/Data"
    let output = LogRedactor.redact(input)

    XCTAssertEqual(
      output,
      "smb://graham:<redacted>@192.168.1.1/Data"
    )
  }

  func testLeavesNormalMessageUnchanged() {
    let input = "Discovered AirPort at 192.168.1.1"

    XCTAssertEqual(LogRedactor.redact(input), input)
  }
}