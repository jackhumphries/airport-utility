import Foundation

struct AirportConnection: Equatable, Sendable {
  var host: String
  var password: String
  var repoPath: String

  init(
    host: String = "time-capsule.local", password: String = "",
    repoPath: String = Self.defaultRepoPath()
  ) {
    self.host = Self.normalizedHost(host)
    self.password = password
    self.repoPath = repoPath
  }

  static func normalizedHost(_ host: String) -> String {
    host.trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "."))
      .lowercased()
  }

  static func defaultRepoPath() -> String {
    let fileManager = FileManager.default

    if let resourcesURL = Bundle.main.resourceURL,
      containsBackendScripts(resourcesURL, fileManager: fileManager)
    {
      return resourcesURL.path
    }

    let currentURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
    if containsBackendScripts(currentURL, fileManager: fileManager) {
      return currentURL.path
    }

    if let executableURL = Bundle.main.executableURL {
      var candidate = executableURL.deletingLastPathComponent()
      for _ in 0..<10 {
        if containsBackendScripts(candidate, fileManager: fileManager) {
          return candidate.path
        }
        let parent = candidate.deletingLastPathComponent()
        if parent.path == candidate.path { break }
        candidate = parent
      }
    }

    #if DEBUG
      // Xcode development fallback (running directly from Xcode rather than
      // via run.sh, where cwd-based detection above already succeeds).
      // #filePath deliberately excluded from release builds: it embeds this
      // machine's absolute checkout path as a literal string in the compiled
      // binary, which Scripts/check-path-leakage.sh correctly flags as a
      // packager-identity leak. #if DEBUG keeps that string out of release
      // builds entirely, rather than trying to strip it after the fact —
      // it isn't debug-info metadata that `strip` would remove, since the
      // fallback logic actually uses the string at runtime.
      let sourceRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // AirPortUtilityCore
        .deletingLastPathComponent()  // Sources
        .deletingLastPathComponent()  // Repository root

      if fileManager.fileExists(
        atPath: sourceRoot.appendingPathComponent("backend/airport_backend.py").path
      ) {
        return sourceRoot.path
      }
    #endif

    return currentURL.path
  }
  private static func containsBackendScripts(
    _ url: URL,
    fileManager: FileManager
  ) -> Bool {
    // A source checkout ships backend/airport_backend.py directly. A packaged
    // release build (see build-app.sh, ADR-0001) instead ships only the
    // frozen self-contained executable at
    // backend/airportbackend/airportbackend, with no .py sources at all —
    // both must be recognized as "this is a valid backend location."
    fileManager.fileExists(
      atPath: url.appendingPathComponent("backend/airport_backend.py").path
    )
      || fileManager.isExecutableFile(
        atPath: url.appendingPathComponent("backend/airportbackend/airportbackend").path
      )
  }
}
struct WirelessClient: Codable, Equatable, Identifiable, Sendable {
  var macAddress: String
  var ipAddress: String
  var hostname: String
  var rssi: Int? = nil
  var noise: Int? = nil
  var dataRateMbps: Double? = nil
  var phyMode: String? = nil

  var id: String { macAddress }

  var advertisedHostname: String? {
    let hostname = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
    return hostname.isEmpty ? nil : hostname
  }

  var displayName: String {
    if let hostname = advertisedHostname {
      return hostname
    }
    let ipAddress = ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    if !ipAddress.isEmpty {
      return ipAddress
    }
    return macAddress.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var detailRows: [WirelessClientDetailRow] {
    [
      WirelessClientDetailRow(
        label: "hardware address",
        value: detailMACAddress),
      WirelessClientDetailRow(
        label: "quality",
        value: qualityLabel),
      WirelessClientDetailRow(
        label: "data rate",
        value: dataRateLabel),
      WirelessClientDetailRow(
        label: "RSSI",
        value: rssiLabel),
      WirelessClientDetailRow(
        label: "SNR",
        value: snrLabel),
      WirelessClientDetailRow(
        label: "PHY mode",
        value: phyModeLabel),
      WirelessClientDetailRow(
        label: "band",
        value: bandLabel),
    ]
  }

  private var normalizedRSSI: Int? {
    guard let rssi else { return nil }
    return rssi > 0 ? rssi - 100 : rssi
  }

  private var detailMACAddress: String {
    let address = macAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    return address.isEmpty ? "Unknown" : address.uppercased()
  }

  private var qualityLabel: String {
    guard let rssi = normalizedRSSI else { return "Unknown" }
    switch rssi {
    case ..<(-99): return "Poor"
    case -99...(-90): return "Fair"
    case -89...(-83): return "Average"
    case -82...(-71): return "Good"
    default: return "Excellent"
    }
  }

  private var dataRateLabel: String {
    guard
      let dataRateMbps,
      dataRateMbps.isFinite,
      dataRateMbps >= 0,
      dataRateMbps < Double(Int.max)
    else {
      return "Unknown"
    }
    let value =
      dataRateMbps.rounded() == dataRateMbps
      ? String(Int(dataRateMbps))
      : String(format: "%g", dataRateMbps)
    return "\(value) Mb/s"
  }

  private var rssiLabel: String {
    guard let rssi = normalizedRSSI else { return "Unknown" }
    return "\(rssi) dBm"
  }

  private var phyModeLabel: String {
    let mode = phyMode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return mode.isEmpty ? "Unknown" : mode
  }

  private var snrLabel: String {
    guard let normalizedRSSI, let noise else { return "Unknown" }
    return "\(normalizedRSSI - noise) dB"
  }

  /// 802.11a and 802.11ac are 5 GHz-only standards; 802.11b and 802.11g are
  /// 2.4 GHz-only. 802.11n/ax operate on both bands, so their presence alone
  /// (without an exclusive marker for either band) is genuinely ambiguous -
  /// reported as unknown rather than guessed, matching the AirPort's own
  /// "802.11n (802.11a/b/g compatible)" convention for disambiguating it.
  private var bandLabel: String {
    guard let phyMode else { return "Unknown" }
    let tokens =
      phyMode
      .replacingOccurrences(of: "802.11", with: "")
      .lowercased()
      .split(separator: "/")
    guard !tokens.isEmpty else { return "Unknown" }
    let fiveGHzOnlyMarkers: Set<Substring> = ["a", "ac"]
    let twoPointFourGHzOnlyMarkers: Set<Substring> = ["b", "g"]
    let hasFiveGHzMarker = tokens.contains { fiveGHzOnlyMarkers.contains($0) }
    let hasTwoPointFourGHzMarker = tokens.contains { twoPointFourGHzOnlyMarkers.contains($0) }
    if hasFiveGHzMarker && !hasTwoPointFourGHzMarker { return "5 GHz" }
    if hasTwoPointFourGHzMarker && !hasFiveGHzMarker { return "2.4 GHz" }
    return "Unknown"
  }
}

struct WirelessClientDetailRow: Equatable, Sendable {
  var label: String
  var value: String
}

struct CommandResult: Equatable, Sendable {
  var arguments: [String]
  var redactedArguments: [String]
  var stdout: String
  var stderr: String
  var exitCode: Int32

