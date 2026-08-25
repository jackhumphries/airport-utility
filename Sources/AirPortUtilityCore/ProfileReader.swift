import Darwin
import Foundation

struct ProfileReader: Sendable {
  private let value: JSONValue

  init(_ value: JSONValue) {
    self.value = value
  }

  static func normalized(_ value: JSONValue) -> ProfileReader {
    ProfileReader(normalizedValue(value))
  }

  private static func normalizedValue(_ value: JSONValue) -> JSONValue {
    let reader = ProfileReader(value)
    if reader.value(at: "restoreProfile") != nil {
      return value
    }
    if let profileDecoded = reader.value(at: "Prof.decoded") {
      return normalizedValue(profileDecoded)
    }
    if let settingsDecoded = reader.value(at: "settings.Prof.decoded") {
      return normalizedValue(settingsDecoded)
    }
    if let settings = reader.value(at: "settings"), looksLikeRestoreProfile(settings) {
      return .object(["restoreProfile": settings])
    }
    if let decoded = reader.value(at: "decoded") {
      return normalizedValue(decoded)
    }
    if let currentProfile = reader.currentProfileValue() {
      return .object(["restoreProfile": currentProfile])
    }
    if looksLikeRestoreProfile(value) {
      return .object(["restoreProfile": value])
    }
    return value
  }

  func reader(_ path: String) -> ProfileReader? {
    guard let value = value(at: path) else { return nil }
    return ProfileReader(value)
  }

  func hasValue(at path: String) -> Bool {
    value(at: path) != nil
  }

  func diagnosticDescription(_ path: String) -> String? {
    guard let value = value(at: path) else { return nil }
    return Self.diagnosticDescription(value)
  }

  private static func diagnosticDescription(_ value: JSONValue) -> String {
    switch value {
    case .null:
      return "null"
    case .bool(let value):
      return String(value)
    case .number(let value):
      return value.rounded() == value ? String(format: "%.0f", value) : String(value)
    case .string(let value):
      return value
    case .array(let values):
      return "[\(values.map(diagnosticDescription).joined(separator: ", "))]"
    case .object(let object):
      return "{" + object.keys.sorted().map {
        "\($0): \(diagnosticDescription(object[$0]!))"
      }.joined(separator: ", ") + "}"
    }
  }

  func hasUsableSetting(at path: String) -> Bool {
    guard let value = value(at: path) else { return false }
    return Self.hasUsableSetting(value)
  }

  func string(_ path: String) -> String? {
    guard let value = value(at: path) else { return nil }
    return Self.string(value)
  }

  func strings(_ path: String) -> [String] {
    guard let value = value(at: path) else { return [] }
    switch value {
    case .array(let values):
      return values.compactMap(Self.string)
    default:
      return Self.string(value).map { [$0] } ?? []
    }
  }

  func data(_ path: String) -> Data? {
    guard let value = value(at: path) else { return nil }
    switch value {
    case .string(let text):
      return Data(text.utf8)
    case .object(let object):
      if case .string(let hex)? = object["hex"] {
        return Self.data(fromHex: hex)
      }
      if case .string(let text)? = object["text"] {
        return Data(text.utf8)
      }
      if let rawValue = object["value"] {
        return ProfileReader(rawValue).data("")
      }
      return nil
    default:
      return nil
    }
  }

  private static func data(fromHex text: String) -> Data? {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.count.isMultiple(of: 2) else { return nil }
    var data = Data()
    var index = text.startIndex
    while index < text.endIndex {
      let end = text.index(index, offsetBy: 2)
      guard let byte = UInt8(text[index..<end], radix: 16) else { return nil }
      data.append(byte)
      index = end
    }
    return data
  }

  func ipv4Address(_ path: String, allowingZero: Bool = false) -> String? {
    guard let value = value(at: path) else { return nil }
    if allowingZero, Self.isZeroIPv4Setting(value) {
      return "0.0.0.0"
    }
    return Self.ipv4Address(fromDirectSetting: value)
  }

  func ipv6Address(_ path: String) -> String? {
    guard let value = value(at: path) else { return nil }
    return Self.ipv6Address(fromDirectSetting: value)
  }

  func bool(_ path: String) -> Bool? {
    guard let value = value(at: path) else { return nil }
    return Self.bool(value)
  }

  func boolFromInt(_ path: String) -> Bool? {
    guard let value = value(at: path) else { return nil }
    if let bool = Self.bool(value) { return bool }
    guard let int = Self.int(value) else { return nil }
    return int != 0
  }

