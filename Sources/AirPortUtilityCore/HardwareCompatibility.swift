// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

import Foundation

enum HardwareCompatibilityCondition: String, Codable, Equatable, Sendable {
  case recognised
  case unrecognised
  case unidentified
}

struct HardwareCompatibilityAssessment: Codable, Equatable, Sendable {
  let condition: HardwareCompatibilityCondition
  let productID: String
  let modelName: String
  let firmwareVersion: String
  let enabledCapabilities: [String]
  let summary: String
}

enum HardwareCompatibility {
  static let recognisedProductIDs: Set<String> = [
    "3", "102", "104", "105", "106", "107", "108", "109", "113", "114", "115", "116",
    "117", "119", "120",
  ]

  nonisolated static func assess(
    productID: String,
    modelName: String,
    firmwareVersion: String,
    capabilities: DeviceCapabilities
  ) -> HardwareCompatibilityAssessment {
    let productID = productID.trimmingCharacters(in: .whitespacesAndNewlines)
    let modelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
    let firmwareVersion = firmwareVersion.trimmingCharacters(in: .whitespacesAndNewlines)
    let condition: HardwareCompatibilityCondition
    let summary: String
    if productID.isEmpty {
      condition = .unidentified
      summary = "This AirPort did not report a product identifier"
    } else if recognisedProductIDs.contains(productID) {
      condition = .recognised
      summary = "Recognised AirPort compatibility profile"
    } else {
      condition = .unrecognised
      summary = "Unrecognised product identifier; include diagnostics in a compatibility report"
    }
    return HardwareCompatibilityAssessment(
      condition: condition,
      productID: productID,
      modelName: modelName,
      firmwareVersion: firmwareVersion,
      enabledCapabilities: enabledCapabilityNames(capabilities),
      summary: summary)
  }

  private nonisolated static func enabledCapabilityNames(
    _ capabilities: DeviceCapabilities
  ) -> [String] {
    var names: [String] = []
    if capabilities.supportsAirPlay { names.append("AirPlay") }
    if capabilities.supportsDisks { names.append("Disks") }
    if capabilities.supportsFirmware { names.append("Firmware") }
    if capabilities.supportsIPv6 { names.append("IPv6") }
    if capabilities.supportsDynamicGlobalHostname { names.append("Dynamic Global Hostname") }
    if capabilities.supportsClassicWDS { names.append("Classic WDS") }
    if capabilities.supportsModem { names.append("Modem") }
    if capabilities.supportsLogging { names.append("Remote Logging") }
    if capabilities.supportsPPPDialIn { names.append("PPP Dial-In") }
    if capabilities.supportsBaseStationMetadata { names.append("Base Station Metadata") }
    if capabilities.supportsLegacyWirelessOptions { names.append("Legacy Wireless Options") }
    if capabilities.supportsLegacyDHCPOptions { names.append("Legacy DHCP Options") }
    if capabilities.supportsAccessControl { names.append("Access Control") }
    return names
  }
}

@MainActor
extension AirportAppModel {
  func hardwareCompatibilityAssessment() -> HardwareCompatibilityAssessment {
    let selected = selectedTopologyDevice()
    let selectedProductID =
      selected?.productID.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return HardwareCompatibility.assess(
      productID: selectedProductID.isEmpty ? baseStation.productID : selectedProductID,
      modelName: selected?.displayModelName ?? "",
      firmwareVersion: baseStation.version,
      capabilities: capabilities)
  }
}