  init(
    arguments: [String], redactedArguments: [String], stdout: String, stderr: String,
    exitCode: Int32
  ) {
    self.arguments = arguments
    self.redactedArguments = redactedArguments
    self.stdout = stdout
    self.stderr = stderr
    self.exitCode = exitCode
  }

  var succeeded: Bool { exitCode == 0 }
  var combinedOutput: String {
    [stdout, stderr].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(
      separator: "\n")
  }
}

struct CommandPreview: Equatable, Sendable {
  var title: String
  var arguments: [String]
  var redactedArguments: [String]
  var output: String
}

enum Pane: String, CaseIterable, Identifiable, Sendable, Codable {
  case baseStation = "Base Station"
  case internet = "Internet"
  case wireless = "Wireless"
  case network = "Network"
  case airPlay = "AirPlay"
  case disks = "Disks"
  case advanced = "Advanced"
  case firmware = "Firmware"
  case diagnostics = "Diagnostics"

  var id: String { rawValue }
}

enum ConnectUsing: String, CaseIterable, Identifiable, Sendable, Codable {
  case dhcp
  case `static`
  case pppoe
  case modem

  var id: String { rawValue }
  var label: String {
    switch self {
    case .dhcp: "DHCP"
    case .static: "Static"
    case .pppoe: "PPPoE"
    case .modem: "Modem"
    }
  }
}

enum RouterMode: String, CaseIterable, Identifiable, Sendable, Codable {
  case dhcpAndNat = "dhcp-and-nat"
  case dhcpOnly = "dhcp-only"
  case natOnly = "nat-only"
  case bridge

  var id: String { rawValue }
  var label: String {
    switch self {
    case .dhcpAndNat: "DHCP and NAT"
    case .dhcpOnly: "DHCP Only"
    case .natOnly: "NAT Only"
    case .bridge: "Off (Bridge Mode)"
    }
  }
}

enum EraseMethod: String, CaseIterable, Identifiable, Sendable {
  case quick
  case zero
  case sevenPass = "7-pass"
  case thirtyFivePass = "35-pass"

  var id: String { rawValue }
  var label: String {
    switch self {
    case .quick: "Quick Erase"
    case .zero: "Zero Out Data"
    case .sevenPass: "7-Pass Erase"
    case .thirtyFivePass: "35-Pass Erase"
    }
  }
}

struct BaseStationState: Equatable, Codable {
  var name = ""
  var serialNumber = ""
  var version = ""
  var productID = ""
  var statusText = "Working normally"
  var problemCodes: [String] = []
  var newAdminPassword = ""
  var verifyAdminPassword = ""
  var rememberPassword = true
  var allowSetupOverWAN = false
  var advancedACPSettingsJSON = ""

  init(
    name: String = "",
    serialNumber: String = "",
    version: String = "",
    productID: String = "",
    statusText: String = "Working normally",
    problemCodes: [String] = [],
    newAdminPassword: String = "",
    verifyAdminPassword: String = "",
    rememberPassword: Bool = true,
    allowSetupOverWAN: Bool = false,
    advancedACPSettingsJSON: String = ""
  ) {
    self.name = name
    self.serialNumber = serialNumber
    self.version = version
    self.productID = productID
    self.statusText = statusText
    self.problemCodes = problemCodes
    self.newAdminPassword = newAdminPassword
    self.verifyAdminPassword = verifyAdminPassword
    self.rememberPassword = rememberPassword
    self.allowSetupOverWAN = allowSetupOverWAN
    self.advancedACPSettingsJSON = advancedACPSettingsJSON
  }

  enum CodingKeys: String, CodingKey {
    case name
    case serialNumber
    case version
    case productID
    case statusText
    case problemCodes
    case newAdminPassword
    case verifyAdminPassword
    case rememberPassword
    case allowSetupOverWAN
    case advancedACPSettingsJSON
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
    serialNumber = try container.decodeIfPresent(String.self, forKey: .serialNumber) ?? ""
    version = try container.decodeIfPresent(String.self, forKey: .version) ?? ""
    productID = try container.decodeIfPresent(String.self, forKey: .productID) ?? ""
    statusText =
      try container.decodeIfPresent(String.self, forKey: .statusText) ?? "Working normally"
    problemCodes = try container.decodeIfPresent([String].self, forKey: .problemCodes) ?? []
    newAdminPassword = try container.decodeIfPresent(String.self, forKey: .newAdminPassword) ?? ""
    verifyAdminPassword =
      try container.decodeIfPresent(String.self, forKey: .verifyAdminPassword) ?? ""
    rememberPassword = try container.decodeIfPresent(Bool.self, forKey: .rememberPassword) ?? true
    allowSetupOverWAN =
      try container.decodeIfPresent(Bool.self, forKey: .allowSetupOverWAN) ?? false
    advancedACPSettingsJSON =
      try container.decodeIfPresent(String.self, forKey: .advancedACPSettingsJSON) ?? ""
  }
}

struct InternetState: Equatable, Codable {
  var connectUsing: ConnectUsing = .dhcp
  var ipv4Address = ""
  var subnetMask = ""
  var routerAddress = ""
  var dnsServers = ""
  var dnsServerPreview = ""
  var domainName = ""
  var ipv6Address = ""
  var ipv6DNSServers = ""
  var ipv6DNSServerPreview = ""
  var pppoeAccount = ""
  var pppoePassword = ""
  var pppoeService = ""
  var pppoeConnection = "always-on"
  var configureIPv6 = "link-local"
  var ipv6Mode = ""
  var ipv6DefaultRoute = ""
  var ipv6Firewall = false
  var dynamicGlobalHostname = false
  var dynamicGlobalHostnameAutoConfig = false
  var globalHostname = ""
  var globalHostnameUser = ""
  var globalHostnamePassword = ""
  var modemPhoneNumber = ""
  var modemAlternateNumber = ""
  var modemAccount = ""
  var modemPassword = ""
  var modemVerifyPassword = ""
  var modemIdleSeconds = 600
  var modemCountryCode = 36
  var modemProtocol = "v90"
  var modemPulseDialing = false
  var modemAutomaticallyDial = true
  var modemIgnoreDialTone = false
  var modemUseAOL = false
}

struct ModemIdleOption: Identifiable, Equatable, Sendable {
  var id: Int { seconds }
  let seconds: Int
  let label: String