  func connectUsing(_ path: String) -> ConnectUsing? {
    switch int(path) {
    case 0x8300: return .dhcp
    case 0x8400: return .static
    case 0x8900: return .pppoe
    case 0x0300: return .dhcp
    case 0x0900: return .modem
    default: return nil
    }
  }

  func pppoeConnection() -> String? {
    let active = bool("restoreProfile.peAC")
    let stayConnected = bool("restoreProfile.peSC")
    guard active != nil || stayConnected != nil else { return nil }
    let isActive = active ?? false
    let shouldStayConnected = stayConnected ?? false
    if isActive && shouldStayConnected { return "always-on" }
    if isActive { return "automatic" }
    return "manual"
  }

  func configureIPv6() -> String? {
    if int("restoreProfile.6cfg") == 0 {
      return "link-local"
    }
    guard let automatic = bool("restoreProfile.6aut") else { return nil }
    return automatic ? "automatic" : "manual"
  }

  func wirelessMode(_ path: String) -> String? {
    switch int(path) {
    case 0: return "create"
    case 1: return "join"
    case 10: return "wds"
    case 20: return "extend"
    case 3: return "off"
    default: return nil
    }
  }

  func wdsMode(_ path: String) -> String? {
    switch int(path) {
    case 0: return "off"
    case 1: return "main"
    case 2: return "relay"
    case 3: return "remote"
    default: return nil
    }
  }

  func wirelessSecurity(_ path: String) -> String? {
    switch int(path) {
    case 1: return "none"
    case 2: return "wep-40"
    case 3: return "wep-128"
    case 4: return "wpa-personal"
    case 5: return "wpa-wpa2-personal"
    case 7: return "wpa2-personal"
    case 9: return "wpa-enterprise"
    case 10: return "wpa-wpa2-enterprise"
    case 12: return "wpa2-enterprise"
    default: return nil
    }
  }

  func radioMode(_ path: String) -> String? {
    switch int(path) {
    case 1: return "80211b"
    case 2: return "80211bg"
    case 3: return "80211g"
    case 4: return "80211a"
    case 5: return "80211n-a"
    case 6: return "80211n-bg"
    case 7: return "80211n-only-24"
    case 8: return "80211n-only-5"
    default: return nil
    }
  }

  func radioChannel(_ path: String) -> String? {
    guard let int = int(path) else { return nil }
    return int == 1000 ? "automatic" : String(int)
  }

  func routerMode(_ path: String) -> RouterMode? {
    switch int(path) {
    case 0: return .dhcpAndNat
    case 1: return .dhcpOnly
    case 2: return .natOnly
    case 3: return .bridge
    default: return nil
    }
  }

  func legacyRouterMode(_ path: String) -> RouterMode? {
    switch rawInt64(path) {
    case 0: return .dhcpAndNat
    case 0xFFFF_FFFF: return .bridge
    default: return nil
    }
  }

  func diskSecurity(_ path: String) -> String? {
    switch int(path) {
    case 0: return "accounts"
    case 1: return "disk-password"
    case 2: return "device-password"
    default: return nil
    }
  }

  func guestDiskAccess(_ path: String) -> String? {
    switch int(path) {
    case 0: return "not-allowed"
    case 1: return "read-only"
    case 2: return "read-write"
    default: return nil
    }
  }

  func dhcpLease(_ path: String) -> (value: String, unit: String)? {
    guard let seconds = int(path), seconds > 0 else { return nil }
    if seconds % 604_800 == 0 {
      return (String(seconds / 604_800), "weeks")
    }
    if seconds % 86_400 == 0 {
      return (String(seconds / 86_400), "days")
    }
    if seconds % 3_600 == 0 {
      return (String(seconds / 3_600), "hours")
    }
    return (String(seconds), "seconds")
  }

  private func currentProfileValue() -> JSONValue? {
    let index = int("currentProfile") ?? 0
    return value(at: "profiles.\(index)")
  }

  private static func looksLikeRestoreProfile(_ value: JSONValue) -> Bool {
    guard case .object(let object) = value else { return false }
    let profileKeys: Set<String> = [
      "WiFi", "bsNM", "bsRM", "dhBg", "dhEn", "laIP", "raNm", "syNm", "waCV", "waIP",
    ]
    return object.keys.contains { profileKeys.contains($0) }
  }

  static func joinNonZeroIPv4(_ values: [String?]) -> String {
    values
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { isUsableIPv4Text($0) }
      .joined(separator: ", ")
  }

  static func joinNonZeroIPv6(_ values: [String?]) -> String {
    values
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { isUsableIPv6Text($0) }
      .joined(separator: ", ")
  }

