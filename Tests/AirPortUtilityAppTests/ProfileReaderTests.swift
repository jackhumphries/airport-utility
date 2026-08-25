import XCTest

@testable import AirPortUtilityCore

@MainActor
final class ProfileReaderTests: XCTestCase {
  func testProfileReaderDescribesRawFileSharingSetting() {
    let reader = ProfileReader(
      .object([
        "restoreProfile": .object([
          "bsFS": .object(["type": .string("int"), "text": .string(" 1 ")])
        ])
      ]))

    XCTAssertEqual(
      reader.diagnosticDescription("restoreProfile.bsFS"),
      "{text:  1 , type: int}")
    XCTAssertEqual(reader.boolFromInt("restoreProfile.bsFS"), true)
  }
  func testWirelessClientDisplayNamePrefersHostnameThenIPAddressThenMACAddress() {
    XCTAssertEqual(
      WirelessClient(
        macAddress: "C8:BC:C8:30:CD:3B",
        ipAddress: "192.168.4.41",
        hostname: "iphone.local"
      ).displayName,
      "iphone.local")
    XCTAssertEqual(
      WirelessClient(
        macAddress: "C8:BC:C8:30:CD:3B",
        ipAddress: "192.168.4.41",
        hostname: ""
      ).displayName,
      "192.168.4.41")
    XCTAssertEqual(
      WirelessClient(
        macAddress: "C8:BC:C8:30:CD:3B",
        ipAddress: "",
        hostname: ""
      ).displayName,
      "C8:BC:C8:30:CD:3B")
    XCTAssertEqual(
      WirelessClient(macAddress: " ", ipAddress: " ", hostname: " ").displayName,
      "")
  }

  func testWirelessClientAdvertisedHostnameIsTrimmedAndDoesNotFallBackToAddress() {
    XCTAssertEqual(
      WirelessClient(
        macAddress: "C8:BC:C8:30:CD:3B",
        ipAddress: "192.168.4.41",
        hostname: "  iphone.local  "
      ).advertisedHostname,
      "iphone.local")
    XCTAssertNil(
      WirelessClient(
        macAddress: "C8:BC:C8:30:CD:3B",
        ipAddress: "192.168.4.41",
        hostname: "  "
      ).advertisedHostname)
  }

  func testLegacySNMPCommunityUsesConfiguredValueOrFallsBackToAdminPassword() {
    XCTAssertEqual(
      AirportAppModel.legacySNMPCommunity(
        configured: " private-community ",
        adminPassword: "password"),
      "private-community")
    XCTAssertEqual(
      AirportAppModel.legacySNMPCommunity(
        configured: "",
        adminPassword: "password"),
      "password")
    XCTAssertEqual(
      AirportAppModel.legacySNMPCommunity(
        configured: nil,
        adminPassword: "password"),
      "password")
  }

  func testApplySpaceshipProfilePopulatesSupportedLegacyOptions() throws {
    var table = Data(repeating: 0, count: 15)
    table.append(1)
    table.append(contentsOf: [0x44, 0x23, 0x33, 0x33, 0x33, 0x33])
    table.append(Data("test".utf8))
    table.append(Data(repeating: 0, count: 30))
    let profile: JSONValue = .object([
      "restoreProfile": .object([
        "syAP": .number(3),
        "syCt": .string("Network Admin"),
        "syLo": .string("New York"),
        "ntSV": .string("time.apple.com"),
        "raMu": .number(85),
        "raPo": .object([
          "type": .string("bytes"), "hex": .string("0032"), "length": .number(2),
        ]),
        "raKT": .number(7_200),
        "raRo": .bool(true),
        "dhMg": .string("Welcome"),
        "dh95": .string("ldap.example.test"),
        "acEn": .bool(true),
        "raFl": .number(0),
        "acTa": .object([
          "type": .string("bytes"),
          "hex": .string(table.map { String(format: "%02x", $0) }.joined()),
          "length": .number(Double(table.count)),
        ]),
      ])
    ])
    let model = AirportAppModel()

    model.apply(profile: profile)

    XCTAssertEqual(model.legacyDeviceOptions.baseStation.contact, "Network Admin")
    XCTAssertEqual(model.legacyDeviceOptions.baseStation.location, "New York")
    XCTAssertTrue(model.legacyDeviceOptions.baseStation.setTimeAutomatically)
    XCTAssertEqual(model.legacyDeviceOptions.baseStation.timeServer, "time.apple.com")
    XCTAssertEqual(model.legacyDeviceOptions.wireless.multicastRate, 85)
    XCTAssertEqual(model.legacyDeviceOptions.wireless.transmitPower, 50)
    XCTAssertEqual(model.legacyDeviceOptions.wireless.groupKeyTimeoutSeconds, 7_200)
    XCTAssertTrue(model.legacyDeviceOptions.wireless.interferenceRobustness)
    XCTAssertEqual(model.legacyDeviceOptions.dhcp.message, "Welcome")
    XCTAssertEqual(model.legacyDeviceOptions.dhcp.ldapServer, "ldap.example.test")
    XCTAssertEqual(model.legacyDeviceOptions.accessControl.mode, "local")
    XCTAssertEqual(model.legacyDeviceOptions.accessControl.entries.first?.macAddress, "44:23:33:33:33:33")
    XCTAssertEqual(model.legacyDeviceOptions.accessControl.entries.first?.description, "test")
  }

