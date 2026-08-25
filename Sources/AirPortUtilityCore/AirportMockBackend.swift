import Foundation

enum AirportMockBackend {
  typealias EnvironmentLookup = (String) -> String?

  static let maStJSON = """
    {
      "decoded": {
        "disks": [
          {
            "deviceName": "wd0",
            "builtIn": true,
            "partitions": [
              {
                "deviceName": "dk2",
                "name": {"type":"bytes","length":24,"text":"Jack's Time Capsule Home","hex":"4a61636b27732054696d652043617073756c6520486f6d65"},
                "format": "HFS",
                "uuid": {"type":"bytes","length":16,"hex":"adabbc6e09e0579081f8444e687f35b9"},
                "size": 953674,
                "sizeFree": 474787
              }
            ]
          },
          {
            "deviceName": "usb0",
            "builtIn": false,
            "partitions": [
              {
                "deviceName": "dk3",
                "name": {"type":"bytes","length":16,"text":"USB Archive Disk","hex":"5553422041726368697665204469736b"},
                "format": "HFS",
                "uuid": {"type":"bytes","length":16,"hex":"22222222222222222222222222222222"},
                "size": 1907348,
                "sizeFree": 1430511
              }
            ]
          }
        ]
      }
    }
    """

  static var diskInventoryRefreshResult: (raw: String, records: [DiskRecord]) {
    (maStJSON, DiskInventoryParser.parse(stdout: maStJSON))
  }

  /// Sample wireless clients for mock/snapshot mode, covering: a real Apple
  /// OUI with a hostname that resolves a device-type guess, a real Sonos
  /// OUI with a vendor-only guess, a real Epson OUI, an OUI not present in
  /// the curated vendor table (unrecognised, not a random guess), and a
  /// locally-administered (randomized) address to exercise the "Private
  /// address" path. Prefixes are real, verified entries from the bundled
  /// oui-vendors.json - see docs/client-identification.md.
  static var sampleWirelessClients: [WirelessClient] {
    [
      WirelessClient(
        macAddress: "00:03:93:aa:bb:01", ipAddress: "192.168.4.21",
        hostname: "Grahams-iPhone", rssi: -45, dataRateMbps: 866, phyMode: "ac"),
      WirelessClient(
        macAddress: "00:0e:58:aa:bb:02", ipAddress: "192.168.4.22",
        hostname: "Living-Room-Sonos", rssi: -58, dataRateMbps: 144, phyMode: "n"),
      WirelessClient(
        macAddress: "00:00:48:aa:bb:03", ipAddress: "192.168.4.23",
        hostname: "EPSON-Printer", rssi: -67, dataRateMbps: 72, phyMode: "n"),
      WirelessClient(
        // 0x10's second-least-significant bit is 0 - a genuine
        // universally-administered address, just not one in the curated
        // vendor table. (0xAA, used in an earlier draft, actually has that
        // bit set, which meant this example was accidentally exercising
        // the same "private address" path as the entry below instead of a
        // real unrecognised-vendor case.)
        macAddress: "10:00:00:00:00:04", ipAddress: "192.168.4.24",
        hostname: "unknown-device", rssi: -71, dataRateMbps: 130, phyMode: "n"),
      WirelessClient(
        macAddress: "02:00:00:00:00:05", ipAddress: "192.168.4.25",
        hostname: "", rssi: -88, dataRateMbps: 65, phyMode: "n"),
    ]
  }

  static func productID(environmentValue: EnvironmentLookup) -> String {
    let value =
      environmentValue("AIRPORT_UTILITY_MOCK_PRODUCT_ID")?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      ?? ""
    return value.isEmpty ? "106" : value
  }

  static func statusText(environmentValue: EnvironmentLookup) -> String {
    switch (environmentValue("AIRPORT_UTILITY_MOCK_STATUS") ?? "ok").lowercased() {
    case "archive", "archiving":
      return "Archiving disk"
    case "corrupt", "corrupted", "disk-corrupted", "disk_corrupted", "repair":
      return "Disk needs repair"
    case "config", "configuration", "configuration-incorrect", "configuration_incorrect":
      return "Configuration problem"
    case "double-nat", "double_nat":
      return "Double NAT"
    case "dns", "no-dns", "no_dns":
      return "No DNS servers configured"
    case "restart", "restarting":
      return "Restarting"
    default:
      return "Working normally"
    }
  }

  static func discoveredDevices(
    statusText: String,
    environmentValue: EnvironmentLookup
  ) -> [AirportDiscoveredDevice] {
    let productID = productID(environmentValue: environmentValue)
    let modelName = AirPortBonjourBrowser.modelName(fromTXTFields: ["syap": productID])
    let root = AirportDiscoveredDevice(
      id: "mock-time-capsule",
      name: "time capsule 4",
      hostName: "time-capsule.local",
      addresses: ["192.168.4.45"],
      identifiers: ["mock-time-capsule"],
      modelName: modelName,
      productID: productID,
      statusText: statusText)
    let express = AirportDiscoveredDevice(
      id: "mock-express",
      name: "studio express",
      hostName: "studio-express.local",
      addresses: ["192.168.4.46"],
      identifiers: ["mock-express"],
      extendsDeviceID: "mock-time-capsule",
      modelName: "AirPort Express",
      productID: "115",
      statusText: "Working normally")
    let extreme = AirportDiscoveredDevice(
      id: "mock-extreme",
      name: "guest extreme",
      hostName: "guest-extreme.local",
      addresses: ["192.168.4.47"],
      identifiers: ["mock-extreme"],
      modelName: "AirPort Extreme",
      productID: "117",
      statusText: "Working normally")

    switch (environmentValue("AIRPORT_UTILITY_MOCK_TOPOLOGY") ?? "single").lowercased() {
    case "independent":
      return [root, extreme]
    case "extend", "extended", "hierarchy":
      return [root, express]
    case "mixed":
      return [root, express, extreme]
    default:
      return [root]
    }
  }