  static let allCases = [
    ModemIdleOption(seconds: 0, label: "Never"),
    ModemIdleOption(seconds: 30, label: "30 seconds"),
    ModemIdleOption(seconds: 60, label: "1 minute"),
    ModemIdleOption(seconds: 120, label: "2 minutes"),
    ModemIdleOption(seconds: 300, label: "5 minutes"),
    ModemIdleOption(seconds: 600, label: "10 minutes"),
    ModemIdleOption(seconds: 900, label: "15 minutes"),
    ModemIdleOption(seconds: 1_200, label: "20 minutes"),
    ModemIdleOption(seconds: 1_800, label: "30 minutes"),
  ]
}

struct ModemCountryOption: Identifiable, Equatable, Sendable {
  var id: Int { code }
  let code: Int
  let name: String

  static let allCases: [ModemCountryOption] = [
    "Australia", "Austria", "Belgium", "Canada", "China", "Czech Republic", "Denmark",
    "Finland", "France", "Germany", "Greece", "Guam", "Hong Kong S.A.R., China",
    "Iceland", "India", "Ireland", "Italy", "Japan", "Latin America", "Malaysia",
    "Netherlands", "New Zealand", "Norway", "Philippines", "Poland", "Portugal",
    "Republic of Korea", "Singapore", "Slovak Republic", "South Africa", "Spain",
    "Sweden", "Switzerland", "Taiwan", "Thailand", "United Kingdom", "United States",
  ].enumerated().map { ModemCountryOption(code: $0.offset, name: $0.element) }
}

struct PPPoEConnectionOption: Identifiable, Equatable, Sendable {
  var id: String { value }
  let value: String
  let label: String

  static let allCases: [PPPoEConnectionOption] = [
    PPPoEConnectionOption(value: "always-on", label: "Always On"),
    PPPoEConnectionOption(value: "automatic", label: "Automatic"),
    PPPoEConnectionOption(value: "manual", label: "Manual"),
  ]
}

struct HostInternetState: Equatable, Sendable, Codable {
  var connectionStatus = ""
  var routerAddress = ""
  var dnsServers = ""
  var isLoading = false
}

struct WirelessState: Equatable, Codable {
  var mode = "create"
  var networkName = ""
  var security = "wpa2-personal"
  var password = ""
  var verifyPassword = ""
  var allowNetworkExtension = false
  var wdsMode = "remote"
  var wdsPeerAirPortIDs = ""
  var regionCode = "0"
  var hiddenNetwork = false
  var radioMode = "80211n-bg"
  var radioChannel = "automatic"
}

enum WirelessSecurityOption: String, CaseIterable, Identifiable, Sendable {
  case none
  case wep40 = "wep-40"
  case wepTransitional = "wep-128"
  case wpaPersonal = "wpa-personal"
  case wpaWPA2Personal = "wpa-wpa2-personal"
  case wpa2Personal = "wpa2-personal"
  case wpaWPA2Enterprise = "wpa-wpa2-enterprise"
  case wpa2Enterprise = "wpa2-enterprise"

  var id: String { rawValue }

  var label: String {
    switch self {
    case .none:
      "None"
    case .wep40:
      "WEP 40-bit"
    case .wepTransitional:
      "WEP (Transitional Security Network)"
    case .wpaPersonal:
      "WPA Personal"
    case .wpaWPA2Personal:
      "WPA/WPA2 Personal"
    case .wpa2Personal:
      "WPA2 Personal"
    case .wpaWPA2Enterprise:
      "WPA/WPA2 Enterprise"
    case .wpa2Enterprise:
      "WPA2 Enterprise"
    }
  }
}

struct WirelessRadioModeOption: Identifiable, Equatable, Sendable {
  var id: String { value }
  let value: String
  let label: String

  static let allCases: [WirelessRadioModeOption] = [
    WirelessRadioModeOption(value: "80211b", label: "802.11b"),
    WirelessRadioModeOption(value: "80211bg", label: "802.11b/g compatible"),
    WirelessRadioModeOption(value: "80211g", label: "802.11g"),
    WirelessRadioModeOption(value: "80211a", label: "802.11a"),
    WirelessRadioModeOption(value: "80211n-a", label: "802.11n (802.11a compatible)"),
    WirelessRadioModeOption(value: "80211n-bg", label: "802.11n (802.11b/g compatible)"),
    WirelessRadioModeOption(value: "80211n-only-24", label: "802.11n only (2.4 GHz)"),
    WirelessRadioModeOption(value: "80211n-only-5", label: "802.11n only (5 GHz)"),
  ]

  static func options(including value: String) -> [WirelessRadioModeOption] {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !allCases.contains(where: { $0.value == trimmed }) else {
      return allCases
    }
    return [WirelessRadioModeOption(value: trimmed, label: "Current (\(trimmed))")] + allCases
  }
}

struct WirelessRegionOption: Identifiable, Equatable, Sendable {
  var code: String
  var name: String

  var id: String { code }