  func testLegacyUpdateSnapshotCanExcludeReadOnlyAccessControlTable() throws {
    let response = try JSONDecoder().decode(
      JSONValue.self,
      from: Data(
        #"{"settings":{"acTa":{"hex":"00000000"},"syNm":{"hex":"616972706f7274"}}}"#.utf8))

    let valuesJSON = AirportAppModel.legacySettingsValuesJSON(
      from: response, excluding: ["acTa"])

    XCTAssertFalse(valuesJSON.contains("acTa"))
    XCTAssertTrue(valuesJSON.contains("syNm"))
  }

  func testApplyProfilePopulatesVisiblePaneState() throws {
    let profile = try JSONDecoder().decode(JSONValue.self, from: Data(Self.profileJSON.utf8))
    let model = AirportAppModel()

    model.apply(profile: profile)

    XCTAssertEqual(model.baseStation.name, "time capsule")
    XCTAssertEqual(model.baseStation.newAdminPassword, "admin-secret")
    XCTAssertEqual(model.baseStation.verifyAdminPassword, "admin-secret")
    XCTAssertEqual(model.internet.connectUsing, .static)
    XCTAssertEqual(model.internet.ipv4Address, "192.168.4.45")
    XCTAssertEqual(model.internet.subnetMask, "255.255.252.0")
    XCTAssertEqual(model.internet.routerAddress, "192.168.4.1")
    XCTAssertEqual(model.internet.dnsServers, "1.1.1.1, 8.8.8.8")
    XCTAssertEqual(model.internet.ipv6DNSServers, "2001:4860:4860::8888")
    XCTAssertEqual(model.internet.domainName, "example.test")
    XCTAssertEqual(model.internet.ipv6Address, "2001:db8::10")
    XCTAssertEqual(model.internet.pppoeAccount, "account")
    XCTAssertEqual(model.internet.pppoePassword, "pppoe-secret")
    XCTAssertEqual(model.internet.pppoeService, "service")
    XCTAssertEqual(model.internet.pppoeConnection, "automatic")
    XCTAssertEqual(model.internet.configureIPv6, "automatic")
    XCTAssertTrue(model.internet.dynamicGlobalHostname)
    XCTAssertEqual(model.internet.globalHostname, "capsule.example.test")
    XCTAssertTrue(model.showsIPv6InternetControls)
    XCTAssertTrue(model.showsDynamicGlobalHostnameControls)

    XCTAssertEqual(model.wireless.mode, "create")
    XCTAssertEqual(model.wireless.networkName, "Jack's Network")
    XCTAssertEqual(model.wireless.security, "wpa-wpa2-personal")
    XCTAssertEqual(model.wireless.regionCode, "0")
    XCTAssertTrue(model.wireless.hiddenNetwork)
    XCTAssertEqual(model.wireless.radioMode, "80211n-bg")
    XCTAssertEqual(model.wireless.radioChannel, "11")
    XCTAssertTrue(model.baseStation.allowSetupOverWAN)

    XCTAssertEqual(model.network.routerMode, .dhcpAndNat)
    XCTAssertEqual(model.network.lanIPAddress, "10.0.1.1")
    XCTAssertEqual(model.network.dhcpRangeStart, "10.0.0.2")
    XCTAssertEqual(model.network.dhcpRangeEnd, "10.0.0.200")
    XCTAssertEqual(model.network.dhcpLease, "1")
    XCTAssertEqual(model.network.dhcpLeaseUnit, "days")
    XCTAssertTrue(model.network.natPMP)
    XCTAssertEqual(model.network.defaultHost, "")

    XCTAssertTrue(model.disks.fileSharing)
    XCTAssertFalse(model.disks.shareOverWAN)
    XCTAssertEqual(model.disks.secureSharedDisks, "disk-password")
    XCTAssertEqual(model.disks.guestAccess, "read-only")
    XCTAssertEqual(model.disks.diskPassword, "disk-secret")
    XCTAssertEqual(model.disks.windowsWorkgroup, "WORKGROUP")
    XCTAssertEqual(model.disks.winsServer, "10.0.0.5")
  }

  func testApplyPartialProfileDoesNotClearDetectedInternetFeatureSupport() throws {
    let profile = try JSONDecoder().decode(JSONValue.self, from: Data(Self.profileJSON.utf8))
    let partialProfile: JSONValue = .object([
      "restoreProfile": .object([
        "syNm": .string("renamed")
      ])
    ])
    let model = AirportAppModel()
    model.apply(profile: profile)

    model.apply(profile: partialProfile)

    XCTAssertEqual(model.baseStation.name, "renamed")
    XCTAssertTrue(model.showsIPv6InternetControls)
    XCTAssertTrue(model.showsDynamicGlobalHostnameControls)
  }

  func testApplyDHCPProfileUsesReportedDNSAsPreviewOnly() throws {
    let profile = try JSONDecoder().decode(JSONValue.self, from: Data(Self.dhcpDNSProfileJSON.utf8))
    let model = AirportAppModel()
    model.internet.dnsServers = "stale-editable-dns"
    model.internet.ipv6DNSServers = "stale-editable-ipv6-dns"

    model.apply(profile: profile)

    XCTAssertEqual(model.internet.connectUsing, .dhcp)
    XCTAssertEqual(model.internet.dnsServers, "")
    XCTAssertEqual(model.internet.dnsServerPreview, "192.168.4.1, 1.1.1.1")
    XCTAssertEqual(model.internet.ipv6DNSServers, "")
    XCTAssertEqual(model.internet.ipv6DNSServerPreview, "2001:4860:4860::8888")
    XCTAssertFalse(model.internetFlags()?.contains { $0.0 == "--dns-server" } == true)
    XCTAssertFalse(model.internetFlags()?.contains { $0.0 == "--ipv6-dns-server" } == true)
  }

  func testApplyDHCPProfileUsesDynamicCurrentDNSWhenConfiguredDNSIsZero() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self, from: Data(Self.dhcpCurrentDNSProfileJSON.utf8))
    let model = AirportAppModel()

    model.apply(profile: profile)

    XCTAssertEqual(model.internet.connectUsing, .dhcp)
    XCTAssertEqual(model.internet.dnsServers, "")
    XCTAssertEqual(model.internet.dnsServerPreview, "192.168.1.1")
    XCTAssertEqual(model.internet.ipv6DNSServers, "")
    XCTAssertEqual(model.internet.ipv6DNSServerPreview, "2001:db8::1")
  }

