// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

import XCTest
@testable import AirPortUtilityCore

final class WiFiCongestionTests: XCTestCase {
  func testTwoFourGHzRecommendationAccountsForOverlappingChannels() throws {
    let observations = [
      WiFiChannelObservation(channel: 1, rssi: -35),
      WiFiChannelObservation(channel: 2, rssi: -45),
      WiFiChannelObservation(channel: 6, rssi: -75),
    ]
    let result = WiFiChannelAnalyzer.analyze(
      observations: observations, currentChannel: 1,
      allowedChannels: Set(1...11))
    let band = try XCTUnwrap(result.first { $0.band == "2.4 GHz" })
    XCTAssertEqual(band.recommendedChannel, 11)
    XCTAssertEqual(band.nearbyNetworks, 3)
  }

  func testFiveGHzRecommendationOnlyUsesAllowedChannels() throws {
    let observations = [
      WiFiChannelObservation(channel: 36, rssi: -40),
      WiFiChannelObservation(channel: 44, rssi: -50),
    ]
    let result = WiFiChannelAnalyzer.analyze(
      observations: observations, currentChannel: 36,
      allowedChannels: [36, 40, 44])
    let band = try XCTUnwrap(result.first { $0.band == "5 GHz" })
    XCTAssertEqual(band.recommendedChannel, 40)
  }

  func testCompetitiveCurrentChannelIsRetained() throws {
    let observations = [WiFiChannelObservation(channel: 6, rssi: -80)]
    let result = WiFiChannelAnalyzer.analyze(
      observations: observations, currentChannel: 1,
      allowedChannels: Set(1...11))
    let band = try XCTUnwrap(result.first { $0.band == "2.4 GHz" })
    XCTAssertEqual(band.recommendedChannel, 1)
    XCTAssertTrue(band.summary.contains("competitive"))
  }
}