  static let allCases = [
    WirelessRegionOption(code: "0", name: "United States"),
    WirelessRegionOption(code: "1", name: "Canada"),
    WirelessRegionOption(code: "2", name: "Mexico"),
    WirelessRegionOption(code: "3", name: "Colombia"),
    WirelessRegionOption(code: "4", name: "Puerto Rico"),
    WirelessRegionOption(code: "5", name: "Brazil"),
    WirelessRegionOption(code: "6", name: "Chile"),
    WirelessRegionOption(code: "7", name: "Japan"),
    WirelessRegionOption(code: "8", name: "Austria"),
    WirelessRegionOption(code: "9", name: "Belgium"),
    WirelessRegionOption(code: "10", name: "Cyprus"),
    WirelessRegionOption(code: "11", name: "Czech Republic"),
    WirelessRegionOption(code: "12", name: "Denmark"),
    WirelessRegionOption(code: "13", name: "Estonia"),
    WirelessRegionOption(code: "14", name: "France"),
    WirelessRegionOption(code: "15", name: "Finland"),
    WirelessRegionOption(code: "16", name: "Germany"),
    WirelessRegionOption(code: "17", name: "Greece"),
    WirelessRegionOption(code: "18", name: "Hungary"),
    WirelessRegionOption(code: "19", name: "Iceland"),
    WirelessRegionOption(code: "20", name: "Italy"),
    WirelessRegionOption(code: "21", name: "Ireland"),
    WirelessRegionOption(code: "22", name: "Latvia"),
    WirelessRegionOption(code: "23", name: "Liechtenstein"),
    WirelessRegionOption(code: "24", name: "Lithuania"),
    WirelessRegionOption(code: "25", name: "Luxembourg"),
    WirelessRegionOption(code: "26", name: "Malta"),
    WirelessRegionOption(code: "27", name: "Netherlands"),
    WirelessRegionOption(code: "28", name: "Norway"),
    WirelessRegionOption(code: "29", name: "Poland"),
    WirelessRegionOption(code: "30", name: "Portugal"),
    WirelessRegionOption(code: "31", name: "Slovak Republic"),
    WirelessRegionOption(code: "32", name: "Slovenia"),
    WirelessRegionOption(code: "33", name: "Spain"),
    WirelessRegionOption(code: "34", name: "Sweden"),
    WirelessRegionOption(code: "35", name: "Switzerland"),
    WirelessRegionOption(code: "36", name: "United Kingdom"),
    WirelessRegionOption(code: "37", name: "Australia"),
    WirelessRegionOption(code: "38", name: "Hong Kong S.A.R., China"),
    WirelessRegionOption(code: "39", name: "New Zealand"),
    WirelessRegionOption(code: "40", name: "Singapore"),
    WirelessRegionOption(code: "41", name: "Philippines"),
    WirelessRegionOption(code: "42", name: "China"),
    WirelessRegionOption(code: "43", name: "Malaysia"),
    WirelessRegionOption(code: "44", name: "Taiwan"),
    WirelessRegionOption(code: "45", name: "South Korea"),
    WirelessRegionOption(code: "46", name: "Thailand"),
    WirelessRegionOption(code: "47", name: "Argentina"),
    WirelessRegionOption(code: "48", name: "Venezuela"),
    WirelessRegionOption(code: "49", name: "Russia"),
    WirelessRegionOption(code: "50", name: "United States"),
    WirelessRegionOption(code: "51", name: "Canada"),
    WirelessRegionOption(code: "52", name: "Bulgaria"),
    WirelessRegionOption(code: "53", name: "Romania"),
    WirelessRegionOption(code: "54", name: "India"),
    WirelessRegionOption(code: "55", name: "Vietnam"),
    WirelessRegionOption(code: "56", name: "Sri Lanka"),
    WirelessRegionOption(code: "57", name: "Brunei"),
    WirelessRegionOption(code: "58", name: "Pakistan"),
    WirelessRegionOption(code: "59", name: "Nepal"),
    WirelessRegionOption(code: "60", name: "Bangladesh"),
    WirelessRegionOption(code: "61", name: "Peru"),
    WirelessRegionOption(code: "62", name: "Afghanistan"),
    WirelessRegionOption(code: "63", name: "Albania"),
    WirelessRegionOption(code: "64", name: "Algeria"),
    WirelessRegionOption(code: "65", name: "American Samoa"),
    WirelessRegionOption(code: "66", name: "Andorra"),
    WirelessRegionOption(code: "67", name: "Angola"),
    WirelessRegionOption(code: "68", name: "Anguilla"),
    WirelessRegionOption(code: "69", name: "Antarctica"),
    WirelessRegionOption(code: "70", name: "Antigua And Barbuda"),
    WirelessRegionOption(code: "71", name: "Armenia"),
    WirelessRegionOption(code: "72", name: "Aruba"),
    WirelessRegionOption(code: "73", name: "Azerbaijan"),
    WirelessRegionOption(code: "74", name: "Bahamas"),
    WirelessRegionOption(code: "75", name: "Bahrain"),
    WirelessRegionOption(code: "76", name: "Barbados"),
    WirelessRegionOption(code: "77", name: "Belarus"),
    WirelessRegionOption(code: "78", name: "Belize"),
    WirelessRegionOption(code: "79", name: "Benin"),
    WirelessRegionOption(code: "80", name: "Bermuda"),
    WirelessRegionOption(code: "81", name: "Bhutan"),
    WirelessRegionOption(code: "82", name: "Bolivia"),
    WirelessRegionOption(code: "83", name: "Bosnia Herzegovina"),
    WirelessRegionOption(code: "84", name: "Botswana"),
    WirelessRegionOption(code: "85", name: "Bouvet Island"),
    WirelessRegionOption(code: "86", name: "British Indian Ocean Territory"),
    WirelessRegionOption(code: "87", name: "Burkina Faso"),
    WirelessRegionOption(code: "88", name: "Burundi"),
    WirelessRegionOption(code: "89", name: "Cambodia"),
    WirelessRegionOption(code: "90", name: "Cameroon"),
    WirelessRegionOption(code: "91", name: "Cape Verde"),
    WirelessRegionOption(code: "92", name: "Cayman Islands"),
    WirelessRegionOption(code: "93", name: "Central African Republic"),
    WirelessRegionOption(code: "94", name: "Chad"),
    WirelessRegionOption(code: "95", name: "Christmas Island"),
    WirelessRegionOption(code: "96", name: "Cocos Islands"),
    WirelessRegionOption(code: "97", name: "Comoros"),
    WirelessRegionOption(code: "98", name: "Congo"),
    WirelessRegionOption(code: "99", name: "Cook Islands"),
    WirelessRegionOption(code: "100", name: "Costa Rica"),
    WirelessRegionOption(code: "101", name: "Ivory Coast"),
    WirelessRegionOption(code: "102", name: "Croatia"),
    WirelessRegionOption(code: "103", name: "Djibouti"),
    WirelessRegionOption(code: "104", name: "Dominica"),
    WirelessRegionOption(code: "105", name: "Dominican Republic"),
    WirelessRegionOption(code: "106", name: "East Timor"),
    WirelessRegionOption(code: "107", name: "Ecuador"),
    WirelessRegionOption(code: "108", name: "Egypt"),
    WirelessRegionOption(code: "109", name: "El Salvador"),
    WirelessRegionOption(code: "110", name: "Equatorial Guinea"),
    WirelessRegionOption(code: "111", name: "Eritrea"),
    WirelessRegionOption(code: "112", name: "Ethiopia"),
    WirelessRegionOption(code: "113", name: "Falkland Islands"),
    WirelessRegionOption(code: "114", name: "Faroe Islands"),
    WirelessRegionOption(code: "115", name: "Fiji"),
    WirelessRegionOption(code: "116", name: "French Guiana"),
    WirelessRegionOption(code: "117", name: "French Polynesia"),
    WirelessRegionOption(code: "118", name: "French Southern Territories"),
    WirelessRegionOption(code: "119", name: "Gabon"),
    WirelessRegionOption(code: "120", name: "Gambia"),
    WirelessRegionOption(code: "121", name: "Georgia"),
    WirelessRegionOption(code: "122", name: "Ghana"),
    WirelessRegionOption(code: "123", name: "Gibraltar"),
    WirelessRegionOption(code: "124", name: "Greenland"),
    WirelessRegionOption(code: "125", name: "Grenada"),
    WirelessRegionOption(code: "126", name: "Guadeloupe"),
    WirelessRegionOption(code: "127", name: "Guam"),
    WirelessRegionOption(code: "128", name: "Guatemala"),
    WirelessRegionOption(code: "129", name: "Guinea"),
    WirelessRegionOption(code: "130", name: "Guinea Bissau"),
    WirelessRegionOption(code: "131", name: "Guyana"),
    WirelessRegionOption(code: "132", name: "Haiti"),
    WirelessRegionOption(code: "133", name: "Honduras"),
    WirelessRegionOption(code: "134", name: "Indonesia"),
    WirelessRegionOption(code: "135", name: "Iran"),
    WirelessRegionOption(code: "136", name: "Iraq"),
    WirelessRegionOption(code: "137", name: "Israel"),
    WirelessRegionOption(code: "138", name: "Jamaica"),
    WirelessRegionOption(code: "139", name: "Jordan"),
    WirelessRegionOption(code: "140", name: "Kazakhstan"),
    WirelessRegionOption(code: "141", name: "Kenya"),
    WirelessRegionOption(code: "142", name: "North Korea"),
    WirelessRegionOption(code: "143", name: "Kuwait"),
    WirelessRegionOption(code: "144", name: "Lebanon"),
    WirelessRegionOption(code: "145", name: "Libya"),
    WirelessRegionOption(code: "146", name: "Macau"),
    WirelessRegionOption(code: "147", name: "Macedonia"),
    WirelessRegionOption(code: "148", name: "Monaco"),
    WirelessRegionOption(code: "149", name: "Morocco"),
    WirelessRegionOption(code: "150", name: "Nicaragua"),
    WirelessRegionOption(code: "151", name: "Oman"),
    WirelessRegionOption(code: "152", name: "Qatar"),
    WirelessRegionOption(code: "153", name: "Saudi Arabia"),
    WirelessRegionOption(code: "154", name: "South Africa"),
    WirelessRegionOption(code: "155", name: "Syria"),
    WirelessRegionOption(code: "156", name: "Trinidad And Tobago"),
    WirelessRegionOption(code: "157", name: "Tunisia"),
    WirelessRegionOption(code: "158", name: "Turkey"),
    WirelessRegionOption(code: "159", name: "United Arab Emirates"),
    WirelessRegionOption(code: "160", name: "Ukraine"),
    WirelessRegionOption(code: "161", name: "Uruguay"),
    WirelessRegionOption(code: "162", name: "Uzbekistan"),
    WirelessRegionOption(code: "163", name: "Yemen"),
    WirelessRegionOption(code: "164", name: "Zimbabwe"),
    WirelessRegionOption(code: "166", name: "Serbia"),
    WirelessRegionOption(code: "167", name: "Laos"),
    WirelessRegionOption(code: "168", name: "Maldives"),
    WirelessRegionOption(code: "169", name: "Mongolia"),
    WirelessRegionOption(code: "170", name: "US Virgin Islands"),
    WirelessRegionOption(code: "171", name: "Panama"),
    WirelessRegionOption(code: "172", name: "Myanmar"),
  ]
}

struct LiveWirelessSettings: Equatable, Codable {
  var mode: String?
  var networkName: String?
  var security: String?
  var regionCode: String?
  var hiddenNetwork: Bool?
  var radioMode: String?
  var radioChannel: String?
  var allowNetworkExtension: Bool?
  var wdsMode: String?
  var wdsPeerAirPortIDs: String?
}

struct NetworkState: Equatable, Codable {
  var lanIPAddress = ""
  var routerMode: RouterMode = .bridge
  var dhcpRangeStart = ""
  var dhcpRangeEnd = ""
  var natPMP = false
  var dhcpLease = "1"
  var dhcpLeaseUnit = "days"
  var defaultHost = ""
}

struct DHCPLeaseUnitOption: Identifiable, Equatable, Sendable {
  var id: String { value }
  let value: String
  let label: String