  static func output(for arguments: [String], dryRun: Bool) -> String {
    if arguments.contains("--upload-firmware") {
      let source =
        arguments.firstIndex(of: "--upload-firmware").flatMap { index in
          arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
        } ?? "firmware image"
      return dryRun
        ? "DRY RUN firmware upload accepted: \(source)"
        : "firmware upload accepted: \(source)"
    }
    if arguments.contains("--archive-disk") && dryRun {
      return "DRY RUN diskd.archiveDisk: Jack's Time Capsule Home -> USB Archive Disk"
    }
    if arguments.contains("--erase-disk") {
      return dryRun
        ? "DRY RUN diskd.eraseDisk: method=quick volumeName=\"Jack's Time Capsule Home\" uuid=adabbc6e09e0579081f8444e687f35b9"
        : "diskd.eraseDisk accepted for Jack's Time Capsule Home."
    }
    if arguments.contains("--archive-disk") {
      return "diskd.archiveDisk accepted. Archive will run asynchronously."
    }
    let keys = changedKeys(in: arguments)
    return dryRun
      ? "DRY RUN acpd.parseDirtyPlist accepted keys: \(keys.joined(separator: ", "))"
      : "acpd.setDirtyPlist accepted keys: \(keys.joined(separator: ", ")). Base station restart may be required."
  }

  private static func changedKeys(in arguments: [String]) -> [String] {
    var keys: [String] = []
    if let settingIndex = arguments.firstIndex(of: "--setting"), settingIndex + 1 < arguments.count
    {
      keys.append(arguments[settingIndex + 1])
    }
    let mapped: [(String, String)] = [
      ("--connect-using", "waCV"),
      ("--ipv4-address", "waIP"),
      ("--subnet-mask", "waSM"),
      ("--router-address", "waRA"),
      ("--dns-server", "waD1/waD2"),
      ("--clear-dns", "waD1/waD2"),
      ("--ipv6-dns-server", "6NS1/6NS2"),
      ("--clear-ipv6-dns", "6NS1/6NS2"),
      ("--domain-name", "waDN"),
      ("--ipv6-address", "6Wad"),
      ("--pppoe-account", "peUN"),
      ("--pppoe-password", "pePW"),
      ("--pppoe-service", "peSN"),
      ("--pppoe-connection", "peAC/peSC/peID"),
      ("--configure-ipv6", "6cfg"),
      ("--dynamic-global-hostname", "wbEn"),
      ("--no-dynamic-global-hostname", "wbEn"),
      ("--global-hostname", "wbHN"),
      ("--global-hostname-user", "wbHU"),
      ("--global-hostname-password", "wbHP"),
      ("--wireless-name", "raNm"),
      ("--wireless-mode", "raSt"),
      ("--wireless-security", "raWM"),
      ("--wireless-password", "raCr/raWE"),
      ("--allow-network-extension", "dWDS"),
      ("--no-allow-network-extension", "dWDS"),
      ("--wds-mode", "bsWM"),
      ("--wds-peer-airport-id", "wdLs"),
      ("--region-code", "syRe"),
      ("--hidden-network", "raCl"),
      ("--no-hidden-network", "raCl"),
      ("--radio-mode", "raMd"),
      ("--radio-channel", "raCh"),
      ("--airplay-enabled", "auRR"),
      ("--no-airplay-enabled", "auRR"),
      ("--airplay-speaker-name", "auNN"),
      ("--airplay-speaker-password", "auNP"),
      ("--clear-airplay-speaker-password", "auNP"),
      ("--airplay-over-wan", "aWan"),
      ("--no-airplay-over-wan", "aWan"),
      ("--allow-setup-over-wan", "waNM"),
      ("--no-allow-setup-over-wan", "waNM"),
      ("--router-mode", "bsRM"),
      ("--dhcp-range-start", "dhBg"),
      ("--dhcp-range-end", "dhEn"),
      ("--dhcp-lease", "dhLe"),
      ("--dhcp-lease-unit", "dhLe"),
      ("--default-host", "nDMZ"),
      ("--clear-default-host", "nDMZ"),
      ("--nat-pmp", "naFl"),
      ("--no-nat-pmp", "naFl"),
      ("--file-sharing", "bsFS"),
      ("--no-file-sharing", "bsFS"),
      ("--disk-security", "bsFM"),
      ("--disk-password", "fssp"),
      ("--guest-disk-access", "bsGA"),
      ("--share-disks-over-wan", "bsRF"),
      ("--no-share-disks-over-wan", "bsRF"),
      ("--windows-workgroup", "SMBw"),
      ("--wins-server", "SMBs"),
    ]
    for item in mapped where arguments.contains(item.0) {
      keys.append(item.1)
    }
    return keys.isEmpty ? ["syNm"] : Array(Set(keys)).sorted()
  }
}
