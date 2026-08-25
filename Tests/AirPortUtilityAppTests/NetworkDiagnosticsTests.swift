// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

import XCTest

@testable import AirPortUtilityCore

final class NetworkDiagnosticsTests: XCTestCase {
  func testBridgeModeMakesDoubleNATNotApplicable() {
    let result = DoubleNATAssessment.assess(
      routerMode: .bridge, wanAddress: "192.168.1.20")
    XCTAssertEqual(result.condition, .notApplicable)
  }

  func testPrivateWANWarnsWhenAirPortRoutes() {
    for address in ["10.0.0.2", "172.16.1.2", "172.31.1.2", "192.168.1.2", "100.64.1.2"] {
      let result = DoubleNATAssessment.assess(
        routerMode: .dhcpAndNat, wanAddress: address)
      XCTAssertEqual(result.condition, .warning, address)
    }
  }

  func testPublicWANPassesWhenAirPortRoutes() {
    let result = DoubleNATAssessment.assess(
      routerMode: .dhcpAndNat, wanAddress: "203.0.113.10")
    XCTAssertEqual(result.condition, .passed)
  }

  func testMissingWANRemainsUnknown() {
    XCTAssertEqual(
      DoubleNATAssessment.assess(routerMode: .dhcpAndNat, wanAddress: "").condition,
      .unknown)
  }
}