  static let allCases: [DHCPLeaseUnitOption] = [
    DHCPLeaseUnitOption(value: "seconds", label: "second"),
    DHCPLeaseUnitOption(value: "minutes", label: "minute"),
    DHCPLeaseUnitOption(value: "hours", label: "hour"),
    DHCPLeaseUnitOption(value: "days", label: "day"),
    DHCPLeaseUnitOption(value: "weeks", label: "week"),
  ]
}

struct DiskAccount: Identifiable, Equatable, Sendable, Codable {
  var id = UUID().uuidString
  var name = ""
  var password = ""
  var verifyPassword = ""
  var access = "read-write"
}

struct DisksState: Equatable, Codable {
  var fileSharing = false
  var secureSharedDisks = "device-password"
  var guestAccess = "not-allowed"
  var shareOverWAN = false
  var diskPassword = ""
  var verifyDiskPassword = ""
  var rememberPassword = true
  var windowsWorkgroup = ""
  var winsServer = ""
  var inventory: [DiskRecord] = []
  var selectedDiskID = ""
  var fileSharingAccounts: [DiskAccount] = []
  var selectedFileSharingAccountID = ""
  var rawInventory = ""
  var didLoadInventory = false
}

struct AirPlayState: Equatable, Codable {
  var enabled = false
  var speakerName = ""
  var speakerPassword = ""
  var verifySpeakerPassword = ""
  var rememberPassword = true
  var overWAN = false
}

struct AdvancedState: Equatable, Codable {
  var syslogDestinationAddress = ""
  var syslogLevel = 5
  var allowSNMP = true
  var allowSNMPOverWAN = false
  var pppDialInEnabled = false
  var pppDialInAccount = ""
  var pppDialInPassword = ""
  var pppDialInVerifyPassword = ""
  var pppDialInAnswerOnRing = 3
  var pppDialInIdleSeconds = 0
  var pppDialInMaximumConnectSeconds = 0
}

struct LegacyBaseStationOptionsState: Equatable, Codable {
  var contact = ""
  var location = ""
  var setTimeAutomatically = false
  var timeServer = ""
}

struct LegacyWirelessOptionsState: Equatable, Codable {
  var multicastRate = 2
  var transmitPower = 100
  var groupKeyTimeoutSeconds = 3_600
  var interferenceRobustness = false
}

struct LegacyDHCPOptionsState: Equatable, Codable {
  var message = ""
  var ldapServer = ""
}

struct AccessControlEntry: Identifiable, Equatable, Codable {
  var id = UUID()
  var macAddress = ""
  var description = ""
}

struct LegacyAccessControlState: Equatable, Codable {
  var mode = "not-enabled"
  var entries: [AccessControlEntry] = []
  var radiusType = "default"
  var primaryAddress = ""
  var primarySecret = ""
  var primaryVerifySecret = ""
  var primaryPort = 1_812
  var secondaryAddress = ""
  var secondarySecret = ""
  var secondaryVerifySecret = ""
  var secondaryPort = 1_812
}

struct LegacyDeviceOptionsState: Equatable, Codable {
  var baseStation = LegacyBaseStationOptionsState()
  var wireless = LegacyWirelessOptionsState()
  var dhcp = LegacyDHCPOptionsState()
  var accessControl = LegacyAccessControlState()
}

struct LiveAdvancedSettings: Equatable, Codable {
  var syslogDestinationAddress: String?
  var syslogLevel: Int?
  var snmpAccessFlags: Int?
  var pppDialInEnabled: Bool?
  var pppDialInAccount: String?
  var pppDialInPassword: String?
  var pppDialInAnswerOnRing: Int?
  var pppDialInIdleSeconds: Int?
  var pppDialInMaximumConnectSeconds: Int?
}

struct SyslogLevelOption: Identifiable, Equatable, Sendable {
  var id: Int { level }
  let level: Int
  let label: String

