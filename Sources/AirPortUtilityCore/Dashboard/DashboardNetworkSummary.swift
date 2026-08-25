// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

import Foundation

struct DashboardNetworkSummary: Equatable, Sendable {
  let internetStatus: String
  let connectionMethod: String
  let wanAddress: String
  let upstreamRouter: String
  let dnsServers: String
  let dhcpStatus: String
  let dhcpRange: String
  let wirelessMode: String
  let wirelessSecurity: String
  let wirelessRadio: String
  let guestNetwork: String
  let warnings: [String]

  init(
    internet: InternetState,
    hostInternet: HostInternetState,
    network: NetworkState,
    wireless: WirelessState,
    statusText: String,
    statusDetails: [String]
  ) {
    internetStatus = Self.nonEmpty(hostInternet.connectionStatus)
    connectionMethod = network.routerMode == .bridge
      ? "Provided by upstream router"
      : internet.connectUsing.label
    wanAddress = network.routerMode == .bridge
      ? "Not applicable in Bridge Mode"
      : Self.nonEmpty(internet.ipv4Address)
    upstreamRouter = Self.firstNonEmpty(internet.routerAddress, hostInternet.routerAddress)
    dnsServers = Self.firstNonEmpty(
      internet.dnsServerPreview, internet.dnsServers, hostInternet.dnsServers)

    switch network.routerMode {
    case .dhcpAndNat, .dhcpOnly:
      dhcpStatus = "Enabled"
    case .natOnly:
      dhcpStatus = "Disabled"
    case .bridge:
      dhcpStatus = "Provided by upstream router"
    }
    let rangeStart = network.dhcpRangeStart.trimmingCharacters(in: .whitespacesAndNewlines)
    let rangeEnd = network.dhcpRangeEnd.trimmingCharacters(in: .whitespacesAndNewlines)
    dhcpRange = rangeStart.isEmpty || rangeEnd.isEmpty
      ? network.routerMode == .bridge ? "Managed upstream" : "Not reported"
      : "\(rangeStart) – \(rangeEnd)"

    wirelessMode = Self.wirelessModeLabel(wireless.mode)
    wirelessSecurity = WirelessSecurityOption(rawValue: wireless.security)?.label
      ?? Self.nonEmpty(wireless.security)
    let radioMode = WirelessRadioModeOption.options(including: wireless.radioMode)
      .first(where: { $0.value == wireless.radioMode })?.label
      ?? Self.nonEmpty(wireless.radioMode)
    let channel = wireless.radioChannel.trimmingCharacters(in: .whitespacesAndNewlines)
    wirelessRadio = channel.isEmpty
      ? radioMode
      : "\(radioMode), channel \(channel == "automatic" ? "automatic" : channel)"
    guestNetwork = "Not reported by this AirPort"

    let normalizedDetails = statusDetails.map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter { !$0.isEmpty }
    let normalizedStatus = statusText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !normalizedDetails.isEmpty {
      warnings = normalizedDetails
    } else if !normalizedStatus.isEmpty
      && normalizedStatus.caseInsensitiveCompare("Working normally") != .orderedSame
    {
      warnings = [normalizedStatus]
    } else {
      warnings = []
    }
  }

  private static func firstNonEmpty(_ values: String...) -> String {
    for value in values {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { return trimmed }
    }
    return "Unknown"
  }

  private static func nonEmpty(_ value: String) -> String {
    firstNonEmpty(value)
  }

  private static func wirelessModeLabel(_ value: String) -> String {
    switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "create": "Create a wireless network"
    case "extend": "Extend a wireless network"
    case "join": "Join a wireless network"
    case "wds": "Participate in a WDS network"
    case "off": "Off"
    case let value: value.isEmpty ? "Unknown" : value
    }
  }
}