  func testApplyDHCPProfileClearsStaleDNSPreviewWhenReportedDNSIsZero() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self, from: Data(Self.dhcpZeroDNSProfileJSON.utf8))
    let model = AirportAppModel()
    model.internet.dnsServerPreview = "192.168.1.1"
    model.internet.ipv6DNSServerPreview = "2001:db8::1"

    model.apply(profile: profile)

    XCTAssertEqual(model.internet.connectUsing, .dhcp)
    XCTAssertEqual(model.internet.dnsServers, "")
    XCTAssertEqual(model.internet.dnsServerPreview, "")
    XCTAssertEqual(model.internet.ipv6DNSServers, "")
    XCTAssertEqual(model.internet.ipv6DNSServerPreview, "")
  }

  func testApplyStaticProfileClearsStaleDNSWhenConfiguredDNSIsZero() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self, from: Data(Self.staticZeroDNSProfileJSON.utf8))
    let model = AirportAppModel()
    model.internet.dnsServers = "1.1.1.1, 8.8.8.8"
    model.internet.ipv6DNSServers = "2001:4860:4860::8888"

    model.apply(profile: profile)

    XCTAssertEqual(model.internet.connectUsing, .static)
    XCTAssertEqual(model.internet.dnsServers, "")
    XCTAssertEqual(model.internet.dnsServerPreview, "")
    XCTAssertEqual(model.internet.ipv6DNSServers, "")
    XCTAssertEqual(model.internet.ipv6DNSServerPreview, "")
  }

  func testApplyProfileDecodesEncodedIPv4DNSServers() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self, from: Data(Self.encodedIPv4DNSProfileJSON.utf8))
    let model = AirportAppModel()

    model.apply(profile: profile)

    XCTAssertEqual(model.internet.connectUsing, .static)
    XCTAssertEqual(model.internet.dnsServers, "192.168.1.1, 1.1.1.1")
    XCTAssertEqual(model.internet.dnsServerPreview, "")
  }

  func testDirectACPIPv4DNSValueDecodesFromHex() throws {
    let setting = try JSONDecoder().decode(
      JSONValue.self,
      from: Data(#"{"hex":"c0a80101","length":4,"value":"3232235777"}"#.utf8))

    XCTAssertEqual(ProfileReader.ipv4Address(fromDirectSetting: setting), "192.168.1.1")
  }

  func testDirectACPIPv4TextRejectsMalformedAddresses() throws {
    let outOfRange = try JSONDecoder().decode(JSONValue.self, from: Data(#""999.168.1.1""#.utf8))
    let leadingZero = try JSONDecoder().decode(JSONValue.self, from: Data(#""192.168.001.1""#.utf8))
    let emptyOctet = try JSONDecoder().decode(JSONValue.self, from: Data(#""192.168..1""#.utf8))
    let allOnes = try JSONDecoder().decode(JSONValue.self, from: Data(#""255.255.255.255""#.utf8))
    let oversizedLength = try JSONDecoder().decode(
      JSONValue.self,
      from: Data(#"{"hex":"c0a80101","length":1e40}"#.utf8))

    XCTAssertNil(ProfileReader.ipv4Address(fromDirectSetting: outOfRange))
    XCTAssertNil(ProfileReader.ipv4Address(fromDirectSetting: leadingZero))
    XCTAssertNil(ProfileReader.ipv4Address(fromDirectSetting: emptyOctet))
    XCTAssertNil(ProfileReader.ipv4Address(fromDirectSetting: allOnes))
    XCTAssertNil(ProfileReader.ipv4Address(fromDirectSetting: oversizedLength))
  }

  func testDirectACPIPv6ValueDecodesFromHex() throws {
    let setting = try JSONDecoder().decode(
      JSONValue.self,
      from: Data(#"{"hex":"20010db8000000000000000000000010","length":16}"#.utf8))

    XCTAssertEqual(ProfileReader.ipv6Address(fromDirectSetting: setting), "2001:db8::10")
  }

  func testDirectACPIPv6ValueRejectsOversizedLengthWithoutCrashing() throws {
    let setting = try JSONDecoder().decode(
      JSONValue.self,
      from: Data(#"{"hex":"20010db8000000000000000000000010","length":1e40}"#.utf8))

    XCTAssertNil(ProfileReader.ipv6Address(fromDirectSetting: setting))
  }

  func testApplyProfileDecodesEncodedIPv6AddressAndWINSServer() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self,
      from: Data(
        #"{"restoreProfile":{"6Wad":{"hex":"20010db8000000000000000000000010","length":16},"SMBs":{"hex":"0a000005","length":4}}}"#
          .utf8))
    let model = AirportAppModel()

    model.apply(profile: profile)

    XCTAssertEqual(model.internet.ipv6Address, "2001:db8::10")
    XCTAssertEqual(model.disks.winsServer, "10.0.0.5")
  }

  func testApplyProfileDecodesEncodedIPv6DNSServers() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self,
      from: Data(
        #"{"restoreProfile":{"waCV":33792,"6NS1":{"hex":"20014860486000000000000000008888","length":16},"6NS2":{"hex":"20014860486000000000000000008844","length":16}}}"#
          .utf8))
    let model = AirportAppModel()

    model.apply(profile: profile)

    XCTAssertEqual(model.internet.connectUsing, .static)
    XCTAssertEqual(model.internet.ipv6DNSServers, "2001:4860:4860::8888, 2001:4860:4860::8844")
    XCTAssertEqual(model.internet.ipv6DNSServerPreview, "")
  }

  func testApplyDHCPProfileDecodesEncodedCurrentIPv6DNSPreview() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self,
      from: Data(
        #"{"restoreProfile":{"waCV":33536,"6NS1":"::","6NS2":"::","ipv6CurrentPrimaryDNSAddress":{"hex":"20010db8000000000000000000000001","length":16}}}"#
          .utf8))
    let model = AirportAppModel()

    model.apply(profile: profile)

    XCTAssertEqual(model.internet.connectUsing, .dhcp)
    XCTAssertEqual(model.internet.ipv6DNSServers, "")
    XCTAssertEqual(model.internet.ipv6DNSServerPreview, "2001:db8::1")
  }

  func testApplyProfileDecodesEncodedDHCPRanges() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self,
      from: Data(
        #"{"restoreProfile":{"dhBg":{"hex":"0a000102","length":4},"dhEn":{"value":"167772616"}}}"#
          .utf8))
    let model = AirportAppModel()

    model.apply(profile: profile)

    XCTAssertEqual(model.network.dhcpRangeStart, "10.0.1.2")
    XCTAssertEqual(model.network.dhcpRangeEnd, "10.0.1.200")
  }

  func testMalformedIPv4ProfileFieldsDoNotReplaceExistingValues() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self,
      from: Data(
        #"{"restoreProfile":{"waIP":"999.168.1.1","waRA":"192.168.001.1","dhBg":"10.0..2","SMBs":"300.0.0.1"}}"#
          .utf8))
    let model = AirportAppModel()
    model.internet.ipv4Address = "192.168.4.45"
    model.internet.routerAddress = "192.168.4.1"
    model.network.dhcpRangeStart = "10.0.1.2"
    model.disks.winsServer = "10.0.0.5"

    model.apply(profile: profile)

    XCTAssertEqual(model.internet.ipv4Address, "192.168.4.45")
    XCTAssertEqual(model.internet.routerAddress, "192.168.4.1")
    XCTAssertEqual(model.network.dhcpRangeStart, "10.0.1.2")
    XCTAssertEqual(model.disks.winsServer, "10.0.0.5")
  }

  func testUnavailableACPSettingSentinelsAreIgnored() throws {
    let setting = try JSONDecoder().decode(
      JSONValue.self,
      from: Data(#"{"hex":"fffffff6","length":4,"value":"4294967286"}"#.utf8))

    XCTAssertNil(ProfileReader.ipv4Address(fromDirectSetting: setting))
    XCTAssertEqual(ProfileReader.joinNonZeroIPv6(["4294967286", "::"]), "")
  }

  func testUnavailableDHCPRangeSentinelsDoNotReplaceExistingValues() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self,
      from: Data(
        #"{"restoreProfile":{"dhBg":{"hex":"fffffff6","length":4,"value":"4294967286"},"dhEn":"--"}}"#
          .utf8))
    let model = AirportAppModel()
    model.network.dhcpRangeStart = "10.0.1.2"
    model.network.dhcpRangeEnd = "10.0.1.200"

    model.apply(profile: profile)

    XCTAssertEqual(model.network.dhcpRangeStart, "10.0.1.2")
    XCTAssertEqual(model.network.dhcpRangeEnd, "10.0.1.200")
  }

  func testApplyProfileAcceptsDecodedWrapperAndKeepsEnteredAdminPassword() throws {
    let wrappedJSON = #"{"decoded": \#(Self.profileJSON)}"#
    let profile = try JSONDecoder().decode(JSONValue.self, from: Data(wrappedJSON.utf8))
    let model = AirportAppModel()
    model.connection.password = "entered-admin-password"

    model.apply(profile: profile)

    XCTAssertEqual(model.baseStation.name, "time capsule")
    XCTAssertEqual(model.baseStation.newAdminPassword, "admin-secret")
    XCTAssertEqual(model.baseStation.verifyAdminPassword, "admin-secret")
    XCTAssertEqual(model.wireless.networkName, "Jack's Network")
  }

  func testApplyProfileAcceptsRawRestoreProfileDictionary() throws {
    let profile = try JSONDecoder().decode(JSONValue.self, from: Data(Self.rawProfileJSON.utf8))
    let model = AirportAppModel()

    model.apply(profile: profile)

    XCTAssertEqual(model.baseStation.name, "raw time capsule")
    XCTAssertEqual(model.internet.ipv4Address, "192.168.4.45")
    XCTAssertEqual(model.network.lanIPAddress, "10.0.1.1")
    XCTAssertEqual(model.wireless.networkName, "Raw Network")
  }

  func testApplyProfileAcceptsLegacyDirectSettingsBatch() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self,
      from: Data(
        """
        {
          "settings": {
            "syNm": {"hex": "616972706f72742d65787072657373", "length": 15, "value": "airport-express"},
            "sySN": {"hex": "364637313931595a553454", "length": 11, "value": "6F7191YZU4T"},
            "syVs": {"hex": "362e33", "length": 3, "value": "6.3"},
            "syAP": {"hex": "00000066", "length": 4, "value": "102"},
            "waCV": {"hex": "00000300", "length": 4, "value": "768"},
            "waIP": {"hex": "c0a8042f", "length": 4, "value": "3232236591"},
            "waSM": {"hex": "fffffc00", "length": 4, "value": "4294966272"},
            "waRA": {"hex": "c0a80401", "length": 4, "value": "3232236545"},
            "laIP": {"hex": "c0a8042f", "length": 4, "value": "3232236591"},
            "waC1": {"hex": "c0a80101", "length": 4, "value": "3232235777"},
            "raNm": {"hex": "616972706f72742d65787072657373", "length": 15, "value": "airport-express"},
            "raSt": {"hex": "00000003", "length": 4, "value": "3"},
            "raMd": {"hex": "0002", "length": 2, "value": "0002"},
            "raCh": {"hex": "00000001", "length": 4, "value": "1"},
            "auRR": {"hex": "0001", "length": 2, "value": "0001"},
            "auNN": {"hex": "616972706f72742d65787072657373", "length": 15, "value": "airport-express"}
          },
          "errors": {
            "Prof": "ACP property Prof failed with error_code -0xa"
          }
        }
        """.utf8))
    let model = AirportAppModel()

    model.apply(profile: profile)

    XCTAssertEqual(model.baseStation.name, "airport-express")
    XCTAssertEqual(model.baseStation.serialNumber, "6F7191YZU4T")
    XCTAssertEqual(model.baseStation.version, "6.3")
    XCTAssertEqual(model.baseStation.productID, "102")
    XCTAssertEqual(model.internet.connectUsing, .dhcp)
    XCTAssertEqual(model.internet.ipv4Address, "192.168.4.47")
    XCTAssertEqual(model.internet.subnetMask, "255.255.252.0")
    XCTAssertEqual(model.internet.routerAddress, "192.168.4.1")
    XCTAssertEqual(model.internet.dnsServerPreview, "192.168.1.1")
    XCTAssertEqual(model.network.lanIPAddress, "192.168.4.47")
    XCTAssertTrue(model.hasCompleteDevicePopoverDetails)
    XCTAssertEqual(model.wireless.mode, "off")
    XCTAssertEqual(model.wireless.networkName, "Off")
    XCTAssertEqual(model.wireless.security, "none")
    XCTAssertEqual(model.wireless.radioChannel, "")
    XCTAssertEqual(model.airPlay.speakerName, "airport-express")
    XCTAssertTrue(model.airPlay.enabled)
  }

  func testLegacyDirectSettingsUseWANIPAsLANIPFallback() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self,
      from: Data(
        """
        {
          "settings": {
            "syNm": {"value": "airport-express"},
            "sySN": {"value": "6F7191YZU4T"},
            "syVs": {"value": "6.3"},
            "syAP": {"value": "102"},
            "waIP": {"hex": "c0a8042f", "length": 4, "value": "3232236591"}
          }
        }
        """.utf8))
    let model = AirportAppModel()

    model.apply(profile: profile)

    XCTAssertEqual(model.internet.ipv4Address, "192.168.4.47")
    XCTAssertEqual(model.network.lanIPAddress, "192.168.4.47")
  }

  func testApplyProfileUsesCurrentProfileWhenRestoreProfileIsMissing() throws {
    let profile = try JSONDecoder().decode(JSONValue.self, from: Data(Self.currentProfileJSON.utf8))
    let model = AirportAppModel()

    model.apply(profile: profile)

    XCTAssertEqual(model.baseStation.name, "active time capsule")
    XCTAssertEqual(model.internet.ipv4Address, "192.168.4.45")
    XCTAssertEqual(model.network.lanIPAddress, "10.0.1.1")
    XCTAssertEqual(model.wireless.networkName, "Active Network")
  }

  func testApplyProfileDoesNotInferIPv6AutomaticWhenAutoconfigureFlagIsMissing() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self, from: Data(Self.profileWithIPv6ModeButNoAutoconfigureFlagJSON.utf8))
    let model = AirportAppModel()
    model.internet.configureIPv6 = "manual"

    model.apply(profile: profile)

    XCTAssertEqual(model.internet.configureIPv6, "manual")
  }

  func testApplyProfileMapsIPv6LinkLocalFromIPv6ModeWithoutAutoconfigureFlag() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self, from: Data(Self.profileWithLinkLocalIPv6ModeJSON.utf8))
    let model = AirportAppModel()
    model.internet.configureIPv6 = "manual"

    model.apply(profile: profile)

    XCTAssertEqual(model.internet.configureIPv6, "link-local")
  }

  func testApplyProfileShowsOffWirelessNetworkNameWhenModeIsOff() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self, from: Data(Self.offWirelessProfileJSON.utf8))
    let model = AirportAppModel()

    model.apply(profile: profile)

    XCTAssertEqual(model.wireless.mode, "off")
    XCTAssertEqual(model.wireless.networkName, "Off")
  }

  func testApplyOffWirelessProfileClearsStaleHiddenWirelessFields() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self, from: Data(Self.offWirelessProfileJSON.utf8))
    let model = AirportAppModel()
    model.wireless.security = "wpa2-personal"
    model.wireless.password = "old-wifi"
    model.wireless.verifyPassword = "old-wifi"
    model.wireless.regionCode = "0"
    model.wireless.hiddenNetwork = true
    model.wireless.radioMode = "80211n-bg"
    model.wireless.radioChannel = "11"

    model.apply(profile: profile)

    XCTAssertEqual(model.wireless.mode, "off")
    XCTAssertEqual(model.wireless.networkName, "Off")
    XCTAssertEqual(model.wireless.security, "none")
    XCTAssertEqual(model.wireless.password, "")
    XCTAssertEqual(model.wireless.verifyPassword, "")
    XCTAssertEqual(model.wireless.regionCode, "")
    XCTAssertFalse(model.wireless.hiddenNetwork)
    XCTAssertEqual(model.wireless.radioMode, "")
    XCTAssertEqual(model.wireless.radioChannel, "")
  }

  func testApplyProfilePopulatesWirelessPasswordFromRadioProfile() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self, from: Data(Self.profileWithRadioWirelessPasswordJSON.utf8))
    let model = AirportAppModel()

    model.apply(profile: profile)

    XCTAssertEqual(model.wireless.password, "radio-wifi-secret")
    XCTAssertEqual(model.wireless.verifyPassword, "radio-wifi-secret")
  }

  func testApplyProfilePrefersRadioClearWirelessPassword() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self, from: Data(Self.profileWithRadioClearWirelessPasswordJSON.utf8))
    let model = AirportAppModel()

    model.apply(profile: profile)

    XCTAssertEqual(model.wireless.password, "clear-wifi-secret")
    XCTAssertEqual(model.wireless.verifyPassword, "clear-wifi-secret")
  }

  func testLiveWirelessSettingsOverrideStaleProfileWirelessValues() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self, from: Data(Self.offWirelessProfileJSON.utf8))
    let model = AirportAppModel()

    model.apply(profile: profile)
    model.apply(
      liveWirelessSettings: AirportAppModel.liveWirelessSettings(
        modeText: "0",
        nameText: "test",
        securityText: "7",
        regionCodeText: "000",
        hiddenNetworkText: "00",
        radioModeText: "0006",
        radioChannelText: "1"
      ))
    model.markClean()

    XCTAssertEqual(model.wireless.mode, "create")
    XCTAssertEqual(model.wireless.networkName, "test")
    XCTAssertEqual(model.wireless.security, "wpa2-personal")
    XCTAssertEqual(model.wireless.regionCode, "0")
    XCTAssertFalse(model.wireless.hiddenNetwork)
    XCTAssertEqual(model.wireless.radioMode, "80211n-bg")
    XCTAssertEqual(model.wireless.radioChannel, "1")
    XCTAssertFalse(model.hasPendingChanges)
  }

  func testLiveWirelessSettingsParseWDSPeersFromEightByteSlots() {
    let settings = AirportAppModel.liveWirelessSettings(
      wdsModeText: "3",
      wdsPeerAirPortIDsText: "0021e9b92ec30000001b6321f58f0000")

    XCTAssertEqual(settings.wdsMode, "remote")
    XCTAssertEqual(settings.wdsPeerAirPortIDs, "00:21:E9:B9:2E:C3, 00:1B:63:21:F5:8F")
  }

  func testLiveAdvancedSettingsParseCapturedSpaceshipValues() throws {
    let value = try JSONDecoder().decode(
      JSONValue.self,
      from: Data(
        """
        {
          "settings": {
            "slCl": {"value": "192.168.5.6"},
            "slvl": {"value": "7"},
            "snAF": {"value": "0"},
            "pdFl": {"value": "1"},
            "pdUN": {"value": "pppaccount"},
            "pdPW": {"value": "ppppassword"},
            "pdAR": {"value": "4"},
            "pdID": {"value": "1200"},
            "pdMC": {"value": "14400"}
          }
        }
        """.utf8))

    let settings = AirportAppModel.liveAdvancedSettings(reader: ProfileReader(value))

    XCTAssertEqual(settings.syslogDestinationAddress, "192.168.5.6")
    XCTAssertEqual(settings.syslogLevel, 7)
    XCTAssertEqual(settings.snmpAccessFlags, 0)
    XCTAssertEqual(settings.pppDialInEnabled, true)
    XCTAssertEqual(settings.pppDialInAccount, "pppaccount")
    XCTAssertEqual(settings.pppDialInPassword, "ppppassword")
    XCTAssertEqual(settings.pppDialInAnswerOnRing, 4)
    XCTAssertEqual(settings.pppDialInIdleSeconds, 1_200)
    XCTAssertEqual(settings.pppDialInMaximumConnectSeconds, 14_400)
  }

  func testApplyProfilePreservesExistingPasswordsWhenPartialProfileOmitsPasswordKeys() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self, from: Data(Self.profileWithoutWirelessOrDiskPasswordJSON.utf8))
    let model = AirportAppModel()
    model.wireless.password = "existing-wifi"
    model.wireless.verifyPassword = "existing-wifi"
    model.disks.secureSharedDisks = "disk-password"
    model.disks.diskPassword = "existing-disk"
    model.disks.verifyDiskPassword = "existing-disk"

    model.apply(profile: profile)

    XCTAssertEqual(model.wireless.security, "wpa-wpa2-personal")
    XCTAssertEqual(model.wireless.password, "existing-wifi")
    XCTAssertEqual(model.wireless.verifyPassword, "existing-wifi")
    XCTAssertEqual(model.disks.secureSharedDisks, "disk-password")
    XCTAssertEqual(model.disks.diskPassword, "existing-disk")
    XCTAssertEqual(model.disks.verifyDiskPassword, "existing-disk")
  }

  func testApplyProfileClearsPasswordsWhenProfileSelectsNoPasswordModes() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self, from: Data(Self.profileWithNoPasswordModesJSON.utf8))
    let model = AirportAppModel()
    model.wireless.password = "existing-wifi"
    model.wireless.verifyPassword = "existing-wifi"
    model.disks.diskPassword = "existing-disk"
    model.disks.verifyDiskPassword = "existing-disk"

    model.apply(profile: profile)

    XCTAssertEqual(model.wireless.security, "none")
    XCTAssertEqual(model.wireless.password, "")
    XCTAssertEqual(model.wireless.verifyPassword, "")
    XCTAssertEqual(model.disks.secureSharedDisks, "device-password")
    XCTAssertEqual(model.disks.diskPassword, "")
    XCTAssertEqual(model.disks.verifyDiskPassword, "")
  }

  func testApplyProfileUsesConnectionPasswordWhenProfileOmitsAdminPassword() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self, from: Data(Self.profileWithoutAdminPasswordJSON.utf8))
    let model = AirportAppModel()
    model.connection.password = "entered-admin-password"

    model.apply(profile: profile)

    XCTAssertEqual(model.baseStation.name, "time capsule")
    XCTAssertEqual(model.baseStation.newAdminPassword, "entered-admin-password")
    XCTAssertEqual(model.baseStation.verifyAdminPassword, "entered-admin-password")
  }

  func testApplyProfilePreservesAdminPasswordWhenProfileAndConnectionOmitIt() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self, from: Data(Self.profileWithoutAdminPasswordJSON.utf8))
    let model = AirportAppModel()
    model.connection.password = "   "
    model.baseStation.newAdminPassword = "existing-admin-password"
    model.baseStation.verifyAdminPassword = "existing-admin-password"

    model.apply(profile: profile)

    XCTAssertEqual(model.baseStation.name, "time capsule")
    XCTAssertEqual(model.baseStation.newAdminPassword, "existing-admin-password")
    XCTAssertEqual(model.baseStation.verifyAdminPassword, "existing-admin-password")
  }

  func testApplyProfileUsesLegacyRouterModeWhenModernRouterModeIsMissing() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self,
      from: Data(#"{"restoreProfile":{"raTr":0}}"#.utf8))
    let model = AirportAppModel()
    model.network.routerMode = .bridge

    model.apply(profile: profile)

    XCTAssertEqual(model.network.routerMode, .dhcpAndNat)
  }

  func testApplyProfileUsesLegacyBridgeModeWhenModernRouterModeIsMissing() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self,
      from: Data(#"{"restoreProfile":{"raTr":4294967295}}"#.utf8))
    let model = AirportAppModel()
    model.network.routerMode = .dhcpAndNat

    model.apply(profile: profile)

    XCTAssertEqual(model.network.routerMode, .bridge)
  }

  func testApplyProfileDoesNotClearDefaultHostWhenProfileOmitsNATDefaultHost() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self, from: Data(Self.profileWithoutDefaultHostJSON.utf8))
    let model = AirportAppModel()
    model.network.defaultHost = "10.0.1.253"

    model.apply(profile: profile)

    XCTAssertEqual(model.network.defaultHost, "10.0.1.253")
  }

  func testApplyProfileDoesNotClearPPPoEConnectionWhenProfileOmitsPolicyFlags() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self, from: Data(Self.profileWithoutPPPoEPolicyJSON.utf8))
    let model = AirportAppModel()
    model.internet.pppoeConnection = "always-on"

    model.apply(profile: profile)

    XCTAssertEqual(model.internet.pppoeConnection, "always-on")
  }

  func testApplyNonPPPoEProfileClearsStalePPPoEFields() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self, from: Data(Self.dhcpDNSProfileJSON.utf8))
    let model = AirportAppModel()
    model.internet.connectUsing = .pppoe
    model.internet.pppoeAccount = "old-account"
    model.internet.pppoePassword = "old-password"
    model.internet.pppoeService = "old-service"
    model.internet.pppoeConnection = "manual"

    model.apply(profile: profile)

    XCTAssertEqual(model.internet.connectUsing, .dhcp)
    XCTAssertEqual(model.internet.pppoeAccount, "")
    XCTAssertEqual(model.internet.pppoePassword, "")
    XCTAssertEqual(model.internet.pppoeService, "")
    XCTAssertEqual(model.internet.pppoeConnection, "always-on")
  }

  func testApplyPPPoEProfilePreservesMissingPPPoEFields() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self, from: Data(Self.profileWithoutPPPoEPolicyJSON.utf8))
    let model = AirportAppModel()
    model.internet.pppoePassword = "existing-password"
    model.internet.pppoeConnection = "manual"

    model.apply(profile: profile)

    XCTAssertEqual(model.internet.connectUsing, .pppoe)
    XCTAssertEqual(model.internet.pppoeAccount, "account-name")
    XCTAssertEqual(model.internet.pppoePassword, "existing-password")
    XCTAssertEqual(model.internet.pppoeService, "service-name")
    XCTAssertEqual(model.internet.pppoeConnection, "manual")
  }

  func testApplyDisabledGlobalHostnameProfileClearsStaleFields() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self, from: Data(Self.profileWithDisabledGlobalHostnameJSON.utf8))
    let model = AirportAppModel()
    model.internet.dynamicGlobalHostname = true
    model.internet.globalHostname = "capsule.example.test"
    model.internet.globalHostnameUser = "host-user"
    model.internet.globalHostnamePassword = "host-secret"

    model.apply(profile: profile)

    XCTAssertFalse(model.internet.dynamicGlobalHostname)
    XCTAssertEqual(model.internet.globalHostname, "")
    XCTAssertEqual(model.internet.globalHostnameUser, "")
    XCTAssertEqual(model.internet.globalHostnamePassword, "")
  }

  func testApplyEnabledGlobalHostnameProfilePreservesMissingCredentials() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self, from: Data(Self.profileWithEnabledGlobalHostnameJSON.utf8))
    let model = AirportAppModel()
    model.internet.globalHostnameUser = "existing-user"
    model.internet.globalHostnamePassword = "existing-secret"

    model.apply(profile: profile)

    XCTAssertTrue(model.internet.dynamicGlobalHostname)
    XCTAssertEqual(model.internet.globalHostname, "capsule.example.test")
    XCTAssertEqual(model.internet.globalHostnameUser, "existing-user")
    XCTAssertEqual(model.internet.globalHostnamePassword, "existing-secret")
  }

  func testUnavailableInternetFeatureSettingsDoNotEnableInternetOptions() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self,
      from: Data(
        """
        {
          "restoreProfile": {
            "6cfg": "--",
            "6aut": {
              "value": "4294967286"
            },
            "6NS1": {
              "hex": "ffffffffffffffffffffffffffffffff",
              "length": 16
            },
            "wbEn": {
              "value": "4294967286"
            },
            "wbHN": "--"
          }
        }
        """.utf8))
    let model = AirportAppModel()

    model.apply(profile: profile)

    XCTAssertFalse(model.showsIPv6InternetControls)
    XCTAssertFalse(model.showsDynamicGlobalHostnameControls)
    XCTAssertFalse(model.showsInternetOptionsControls)
  }

  func testDevicePopoverDetailsAreAvailableAfterProfileDataLoads() throws {
    let profile = try JSONDecoder().decode(JSONValue.self, from: Data(Self.profileJSON.utf8))
    let model = AirportAppModel()

    XCTAssertFalse(model.hasDevicePopoverDetails)

    model.baseStation.serialNumber = "C86TEST123"
    model.baseStation.version = "7.9.1"
    model.apply(profile: profile)

    XCTAssertTrue(model.hasDevicePopoverDetails)
  }

  func testUnavailableProfilePlaceholdersDoNotReplacePreloadedFields() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self, from: Data(Self.profileWithUnavailablePlaceholdersJSON.utf8))
    let model = AirportAppModel()
    model.baseStation.name = "time capsule"
    model.baseStation.serialNumber = "C86TEST123"
    model.baseStation.version = "7.9.1"
    model.internet.ipv4Address = "192.168.4.45"
    model.internet.subnetMask = "255.255.252.0"
    model.internet.routerAddress = "192.168.4.1"
    model.internet.dnsServers = "1.1.1.1, 8.8.8.8"
    model.internet.ipv6DNSServers = "2001:4860:4860::8888"
    model.network.lanIPAddress = "10.0.1.1"
    model.wireless.networkName = "Jack's Network"

    model.apply(profile: profile)

    XCTAssertEqual(model.baseStation.name, "time capsule")
    XCTAssertEqual(model.baseStation.serialNumber, "C86TEST123")
    XCTAssertEqual(model.baseStation.version, "7.9.1")
    XCTAssertEqual(model.internet.ipv4Address, "192.168.4.45")
    XCTAssertEqual(model.internet.subnetMask, "255.255.252.0")
    XCTAssertEqual(model.internet.routerAddress, "192.168.4.1")
    XCTAssertEqual(model.internet.dnsServers, "1.1.1.1, 8.8.8.8")
    XCTAssertEqual(model.internet.ipv6DNSServers, "2001:4860:4860::8888")
    XCTAssertEqual(model.network.lanIPAddress, "10.0.1.1")
    XCTAssertEqual(model.wireless.networkName, "Jack's Network")
    XCTAssertTrue(model.hasDevicePopoverDetails)
  }

  func testAllOnesIPv4SentinelDoesNotReplacePreloadedSubnetMask() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self,
      from: Data(
        """
        {
          "restoreProfile": {
            "waSM": "255.255.255.255"
          }
        }
        """.utf8))
    let model = AirportAppModel()
    model.internet.subnetMask = "255.255.252.0"

    model.apply(profile: profile)

    XCTAssertEqual(model.internet.subnetMask, "255.255.252.0")
  }

  func testUnavailableNumericSentinelsDoNotReplacePreloadedFields() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self, from: Data(Self.profileWithUnavailableNumericSentinelsJSON.utf8))
    let model = AirportAppModel()
    model.internet.connectUsing = .static
    model.internet.domainName = "example.test"
    model.wireless.mode = "create"
    model.wireless.networkName = "Jack's Network"
    model.wireless.security = "wpa2-personal"
    model.wireless.regionCode = "0"
    model.wireless.hiddenNetwork = true
    model.wireless.radioMode = "80211n-bg"
    model.wireless.radioChannel = "automatic"
    model.network.natPMP = true
    model.disks.fileSharing = true
    model.disks.secureSharedDisks = "disk-password"
    model.disks.guestAccess = "read-only"

    model.apply(profile: profile)

    XCTAssertEqual(model.internet.connectUsing, .static)
    XCTAssertEqual(model.internet.domainName, "example.test")
    XCTAssertEqual(model.wireless.mode, "create")
    XCTAssertEqual(model.wireless.networkName, "Jack's Network")
    XCTAssertEqual(model.wireless.security, "wpa2-personal")
    XCTAssertEqual(model.wireless.regionCode, "0")
    XCTAssertTrue(model.wireless.hiddenNetwork)
    XCTAssertEqual(model.wireless.radioMode, "80211n-bg")
    XCTAssertEqual(model.wireless.radioChannel, "automatic")
    XCTAssertTrue(model.network.natPMP)
    XCTAssertTrue(model.disks.fileSharing)
    XCTAssertEqual(model.disks.secureSharedDisks, "disk-password")
    XCTAssertEqual(model.disks.guestAccess, "read-only")
  }

  func testOutOfRangeNumericProfileValuesDoNotCrashOrReplacePreloadedFields() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self,
      from: Data(
        """
        {
          "restoreProfile": {
            "bsFM": 1e40,
            "bsGA": 1e40,
            "bsRM": 1e40,
            "syRe": 1e40,
            "waCV": 1e40,
            "WiFi": {
              "radios": [
                {
                  "raCh": 1e40,
                  "raCl": 1e40,
                  "raMd": 1e40,
                  "raSt": 1e40,
                  "raWM": 1e40
                }
              ]
            }
          }
        }
        """.utf8))
    let model = AirportAppModel()
    model.internet.connectUsing = .static
    model.wireless.mode = "create"
    model.wireless.security = "wpa2-personal"
    model.wireless.regionCode = "0"
    model.wireless.hiddenNetwork = true
    model.wireless.radioMode = "80211n-bg"
    model.wireless.radioChannel = "automatic"
    model.network.routerMode = .dhcpAndNat
    model.disks.secureSharedDisks = "disk-password"
    model.disks.guestAccess = "read-only"

    model.apply(profile: profile)

    XCTAssertEqual(model.internet.connectUsing, .static)
    XCTAssertEqual(model.wireless.mode, "create")
    XCTAssertEqual(model.wireless.security, "wpa2-personal")
    XCTAssertEqual(model.wireless.regionCode, "0")
    XCTAssertTrue(model.wireless.hiddenNetwork)
    XCTAssertEqual(model.wireless.radioMode, "80211n-bg")
    XCTAssertEqual(model.wireless.radioChannel, "automatic")
    XCTAssertEqual(model.network.routerMode, .dhcpAndNat)
    XCTAssertEqual(model.disks.secureSharedDisks, "disk-password")
    XCTAssertEqual(model.disks.guestAccess, "read-only")
  }

  func testApplyProfilePopulatesEncodedScalarProfileFields() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self, from: Data(Self.profileWithEncodedScalarFieldsJSON.utf8))
    let model = AirportAppModel()

    model.apply(profile: profile)

    XCTAssertEqual(model.internet.connectUsing, .static)
    XCTAssertEqual(model.internet.ipv4Address, "192.168.4.45")
    XCTAssertEqual(model.internet.subnetMask, "255.255.252.0")
    XCTAssertEqual(model.internet.routerAddress, "192.168.4.1")
    XCTAssertTrue(model.internet.dynamicGlobalHostname)
    XCTAssertEqual(model.wireless.mode, "create")
    XCTAssertEqual(model.wireless.networkName, "Encoded Network")
    XCTAssertEqual(model.wireless.security, "wpa-wpa2-personal")
    XCTAssertTrue(model.wireless.hiddenNetwork)
    XCTAssertEqual(model.wireless.radioMode, "80211n-bg")
    XCTAssertEqual(model.wireless.radioChannel, "11")
    XCTAssertEqual(model.network.routerMode, .dhcpAndNat)
    XCTAssertEqual(model.network.lanIPAddress, "10.0.1.1")
    XCTAssertEqual(model.network.defaultHost, "10.0.1.253")
    XCTAssertTrue(model.network.natPMP)
    XCTAssertTrue(model.disks.fileSharing)
    XCTAssertEqual(model.disks.secureSharedDisks, "disk-password")
    XCTAssertEqual(model.disks.guestAccess, "read-only")
  }

  func testApplyProfilePopulatesEncodedScalarValueFieldsWithoutText() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self, from: Data(Self.profileWithEncodedValueScalarFieldsJSON.utf8))
    let model = AirportAppModel()

    model.apply(profile: profile)

    XCTAssertEqual(model.internet.connectUsing, .static)
    XCTAssertTrue(model.internet.dynamicGlobalHostname)
    XCTAssertEqual(model.wireless.mode, "create")
    XCTAssertEqual(model.wireless.security, "wpa-wpa2-personal")
    XCTAssertTrue(model.wireless.hiddenNetwork)
    XCTAssertEqual(model.wireless.radioMode, "80211n-bg")
    XCTAssertEqual(model.wireless.radioChannel, "11")
    XCTAssertEqual(model.network.routerMode, .dhcpAndNat)
    XCTAssertTrue(model.network.natPMP)
    XCTAssertTrue(model.disks.fileSharing)
    XCTAssertEqual(model.disks.secureSharedDisks, "disk-password")
    XCTAssertEqual(model.disks.guestAccess, "read-only")
  }

  func testApplyProfileDecodesWhitespacePaddedEncodedScalarText() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self, from: Data(Self.profileWithWhitespaceEncodedScalarTextJSON.utf8))
    let model = AirportAppModel()

    model.apply(profile: profile)

    XCTAssertEqual(model.internet.connectUsing, .static)
    XCTAssertEqual(model.internet.configureIPv6, "automatic")
    XCTAssertTrue(model.internet.dynamicGlobalHostname)
    XCTAssertEqual(model.wireless.mode, "create")
    XCTAssertEqual(model.wireless.security, "wpa-wpa2-personal")
    XCTAssertTrue(model.wireless.hiddenNetwork)
    XCTAssertEqual(model.wireless.radioMode, "80211n-bg")
    XCTAssertEqual(model.wireless.radioChannel, "11")
    XCTAssertEqual(model.network.routerMode, .dhcpAndNat)
    XCTAssertTrue(model.disks.fileSharing)
    XCTAssertEqual(model.disks.secureSharedDisks, "disk-password")
    XCTAssertEqual(model.disks.guestAccess, "read-only")
  }

  func testApplyProfileTrimsStringFields() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self, from: Data(Self.profileWithWhitespaceStringFieldsJSON.utf8))
    let model = AirportAppModel()

    model.apply(profile: profile)

    XCTAssertEqual(model.baseStation.name, "Time Capsule")
    XCTAssertEqual(model.internet.domainName, "example.test")
    XCTAssertEqual(model.internet.pppoeAccount, "account")
    XCTAssertEqual(model.wireless.networkName, "Network")
    XCTAssertEqual(model.disks.windowsWorkgroup, "WORKGROUP")
  }

  func testEncodedZeroDefaultHostClearsDefaultHost() throws {
    let profile = try JSONDecoder().decode(
      JSONValue.self, from: Data(Self.profileWithEncodedZeroDefaultHostJSON.utf8))
    let model = AirportAppModel()
    model.network.defaultHost = "10.0.1.253"

    model.apply(profile: profile)

    XCTAssertEqual(model.network.defaultHost, "")
  }

  private static let profileJSON = """
    {
      "restoreProfile": {
        "6aut": true,
        "6cfg": 5,
        "6NS1": "2001:4860:4860::8888",
        "6NS2": "::",
        "6Wad": "2001:db8::10",
        "SMBs": "10.0.0.5",
        "SMBw": "WORKGROUP",
        "WiFi": {
          "radios": [
            {
              "raCh": 11,
              "raCl": true,
              "raMd": 6,
              "raNm": "Jack's Network",
              "raSt": 0,
              "raWM": 5
            }
          ]
        },
        "bsFM": 1,
        "bsFS": 1,
        "bsGA": 1,
        "bsRM": 0,
        "bsRF": 0,
        "raWB": true,
        "laIP": "10.0.1.1",
        "dhBg": "10.0.0.2",
        "dhEn": "10.0.0.200",
        "dhLe": 86400,
        "fssp": "disk-secret",
        "nDMZ": "0.0.0.0",
        "naFl": 1,
        "peAC": true,
        "pePW": "pppoe-secret",
        "peSC": false,
        "peSN": "service",
        "peUN": "account",
        "syNm": "time capsule",
        "syPW": "admin-secret",
        "syRe": 0,
        "waCV": 33792,
        "waD1": "1.1.1.1",
        "waD2": "8.8.8.8",
        "waD3": "0.0.0.0",
        "waDN": "example.test",
        "waIP": "192.168.4.45",
        "waRA": "192.168.4.1",
        "waSM": "255.255.252.0",
        "wbEn": true,
        "wbHN": "capsule.example.test",
        "wbHP": "host-secret",
        "wbHU": "host-user"
      }
    }
    """

  private static let dhcpDNSProfileJSON = """
    {
      "restoreProfile": {
        "6NS1": "2001:4860:4860::8888",
        "6NS2": "::",
        "waCV": 33536,
        "waD1": "192.168.4.1",
        "waD2": "1.1.1.1",
        "waD3": "0.0.0.0"
      }
    }
    """

  private static let encodedIPv4DNSProfileJSON = """
    {
      "restoreProfile": {
        "waCV": 33792,
        "waD1": {"type": "ipv4", "length": 4, "hex": "c0a80101"},
        "waD2": {"type": "ipv4", "value": "16843009"},
        "waD3": {"type": "ipv4", "length": 4, "hex": "00000000"}
      }
    }
    """

  private static let dhcpCurrentDNSProfileJSON = """
    {
      "restoreProfile": {
        "6NS1": "::",
        "6NS2": "::",
        "dhcpIPv6DNS1": "0",
        "dhcpIPv6DNS2": "::",
        "ipv6CurrentPrimaryDNSAddress": "2001:db8::1",
        "waCV": 33536,
        "waD1": "0.0.0.0",
        "waD2": "0.0.0.0",
        "waD3": "0.0.0.0",
        "dhcpDNS1": "0",
        "dhcpDNS2": "0.0.0.0",
        "currentDNS1": "192.168.1.1",
        "currentDNS2": "0.0.0.0"
      }
    }
    """

  private static let dhcpZeroDNSProfileJSON = """
    {
      "restoreProfile": {
        "6NS1": "::",
        "6NS2": "::",
        "dhcpIPv6DNS1": "0",
        "dhcpIPv6DNS2": "::",
        "waCV": 33536,
        "waD1": "0.0.0.0",
        "waD2": "0.0.0.0",
        "waD3": "0.0.0.0",
        "dhcpDNS1": "0",
        "dhcpDNS2": "0.0.0.0"
      }
    }
    """

  private static let staticZeroDNSProfileJSON = """
    {
      "restoreProfile": {
        "6NS1": "::",
        "6NS2": "::",
        "waCV": 33792,
        "waD1": "0.0.0.0",
        "waD2": "0.0.0.0",
        "waD3": "0.0.0.0"
      }
    }
    """

  private static let rawProfileJSON = """
    {
      "WiFi": {
        "radios": [
          {
            "raNm": "Raw Network",
            "raSt": 0,
            "raWM": 5
          }
        ]
      },
      "bsRM": 0,
      "laIP": "10.0.1.1",
      "syNm": "raw time capsule",
      "waCV": 33792,
      "waIP": "192.168.4.45"
    }
    """

  private static let currentProfileJSON = """
    {
      "currentProfile": 1,
      "profiles": [
        {
          "WiFi": {
            "radios": [
              {
                "raNm": "Inactive Network"
              }
            ]
          },
          "laIP": "10.0.0.1",
          "syNm": "inactive time capsule",
          "waIP": "192.168.0.1"
        },
        {
          "WiFi": {
            "radios": [
              {
                "raNm": "Active Network",
                "raSt": 0,
                "raWM": 5
              }
            ]
          },
          "bsRM": 0,
          "laIP": "10.0.1.1",
          "syNm": "active time capsule",
          "waCV": 33792,
          "waIP": "192.168.4.45"
        }
      ]
    }
    """

  private static let offWirelessProfileJSON = """
    {
      "restoreProfile": {
        "WiFi": {
          "radios": [
            {
              "raNm": "Stale Network",
              "raSt": 3
            }
          ]
        },
        "bsNM": 3,
        "syNm": "time capsule"
      }
    }
    """

  private static let profileWithRadioWirelessPasswordJSON = """
    {
      "restoreProfile": {
        "WiFi": {
          "radios": [
            {
              "raWE": {
                "type": "bytes",
                "length": 17,
                "text": "radio-wifi-secret",
                "hex": "726164696f2d776966692d736563726574"
              }
            }
          ]
        }
      }
    }
    """

  private static let profileWithRadioClearWirelessPasswordJSON = """
    {
      "restoreProfile": {
        "WiFi": {
          "radios": [
            {
              "raCr": {
                "type": "bytes",
                "length": 17,
                "text": "clear-wifi-secret",
                "hex": "636c6561722d776966692d736563726574"
              },
              "raWE": {
                "type": "bytes",
                "length": 14,
                "text": "derived-secret",
                "hex": "646572697665642d736563726574"
              }
            }
          ]
        }
      }
    }
    """

  private static let profileWithoutWirelessOrDiskPasswordJSON = """
    {
      "restoreProfile": {
        "WiFi": {
          "radios": [
            {
              "raWM": 5
            }
          ]
        },
        "bsFM": 1
      }
    }
    """

  private static let profileWithNoPasswordModesJSON = """
    {
      "restoreProfile": {
        "WiFi": {
          "radios": [
            {
              "raWM": 1
            }
          ]
        },
        "bsFM": 2
      }
    }
    """

  private static let profileWithIPv6ModeButNoAutoconfigureFlagJSON = """
    {
      "restoreProfile": {
        "6cfg": 5
      }
    }
    """

  private static let profileWithLinkLocalIPv6ModeJSON = """
    {
      "restoreProfile": {
        "6cfg": 0
      }
    }
    """

  private static let profileWithoutAdminPasswordJSON = """
    {
      "restoreProfile": {
        "syNm": "time capsule",
        "waCV": 33792
      }
    }
    """

  private static let profileWithoutDefaultHostJSON = """
    {
      "restoreProfile": {
        "bsRM": 0,
        "dhBg": "10.0.1.2",
        "dhEn": "10.0.1.200"
      }
    }
    """

  private static let profileWithoutPPPoEPolicyJSON = """
    {
      "restoreProfile": {
        "waCV": 35072,
        "peUN": "account-name",
        "peSN": "service-name"
      }
    }
    """

  private static let profileWithDisabledGlobalHostnameJSON = """
    {
      "restoreProfile": {
        "wbEn": false
      }
    }
    """

  private static let profileWithEnabledGlobalHostnameJSON = """
    {
      "restoreProfile": {
        "wbEn": true,
        "wbHN": "capsule.example.test"
      }
    }
    """

  private static let profileWithUnavailablePlaceholdersJSON = """
    {
      "restoreProfile": {
        "6NS1": "--",
        "6NS2": "--",
        "WiFi": {
          "radios": [
            {
              "raNm": "--"
            }
          ]
        },
        "laIP": "--",
        "syNm": "--",
        "waD1": "--",
        "waD2": "--",
        "waD3": "--",
        "waIP": "--",
        "waRA": "--",
        "waSM": "--"
      }
    }
    """

  private static let profileWithUnavailableNumericSentinelsJSON = """
    {
      "restoreProfile": {
        "WiFi": {
          "radios": [
            {
              "raCh": -1,
              "raCl": -1,
              "raMd": -1,
              "raNm": "4294967295",
              "raSt": -1,
              "raWM": -1
            }
          ]
        },
        "bsFM": -1,
        "bsFS": -1,
        "bsGA": -1,
        "syRe": -1,
        "waCV": -1,
        "waDN": "0xffffffff",
        "naFl": -1
      }
    }
    """

  private static let profileWithEncodedScalarFieldsJSON = """
    {
      "restoreProfile": {
        "6aut": {"type": "bool", "text": "true"},
        "WiFi": {
          "radios": [
            {
              "raCh": {"type": "int", "text": "11"},
              "raCl": {"type": "bool", "text": "true"},
              "raMd": {"type": "int", "text": "6"},
              "raNm": {
                "type": "bytes",
                "length": 15,
                "text": "Encoded Network",
                "hex": "456e636f646564204e6574776f726b"
              },
              "raSt": {"type": "int", "text": "0"},
              "raWM": {"type": "int", "text": "5"}
            }
          ]
        },
        "bsFM": {"type": "int", "text": "1"},
        "bsFS": {"type": "bool", "text": "true"},
        "bsGA": {"type": "int", "text": "1"},
        "bsNM": {"type": "int", "text": "0"},
        "bsRM": {"type": "int", "text": "0"},
        "bsRF": {"type": "bool", "text": "false"},
        "laIP": {"type": "ipv4", "length": 4, "hex": "0a000101"},
        "naFl": {"type": "int", "text": "1"},
        "nDMZ": 167772669,
        "waCV": {"type": "int", "text": "33792"},
        "waIP": {"type": "ipv4", "length": 4, "hex": "c0a8042d"},
        "waRA": {"type": "ipv4", "length": 4, "hex": "c0a80401"},
        "waSM": {"type": "ipv4", "length": 4, "hex": "fffffc00"},
        "wbEn": {"type": "bool", "text": "true"}
      }
    }
    """

  private static let profileWithEncodedValueScalarFieldsJSON = """
    {
      "restoreProfile": {
        "WiFi": {
          "radios": [
            {
              "raCh": {"type": "int", "value": "11"},
              "raCl": {"type": "bool", "value": true},
              "raMd": {"type": "int", "value": "6"},
              "raSt": {"type": "int", "value": "0"},
              "raWM": {"type": "int", "value": "5"}
            }
          ]
        },
        "bsFM": {"type": "int", "value": "1"},
        "bsFS": {"type": "bool", "value": true},
        "bsGA": {"type": "int", "value": "1"},
        "bsNM": {"type": "int", "value": "0"},
        "bsRM": {"type": "int", "value": "0"},
        "naFl": {"type": "int", "value": "1"},
        "waCV": {"type": "int", "value": "33792"},
        "wbEn": {"type": "bool", "value": true}
      }
    }
    """

  private static let profileWithWhitespaceEncodedScalarTextJSON = """
    {
      "restoreProfile": {
        "6aut": {"type": "bool", "text": " true "},
        "WiFi": {
          "radios": [
            {
              "raCh": {"type": "int", "text": " 11 "},
              "raCl": {"type": "bool", "text": " true "},
              "raMd": {"type": "int", "text": " 6 "},
              "raSt": {"type": "int", "text": " 0 "},
              "raWM": {"type": "int", "text": " 5 "}
            }
          ]
        },
        "bsFM": {"type": "int", "text": " 1 "},
        "bsFS": {"type": "int", "text": " 1 "},
        "bsGA": {"type": "int", "text": " 1 "},
        "bsRM": {"type": "int", "text": " 0 "},
        "waCV": {"type": "int", "text": " 33792 "},
        "wbEn": {"type": "bool", "text": " true "}
      }
    }
    """

  private static let profileWithWhitespaceStringFieldsJSON = """
    {
      "restoreProfile": {
        "WiFi": {
          "radios": [
            {
              "raNm": {
                "type": "bytes",
                "text": " Network "
              }
            }
          ]
        },
        "peUN": " account ",
        "SMBw": " WORKGROUP ",
        "syNm": " Time Capsule ",
        "waDN": {
          "type": "string",
          "text": " example.test "
        }
      }
    }
    """

  private static let profileWithEncodedZeroDefaultHostJSON = """
    {
      "restoreProfile": {
        "nDMZ": {"type": "ipv4", "length": 4, "hex": "00000000"}
      }
    }
    """
}