  static let allCases = [
    SyslogLevelOption(level: 0, label: "0 - Emergency"),
    SyslogLevelOption(level: 1, label: "1 - Alert"),
    SyslogLevelOption(level: 2, label: "2 - Critical"),
    SyslogLevelOption(level: 3, label: "3 - Error"),
    SyslogLevelOption(level: 4, label: "4 - Warning"),
    SyslogLevelOption(level: 5, label: "5 - Notice"),
    SyslogLevelOption(level: 6, label: "6 - Informational"),
    SyslogLevelOption(level: 7, label: "7 - Debug"),
  ]
}

struct PPPDialInMaximumConnectOption: Identifiable, Equatable, Sendable {
  var id: Int { seconds }
  let seconds: Int
  let label: String

  static let allCases = [
    PPPDialInMaximumConnectOption(seconds: 0, label: "Never Disconnect"),
    PPPDialInMaximumConnectOption(seconds: 900, label: "15 minutes"),
    PPPDialInMaximumConnectOption(seconds: 1_800, label: "30 minutes"),
    PPPDialInMaximumConnectOption(seconds: 3_600, label: "1 hour"),
    PPPDialInMaximumConnectOption(seconds: 7_200, label: "2 hours"),
    PPPDialInMaximumConnectOption(seconds: 14_400, label: "4 hours"),
    PPPDialInMaximumConnectOption(seconds: 28_800, label: "8 hours"),
  ]
}

struct MulticastRateOption: Identifiable, Equatable, Sendable {
  var id: Int { value }
  let value: Int
  let label: String

  static let allCases = [
    MulticastRateOption(value: 1, label: "1 Mbps"),
    MulticastRateOption(value: 2, label: "2 Mbps"),
    MulticastRateOption(value: 85, label: "5.5 Mbps"),
    MulticastRateOption(value: 6, label: "6 Mbps"),
    MulticastRateOption(value: 9, label: "9 Mbps"),
    MulticastRateOption(value: 17, label: "11 Mbps"),
    MulticastRateOption(value: 18, label: "12 Mbps"),
    MulticastRateOption(value: 24, label: "18 Mbps"),
    MulticastRateOption(value: 36, label: "24 Mbps"),
    MulticastRateOption(value: 1_000, label: "Low"),
    MulticastRateOption(value: 2_000, label: "Medium"),
    MulticastRateOption(value: 3_000, label: "High"),
  ]
}

struct TransmitPowerOption: Identifiable, Equatable, Sendable {
  var id: Int { percent }
  let percent: Int
  var label: String { "\(percent)%" }

  static let allCases = [10, 25, 50, 100].map(TransmitPowerOption.init(percent:))
}

struct DeviceCapabilities: Equatable, Codable {
  var supportsAirPlay = false
  var supportsDisks = false
  var supportsFirmware = false
  var supportsIPv6 = true
  var supportsDynamicGlobalHostname = true
  var supportsClassicWDS = false
  var supportsModem = false
  var supportsLogging = false
  var supportsPPPDialIn = false
  var supportsBaseStationMetadata = false
  var supportsLegacyWirelessOptions = false
  var supportsLegacyDHCPOptions = false
  var supportsAccessControl = false

  var supportsInternetOptions: Bool {
    supportsIPv6 || supportsDynamicGlobalHostname
  }

