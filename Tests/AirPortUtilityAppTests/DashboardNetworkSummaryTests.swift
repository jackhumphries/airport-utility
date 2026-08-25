// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

import XCTest

@testable import AirPortUtilityCore

final class DashboardNetworkSummaryTests: XCTestCase {
  func testBridgeModeUsesUpstreamInternetAndDHCPDetails() {
    let summary = DashboardNetworkSummary(
      internet: InternetState(
        connectUsing: .dhcp,
        routerAddress: "192.168.1.254",
        dnsServerPreview: "1.1.1.1, 8.8.8.8"),
      hostInternet: HostInternetState(connectionStatus: "Connected"),
      network: NetworkState(routerMode: .bridge),
      wireless: WirelessState(
        mode: "create", networkName: "NachoWifi 5GHz", security: "wpa2-personal",
        radioMode: "80211n-a", radioChannel: "automatic"),
      statusText: "Working normally",
      statusDetails: [])

    XCTAssertEqual(summary.internetStatus, "Connected")
    XCTAssertEqual(summary.connectionMethod, "Provided by upstream router")
    XCTAssertEqual(summary.wanAddress, "Not applicable in Bridge Mode")
    XCTAssertEqual(summary.upstreamRouter, "192.168.1.254")
    XCTAssertEqual(summary.dnsServers, "1.1.1.1, 8.8.8.8")
    XCTAssertEqual(summary.dhcpStatus, "Provided by upstream router")
    XCTAssertEqual(summary.dhcpRange, "Managed upstream")
    XCTAssertEqual(summary.wirelessSecurity, "WPA2 Personal")
    XCTAssertEqual(summary.wirelessRadio, "802.11n (802.11a compatible), channel automatic")
    XCTAssertTrue(summary.warnings.isEmpty)
  }

  func testRoutedModeDisplaysWANAndDHCPRange() {
    let summary = DashboardNetworkSummary(
      internet: InternetState(
        connectUsing: .static,
        ipv4Address: "203.0.113.10",
        routerAddress: "203.0.113.1",
        dnsServers: "9.9.9.9"),
      hostInternet: HostInternetState(connectionStatus: "Connected"),
      network: NetworkState(
        routerMode: .dhcpAndNat,
        dhcpRangeStart: "10.0.1.2",
        dhcpRangeEnd: "10.0.1.200"),
      wireless: WirelessState(),
      statusText: "Double NAT",
      statusDetails: ["Another router appears to be providing NAT upstream."])

    XCTAssertEqual(summary.connectionMethod, "Static")
    XCTAssertEqual(summary.wanAddress, "203.0.113.10")
    XCTAssertEqual(summary.dhcpStatus, "Enabled")
    XCTAssertEqual(summary.dhcpRange, "10.0.1.2 – 10.0.1.200")
    XCTAssertEqual(summary.warnings, ["Another router appears to be providing NAT upstream."])
  }

  func testUnknownGuestNetworkIsNotInvented() {
    let summary = DashboardNetworkSummary(
      internet: InternetState(), hostInternet: HostInternetState(),
      network: NetworkState(), wireless: WirelessState(),
      statusText: "Working normally", statusDetails: [])

    XCTAssertEqual(summary.guestNetwork, "Not reported by this AirPort")
  }
}
