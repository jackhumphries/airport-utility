// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

import Foundation

/// Looks up the vendor behind a MAC address's OUI (Organizationally Unique
/// Identifier) prefix, using a curated subset of the official IEEE MA-L
/// registry covering vendors common on a home network. See
/// docs/client-identification.md for the data source and how it was built.
enum MACVendorLookup {
  private static let table: [String: String] = loadTable()

  /// The vendor name for a MAC address, or nil when the address is
  /// locally-administered (randomized) or its OUI isn't in the curated
  /// table. An unmatched real address is reported as unknown - this never
  /// guesses a plausible-looking neighbor for an OUI it doesn't recognise.
  static func vendor(forMACAddress macAddress: String) -> String? {
    guard !isLocallyAdministered(macAddress), let prefix = normalizedOUIPrefix(macAddress) else {
      return nil
    }
    return table[prefix]
  }

  /// True when the address's first octet has the locally-administered bit
  /// set (the second-least-significant bit) - the standard signal iOS,
  /// Android, and macOS use to mark a randomized MAC address chosen for
  /// privacy rather than one assigned by a manufacturer. A vendor lookup on
  /// such an address would be meaningless at best, misleading at worst.
  static func isLocallyAdministered(_ macAddress: String) -> Bool {
    guard let firstByte = firstOctet(macAddress) else { return false }
    return firstByte & 0x02 != 0
  }

  private static func firstOctet(_ macAddress: String) -> UInt8? {
    let hex = macAddress.filter(\.isHexDigit)
    guard hex.count >= 2 else { return nil }
    return UInt8(hex.prefix(2), radix: 16)
  }

  private static func normalizedOUIPrefix(_ macAddress: String) -> String? {
    let hex = macAddress.filter(\.isHexDigit).uppercased()
    guard hex.count >= 6 else { return nil }
    return String(hex.prefix(6))
  }

  private static func loadTable() -> [String: String] {
    guard
      let url = Bundle.main.url(forResource: "oui-vendors", withExtension: "json")
        ?? Bundle.module.url(forResource: "oui-vendors", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let decoded = try? JSONDecoder().decode([String: String].self, from: data)
    else {
      AppLogger.shared.error("Could not load the OUI vendor table", category: .network)
      return [:]
    }
    return decoded
  }
}

/// A guessed category for a wireless client, shown alongside its vendor.
/// Deliberately conservative: `.unknown` is the correct answer whenever the
/// signal isn't strong enough to be confident, matching this app's existing
/// "never estimate missing device data" rule (see
/// docs/hardware-compatibility.md's Recognised/Unrecognised/Unidentified
/// states for the same philosophy applied elsewhere).
enum ClientDeviceType: String, CaseIterable, Sendable {
  case iPhone
  case iPad
  case mac
  case appleTV
  case homePod
  case appleWatch
  case printer
  case smartSpeaker
  case gameConsole
  case networkDevice
  case unknown

  var label: String {
    switch self {
    case .iPhone: "iPhone"
    case .iPad: "iPad"
    case .mac: "Mac"
    case .appleTV: "Apple TV"
    case .homePod: "HomePod"
    case .appleWatch: "Apple Watch"
    case .printer: "Printer"
    case .smartSpeaker: "Speaker"
    case .gameConsole: "Game Console"
    case .networkDevice: "Network Device"
    case .unknown: "Unknown"
    }
  }

  var systemImage: String {
    switch self {
    case .iPhone: "iphone"
    case .iPad: "ipad"
    case .mac: "desktopcomputer"
    case .appleTV: "appletv"
    case .homePod: "homepod"
    case .appleWatch: "applewatch"
    case .printer: "printer.fill"
    case .smartSpeaker: "hifispeaker.fill"
    case .gameConsole: "gamecontroller.fill"
    case .networkDevice: "network"
    case .unknown: "questionmark.circle"
    }
  }

  /// Hostname patterns are trusted first, since a hostname that literally
  /// names the device ("Grahams-iPhone") is a much stronger signal than any
  /// vendor. Vendor-only guesses are limited to a short list of vendors
  /// that are, in practice, single-purpose on a home network - most vendors
  /// in the lookup table (Samsung, LG, Sony, Panasonic, Canon, ASUS,
  /// Broadcom, Espressif, and any module/OEM vendor whose chips end up in
  /// many different rebranded products) are deliberately excluded here
  /// because they make or supply too many device categories to guess from
  /// vendor alone without real risk of being confidently wrong.
  static func guess(hostname: String?, vendor: String?) -> ClientDeviceType {
    let host = (hostname ?? "").lowercased()

    if !host.isEmpty {
      if host.contains("iphone") { return .iPhone }
      if host.contains("ipad") { return .iPad }
      if host.contains("macbook") || host.contains("imac")
        || host.contains("mac-mini") || host.contains("mac mini")
        || host.contains("mac-studio") || host.contains("mac studio")
        || host.contains("mac-pro") || host.contains("mac pro")
      {
        return .mac
      }
      if host.contains("apple-tv") || host.contains("appletv") { return .appleTV }
      if host.contains("homepod") { return .homePod }
      if host.contains("watch") { return .appleWatch }
    }

    switch vendor {
    case "Sonos": return .smartSpeaker
    case "Nintendo": return .gameConsole
    case "Epson", "Brother": return .printer
    case "Ubiquiti", "eero": return .networkDevice
    default: return .unknown
    }
  }
}

extension WirelessClient {
  var vendorName: String? { MACVendorLookup.vendor(forMACAddress: macAddress) }

  var isPrivateAddress: Bool { MACVendorLookup.isLocallyAdministered(macAddress) }

  var guessedDeviceType: ClientDeviceType {
    ClientDeviceType.guess(hostname: advertisedHostname, vendor: vendorName)
  }
}

/// A local-only friendly name for a wireless client, keyed by MAC address.
/// Never written to the AirPort - purely a display override kept on this
/// Mac, following the same file-per-feature persistence pattern as
/// `HealthHistoryStore`.
@MainActor
final class ClientIdentityStore {
  private let fileURL: URL

  init(fileURL: URL = ClientIdentityStore.defaultFileURL()) {
    self.fileURL = fileURL
  }

  func load() -> [String: String] {
    guard let data = try? Data(contentsOf: fileURL) else { return [:] }
    return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
  }

  func save(_ namesByMACAddress: [String: String]) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(namesByMACAddress) else { return }
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true)
      try data.write(to: fileURL, options: .atomic)
    } catch {
      AppLogger.shared.error(
        "Could not save client names: \(error.localizedDescription)", category: .network)
    }
  }

  nonisolated static func defaultFileURL() -> URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("AirPort Utility Powerhouse", isDirectory: true)
      .appendingPathComponent("ClientIdentity", isDirectory: true)
      .appendingPathComponent("client-names.json")
  }
}

@MainActor
extension AirportAppModel {
  private static func normalizedMACKey(_ macAddress: String) -> String {
    macAddress.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
  }

  func customClientName(forMACAddress macAddress: String) -> String? {
    let name = clientCustomNames[Self.normalizedMACKey(macAddress)]?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return (name?.isEmpty ?? true) ? nil : name
  }

  func setCustomClientName(_ name: String?, forMACAddress macAddress: String) {
    let key = Self.normalizedMACKey(macAddress)
    let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let trimmed, !trimmed.isEmpty {
      clientCustomNames[key] = trimmed
    } else {
      clientCustomNames.removeValue(forKey: key)
    }
    clientIdentityStore.save(clientCustomNames)
  }

  func displayName(for client: WirelessClient) -> String {
    customClientName(forMACAddress: client.macAddress) ?? client.displayName
  }
}