  init(
    supportsAirPlay: Bool = false,
    supportsDisks: Bool = false,
    supportsFirmware: Bool = false,
    supportsIPv6: Bool = true,
    supportsDynamicGlobalHostname: Bool = true,
    supportsClassicWDS: Bool = false,
    supportsModem: Bool = false,
    supportsLogging: Bool = false,
    supportsPPPDialIn: Bool = false,
    supportsBaseStationMetadata: Bool = false,
    supportsLegacyWirelessOptions: Bool = false,
    supportsLegacyDHCPOptions: Bool = false,
    supportsAccessControl: Bool = false
  ) {
    self.supportsAirPlay = supportsAirPlay
    self.supportsDisks = supportsDisks
    self.supportsFirmware = supportsFirmware
    self.supportsIPv6 = supportsIPv6
    self.supportsDynamicGlobalHostname = supportsDynamicGlobalHostname
    self.supportsClassicWDS = supportsClassicWDS
    self.supportsModem = supportsModem
    self.supportsLogging = supportsLogging
    self.supportsPPPDialIn = supportsPPPDialIn
    self.supportsBaseStationMetadata = supportsBaseStationMetadata
    self.supportsLegacyWirelessOptions = supportsLegacyWirelessOptions
    self.supportsLegacyDHCPOptions = supportsLegacyDHCPOptions
    self.supportsAccessControl = supportsAccessControl
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    supportsAirPlay = try container.decodeIfPresent(Bool.self, forKey: .supportsAirPlay) ?? false
    supportsDisks = try container.decodeIfPresent(Bool.self, forKey: .supportsDisks) ?? false
    supportsFirmware = try container.decodeIfPresent(Bool.self, forKey: .supportsFirmware) ?? false
    supportsIPv6 = try container.decodeIfPresent(Bool.self, forKey: .supportsIPv6) ?? true
    supportsDynamicGlobalHostname =
      try container.decodeIfPresent(Bool.self, forKey: .supportsDynamicGlobalHostname) ?? true
    supportsClassicWDS =
      try container.decodeIfPresent(Bool.self, forKey: .supportsClassicWDS) ?? false
    supportsModem = try container.decodeIfPresent(Bool.self, forKey: .supportsModem) ?? false
    supportsLogging = try container.decodeIfPresent(Bool.self, forKey: .supportsLogging) ?? false
    supportsPPPDialIn =
      try container.decodeIfPresent(Bool.self, forKey: .supportsPPPDialIn) ?? false
    supportsBaseStationMetadata =
      try container.decodeIfPresent(Bool.self, forKey: .supportsBaseStationMetadata) ?? false
    supportsLegacyWirelessOptions =
      try container.decodeIfPresent(Bool.self, forKey: .supportsLegacyWirelessOptions) ?? false
    supportsLegacyDHCPOptions =
      try container.decodeIfPresent(Bool.self, forKey: .supportsLegacyDHCPOptions) ?? false
    supportsAccessControl =
      try container.decodeIfPresent(Bool.self, forKey: .supportsAccessControl) ?? false
  }

  static func forProductID(_ productID: String) -> DeviceCapabilities {
    let productID = productID.trimmingCharacters(in: .whitespacesAndNewlines)
    return DeviceCapabilities(
      supportsAirPlay: Self.airPlayProductIDs.contains(productID),
      supportsDisks: Self.diskProductIDs.contains(productID),
      supportsFirmware: FirmwareCatalog.supportedProductIDs.contains(productID),
      supportsModem: Self.modemProductIDs.contains(productID),
      supportsLogging: Self.loggingProductIDs.contains(productID),
      supportsPPPDialIn: Self.pppDialInProductIDs.contains(productID),
      supportsBaseStationMetadata: Self.legacyOptionProductIDs.contains(productID),
      supportsLegacyWirelessOptions: Self.legacyOptionProductIDs.contains(productID),
      supportsLegacyDHCPOptions: Self.legacyOptionProductIDs.contains(productID),
      supportsAccessControl: Self.legacyOptionProductIDs.contains(productID)
    )
  }

  private static let airPlayProductIDs: Set<String> = ["102", "107", "115"]
  private static let diskProductIDs: Set<String> = ["106", "109", "113", "116", "119", "120"]
  private static let modemProductIDs: Set<String> = ["3"]
  private static let loggingProductIDs: Set<String> = ["3"]
  private static let pppDialInProductIDs: Set<String> = ["3"]
  private static let legacyOptionProductIDs: Set<String> = ["3"]
}

struct FirmwareImage: Identifiable, Equatable, Sendable, Codable {
  var productID: String
  var version: String
  var sourceVersion: String
  var location: URL
  var sizeInBytes: Int
  var newest: Bool

  var id: String { "\(productID)-\(sourceVersion)-\(version)" }

  var isLocalFile: Bool {
    location.isFileURL
  }

  var displayName: String {
    if isLocalFile {
      return "\(version) (Chosen File)"
    }
    return newest ? "\(version) (Latest)" : version
  }
}

struct FirmwareState: Equatable {
  var currentVersion = ""
  var productID = ""
  var images: [FirmwareImage] = []
  var selectedImageID = ""
  var isLoading = false
  var hasLoadedImages = false
  var lastError = ""
  var installStatus = ""
  var transferProgress = FirmwareTransferProgress()

  var selectedImage: FirmwareImage? {
    images.first { $0.id == selectedImageID } ?? images.first
  }
}

enum FirmwareTransferPhase: String, Equatable, Sendable {
  case none
  case download
  case upload
  case program
  case restart

  var label: String {
    switch self {
    case .none:
      ""
    case .download:
      "Downloading from Apple"
    case .upload:
      "Uploading to AirPort"
    case .program:
      "Preparing on AirPort"
    case .restart:
      "Restarting AirPort"
    }
  }
}

struct FirmwareTransferProgress: Equatable, Sendable {
  var phase: FirmwareTransferPhase = .none
  var completed: Double = 0
  var total: Double = 1
  var detail = ""
  var isIndeterminate = false

  var isVisible: Bool {
    phase != .none
  }

  var fraction: Double? {
    guard !isIndeterminate, total > 0 else { return nil }
    return min(max(completed / total, 0), 1)
  }

  var percentText: String {
    guard let fraction else { return "" }
    return "\(Int((fraction * 100).rounded()))%"
  }

  static func determinate(
    phase: FirmwareTransferPhase,
    completed: Double,
    total: Double,
    detail: String
  ) -> FirmwareTransferProgress {
    FirmwareTransferProgress(
      phase: phase,
      completed: completed,
      total: max(total, 1),
      detail: detail)
  }

  static func byteProgress(
    phase: FirmwareTransferPhase,
    completed: Int64,
    total: Int64
  ) -> FirmwareTransferProgress {
    let safeCompleted = max(completed, 0)
    let safeTotal = max(total, 1)
    return determinate(
      phase: phase,
      completed: Double(safeCompleted),
      total: Double(safeTotal),
      detail: "\(byteCountText(safeCompleted)) of \(byteCountText(safeTotal))")
  }

  private static func byteCountText(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
}

struct AirportSettingsSnapshot: Equatable, Codable {
  var baseStation = BaseStationState()
  var internet = InternetState()
  var wireless = WirelessState()
  var network = NetworkState()
  var airPlay = AirPlayState()
  var disks = DisksState()
  var advanced = AdvancedState()
  var legacyDeviceOptions = LegacyDeviceOptionsState()