  static func ipv4Address(fromDirectSetting value: JSONValue) -> String? {
    guard case .object(let object) = value else {
      return string(value).flatMap(ipv4Address(fromSettingText:))
    }
    if case .string(let hex)? = object["hex"],
      case .number(let length)? = object["length"],
      safeInt64(length) == 4,
      let address = ipv4Address(fromHex: hex)
    {
      return address
    }
    if let rawValue = object["value"], let text = string(rawValue) {
      return ipv4Address(fromSettingText: text)
    }
    return nil
  }

  static func ipv6Address(fromDirectSetting value: JSONValue) -> String? {
    guard case .object(let object) = value else {
      return string(value).flatMap(ipv6Address(fromSettingText:))
    }
    if case .string(let hex)? = object["hex"],
      case .number(let length)? = object["length"],
      safeInt64(length) == 16,
      let address = ipv6Address(fromHex: hex)
    {
      return address
    }
    if let rawValue = object["value"], let text = string(rawValue) {
      return ipv6Address(fromSettingText: text)
    }
    return nil
  }

  static func isUsableSettingText(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed != "--" else { return false }
    let unavailableSentinels: Set<String> = [
      "-1", "-10", "4294967295", "4294967286", "0xffffffff", "0xfffffff6",
      "ffffffff", "fffffff6",
    ]
    return !unavailableSentinels.contains(trimmed.lowercased())
  }

  private static func isUsableIPv4Text(_ text: String) -> Bool {
    isUsableSettingText(text) && text != "0" && text != "0.0.0.0"
      && text != "255.255.255.255"
  }

  private static func isUsableIPv6Text(_ text: String) -> Bool {
    let zeroHex = "00000000000000000000000000000000"
    let allOnesHex = "ffffffffffffffffffffffffffffffff"
    let allOnesAddress = "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff"
    let lowered = text.lowercased()
    return isUsableSettingText(text) && text != "0" && text != "::" && lowered != zeroHex
      && lowered != allOnesHex && lowered != allOnesAddress
  }

  private static func ipv4Address(fromSettingText text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard isUsableIPv4Text(trimmed) else { return nil }
    if trimmed.split(separator: ".").count == 4 {
      return isDottedIPv4Address(trimmed) ? trimmed : nil
    }
    if let value = UInt32(trimmed), value > 0 {
      return ipv4Address(fromInteger: value)
    }
    return nil
  }

  private static func isDottedIPv4Address(_ text: String) -> Bool {
    let parts = text.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 4 else { return false }
    return parts.allSatisfy { part in
      !part.isEmpty && part.allSatisfy(\.isNumber) && (part.count == 1 || part.first != "0")
        && UInt8(part) != nil
    }
  }

  private static func isZeroIPv4Setting(_ value: JSONValue) -> Bool {
    switch value {
    case .number(let number):
      return number == 0
    case .string(let text):
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      return trimmed == "0" || trimmed == "0.0.0.0" || trimmed == "00000000"
    case .object(let object):
      if case .string(let hex)? = object["hex"],
        case .number(let length)? = object["length"],
        safeInt64(length) == 4,
        hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "00000000"
      {
        return true
      }
      if let rawValue = object["value"] {
        return isZeroIPv4Setting(rawValue)
      }
      if case .string(let text)? = object["text"] {
        return isZeroIPv4Setting(.string(text))
      }
      return false
    default:
      return false
    }
  }

  private static func ipv4Address(fromHex hex: String) -> String? {
    let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count == 8, let value = UInt32(trimmed, radix: 16), value > 0 else {
      return nil
    }
    return ipv4Address(fromInteger: value)
  }

  private static func ipv4Address(fromInteger value: UInt32) -> String? {
    guard value != 0, value != 0xffff_ffff, value != 0xffff_fff6 else { return nil }
    let octets = [
      (value >> 24) & 0xff,
      (value >> 16) & 0xff,
      (value >> 8) & 0xff,
      value & 0xff,
    ]
    return octets.map(String.init).joined(separator: ".")
  }

  private static func ipv6Address(fromSettingText text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard isUsableIPv6Text(trimmed) else { return nil }
    return canonicalIPv6Address(trimmed)
  }

  static func ipv6Address(fromHex hex: String) -> String? {
    let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard trimmed.count == 32,
      trimmed.allSatisfy({ $0.isNumber || ("a"..."f").contains($0) }),
      isUsableIPv6Text(trimmed)
    else {
      return nil
    }
    var groups: [String] = []
    var index = trimmed.startIndex
    while index < trimmed.endIndex {
      let end = trimmed.index(index, offsetBy: 4)
      groups.append(String(trimmed[index..<end]))
      index = end
    }
    return canonicalIPv6Address(groups.joined(separator: ":"))
  }