  init(
    baseStation: BaseStationState = BaseStationState(),
    internet: InternetState = InternetState(),
    wireless: WirelessState = WirelessState(),
    network: NetworkState = NetworkState(),
    airPlay: AirPlayState = AirPlayState(),
    disks: DisksState = DisksState(),
    advanced: AdvancedState = AdvancedState(),
    legacyDeviceOptions: LegacyDeviceOptionsState = LegacyDeviceOptionsState()
  ) {
    self.baseStation = baseStation
    self.internet = internet
    self.wireless = wireless
    self.network = network
    self.airPlay = airPlay
    self.disks = disks
    self.advanced = advanced
    self.legacyDeviceOptions = legacyDeviceOptions
  }

  enum CodingKeys: String, CodingKey {
    case baseStation
    case internet
    case wireless
    case network
    case airPlay
    case disks
    case advanced
    case legacyDeviceOptions
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    baseStation =
      try container.decodeIfPresent(BaseStationState.self, forKey: .baseStation)
      ?? BaseStationState()
    internet =
      try container.decodeIfPresent(InternetState.self, forKey: .internet)
      ?? InternetState()
    wireless =
      try container.decodeIfPresent(WirelessState.self, forKey: .wireless)
      ?? WirelessState()
    network =
      try container.decodeIfPresent(NetworkState.self, forKey: .network)
      ?? NetworkState()
    airPlay =
      try container.decodeIfPresent(AirPlayState.self, forKey: .airPlay)
      ?? AirPlayState()
    disks = try container.decodeIfPresent(DisksState.self, forKey: .disks) ?? DisksState()
    advanced =
      try container.decodeIfPresent(AdvancedState.self, forKey: .advanced)
      ?? AdvancedState()
    legacyDeviceOptions =
      try container.decodeIfPresent(LegacyDeviceOptionsState.self, forKey: .legacyDeviceOptions)
      ?? LegacyDeviceOptionsState()
  }
}

struct DiskRecord: Identifiable, Equatable, Sendable, Codable {
  var id: String { uuid.isEmpty ? "\(deviceName)-\(name)" : uuid }
  var deviceName: String
  var name: String
  var format: String
  var uuid: String
  var size: Int64?
  var sizeFree: Int64?
  var builtIn: Bool
}

struct AirportDiscoveredDevice: Identifiable, Equatable, Sendable {
  var id: String
  var name: String
  var hostName: String
  var addresses: [String] = []
  var identifiers: [String] = []
  var txtFields: [String: String] = [:]
  var extendsDeviceID: String?
  var modelName: String = ""
  var productID: String = ""
  var statusText: String = ""

  var displayName: String {
    let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if !displayName.isEmpty { return displayName }
    return connectionHost
  }

  var displayModelName: String {
    let modelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
    if !modelName.isEmpty { return modelName }
    return "AirPort Base Station"
  }

  var connectionHost: String {
    let normalizedAddresses =
      addresses
      .map(AirportConnection.normalizedHost)
      .filter { !$0.isEmpty }
    if let ipv4Address = normalizedAddresses.first(where: { $0.contains(".") }) {
      return ipv4Address
    }
    if let address = normalizedAddresses.first {
      return address
    }
    return AirportConnection.normalizedHost(hostName)
  }

  var normalizedConnectionHosts: [String] {
    Self.uniqueNonEmptyValues(([hostName] + addresses).map(AirportConnection.normalizedHost))
  }

  var normalizedStableIdentifiers: [String] {
    Self.uniqueNonEmptyValues(identifiers.map(Self.normalizedStableIdentifier))
  }

  var isNewAirPortDevice: Bool {
    if let flags = txtFields["syfl"].flatMap(Self.txtInteger) {
      return flags & 0x40 != 0
    }
    return false
  }

  var requiresSetup: Bool {
    if isNewAirPortDevice { return true }
    let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.range(
      of: #"^(?:AirPort (?:Express|Extreme|Time Capsule)|Base Station) [0-9a-f]{6}$"#,
      options: [.regularExpression, .caseInsensitive]) != nil
  }

  var problemCodes: [String] {
    guard let problemText = txtFields["prob"] else { return [] }
    return Self.txtProblemCodes(problemText)
  }

  var usesDefaultAdminPassword: Bool {
    isNewAirPortDevice || problemCodes.contains("pubP")
  }

  func matchesConnectionHost(_ host: String) -> Bool {
    let host = AirportConnection.normalizedHost(host)
    return !host.isEmpty && normalizedConnectionHosts.contains(host)
  }

  func sharesConnectionIdentity(with other: AirportDiscoveredDevice) -> Bool {
    let identifiers = Set(normalizedStableIdentifiers)
    if !identifiers.isEmpty && !identifiers.isDisjoint(with: Set(other.normalizedStableIdentifiers))
    {
      return true
    }
    let hosts = Set(normalizedConnectionHosts)
    return !hosts.isEmpty && !hosts.isDisjoint(with: Set(other.normalizedConnectionHosts))
  }

  func sharesStableIdentity(with identifiers: [String]) -> Bool {
    let ownIdentifiers = Set(normalizedStableIdentifiers)
    let otherIdentifiers = Set(
      identifiers
        .map(Self.normalizedStableIdentifier)
        .filter { !$0.isEmpty })
    return !ownIdentifiers.isEmpty && !ownIdentifiers.isDisjoint(with: otherIdentifiers)
  }

  private static func normalizedStableIdentifier(_ identifier: String) -> String {
    identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private static func uniqueNonEmptyValues(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    var unique: [String] = []
    for value in values where !value.isEmpty && !seen.contains(value) {
      seen.insert(value)
      unique.append(value)
    }
    return unique
  }

  private static func txtInteger(_ value: String) -> Int? {
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if text.hasPrefix("0x") {
      return Int(text.dropFirst(2), radix: 16)
    }
    return Int(text)
  }

  private static func txtProblemCodes(_ value: String) -> [String] {
    value
      .replacingOccurrences(of: "\\;", with: ";")
      .split(separator: ";")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && $0 != "+" }
  }
}

struct AirportTopologyTree: Identifiable, Equatable {
  var device: AirportDiscoveredDevice
  var children: [AirportTopologyTree]

  var id: String { device.id }
}

struct TopologyDevicePlacement: Equatable {
  var deviceID: String
  var row: Int
  var column: Int
  var parentID: String?
}

enum JSONValue: Codable, Equatable, Sendable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case object([String: JSONValue])
  case array([JSONValue])
  case null

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([String: JSONValue].self) {
      self = .object(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Unsupported JSON value")
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .bool(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .null: try container.encodeNil()
    }
  }
}