  private static func canonicalIPv6Address(_ text: String) -> String? {
    var address = in6_addr()
    guard text.withCString({ inet_pton(AF_INET6, $0, &address) == 1 }) else { return nil }
    var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
    var canonicalAddress = address
    guard inet_ntop(AF_INET6, &canonicalAddress, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil
    else {
      return nil
    }
    return buffer.withUnsafeBufferPointer { pointer in
      guard let baseAddress = pointer.baseAddress else { return nil }
      return String(validatingCString: baseAddress)
    }
  }

  private func int(_ path: String) -> Int? {
    guard let value = value(at: path) else { return nil }
    return Self.int(value)
  }

  private func int64(_ path: String) -> Int64? {
    rawInt64(path)
  }

  private func rawInt64(_ path: String) -> Int64? {
    guard let value = value(at: path) else { return nil }
    return Self.rawInt64(value)
  }

  private func value(at path: String) -> JSONValue? {
    var current = value
    for part in path.split(separator: ".").map(String.init) {
      if let index = Int(part) {
        guard case .array(let values) = current, values.indices.contains(index) else { return nil }
        current = values[index]
      } else {
        guard case .object(let object) = current, let next = object[part] else { return nil }
        current = next
      }
    }
    return current
  }

  private static func string(_ value: JSONValue) -> String? {
    func usable(_ text: String) -> String? {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      return isUsableSettingText(trimmed) ? trimmed : nil
    }

    switch value {
    case .string(let text):
      return usable(text)
    case .number(let number):
      if number.rounded() == number {
        guard let intValue = safeInt64(number) else { return nil }
        guard !isUnavailableInteger(intValue) else { return nil }
        return String(intValue)
      }
      return String(number)
    case .bool(let bool):
      return bool ? "true" : "false"
    case .object(let object):
      if case .string(let text) = object["text"] { return usable(text) }
      if let rawValue = object["value"] { return string(rawValue) }
      return nil
    default:
      return nil
    }
  }

  private static func hasUsableSetting(_ value: JSONValue) -> Bool {
    string(value) != nil
      || bool(value) != nil
      || int(value) != nil
      || ipv4Address(fromDirectSetting: value) != nil
      || ipv6Address(fromDirectSetting: value) != nil
  }

  private static func bool(_ value: JSONValue) -> Bool? {
    switch value {
    case .bool(let bool):
      return bool
    case .number(let number):
      if number.rounded() == number {
        guard let intValue = safeInt64(number), !isUnavailableInteger(intValue) else {
          return nil
        }
      }
      return number != 0
    case .string(let text):
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard isUsableSettingText(trimmed) else { return nil }
      if ["true", "yes", "1"].contains(trimmed.lowercased()) { return true }
      if ["false", "no", "0"].contains(trimmed.lowercased()) { return false }
      return nil
    case .object(let object):
      if let text = string(.object(object)) {
        return bool(.string(text))
      }
      if let rawValue = object["value"] {
        return bool(rawValue)
      }
      return nil
    default:
      return nil
    }
  }

  private static func int(_ value: JSONValue) -> Int? {
    switch value {
    case .number(let number):
      guard let intValue = safeInt64(number) else { return nil }
      guard !isUnavailableInteger(intValue) else { return nil }
      return Int(intValue)
    case .string(let text):
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard isUsableSettingText(trimmed), let intValue = Int64(trimmed),
        !isUnavailableInteger(intValue)
      else { return nil }
      return Int(intValue)
    case .object(let object):
      if let text = string(.object(object)) {
        return int(.string(text))
      }
      if let rawValue = object["value"] {
        return int(rawValue)
      }
      return nil
    default:
      return nil
    }
  }

  private static func rawInt64(_ value: JSONValue) -> Int64? {
    switch value {
    case .number(let number):
      return safeInt64(number)
    case .string(let text):
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard isUsableSettingText(trimmed) else { return nil }
      return Int64(trimmed)
    case .object(let object):
      if let text = string(.object(object)) {
        return rawInt64(.string(text))
      }
      if let rawValue = object["value"] {
        return rawInt64(rawValue)
      }
      return nil
    default:
      return nil
    }
  }

  private static func isUnavailableInteger(_ value: Int64) -> Bool {
    [-1, -10, 4_294_967_295, 4_294_967_286].contains(value)
  }

  private static func safeInt64(_ number: Double) -> Int64? {
    guard number.isFinite, number.rounded() == number,
      number >= -9_223_372_036_854_775_808.0,
      number < 9_223_372_036_854_775_808.0
    else {
      return nil
    }
    return Int64(number)
  }
}
