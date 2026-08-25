import AppKit
import XCTest

@testable import AirPortUtilityCore

private final class MemoryAirportPasswordStore: AirportPasswordStore {
  var passwords: [String: String] = [:]

  func password(for host: String) -> String? {
    passwords[AirportConnection.normalizedHost(host)]
  }

  func savePassword(_ password: String, for host: String) {
    passwords[AirportConnection.normalizedHost(host)] = password
  }

  func deletePassword(for host: String) {
    passwords.removeValue(forKey: AirportConnection.normalizedHost(host))
  }
}

private actor TestAsyncGate {
  private var isReleased = false

  func wait() async throws {
    while !isReleased {
      try await Task.sleep(nanoseconds: 1_000_000)
    }
  }

  func release() {
    isReleased = true
  }
}

private enum WirelessClientTestError: Error {
  case unavailable
}

@MainActor
final class PaneFlagTests: XCTestCase {
  private func fixtureURL(
    _ text: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws -> URL {
    try XCTUnwrap(URL(string: text), file: file, line: line)
  }

  private func detectInternetOptionsSupport(
    _ model: AirportAppModel,
    supportsIPv6: Bool = true,
    supportsDynamicGlobalHostname: Bool = true,
    supportsClassicWDS: Bool? = nil
  ) {
    model.applyAuthoritativeBaseStationIdentity(
      readName: "Time Capsule",
      serialNumber: "C86TEST123",
      version: "7.9.1",
      productID: "106",
      supportsIPv6: supportsIPv6,
      supportsDynamicGlobalHostname: supportsDynamicGlobalHostname,
      supportsClassicWDS: supportsClassicWDS)
  }

  func testTopologyTreesKeepIndependentDevicesSideBySide() {
    let capsule = AirportDiscoveredDevice(
      id: "capsule",
      name: "Studio Capsule",
      hostName: "studio-capsule.local",
      modelName: "AirPort Time Capsule",
      productID: "106")
    let extreme = AirportDiscoveredDevice(
      id: "extreme",
      name: "Guest Extreme",
      hostName: "guest-extreme.local",
      modelName: "AirPort Extreme",
      productID: "117")

    let trees = AirportAppModel.topologyTrees(from: [capsule, extreme])

    XCTAssertEqual(trees.map(\.device.id), ["capsule", "extreme"])
    XCTAssertTrue(trees.allSatisfy(\.children.isEmpty))
  }

  func testTopologyTreesNestDevicesThatExtendAnotherDevice() {
    let capsule = AirportDiscoveredDevice(
      id: "capsule",
      name: "Studio Capsule",
      hostName: "studio-capsule.local",
      modelName: "AirPort Time Capsule",
      productID: "106")
    let express = AirportDiscoveredDevice(
      id: "express",
      name: "Studio Express",
      hostName: "studio-express.local",
      extendsDeviceID: "capsule",
      modelName: "AirPort Express",
      productID: "115")

    let trees = AirportAppModel.topologyTrees(from: [capsule, express])

    XCTAssertEqual(trees.count, 1)
    XCTAssertEqual(trees.first?.device.id, "capsule")
    XCTAssertEqual(trees.first?.children.map(\.device.id), ["express"])
  }

  func testMostUpstreamAirPortChoosesTopologyRootInsteadOfExtender() {
    let model = AirportAppModel(passwordStore: MemoryAirportPasswordStore())
    let capsule = AirportDiscoveredDevice(
      id: "capsule", name: "Time Capsule", hostName: "time-capsule.local",
      modelName: "AirPort Time Capsule")
    let express = AirportDiscoveredDevice(
      id: "express", name: "Office Express", hostName: "office-express.local",
      extendsDeviceID: capsule.id, modelName: "AirPort Express")

    XCTAssertEqual(model.mostUpstreamAirPort(from: [express, capsule])?.id, capsule.id)
  }

  func testLaunchConnectionSelectsMostUpstreamAirPort() {
    let model = AirportAppModel(passwordStore: MemoryAirportPasswordStore())
    let capsule = AirportDiscoveredDevice(
      id: "capsule", name: "Time Capsule", hostName: "time-capsule.local",
      modelName: "AirPort Time Capsule")
    let express = AirportDiscoveredDevice(
      id: "express", name: "Office Express", hostName: "office-express.local",
      extendsDeviceID: capsule.id, modelName: "AirPort Express")
    model.updateDiscoveredDevices([express, capsule])

    model.connectToMostUpstreamAirPortOnLaunch()

    XCTAssertEqual(model.selectedTopologyDeviceID, capsule.id)
    XCTAssertEqual(model.connection.host, "time-capsule.local")
    XCTAssertEqual(model.status, "Enter base station password to load settings.")
  }

  func testManualTopologySelectionCancelsAutomaticLaunchSelection() {
    let model = AirportAppModel(passwordStore: MemoryAirportPasswordStore())
    let capsule = AirportDiscoveredDevice(
      id: "capsule", name: "Time Capsule", hostName: "time-capsule.local",
      modelName: "AirPort Time Capsule")
    let express = AirportDiscoveredDevice(
      id: "express", name: "Office Express", hostName: "office-express.local",
      extendsDeviceID: capsule.id, modelName: "AirPort Express")
    model.updateDiscoveredDevices([express, capsule])
    model.selectTopologyDevice(express)

    model.connectToMostUpstreamAirPortOnLaunch()

    XCTAssertEqual(model.selectedTopologyDeviceID, express.id)
    XCTAssertEqual(model.connection.host, "office-express.local")
  }

  func testTopologyConnectionUsesWirelessClientMACToSelectDottedStyle() {
    let model = AirportAppModel()
    model.connection.host = "time-capsule.local"
    let capsule = AirportDiscoveredDevice(
      id: "capsule",
      name: "Time Capsule",
      hostName: "time-capsule.local")
    let wirelessExpress = AirportDiscoveredDevice(
      id: "wireless-express",
      name: "Garage APE",
      hostName: "garage-ape.local",
      identifiers: ["rama:d0-03-4b-64-aa-4e"],
      extendsDeviceID: capsule.id)
    let wiredExpress = AirportDiscoveredDevice(
      id: "wired-express",
      name: "Library APE",
      hostName: "library-ape.local",
      identifiers: ["rama:20-c9-d0-a3-1f-0e"],
      extendsDeviceID: capsule.id)
    model.wirelessClients = [
      WirelessClient(
        macAddress: "D0:03:4B:64:AA:4E",
        ipAddress: "",
        hostname: "")
    ]

    XCTAssertTrue(model.isWirelessTopologyConnection(from: wirelessExpress, to: capsule))
    XCTAssertFalse(model.isWirelessTopologyConnection(from: wiredExpress, to: capsule))
  }

  func testTopologyTreesSupportMixedIndependentAndExtendedDevices() {
    let capsule = AirportDiscoveredDevice(
      id: "capsule",
      name: "Studio Capsule",
      hostName: "studio-capsule.local",
      modelName: "AirPort Time Capsule",
      productID: "106")
    let express = AirportDiscoveredDevice(
      id: "express",
      name: "Studio Express",
      hostName: "studio-express.local",
      extendsDeviceID: "capsule",
      modelName: "AirPort Express",
      productID: "115")
    let extreme = AirportDiscoveredDevice(
      id: "extreme",
      name: "Guest Extreme",
      hostName: "guest-extreme.local",
      modelName: "AirPort Extreme",
      productID: "117")

    let trees = AirportAppModel.topologyTrees(from: [capsule, express, extreme])

    XCTAssertEqual(trees.map(\.device.id), ["capsule", "extreme"])
    XCTAssertEqual(trees.first?.children.map(\.device.id), ["express"])
    XCTAssertEqual(trees.last?.children.count, 0)
  }

  func testMainWindowWidthStaysDefaultForThreeTopologyRoots() {
    let size = AirPortMainWindowMetrics.contentSize(forTopologyRootCount: 3)

    XCTAssertEqual(size.width, 800)
    XCTAssertEqual(size.height, 504)
  }

  func testMainWindowWidthExpandsForFourTopologyRoots() {
    let size = AirPortMainWindowMetrics.contentSize(forTopologyRootCount: 4)

    XCTAssertEqual(size.width, 1072)
    XCTAssertEqual(size.height, 504)
  }

  func testConfigurationSheetWidthExpandsToFitSevenTabs() {
    let panes: [Pane] = [
      .baseStation, .internet, .wireless, .network, .airPlay, .advanced, .firmware,
    ]

    XCTAssertEqual(AirPortLayout.topTabsWidth(for: panes), 544)
    XCTAssertEqual(AirPortLayout.configurationSheetWidth(for: panes), 640)
    XCTAssertEqual(
      AirPortLayout.configurationSheetWidth(for: panes) - AirPortLayout.topTabsWidth(for: panes),
      96)
    XCTAssertGreaterThan(
      AirPortLayout.configurationSheetWidth(for: panes),
      AirPortLayout.defaultConfigurationSheetWidth)
  }

  func testMainWindowExpandsToFitConfigurationSheet() {
    let panes: [Pane] = [
      .baseStation, .internet, .wireless, .network, .airPlay, .advanced, .firmware,
    ]

    let size = AirPortMainWindowMetrics.contentSize(
      forTopologyRootCount: 1,
      configurationPanes: panes)

    XCTAssertGreaterThanOrEqual(size.width, AirPortLayout.configurationSheetWidth(for: panes))
    XCTAssertEqual(size.height, AirPortLayout.configurationSheetHeight)
  }

  func testConfigurationSheetFooterHasDedicatedVerticalSeparation() {
    XCTAssertEqual(AirPortLayout.configurationFooterTopPadding, 12)
    XCTAssertEqual(AirPortLayout.configurationSheetHeight, 579)
    XCTAssertEqual(
      AirPortLayout.configurationSheetInsetHeight,
      AirPortLayout.configurationSheetHeight - 42)
  }

  func testDiscoveredDeviceIdentityListsAreNormalizedAndDeduplicated() {
    let device = AirportDiscoveredDevice(
      id: "capsule",
      name: "Studio Capsule",
      hostName: " Time-Capsule.local. ",
      addresses: ["time-capsule.local", "192.168.4.45", "192.168.4.45"],
      identifiers: [" WAMA:00-11-22-33-44-55 ", "wama:00-11-22-33-44-55", ""])

    XCTAssertEqual(
      device.normalizedConnectionHosts,
      ["time-capsule.local", "192.168.4.45"])
    XCTAssertEqual(device.normalizedStableIdentifiers, ["wama:00-11-22-33-44-55"])
  }

  func testFirmwareUpdateBadgeAppearsOnlyOnConnectedDeviceWithNewerAppleFirmware() throws {
    let capsule = AirportDiscoveredDevice(
      id: "capsule",
      name: "Studio Capsule",
      hostName: "studio-capsule.local",
      identifiers: ["CAPSULE-ID"],
      modelName: "AirPort Time Capsule",
      productID: "106")
    let express = AirportDiscoveredDevice(
      id: "express",
      name: "Studio Express",
      hostName: "studio-express.local",
      modelName: "AirPort Express",
      productID: "115")
    let model = AirportAppModel()
    model.updateDiscoveredDevices([capsule, express])
    model.selectTopologyDevice(capsule)
    model.applyAuthoritativeBaseStationIdentity(
      readName: "Studio Capsule",
      serialNumber: "CAPSULE",
      version: "7.6.9",
      productID: "106")
    model.firmware.images = [
      FirmwareImage(
        productID: "106",
        version: "7.8.1",
        sourceVersion: "78100.3",
        location: try fixtureURL("https://apsu.apple.com/106/7.8.1.basebinary"),
        sizeInBytes: 40,
        newest: true)
    ]

    XCTAssertEqual(model.firmwareUpdateBadgeCount(for: capsule), 1)
    XCTAssertEqual(model.firmwareUpdateBadgeCount(for: express), 0)
    XCTAssertEqual(model.selectedDeviceFirmwareUpdateBadgeCount, 1)
    XCTAssertEqual(model.selectedDeviceFirmwareUpdateDetail, "Firmware 7.8.1 available")
  }

  func testFirmwareUpdateBadgePersistsWhenAnotherDeviceIsSelected() throws {
    let capsule = AirportDiscoveredDevice(
      id: "capsule",
      name: "Studio Capsule",
      hostName: "studio-capsule.local",
      identifiers: ["wama:00-11-22-33-44-55"],
      modelName: "AirPort Time Capsule",
      productID: "106")
    let extreme = AirportDiscoveredDevice(
      id: "extreme",
      name: "Studio Extreme",
      hostName: "studio-extreme.local",
      identifiers: ["wama:66-77-88-99-aa-bb"],
      modelName: "AirPort Extreme",
      productID: "120")
    let model = AirportAppModel()
    model.updateDiscoveredDevices([capsule, extreme])
    model.selectTopologyDevice(capsule)
    model.applyAuthoritativeBaseStationIdentity(
      readName: "Studio Capsule",
      serialNumber: "CAPSULE",
      version: "7.6.9",
      productID: "106")
    model.firmware.images = [
      FirmwareImage(
        productID: "106",
        version: "7.8.1",
        sourceVersion: "78100.3",
        location: try fixtureURL("https://apsu.apple.com/106/7.8.1.basebinary"),
        sizeInBytes: 40,
        newest: true)
    ]
    model.applyAuthoritativeBaseStationIdentity(
      readName: "Studio Capsule",
      serialNumber: "CAPSULE",
      version: "7.6.9",
      productID: "106")

    model.selectTopologyDevice(extreme)
    model.firmware.images = []
    model.applyAuthoritativeBaseStationIdentity(
      readName: "Studio Extreme",
      serialNumber: "EXTREME",
      version: "7.9.1",
      productID: "120")

    XCTAssertEqual(model.firmwareUpdateBadgeCount(for: capsule), 1)
    XCTAssertEqual(model.firmwareUpdateBadgeCount(for: extreme), 0)

    model.selectTopologyDevice(capsule)
    XCTAssertEqual(model.selectedDeviceFirmwareUpdateBadgeCount, 1)
    XCTAssertEqual(model.selectedDeviceFirmwareUpdateDetail, "Firmware 7.8.1 available")
  }

  func testFirmwareUpdateBadgeClearsWhenSelectedDeviceNoLongerHasUpdate() throws {
    let capsule = AirportDiscoveredDevice(
      id: "capsule",
      name: "Studio Capsule",
      hostName: "studio-capsule.local",
      identifiers: ["wama:00-11-22-33-44-55"],
      modelName: "AirPort Time Capsule",
      productID: "106")
    let model = AirportAppModel()
    model.updateDiscoveredDevices([capsule])
    model.selectTopologyDevice(capsule)
    model.applyAuthoritativeBaseStationIdentity(
      readName: "Studio Capsule",
      serialNumber: "CAPSULE",
      version: "7.6.9",
      productID: "106")
    model.firmware.images = [
      FirmwareImage(
        productID: "106",
        version: "7.8.1",
        sourceVersion: "78100.3",
        location: try fixtureURL("https://apsu.apple.com/106/7.8.1.basebinary"),
        sizeInBytes: 40,
        newest: true)
    ]
    model.applyAuthoritativeBaseStationIdentity(
      readName: "Studio Capsule",
      serialNumber: "CAPSULE",
      version: "7.6.9",
      productID: "106")

    XCTAssertEqual(model.firmwareUpdateBadgeCount(for: capsule), 1)

    model.applyAuthoritativeBaseStationIdentity(
      readName: "Studio Capsule",
      serialNumber: "CAPSULE",
      version: "7.8.1",
      productID: "106")

    XCTAssertEqual(model.firmwareUpdateBadgeCount(for: capsule), 0)
    XCTAssertEqual(model.selectedDeviceFirmwareUpdateBadgeCount, 0)
  }

  func testFirmwareUpdateBadgeIgnoresCurrentAndChosenFirmwareImages() throws {
    let capsule = AirportDiscoveredDevice(
      id: "capsule",
      name: "Studio Capsule",
      hostName: "studio-capsule.local",
      modelName: "AirPort Time Capsule",
      productID: "106")
    let model = AirportAppModel()
    model.updateDiscoveredDevices([capsule])
    model.selectTopologyDevice(capsule)
    model.applyAuthoritativeBaseStationIdentity(
      readName: "Studio Capsule",
      serialNumber: "CAPSULE",
      version: "7.8.1",
      productID: "106")
    model.firmware.images = [
      FirmwareImage(
        productID: "106",
        version: "7.8.1",
        sourceVersion: "78100.3",
        location: try fixtureURL("https://apsu.apple.com/106/7.8.1.basebinary"),
        sizeInBytes: 40,
        newest: true),
      FirmwareImage(
        productID: "106",
        version: "7.9.1",
        sourceVersion: "chosen-local",
        location: URL(fileURLWithPath: "/tmp/7.9.1.basebinary"),
        sizeInBytes: 40,
        newest: true),
    ]

    XCTAssertEqual(model.firmwareUpdateBadgeCount(for: capsule), 0)
    XCTAssertEqual(model.selectedDeviceFirmwareUpdateBadgeCount, 0)
    XCTAssertEqual(model.selectedDeviceFirmwareUpdateDetail, "")
  }

  func testFirmwareUpdateEditActionOpensFirmwarePane() {
    let model = AirportAppModel()
    model.applyAuthoritativeBaseStationIdentity(
      readName: "Studio Capsule",
      serialNumber: "CAPSULE",
      version: "7.6.9",
      productID: "106")

    model.beginEditingFirmware()

    XCTAssertTrue(model.isEditingDevice)
    XCTAssertEqual(model.selectedPane, .firmware)
  }

  func testTopologyImageFallsBackToModelAndDeviceNameWhenProductIDIsMissing() {
    XCTAssertEqual(
      AirportDiscoveredDevice(
        id: "capsule",
        name: "Time Capsule",
        hostName: "time-capsule.local"
      ).topologyImageName,
      "TimeCapsule-3D-cropped~mac.tiff")

    XCTAssertEqual(
      AirportDiscoveredDevice(
        id: "express",
        name: "Studio",
        hostName: "studio.local",
        modelName: "AirPort Express"
      ).topologyImageName,
      "AirPortExpress-3D-cropped~mac.tiff")

    XCTAssertEqual(
      AirportDiscoveredDevice(
        id: "extreme",
        name: "Guest",
        hostName: "guest.local",
        modelName: "AirPort Extreme"
      ).topologyImageName,
      "AirPortExtremeN-3D-cropped~mac.tiff")

    XCTAssertEqual(
      AirportDiscoveredDevice(
        id: "unknown",
        name: "Base Station",
        hostName: "base-station.local"
      ).topologyImageName,
      "GenericBase-3D-cropped~mac.tiff")
  }

  func testBonjourProductIDSelectsResetExpressIcon() {
    let fields = AirPortBonjourBrowser.airportTXTFields(from: [
      "syDs": Data("Apple\\ Base\\ Station\\ V6.3".utf8),
      "syAP": Data("102".utf8),
    ])
    let device = AirportDiscoveredDevice(
      id: "reset-express",
      name: "Base Station 21f58f",
      hostName: "Base-Station-21f58f.local.",
      txtFields: fields,
      modelName: AirPortBonjourBrowser.modelName(fromTXTFields: fields),
      productID: fields["syap"] ?? "")

    XCTAssertEqual(device.productID, "102")
    XCTAssertEqual(device.displayModelName, "AirPort Express")
    XCTAssertEqual(device.topologyImageName, "AirPortExpress-3D-cropped~mac.tiff")
  }

  func testBonjourProductIDSelectsLegacyExtremeIcon() {
    let fields = AirPortBonjourBrowser.airportTXTFields(from: [
      "syDs": Data("Apple\\ Base\\ Station\\ V5.7".utf8),
      "syAP": Data("3".utf8),
    ])
    let device = AirportDiscoveredDevice(
      id: "legacy-extreme",
      name: "Base Station 9f1234",
      hostName: "Base-Station-9f1234.local.",
      txtFields: fields,
      modelName: AirPortBonjourBrowser.modelName(fromTXTFields: fields),
      productID: fields["syap"] ?? "")

    XCTAssertEqual(device.productID, "3")
    XCTAssertEqual(device.displayModelName, "AirPort Extreme")
    XCTAssertEqual(device.topologyImageName, "AirPortExtremeG-3D-cropped~mac.tiff")
  }

  func testBonjourProductIDSelectsUprightExtremeIcon() {
    let fields = AirPortBonjourBrowser.airportTXTFields(from: [
      "syDs": Data("AirPort\\ Extreme\\ 802.11ac\\ V7.9.1".utf8),
      "syAP": Data("120".utf8),
    ])
    let device = AirportDiscoveredDevice(
      id: "upright-extreme",
      name: "Office Extreme",
      hostName: "Office-Extreme.local.",
      txtFields: fields,
      modelName: AirPortBonjourBrowser.modelName(fromTXTFields: fields),
      productID: fields["syap"] ?? "")

    XCTAssertEqual(device.productID, "120")
    XCTAssertEqual(device.displayModelName, "AirPort Extreme 802.11ac")
    XCTAssertEqual(device.topologyImageName, "AirPort-8-3D-cropped~mac.tiff")
  }

  func testTowerTimeCapsuleUsesUprightIcon() {
    let device = AirportDiscoveredDevice(
      id: "tower-capsule",
      name: "Office Time Capsule",
      hostName: "office-time-capsule.local",
      modelName: "AirPort Time Capsule 802.11ac",
      productID: "119")

    XCTAssertEqual(device.topologyImageName, "AirPort-8-3D-cropped~mac.tiff")
  }

  func testMockDiscoveryHonorsConfiguredProductIdentity() throws {
    let devices = AirportMockBackend.discoveredDevices(
      statusText: "Working normally",
      environmentValue: { key in
        key == "AIRPORT_UTILITY_MOCK_PRODUCT_ID" ? "119" : nil
      })
    let device = try XCTUnwrap(devices.first)

    XCTAssertEqual(device.productID, "119")
    XCTAssertEqual(device.modelName, "AirPort Time Capsule")
    XCTAssertEqual(device.topologyImageName, "AirPort-8-3D-cropped~mac.tiff")
  }

  func testMockStateMarksConnectionPasswordAsRemembered() {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let model = AirportAppModel()

    XCTAssertTrue(model.rememberConnectionPassword)
  }

  func testMockProductIdentityDefaultsWhenConfiguredValueIsBlank() {
    XCTAssertEqual(
      AirportMockBackend.productID(environmentValue: { _ in "  " }),
      "106")
  }

  func testReplacementArtworkLoadsImagesForLegacyIconNames() {
    let legacyNames = [
      "Internet-3D~mac.tiff",
      "AirPortExpress-3D-cropped~mac.tiff",
      "AirPortEx-3D-cropped~mac.tiff",
      "TimeCapsule-3D-cropped~mac.tiff",
      "AirPort-8-3D-cropped~mac.tiff",
      "AirPortExtremeN-3D-cropped~mac.tiff",
      "AirPortExtremeG-3D-cropped~mac.tiff",
      "GenericBase-3D-cropped~mac.tiff",
      "AirDisk.icns",
      "Drives.icns",
    ]

    for legacyName in legacyNames {
      XCTAssertEqual(
        AirPortReplacementArtwork.resourceName(for: legacyName),
        legacyName,
        "Expected to use original AirPort Utility artwork for \(legacyName)")
      XCTAssertNotNil(
        airPortReplacementNSImage(named: legacyName),
        "Expected replacement artwork for \(legacyName)")
    }
  }

  func testDeviceStatusTextMapsKnownProblemCodes() {
    XCTAssertEqual(AirportAppModel.deviceStatusText(problemCodes: []), "Working normally")
    XCTAssertEqual(AirportAppModel.deviceStatusText(problemCodes: ["ArcI"]), "Archiving disk")
    XCTAssertEqual(AirportAppModel.deviceStatusText(problemCodes: ["fsck"]), "Disk needs repair")
    XCTAssertEqual(
      AirportAppModel.deviceStatusText(problemCodes: ["vErr01"]), "Configuration problem")
    XCTAssertEqual(AirportAppModel.deviceStatusText(problemCodes: ["DubN"]), "Double NAT")
    XCTAssertEqual(AirportAppModel.deviceStatusText(problemCodes: ["pubP"]), "Default password")
    XCTAssertEqual(
      AirportAppModel.deviceStatusText(problemCodes: ["opNW"]), "Open wireless network")
    XCTAssertEqual(
      AirportAppModel.deviceStatusText(problemCodes: ["waCF"]), "WAN setup over Ethernet")
  }

  func testDeviceStatusDetailExplainsDoubleNATBridgeMismatch() {
    XCTAssertEqual(
      AirportAppModel.deviceStatusDetail(problemCodes: ["DubN"], routerMode: .bridge),
      "Reports Double NAT despite Bridge Mode.")
    XCTAssertEqual(
      AirportAppModel.deviceStatusDetail(problemCodes: ["DubN"], routerMode: .dhcpAndNat),
      "Another router appears to be providing NAT upstream of this base station.")
  }

  func testDeviceStatusDetailsIncludeMultipleReportedProblems() {
    XCTAssertEqual(
      AirportAppModel.deviceStatusDetails(
        problemCodes: ["waCF", "DubN", "opNW"],
        routerMode: .bridge),
      [
        "Reports Double NAT despite Bridge Mode.",
        "The wireless network is open and does not require a Wi-Fi password.",
        "Setup over the Ethernet WAN port is enabled.",
      ])
  }

  func testApplyDeviceStatusPreservesProblemCodesForDetails() {
    let model = AirportAppModel()
    model.network.routerMode = .bridge

    model.applyDeviceStatus(problemCodes: ["waCF", "DubN"])

    XCTAssertEqual(model.baseStation.problemCodes, ["waCF", "DubN"])
    XCTAssertEqual(model.selectedDeviceStatusText(), "Double NAT")
    XCTAssertEqual(model.selectedDeviceStatusDetail(), "Reports Double NAT despite Bridge Mode.")
    XCTAssertEqual(
      model.selectedDeviceStatusDetails(),
      [
        "Reports Double NAT despite Bridge Mode.",
        "Setup over the Ethernet WAN port is enabled.",
      ])
  }

  func testLiveRemoteConfigurationBlockOverridesProfileWANSetupFlag() throws {
    let model = AirportAppModel()

    let value = try JSONDecoder().decode(
      JSONValue.self,
      from: Data(
        """
        {
          "settings": {
            "Prof": {
              "decoded": {
                "restoreProfile": {
                  "raWB": false
                }
              }
            },
            "waNM": {
              "value": "0"
            },
            "sySt": {
              "decoded": {
                "problems": [
                  "waCF",
                  "DubN"
                ]
              }
            }
          }
        }
        """.utf8))

    model.apply(profile: value)
    if let allowSetupOverWAN = AirportAppModel.liveAllowSetupOverWANForTesting(
      reader: ProfileReader(value))
    {
      model.baseStation.allowSetupOverWAN = allowSetupOverWAN
    }

    XCTAssertTrue(model.baseStation.allowSetupOverWAN)
  }

  func testLiveRemoteConfigurationUsesDirectWANSetupFlagWhenAvailable() throws {
    let value = try JSONDecoder().decode(
      JSONValue.self,
      from: Data(
        """
        {
          "settings": {
            "raWB": {
              "value": "0"
            },
            "waNM": {
              "value": "0"
            }
          }
        }
        """.utf8))

    let allowSetupOverWAN = AirportAppModel.liveAllowSetupOverWANForTesting(
      reader: ProfileReader(value))

    XCTAssertEqual(allowSetupOverWAN, false)
  }

  func testBonjourProblemTXTRecordDrivesDeviceStatusText() {
    let fields = AirPortBonjourBrowser.airportTXTFields(from: [
      "prob": Data("waCF;opNW;pubP;+".utf8)
    ])
    let device = AirportDiscoveredDevice(
      id: "warning-capsule",
      name: "time capsule",
      hostName: "time-capsule.local.",
      txtFields: fields)

    XCTAssertEqual(device.problemCodes, ["waCF", "opNW", "pubP"])
    XCTAssertEqual(AirportAppModel().deviceStatusText(for: device), "Default password")
  }

  func testBonjourTXTRecordUpdateClearsTransientProblemWithoutRescan() async throws {
    var updates: [[AirportDiscoveredDevice]] = []
    let browser = AirPortBonjourBrowser { devices in
      updates.append(devices)
    }
    defer { browser.stop() }
    let service = NetService(
      domain: "local.",
      type: "_airport._tcp.",
      name: "airport extreme",
      port: 5009)
    let discoveryBrowser = NetServiceBrowser()
    let identityFields = [
      "syAP": Data("120".utf8),
      "waMA": Data("80-EA-96-E7-9E-E3".utf8),
    ]
    var warningFields = identityFields
    warningFields["prob"] = Data("nDNS".utf8)

    browser.netServiceBrowser(
      discoveryBrowser, didFind: service, moreComing: false)
    await Task.yield()
    browser.netService(
      service,
      didUpdateTXTRecord: NetService.data(fromTXTRecord: warningFields))
    await Task.yield()

    let warningDevice = try XCTUnwrap(updates.last?.first)
    XCTAssertEqual(warningDevice.problemCodes, ["nDNS"])
    XCTAssertEqual(
      AirportAppModel().deviceStatusText(for: warningDevice), "No DNS servers configured")

    browser.netService(
      service,
      didUpdateTXTRecord: NetService.data(fromTXTRecord: identityFields))
    await Task.yield()

    let healthyDevice = try XCTUnwrap(updates.last?.first)
    XCTAssertTrue(healthyDevice.problemCodes.isEmpty)
    XCTAssertEqual(AirportAppModel().deviceStatusText(for: healthyDevice), "Working normally")

    browser.netServiceBrowser(
      discoveryBrowser, didRemove: service, moreComing: false)
    await Task.yield()

    XCTAssertTrue(try XCTUnwrap(updates.last).isEmpty)
    let updateCountAfterRemoval = updates.count

    browser.netService(
      service,
      didUpdateTXTRecord: NetService.data(fromTXTRecord: warningFields))
    browser.netServiceDidResolveAddress(service)
    browser.netService(service, didNotResolve: [:])
    await Task.yield()

    XCTAssertEqual(updates.count, updateCountAfterRemoval)
    XCTAssertTrue(try XCTUnwrap(updates.last).isEmpty)
  }

  func testVisiblePanesFollowDeviceCapabilities() {
    let express = AirportAppModel()
    express.applyAuthoritativeBaseStationIdentity(
      readName: "Studio Express",
      serialNumber: "EXPRESS",
      version: "7.8.1",
      productID: "115")
    XCTAssertTrue(express.visiblePanes.contains(.airPlay))
    XCTAssertFalse(express.visiblePanes.contains(.disks))
    XCTAssertTrue(express.visiblePanes.contains(.firmware))
    XCTAssertFalse(express.capabilities.supportsBaseStationMetadata)

    let capsule = AirportAppModel()
    capsule.applyAuthoritativeBaseStationIdentity(
      readName: "Studio Capsule",
      serialNumber: "CAPSULE",
      version: "7.8.1",
      productID: "106")
    XCTAssertFalse(capsule.visiblePanes.contains(.airPlay))
    XCTAssertTrue(capsule.visiblePanes.contains(.disks))
    XCTAssertTrue(capsule.visiblePanes.contains(.firmware))
    XCTAssertFalse(capsule.capabilities.supportsBaseStationMetadata)

    let extreme = AirportAppModel()
    extreme.applyAuthoritativeBaseStationIdentity(
      readName: "Guest Extreme",
      serialNumber: "EXTREME",
      version: "7.8.1",
      productID: "117")
    XCTAssertFalse(extreme.visiblePanes.contains(.airPlay))
    XCTAssertFalse(extreme.visiblePanes.contains(.disks))
    XCTAssertTrue(extreme.visiblePanes.contains(.firmware))
    XCTAssertFalse(extreme.capabilities.supportsBaseStationMetadata)

    let acExtreme = AirportAppModel()
    acExtreme.applyAuthoritativeBaseStationIdentity(
      readName: "Office Extreme",
      serialNumber: "ACEXTREME",
      version: "7.9.1",
      productID: "120")
    XCTAssertFalse(acExtreme.visiblePanes.contains(.airPlay))
    XCTAssertTrue(acExtreme.visiblePanes.contains(.disks))
    XCTAssertTrue(acExtreme.visiblePanes.contains(.firmware))
    XCTAssertFalse(acExtreme.capabilities.supportsBaseStationMetadata)

    let spaceship = AirportAppModel()
    spaceship.applyAuthoritativeBaseStationIdentity(
      readName: "AirPort Extreme",
      serialNumber: "SPACESHIP",
      version: "5.7",
      productID: "3")
    XCTAssertFalse(spaceship.visiblePanes.contains(.airPlay))
    XCTAssertTrue(spaceship.visiblePanes.contains(.advanced))
    XCTAssertTrue(spaceship.showsLoggingControls)
    XCTAssertTrue(spaceship.showsPPPDialInControls)
    XCTAssertTrue(spaceship.capabilities.supportsBaseStationMetadata)
    XCTAssertTrue(spaceship.capabilities.supportsLegacyWirelessOptions)
    XCTAssertTrue(spaceship.capabilities.supportsLegacyDHCPOptions)
    XCTAssertTrue(spaceship.showsAccessControlControls)
  }

  func testAdvancedFlagsUseCapturedLoggingAndPPPDialInProperties() {
    let model = AirportAppModel()
    model.applyAuthoritativeBaseStationIdentity(
      readName: "AirPort Extreme",
      serialNumber: "SPACESHIP",
      version: "5.7",
      productID: "3")
    model.advanced.syslogDestinationAddress = "192.168.5.6"
    model.advanced.syslogLevel = 7
    model.advanced.allowSNMP = true
    model.advanced.allowSNMPOverWAN = true
    model.advanced.pppDialInEnabled = true
    model.advanced.pppDialInAccount = "pppaccount"
    model.advanced.pppDialInPassword = "ppppassword"
    model.advanced.pppDialInVerifyPassword = "ppppassword"
    model.advanced.pppDialInAnswerOnRing = 4
    model.advanced.pppDialInIdleSeconds = 1_200
    model.advanced.pppDialInMaximumConnectSeconds = 14_400

    XCTAssertEqual(
      model.advancedFlags()?.map { "\($0.0)=\($0.1 ?? "")" },
      [
        "--syslog-destination=192.168.5.6",
        "--syslog-level=7",
        "--snmp-access-flags=0",
        "--ppp-dial-in-enabled=",
        "--ppp-dial-in-account=pppaccount",
        "--ppp-dial-in-password=ppppassword",
        "--ppp-dial-in-answer-on-ring=4",
        "--ppp-dial-in-idle-seconds=1200",
        "--ppp-dial-in-maximum-connect-seconds=14400",
        "--access-control-mode=not-enabled",
      ])
  }

  func testSpaceshipLegacyOptionFlagsUseCapturedProperties() throws {
    let model = AirportAppModel()
    model.applyAuthoritativeBaseStationIdentity(
      readName: "AirPort Extreme",
      serialNumber: "SPACESHIP",
      version: "5.7",
      productID: "3")
    model.network.routerMode = .dhcpAndNat
    model.network.dhcpRangeStart = "10.0.1.2"
    model.network.dhcpRangeEnd = "10.0.1.200"
    model.markClean()

    model.legacyDeviceOptions.baseStation.contact = "Network Admin"
    model.legacyDeviceOptions.baseStation.location = "New York"
    model.legacyDeviceOptions.baseStation.setTimeAutomatically = true
    model.legacyDeviceOptions.baseStation.timeServer = "time.apple.com"
    let baseArguments = try XCTUnwrap(
      model.baseStationCommands(dryRun: true, changesOnly: true)?.last?.1)
    XCTAssertTrue(baseArguments.contains("--base-station-contact"))
    XCTAssertTrue(baseArguments.contains("--base-station-location"))
    XCTAssertTrue(baseArguments.contains("--time-server"))

    model.legacyDeviceOptions.wireless.multicastRate = 85
    model.legacyDeviceOptions.wireless.transmitPower = 50
    model.legacyDeviceOptions.wireless.groupKeyTimeoutSeconds = 7_200
    model.legacyDeviceOptions.wireless.interferenceRobustness = true
    XCTAssertEqual(
      model.wirelessFlags(changesOnly: true)?.map(\.0),
      [
        "--multicast-rate", "--transmit-power", "--group-key-timeout-seconds",
        "--interference-robustness",
      ])

    model.legacyDeviceOptions.dhcp.message = "Welcome"
    model.legacyDeviceOptions.dhcp.ldapServer = "ldap.example.test"
    XCTAssertEqual(
      model.networkFlags(changesOnly: true)?.map(\.0),
      ["--dhcp-message", "--ldap-server"])

    model.legacyDeviceOptions.accessControl.mode = "local"
    model.legacyDeviceOptions.accessControl.entries = [
      AccessControlEntry(macAddress: "44:23:33:33:33:33", description: "test")
    ]
    XCTAssertEqual(
      model.advancedFlags(changesOnly: true)?.map(\.0),
      ["--access-control-mode", "--access-control-entries-json"])
  }

  func testModernBaseStationOptionsExcludeContactAndLocationButKeepTimeServer() throws {
    let model = AirportAppModel()
    model.applyAuthoritativeBaseStationIdentity(
      readName: "Studio Capsule",
      serialNumber: "CAPSULE",
      version: "7.8.1",
      productID: "106")
    model.markClean()

    model.legacyDeviceOptions.baseStation.contact = "Network Admin"
    model.legacyDeviceOptions.baseStation.location = "New York"
    model.legacyDeviceOptions.baseStation.setTimeAutomatically = true
    model.legacyDeviceOptions.baseStation.timeServer = "time.apple.com"

    let arguments = try XCTUnwrap(
      model.baseStationCommands(dryRun: true, changesOnly: true)?.last?.1)
    XCTAssertFalse(arguments.contains("--base-station-contact"))
    XCTAssertFalse(arguments.contains("--base-station-location"))
    XCTAssertTrue(arguments.contains("--time-server"))
  }

  func testPPPDialInIsRejectedWhenModemInternetIsSelected() {
    let model = AirportAppModel()
    model.applyAuthoritativeBaseStationIdentity(
      readName: "AirPort Extreme",
      serialNumber: "SPACESHIP",
      version: "5.7",
      productID: "3")
    model.internet.connectUsing = .modem
    model.advanced.pppDialInEnabled = true

    XCTAssertNil(model.advancedFlags())
    XCTAssertEqual(
      model.status,
      "PPP Dial-in is not allowed when configured to connect to the Internet via the Modem or AOL.")
  }

  func testAuthoritativeIdentityCanDisableUnsupportedInternetFeatures() {
    let model = AirportAppModel()

    model.applyAuthoritativeBaseStationIdentity(
      readName: "Legacy Express",
      serialNumber: "EXPRESS",
      version: "6.3",
      productID: "102",
      supportsIPv6: false,
      supportsDynamicGlobalHostname: false)

    XCTAssertFalse(model.capabilities.supportsIPv6)
    XCTAssertFalse(model.capabilities.supportsDynamicGlobalHostname)
    XCTAssertFalse(model.capabilities.supportsInternetOptions)
    XCTAssertFalse(model.showsIPv6InternetControls)
    XCTAssertFalse(model.showsDynamicGlobalHostnameControls)
    XCTAssertFalse(model.showsInternetOptionsControls)
    XCTAssertTrue(model.visiblePanes.contains(.airPlay))
    XCTAssertFalse(model.visiblePanes.contains(.disks))
  }

  func testInternetOptionsAreHiddenUntilRuntimeSupportIsDetected() {
    let model = AirportAppModel()

    XCTAssertFalse(model.showsIPv6InternetControls)
    XCTAssertFalse(model.showsDynamicGlobalHostnameControls)
    XCTAssertFalse(model.showsInternetOptionsControls)

    model.applyAuthoritativeBaseStationIdentity(
      readName: "Unknown Express",
      serialNumber: "EXPRESS",
      version: "6.3",
      productID: "102")

    XCTAssertFalse(model.showsIPv6InternetControls)
    XCTAssertFalse(model.showsDynamicGlobalHostnameControls)
    XCTAssertFalse(model.showsInternetOptionsControls)
  }

  func testAuthoritativeIdentityCanEnableDetectedInternetFeatures() {
    let model = AirportAppModel()

    model.applyAuthoritativeBaseStationIdentity(
      readName: "Modern Capsule",
      serialNumber: "CAPSULE",
      version: "7.8.1",
      productID: "106",
      supportsIPv6: true,
      supportsDynamicGlobalHostname: true)

    XCTAssertTrue(model.capabilities.supportsIPv6)
    XCTAssertTrue(model.capabilities.supportsDynamicGlobalHostname)
    XCTAssertTrue(model.capabilities.supportsInternetOptions)
    XCTAssertTrue(model.showsIPv6InternetControls)
    XCTAssertTrue(model.showsDynamicGlobalHostnameControls)
    XCTAssertTrue(model.showsInternetOptionsControls)
  }

  func testAuthoritativeIdentityCanEnableDetectedClassicWDS() {
    let model = AirportAppModel()

    model.applyAuthoritativeBaseStationIdentity(
      readName: "Legacy Express",
      serialNumber: "EXPRESS",
      version: "6.3",
      productID: "102",
      supportsClassicWDS: true)

    XCTAssertTrue(model.capabilities.supportsClassicWDS)
    XCTAssertTrue(model.showsClassicWDSWirelessControls)
  }

  func testWirelessFlagsRejectClassicWDSWhenRuntimeSupportIsMissing() {
    let model = AirportAppModel()
    model.wireless.mode = "wds"
    model.wireless.networkName = "Network"
    model.wireless.security = "none"
    model.wireless.wdsPeerAirPortIDs = "00:21:E9:B9:2E:C3"

    XCTAssertNil(model.wirelessFlags())
    XCTAssertEqual(model.status, "Wireless Mode must be create, extend, off.")
  }

  func testAuthoritativeIdentityCanEnableWirelessClientModeForExpress() {
    let model = AirportAppModel()

    model.applyAuthoritativeBaseStationIdentity(
      readName: "Legacy Express",
      serialNumber: "EXPRESS",
      version: "6.3",
      productID: "102")

    XCTAssertTrue(model.capabilities.supportsAirPlay)
    XCTAssertTrue(model.showsWirelessClientModeControls)
  }

  func testAOLModemModeHidesExtendedModemControls() {
    let model = AirportAppModel()
    model.applyAuthoritativeBaseStationIdentity(
      readName: "airport extreme spaceship",
      serialNumber: "",
      version: "5.7",
      productID: "3")
    model.internet.connectUsing = .modem

    XCTAssertTrue(model.showsModemControls)
    XCTAssertTrue(model.showsExtendedModemControls)

    model.internet.modemUseAOL = true

    XCTAssertTrue(model.showsModemControls)
    XCTAssertFalse(model.showsExtendedModemControls)
  }

  func testWirelessFlagsIncludeJoinModeForExpress() {
    let model = AirportAppModel()
    model.applyAuthoritativeBaseStationIdentity(
      readName: "Legacy Express",
      serialNumber: "EXPRESS",
      version: "6.3",
      productID: "102")
    model.wireless.mode = "join"
    model.wireless.networkName = "Network"
    model.wireless.security = "none"

    let flags = model.wirelessFlags()
    XCTAssertEqual(flags?.first?.0, "--wireless-mode")
    XCTAssertEqual(flags?.first?.1, "join")
  }

  func testLegacyExpressJoinModeUsesCompatibleSecurityOptions() {
    let model = AirportAppModel()
    model.applyAuthoritativeBaseStationIdentity(
      readName: "Legacy Express",
      serialNumber: "EXPRESS",
      version: "6.3",
      productID: "102")
    model.wireless.mode = "join"

    XCTAssertEqual(
      model.wirelessSecurityOptions.map(\.rawValue),
      ["none", "wep-40", "wep-128", "wpa-personal", "wpa-wpa2-personal"])
  }

  func testLegacyExpressJoinModeRejectsWPA2OnlySecurity() {
    let model = AirportAppModel()
    model.applyAuthoritativeBaseStationIdentity(
      readName: "Legacy Express",
      serialNumber: "EXPRESS",
      version: "6.3",
      productID: "102")
    model.wireless.mode = "join"
    model.wireless.networkName = "Network"
    model.wireless.security = "wpa2-personal"
    model.wireless.password = "wifi-secret"
    model.wireless.verifyPassword = "wifi-secret"

    XCTAssertNil(model.wirelessFlags())
    XCTAssertEqual(model.status, "Wireless Security is not supported.")
  }

  func testWirelessFlagsRejectJoinModeWhenClientModeIsUnsupported() {
    let model = AirportAppModel()
    model.wireless.mode = "join"
    model.wireless.networkName = "Network"
    model.wireless.security = "none"

    XCTAssertNil(model.wirelessFlags())
    XCTAssertEqual(model.status, "Wireless Mode must be create, extend, off.")
  }

  func testChangingProductsClearsStaleDetectedInternetFeatureSupport() {
    let model = AirportAppModel()
    model.applyAuthoritativeBaseStationIdentity(
      readName: "Modern Capsule",
      serialNumber: "CAPSULE",
      version: "7.8.1",
      productID: "106",
      supportsIPv6: true,
      supportsDynamicGlobalHostname: true)
    XCTAssertTrue(model.showsIPv6InternetControls)
    XCTAssertTrue(model.showsDynamicGlobalHostnameControls)

    model.applyAuthoritativeBaseStationIdentity(
      readName: "Legacy Express",
      serialNumber: "EXPRESS",
      version: "6.3",
      productID: "102")

    XCTAssertFalse(model.showsIPv6InternetControls)
    XCTAssertFalse(model.showsDynamicGlobalHostnameControls)
    XCTAssertFalse(model.showsInternetOptionsControls)
  }

  func testAirPlayFlagsValidateAndEmitAudioSettings() {
    let model = AirportAppModel()
    model.applyAuthoritativeBaseStationIdentity(
      readName: "Studio Express",
      serialNumber: "EXPRESS",
      version: "7.8.1",
      productID: "115")
    model.markClean()

    model.airPlay.enabled = true
    model.airPlay.speakerName = "Studio Express"
    model.airPlay.speakerPassword = "audio-secret"
    model.airPlay.verifySpeakerPassword = "audio-secret"
    model.airPlay.overWAN = true

    let flags = model.airPlayFlags(changesOnly: true)
    XCTAssertTrue(flags?.contains { $0 == ("--airplay-enabled", nil) } == true)
    XCTAssertTrue(flags?.contains { $0 == ("--airplay-speaker-name", "Studio Express") } == true)
    XCTAssertTrue(flags?.contains { $0 == ("--airplay-speaker-password", "audio-secret") } == true)
    XCTAssertTrue(flags?.contains { $0 == ("--airplay-over-wan", nil) } == true)

    model.airPlay.verifySpeakerPassword = "different"
    XCTAssertNil(model.airPlayFlags(changesOnly: true))
    XCTAssertEqual(model.status, "AirPlay passwords do not match.")
  }

  func testAirPlayFlagsAreUnavailableForNonAirPlayDevices() {
    let model = AirportAppModel()
    model.applyAuthoritativeBaseStationIdentity(
      readName: "Guest Extreme",
      serialNumber: "EXTREME",
      version: "7.8.1",
      productID: "117")

    model.airPlay.enabled = true

    XCTAssertFalse(model.visiblePanes.contains(.airPlay))
    XCTAssertNil(model.airPlayFlags(changesOnly: true))
    XCTAssertEqual(model.status, "This base station does not support AirPlay.")
  }

  func testFirmwareCatalogFiltersAndSortsImagesForProductID() throws {
    let manifest: [String: Any] = [
      "firmwareUpdates": [
        [
          "productID": 115,
          "version": "7.6.9",
          "sourceVersion": "76900.11",
          "location": "https://apsu.apple.com/115/769.basebinary",
          "sizeInBytes": 20,
        ],
        [
          "productID": 115,
          "version": "7.8.1",
          "sourceVersion": "78100.3",
          "location": "https://apsu.apple.com/115/781.basebinary",
          "sizeInBytes": 30,
          "newest": true,
        ],
        [
          "productID": 106,
          "version": "7.8.1",
          "sourceVersion": "78100.3",
          "location": "https://apsu.apple.com/106/781.basebinary",
          "sizeInBytes": 40,
        ],
      ]
    ]
    let data = try PropertyListSerialization.data(
      fromPropertyList: manifest,
      format: .xml,
      options: 0)

    let images = try FirmwareCatalog.images(forProductID: "115", in: data)

    XCTAssertEqual(images.map(\.version), ["7.8.1", "7.6.9"])
    XCTAssertEqual(images.first?.displayName, "7.8.1 (Latest)")
    XCTAssertEqual(images.first?.sizeInBytes, 30)
  }

  func testFirmwareDownloadServiceCachesDifferentFirmwareVersions() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("airport-firmware-cache-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let recorder = FirmwareDownloadRecorder(temporaryDirectory: temporaryDirectory)
    let service = FirmwareDownloadService(
      root: temporaryDirectory,
      download: { url, progress in try await recorder.download(url, progress: progress) })
    let images = FirmwareCatalog.mockImages(forProductID: "106")
    let latest = try XCTUnwrap(images.first { $0.version == "7.8.1" })
    let previous = try XCTUnwrap(images.first { $0.version == "7.6.9" })

    let latestURL = try await service.downloadImage(latest)
    let previousURL = try await service.downloadImage(previous)
    let cachedLatestURL = try await service.downloadImage(latest)

    XCTAssertEqual(recorder.requestedLocations, [latest.location, previous.location])
    XCTAssertEqual(latestURL, cachedLatestURL)
    XCTAssertNotEqual(latestURL, previousURL)
    XCTAssertTrue(latestURL.path.contains("/AirPort Utility/Firmware/"))
    XCTAssertTrue(latestURL.path.contains("/106/78100.3/7.8.1.basebinary"))
    XCTAssertTrue(previousURL.path.contains("/106/76900.11/7.6.9.basebinary"))
    XCTAssertEqual(
      try String(contentsOf: latestURL, encoding: .utf8),
      "firmware payload from \(latest.location.absoluteString)")
    XCTAssertEqual(
      try String(contentsOf: previousURL, encoding: .utf8),
      "firmware payload from \(previous.location.absoluteString)")
  }

  func testFirmwareDownloadServiceReusesLegacyApplicationCache() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "airport-firmware-legacy-cache-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let image = try XCTUnwrap(FirmwareCatalog.mockImages(forProductID: "106").first)
    let legacyURL =
      temporaryDirectory
      .appendingPathComponent("NewAirPortUtility", isDirectory: true)
      .appendingPathComponent("Firmware", isDirectory: true)
      .appendingPathComponent(image.productID, isDirectory: true)
      .appendingPathComponent(image.sourceVersion, isDirectory: true)
      .appendingPathComponent("\(image.version).basebinary")
    try FileManager.default.createDirectory(
      at: legacyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("cached firmware".utf8).write(to: legacyURL)

    let service = FirmwareDownloadService(root: temporaryDirectory)

    XCTAssertEqual(service.localURL(for: image), legacyURL)
  }

  func testFirmwareDownloadServiceReplacesEmptyCachedFirmwareImage() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "airport-firmware-empty-cache-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let recorder = FirmwareDownloadRecorder(temporaryDirectory: temporaryDirectory)
    let service = FirmwareDownloadService(
      root: temporaryDirectory,
      download: { url, progress in try await recorder.download(url, progress: progress) })
    let image = try XCTUnwrap(FirmwareCatalog.mockImages(forProductID: "106").first)
    let cachedURL = service.localURL(for: image)
    try FileManager.default.createDirectory(
      at: cachedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data().write(to: cachedURL)

    let downloadedURL = try await service.downloadImage(image)

    XCTAssertEqual(downloadedURL, cachedURL)
    XCTAssertEqual(recorder.requestedLocations, [image.location])
    XCTAssertGreaterThan(
      try Data(contentsOf: downloadedURL).count,
      0)
  }

  func testFirmwareDownloadServiceReportsDownloadAndCachedProgress() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("airport-firmware-progress-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let recorder = FirmwareDownloadRecorder(temporaryDirectory: temporaryDirectory)
    let service = FirmwareDownloadService(
      root: temporaryDirectory,
      download: { url, progress in try await recorder.download(url, progress: progress) })
    let image = try XCTUnwrap(FirmwareCatalog.mockImages(forProductID: "106").first)
    let firstProgress = FirmwareProgressRecorder()

    let localURL = try await service.downloadImage(image) { completed, total in
      await firstProgress.record(completed: completed, total: total)
    }

    let firstEvents = await firstProgress.events
    XCTAssertEqual(recorder.requestedLocations, [image.location])
    XCTAssertEqual(firstEvents.count, 2)
    XCTAssertEqual(firstEvents.last?.completed, firstEvents.last?.total)

    let cachedProgress = FirmwareProgressRecorder()
    _ = try await service.downloadImage(image) { completed, total in
      await cachedProgress.record(completed: completed, total: total)
    }

    let cachedSize = try XCTUnwrap(localURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)
    let cachedEvents = await cachedProgress.events
    XCTAssertEqual(recorder.requestedLocations, [image.location])
    XCTAssertEqual(
      cachedEvents,
      [FirmwareProgressEvent(completed: Int64(cachedSize), total: Int64(cachedSize))])
  }

  func testFirmwareRefreshSelectsNewestImageWhenCurrentVersionIsOlder() async throws {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let model = AirportAppModel()
    let latest = try XCTUnwrap(model.firmware.images.first { $0.version == "7.8.1" })
    model.firmware.currentVersion = "7.6.9"
    model.baseStation.version = "7.6.9"
    model.firmware.selectedImageID = ""

    model.refreshFirmwareImages()
    try await waitForIdle(model)

    XCTAssertEqual(model.firmware.selectedImageID, latest.id)
    XCTAssertEqual(model.firmware.selectedImage?.version, "7.8.1")
  }

  func testFirmwareRefreshPreservesExplicitSelectedImage() async throws {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let model = AirportAppModel()
    let previous = try XCTUnwrap(model.firmware.images.first { $0.version == "7.6.9" })
    model.firmware.currentVersion = "7.6.9"
    model.baseStation.version = "7.6.9"
    model.firmware.selectedImageID = previous.id

    model.refreshFirmwareImages()
    try await waitForIdle(model)

    XCTAssertEqual(model.firmware.selectedImageID, previous.id)
    XCTAssertEqual(model.firmware.selectedImage?.version, "7.6.9")
  }

  func testChoosingFirmwareImageAddsLocalFileToFirmwareChoices() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("airport-firmware-choice-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let localFirmware = temporaryDirectory.appendingPathComponent("7.8.1.basebinary")
    try Data(repeating: 0x46, count: 12).write(to: localFirmware)

    let model = AirportAppModel()
    model.applyAuthoritativeBaseStationIdentity(
      readName: "Lab Capsule",
      serialNumber: "LAB-SERIAL",
      version: "7.8.1",
      productID: "106")

    model.chooseFirmwareImage(at: localFirmware)

    let selected = try XCTUnwrap(model.firmware.selectedImage)
    XCTAssertEqual(selected.location, localFirmware)
    XCTAssertEqual(selected.version, "7.8.1")
    XCTAssertEqual(selected.sizeInBytes, 12)
    XCTAssertEqual(selected.displayName, "7.8.1 (Chosen File)")
    XCTAssertEqual(model.firmware.images.first, selected)
    XCTAssertEqual(model.firmware.installStatus, "Selected firmware image 7.8.1.basebinary.")
  }

  func testMockFirmwareInstallSwitchesVersionsAndCanReinstallCurrentVersion() async throws {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let model = AirportAppModel()
    let previous = try XCTUnwrap(model.firmware.images.first { $0.version == "7.6.9" })
    let latest = try XCTUnwrap(model.firmware.images.first { $0.version == "7.8.1" })
    model.firmwareInstallVerificationDelayNanoseconds = 0

    model.firmware.selectedImageID = previous.id
    model.installSelectedFirmware()
    try await waitForIdle(model)
    try await waitForStatus(model, "Firmware 7.6.9 installed. Mock mode.")

    XCTAssertEqual(model.status, "Firmware 7.6.9 installed. Mock mode.")
    XCTAssertEqual(model.baseStation.version, "7.6.9")
    XCTAssertEqual(model.firmware.currentVersion, "7.6.9")
    XCTAssertEqual(model.firmware.installStatus, "Verified installed firmware 7.6.9.")
    XCTAssertEqual(model.firmware.selectedImageID, previous.id)
    XCTAssertTrue(model.logs.contains { $0.contains("--upload-firmware") && $0.contains("7.6.9") })

    model.installSelectedFirmware()
    try await waitForIdle(model)
    try await waitForStatus(model, "Firmware 7.6.9 reinstalled. Mock mode.")

    XCTAssertEqual(model.status, "Firmware 7.6.9 reinstalled. Mock mode.")
    XCTAssertEqual(model.baseStation.version, "7.6.9")
    XCTAssertEqual(model.firmware.installStatus, "Verified installed firmware 7.6.9.")
    XCTAssertEqual(
      model.logs.filter { $0.contains("--upload-firmware") && $0.contains("7.6.9") }.count,
      2)

    model.firmware.selectedImageID = latest.id
    model.installSelectedFirmware()
    try await waitForIdle(model)
    try await waitForStatus(model, "Firmware 7.8.1 installed. Mock mode.")

    XCTAssertEqual(model.status, "Firmware 7.8.1 installed. Mock mode.")
    XCTAssertEqual(model.baseStation.version, "7.8.1")
    XCTAssertEqual(model.firmware.currentVersion, "7.8.1")
    XCTAssertEqual(model.firmware.installStatus, "Verified installed firmware 7.8.1.")
    XCTAssertEqual(model.firmware.selectedImageID, latest.id)
  }

  func testFirmwareInstallDownloadsUploadsAndReturnsToLaunchPageForRestart() async throws {
    let repo = try makeFirmwareInstallScriptRepo(reportedVersion: "7.6.9")
    defer { try? FileManager.default.removeItem(at: repo.directory) }
    let recorder = FirmwareDownloadRecorder(temporaryDirectory: repo.directory)
    let model = AirportAppModel()
    let previous = try XCTUnwrap(FirmwareCatalog.mockImages(forProductID: "106").last)

    configureFirmwareInstallModel(
      model,
      repoDirectory: repo.directory,
      selectedImage: previous,
      downloadRecorder: recorder)

    model.installSelectedFirmware()
    try await waitForIdle(model)

    let expectedLocalURL = model.firmwareDownloadService.localURL(for: previous)
    let writeLog = try String(contentsOf: repo.writeLog, encoding: .utf8)
    XCTAssertEqual(recorder.requestedLocations, [previous.location])
    XCTAssertTrue(writeLog.contains("--upload-firmware"))
    XCTAssertTrue(writeLog.contains(expectedLocalURL.path))
    XCTAssertEqual(model.status, "Firmware uploaded. 7.6.9 will install after restart.")
    XCTAssertEqual(model.baseStation.version, "7.8.1")
    XCTAssertEqual(model.firmware.currentVersion, "7.8.1")
    XCTAssertEqual(model.firmware.installStatus, "Firmware uploaded. Restart requested.")
    XCTAssertEqual(model.firmware.transferProgress.phase, .restart)
    XCTAssertEqual(model.firmware.transferProgress.fraction, 1.0)
    XCTAssertFalse(model.isEditingDevice)
    XCTAssertEqual(model.selectedPane, .baseStation)
    let device = try XCTUnwrap(model.visibleTopologyDevices.first)
    XCTAssertTrue(model.isTopologyDeviceUpdating(device))
    XCTAssertEqual(model.deviceStatusText(for: device), "Restarting")
    XCTAssertTrue(
      model.logs.contains {
        $0.contains("Firmware upload: Upload completed (96/96); restart requested.")
          && $0.contains("Host: fe80::21f:f3ff:fec9:6299%en0.")
      })
  }

  func testFirmwareInstallUsesChosenLocalFirmwareFileWithoutDownloading() async throws {
    let repo = try makeFirmwareInstallScriptRepo(reportedVersion: "7.6.9")
    defer { try? FileManager.default.removeItem(at: repo.directory) }
    let recorder = FirmwareDownloadRecorder(temporaryDirectory: repo.directory)
    let model = AirportAppModel()
    let previous = try XCTUnwrap(FirmwareCatalog.mockImages(forProductID: "106").last)
    let localFirmware = repo.directory.appendingPathComponent("7.6.9.basebinary")
    try Data(repeating: 0x46, count: 16).write(to: localFirmware)

    configureFirmwareInstallModel(
      model,
      repoDirectory: repo.directory,
      selectedImage: previous,
      downloadRecorder: recorder)
    model.chooseFirmwareImage(at: localFirmware)

    model.installSelectedFirmware()
    try await waitForIdle(model)

    let writeLog = try String(contentsOf: repo.writeLog, encoding: .utf8)
    XCTAssertTrue(recorder.requestedLocations.isEmpty)
    XCTAssertTrue(writeLog.contains("--upload-firmware"))
    XCTAssertTrue(writeLog.contains(localFirmware.path))
    XCTAssertEqual(model.status, "Firmware uploaded. 7.6.9 will install after restart.")
    XCTAssertEqual(model.firmware.installStatus, "Firmware uploaded. Restart requested.")
  }

  func testFirmwareInstallCanVerifyCurrentVersionInBackgroundAfterRestart() async throws {
    let repo = try makeFirmwareInstallScriptRepo(
      reportedVersion: "7.8.1",
      readFailuresBeforeVersion: 1)
    defer { try? FileManager.default.removeItem(at: repo.directory) }
    let recorder = FirmwareDownloadRecorder(temporaryDirectory: repo.directory)
    let model = AirportAppModel()
    let current = try XCTUnwrap(FirmwareCatalog.mockImages(forProductID: "106").first)

    configureFirmwareInstallModel(
      model,
      repoDirectory: repo.directory,
      selectedImage: current,
      downloadRecorder: recorder)
    model.firmwareInstallVerificationDelayNanoseconds = 0
    model.recoveryGuidance = RecoveryGuidance(
      reason: .firmwareVerificationFailed,
      host: AirportConnection.normalizedHost(model.connection.host),
      deviceName: "stale", date: Date(), detail: "stale guidance")

    model.installSelectedFirmware()
    try await waitForIdle(model)
    try await waitForStatus(model, "Firmware 7.8.1 reinstalled. Upload reached 96/96.")

    let writeLog = try String(contentsOf: repo.writeLog, encoding: .utf8)
    XCTAssertEqual(recorder.requestedLocations, [current.location])
    XCTAssertTrue(writeLog.contains("--upload-firmware"))
    XCTAssertEqual(model.status, "Firmware 7.8.1 reinstalled. Upload reached 96/96.")
    XCTAssertEqual(model.baseStation.version, "7.8.1")
    XCTAssertEqual(model.firmware.currentVersion, "7.8.1")
    XCTAssertEqual(model.firmware.installStatus, "Verified installed firmware 7.8.1.")
    let device = try XCTUnwrap(model.visibleTopologyDevices.first)
    XCTAssertFalse(model.isTopologyDeviceUpdating(device))
    XCTAssertFalse(model.firmware.transferProgress.isVisible)
    XCTAssertNil(model.recoveryGuidance)
  }

  func testFirmwareInstallReportsIncompleteBackendUploadProgress() async throws {
    let repo = try makeFirmwareInstallScriptRepo(
      reportedVersion: "7.6.9",
      firmwareUploadResultJSON: """
        {
          "method": "property-stream",
          "progress": {
            "available": true,
            "complete": false,
            "current": 24,
            "raw": "24/96",
            "total": 96
          },
          "rebootCommand": {
            "sent": false
          },
          "uploadHost": "fe80::21f:f3ff:fec9:6299%en0"
        }
        """)
    defer { try? FileManager.default.removeItem(at: repo.directory) }
    let recorder = FirmwareDownloadRecorder(temporaryDirectory: repo.directory)
    let model = AirportAppModel()
    let previous = try XCTUnwrap(FirmwareCatalog.mockImages(forProductID: "106").last)

    configureFirmwareInstallModel(
      model,
      repoDirectory: repo.directory,
      selectedImage: previous,
      downloadRecorder: recorder)

    model.installSelectedFirmware()
    try await waitForIdle(model)

    XCTAssertEqual(
      model.status,
      "Firmware upload did not complete. Last reported progress: 24/96.")
    XCTAssertEqual(model.firmware.installStatus, "Upload progress 24/96.")
    XCTAssertEqual(model.firmware.transferProgress.phase, .program)
    XCTAssertEqual(model.firmware.transferProgress.detail, "24/96")
    XCTAssertEqual(model.baseStation.version, "7.8.1")
    XCTAssertEqual(model.firmware.currentVersion, "7.8.1")
  }

  func testFirmwareInstallReportsMissingBackendRebootCommand() async throws {
    let repo = try makeFirmwareInstallScriptRepo(
      reportedVersion: "7.6.9",
      firmwareUploadResultJSON: """
        {
          "method": "property-stream",
          "progress": {
            "available": true,
            "complete": true,
            "current": 96,
            "raw": "96/96",
            "total": 96
          },
          "rebootCommand": {
            "sent": false
          },
          "uploadHost": "fe80::21f:f3ff:fec9:6299%en0"
        }
        """)
    defer { try? FileManager.default.removeItem(at: repo.directory) }
    let recorder = FirmwareDownloadRecorder(temporaryDirectory: repo.directory)
    let model = AirportAppModel()
    let previous = try XCTUnwrap(FirmwareCatalog.mockImages(forProductID: "106").last)

    configureFirmwareInstallModel(
      model,
      repoDirectory: repo.directory,
      selectedImage: previous,
      downloadRecorder: recorder)

    model.installSelectedFirmware()
    try await waitForIdle(model)

    XCTAssertEqual(
      model.status,
      "Firmware upload completed, but the base station reboot command was not sent.")
    XCTAssertEqual(model.firmware.installStatus, "Upload completed (96/96).")
    XCTAssertEqual(model.firmware.transferProgress.phase, .program)
    XCTAssertEqual(model.firmware.transferProgress.fraction, 1.0)
    XCTAssertEqual(model.baseStation.version, "7.8.1")
    XCTAssertEqual(model.firmware.currentVersion, "7.8.1")
  }

  func testFirmwareInstallStillAcceptsLegacyUploadOutputWithoutResultJSON() async throws {
    let repo = try makeFirmwareInstallScriptRepo(
      reportedVersion: "7.6.9",
      firmwareUploadResultJSON: nil)
    defer { try? FileManager.default.removeItem(at: repo.directory) }
    let recorder = FirmwareDownloadRecorder(temporaryDirectory: repo.directory)
    let model = AirportAppModel()
    let previous = try XCTUnwrap(FirmwareCatalog.mockImages(forProductID: "106").last)

    configureFirmwareInstallModel(
      model,
      repoDirectory: repo.directory,
      selectedImage: previous,
      downloadRecorder: recorder)

    model.installSelectedFirmware()
    try await waitForIdle(model)

    XCTAssertEqual(model.status, "Firmware uploaded. 7.6.9 will install after restart.")
    XCTAssertEqual(model.firmware.installStatus, "Firmware uploaded. Restart requested.")
    XCTAssertEqual(model.baseStation.version, "7.8.1")
    XCTAssertEqual(model.firmware.currentVersion, "7.8.1")
  }

  func testFirmwareInstallReportsVerificationMismatch() async throws {
    let repo = try makeFirmwareInstallScriptRepo(reportedVersion: "7.8.1")
    defer { try? FileManager.default.removeItem(at: repo.directory) }
    let recorder = FirmwareDownloadRecorder(temporaryDirectory: repo.directory)
    let model = AirportAppModel()
    let previous = try XCTUnwrap(FirmwareCatalog.mockImages(forProductID: "106").last)

    configureFirmwareInstallModel(
      model,
      repoDirectory: repo.directory,
      selectedImage: previous,
      downloadRecorder: recorder)
    model.firmwareInstallVerificationDelayNanoseconds = 0

    model.installSelectedFirmware()
    try await waitForIdle(model)
    try await waitForStatus(
      model,
      "Firmware install completed, but the base station reports version 7.8.1 instead of 7.6.9.")

    let writeLog = try String(contentsOf: repo.writeLog, encoding: .utf8)
    XCTAssertEqual(recorder.requestedLocations, [previous.location])
    XCTAssertTrue(writeLog.contains("--upload-firmware"))
    XCTAssertEqual(model.baseStation.version, "7.8.1")
    XCTAssertEqual(model.firmware.currentVersion, "7.8.1")
    XCTAssertEqual(
      model.status,
      "Firmware install completed, but the base station reports version 7.8.1 instead of 7.6.9.")
    XCTAssertTrue(
      model.logs.contains {
        $0.contains(
          "Firmware verification failed: Firmware install completed, but the base station reports version 7.8.1 instead of 7.6.9."
        )
      })
    XCTAssertEqual(model.recoveryGuidance?.reason, .firmwareVerificationFailed)
  }

  func testPreferencesMenuCommandPresentsPreferencesSheet() {
    let model = AirportAppModel()
    model.isDevicePopoverPresented = true
    model.isInternetPopoverPresented = true
    model.isShowingPasswords = true
    model.isShowingConfigureOther = true

    model.showPreferences()

    XCTAssertTrue(model.isShowingPreferences)
    XCTAssertFalse(model.isDevicePopoverPresented)
    XCTAssertFalse(model.isInternetPopoverPresented)
    XCTAssertFalse(model.isShowingPasswords)
    XCTAssertFalse(model.isShowingConfigureOther)
  }

  func testConfigureOtherMenuCommandPresentsConnectionSheet() {
    let model = AirportAppModel()
    model.isDevicePopoverPresented = true
    model.isInternetPopoverPresented = true
    model.isShowingPasswords = true
    model.isShowingPreferences = true

    model.showConfigureOther()

    XCTAssertTrue(model.isShowingConfigureOther)
    XCTAssertFalse(model.isDevicePopoverPresented)
    XCTAssertFalse(model.isInternetPopoverPresented)
    XCTAssertFalse(model.isShowingPasswords)
    XCTAssertFalse(model.isShowingPreferences)
  }

  func testShowPasswordsDismissesOtherMenuSheets() {
    let model = AirportAppModel()
    let device = AirportDiscoveredDevice(
      id: "selected", name: "Selected Capsule", hostName: "selected.local.")
    model.updateDiscoveredDevices([device])
    model.selectTopologyDevice(device)
    model.isShowingPreferences = true
    model.isShowingConfigureOther = true

    model.showPasswords()

    XCTAssertTrue(model.isShowingPasswords)
    XCTAssertFalse(model.isShowingPreferences)
    XCTAssertFalse(model.isShowingConfigureOther)
  }

  func testMenuSheetPresentationDismissesEditingSheetWithoutDiscardingPendingChanges() {
    let model = AirportAppModel()
    model.baseStation.name = "Clean Capsule"
    model.markClean()
    model.beginEditing()
    model.baseStation.name = "Draft Capsule"

    model.showPreferences()

    XCTAssertFalse(model.isEditingDevice)
    XCTAssertTrue(model.isShowingPreferences)
    XCTAssertEqual(model.baseStation.name, "Draft Capsule")
    XCTAssertTrue(model.hasPendingChanges)
  }

  func testBeginEditingDismissesMenuSheets() {
    let model = AirportAppModel()
    model.isShowingPasswords = true
    model.isShowingPreferences = true
    model.isShowingConfigureOther = true

    model.beginEditing()

    XCTAssertTrue(model.isEditingDevice)
    XCTAssertFalse(model.isShowingPasswords)
    XCTAssertFalse(model.isShowingPreferences)
    XCTAssertFalse(model.isShowingConfigureOther)
  }

  func testOtherWiFiDevicesMenuShowsDiscoveredDevices() {
    let selectedDevice = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Selected",
      name: "Selected Capsule",
      hostName: "selected.local."
    )
    let otherDevice = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Other",
      name: "Other Capsule",
      hostName: "other.local."
    )
    let button = NSPopUpButton(frame: .zero, pullsDown: true)

    OtherWiFiDevicesMenu.configure(
      button,
      showConnectItem: true,
      devices: [selectedDevice, otherDevice],
      selectedDeviceID: selectedDevice.id)

    let titles = button.menu?.items.filter { !$0.isSeparatorItem }.map(\.title)
    XCTAssertEqual(
      titles,
      [
        OtherWiFiDevicesMenu.title,
        OtherWiFiDevicesMenu.connectTitle,
        "Selected Capsule",
        "Other Capsule",
        OtherWiFiDevicesMenu.networkInterfacesTitle,
        "Ethernet 1",
        "Wi-Fi",
      ])
    XCTAssertNil(button.menu?.items.first { $0.title == OtherWiFiDevicesMenu.placeholderTitle })
    XCTAssertTrue(button.menu?.item(withTitle: OtherWiFiDevicesMenu.title)?.isEnabled ?? false)
    XCTAssertFalse(
      button.menu?.item(withTitle: OtherWiFiDevicesMenu.networkInterfacesTitle)?.isEnabled ?? true)
    let selectedItem = button.menu?.items.first { $0.title == "Selected Capsule" }
    XCTAssertEqual(selectedItem?.representedObject as? String, selectedDevice.id)
    XCTAssertEqual(selectedItem?.state, .on)
    XCTAssertTrue(selectedItem?.isEnabled ?? false)
    let otherItem = button.menu?.items.first { $0.title == "Other Capsule" }
    XCTAssertEqual(otherItem?.representedObject as? String, otherDevice.id)
    XCTAssertEqual(otherItem?.state, .off)
    XCTAssertTrue(otherItem?.isEnabled ?? false)
    XCTAssertTrue(button.menu?.item(withTitle: "Ethernet 1")?.isEnabled ?? false)
    XCTAssertEqual(button.menu?.item(withTitle: "Ethernet 1")?.state, .on)
    XCTAssertTrue(button.menu?.item(withTitle: "Wi-Fi")?.isEnabled ?? false)
  }

  func testOtherWiFiDevicesButtonTitleDoesNotUseDisabledHeaderItem() {
    let button = NSPopUpButton(frame: .zero, pullsDown: true)

    OtherWiFiDevicesMenu.configureButtonAppearance(button)
    OtherWiFiDevicesMenu.configure(
      button,
      showConnectItem: false,
      devices: [],
      selectedDeviceID: nil)

    XCTAssertTrue(button.isEnabled)
    XCTAssertEqual(button.title, OtherWiFiDevicesMenu.title)
    XCTAssertTrue(button.menu?.item(withTitle: OtherWiFiDevicesMenu.title)?.isEnabled ?? false)
  }

  func testOtherWiFiDevicesMenuShowsPlaceholderWhenNoDevicesAreDiscovered() {
    let button = NSPopUpButton(frame: .zero, pullsDown: true)

    OtherWiFiDevicesMenu.configure(
      button,
      showConnectItem: false,
      devices: [],
      selectedDeviceID: nil)

    let titles = button.menu?.items.filter { !$0.isSeparatorItem }.map(\.title)
    XCTAssertEqual(
      titles,
      [
        OtherWiFiDevicesMenu.title,
        OtherWiFiDevicesMenu.placeholderTitle,
        OtherWiFiDevicesMenu.networkInterfacesTitle,
        "Ethernet 1",
        "Wi-Fi",
      ])
    XCTAssertTrue(button.menu?.item(withTitle: OtherWiFiDevicesMenu.title)?.isEnabled ?? false)
    XCTAssertFalse(
      button.menu?.item(withTitle: OtherWiFiDevicesMenu.placeholderTitle)?.isEnabled ?? true)
    XCTAssertTrue(button.menu?.item(withTitle: "Ethernet 1")?.isEnabled ?? false)
    XCTAssertTrue(button.menu?.item(withTitle: "Wi-Fi")?.isEnabled ?? false)
  }

  func testOtherWiFiDevicesMenuNetworkInterfacesAreSelectable() throws {
    let button = NSPopUpButton(frame: .zero, pullsDown: true)
    var selectedInterface: String?
    let coordinator = OtherWiFiDevicesMenu.Coordinator(
      onConnect: {},
      onSelectDeviceID: { _ in },
      onSelectNetworkInterface: { title in
        selectedInterface = title
      })
    coordinator.button = button

    OtherWiFiDevicesMenu.configure(
      button,
      showConnectItem: false,
      devices: [],
      selectedDeviceID: nil,
      selectedNetworkInterfaceTitle: "Wi-Fi",
      target: coordinator)

    let ethernetItem = try XCTUnwrap(button.menu?.item(withTitle: "Ethernet 1"))
    let wifiItem = try XCTUnwrap(button.menu?.item(withTitle: "Wi-Fi"))
    XCTAssertTrue(ethernetItem.isEnabled)
    XCTAssertTrue(wifiItem.isEnabled)
    XCTAssertEqual(ethernetItem.state, .off)
    XCTAssertEqual(wifiItem.state, .on)

    coordinator.selectMenuItem(ethernetItem)

    XCTAssertEqual(selectedInterface, "Ethernet 1")
    XCTAssertEqual(button.indexOfSelectedItem, 0)
    XCTAssertEqual(button.title, OtherWiFiDevicesMenu.title)
  }

  func testOtherWiFiDevicesMenuSelectionRoutesSelectedDeviceID() {
    let device = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Time Capsule",
      name: "Time Capsule",
      hostName: "time-capsule.local."
    )
    let button = NSPopUpButton(frame: .zero, pullsDown: true)
    var selectedDeviceID: String?
    var didRequestManualConnection = false
    let coordinator = OtherWiFiDevicesMenu.Coordinator(
      onConnect: {
        didRequestManualConnection = true
      },
      onSelectDeviceID: { deviceID in
        selectedDeviceID = deviceID
      })
    coordinator.button = button
    OtherWiFiDevicesMenu.configure(
      button,
      showConnectItem: true,
      devices: [device],
      selectedDeviceID: nil,
      target: coordinator)

    button.selectItem(withTitle: "Time Capsule")
    coordinator.selectPopUpButton(button)

    XCTAssertEqual(selectedDeviceID, device.id)
    XCTAssertFalse(didRequestManualConnection)
    XCTAssertEqual(button.indexOfSelectedItem, 0)
    XCTAssertEqual(button.title, OtherWiFiDevicesMenu.title)

    button.selectItem(withTitle: OtherWiFiDevicesMenu.connectTitle)
    coordinator.selectPopUpButton(button)

    XCTAssertTrue(didRequestManualConnection)
    XCTAssertEqual(button.indexOfSelectedItem, 0)
    XCTAssertEqual(button.title, OtherWiFiDevicesMenu.title)
  }

  func testOtherWiFiDevicesMenuItemsAreTargetedToCoordinator() throws {
    let device = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Time Capsule",
      name: "Time Capsule",
      hostName: "time-capsule.local."
    )
    let button = NSPopUpButton(frame: .zero, pullsDown: true)
    var selectedDeviceID: String?
    var didRequestManualConnection = false
    let coordinator = OtherWiFiDevicesMenu.Coordinator(
      onConnect: {
        didRequestManualConnection = true
      },
      onSelectDeviceID: { deviceID in
        selectedDeviceID = deviceID
      })
    coordinator.button = button

    OtherWiFiDevicesMenu.configureButtonAppearance(button)
    OtherWiFiDevicesMenu.configure(
      button,
      showConnectItem: true,
      devices: [device],
      selectedDeviceID: nil,
      target: coordinator)

    let connectItem = try XCTUnwrap(button.menu?.item(withTitle: OtherWiFiDevicesMenu.connectTitle))
    XCTAssertTrue(connectItem.target === coordinator)
    XCTAssertEqual(
      connectItem.action, #selector(OtherWiFiDevicesMenu.Coordinator.selectMenuItem(_:)))

    coordinator.selectMenuItem(connectItem)

    XCTAssertTrue(didRequestManualConnection)
    XCTAssertNil(selectedDeviceID)
    XCTAssertEqual(button.indexOfSelectedItem, 0)
    XCTAssertEqual(button.title, OtherWiFiDevicesMenu.title)

    let deviceItem = try XCTUnwrap(button.menu?.item(withTitle: "Time Capsule"))
    XCTAssertTrue(deviceItem.target === coordinator)
    XCTAssertEqual(
      deviceItem.action, #selector(OtherWiFiDevicesMenu.Coordinator.selectMenuItem(_:)))

    coordinator.selectMenuItem(deviceItem)

    XCTAssertEqual(selectedDeviceID, device.id)
    XCTAssertEqual(button.indexOfSelectedItem, 0)
    XCTAssertEqual(button.title, OtherWiFiDevicesMenu.title)
  }

  func testOtherWiFiDevicesMenuSelectionPresentsDiscoveredDeviceThroughModel() {
    let model = AirportAppModel()
    let unresolvedDevice = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Unresolved",
      name: "Unresolved",
      hostName: ""
    )
    let device = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Time Capsule",
      name: "Time Capsule",
      hostName: "time-capsule.local."
    )
    model.updateDiscoveredDevices([unresolvedDevice, device])

    model.presentOtherWiFiDeviceFromMenu(id: device.id)

    XCTAssertEqual(model.otherWiFiDevicesMenuDevices.map(\.id), [device.id])
    XCTAssertEqual(model.selectedTopologyDeviceID, device.id)
    XCTAssertEqual(model.connection.host, "time-capsule.local")
    XCTAssertEqual(model.baseStation.name, "Time Capsule")
    XCTAssertTrue(model.isDevicePopoverPresented)
    XCTAssertTrue(model.shouldShowDeviceConnectionPrompt)
  }

  func testLiveDevicePopoverRequestsConnectionUntilCredentialsOrDetailsExist() {
    let savedMockMode = getenv("AIRPORT_UTILITY_MOCK").map { String(cString: $0) }
    let savedPassword = getenv("AIRPORT_UTILITY_PASSWORD").map { String(cString: $0) }
    unsetenv("AIRPORT_UTILITY_MOCK")
    unsetenv("AIRPORT_UTILITY_PASSWORD")
    defer {
      if let savedMockMode {
        setenv("AIRPORT_UTILITY_MOCK", savedMockMode, 1)
      }
      if let savedPassword {
        setenv("AIRPORT_UTILITY_PASSWORD", savedPassword, 1)
      }
    }

    let model = AirportAppModel()

    XCTAssertTrue(model.needsConnectionDetailsBeforeLoadingDevice)

    model.connection.password = "secret"
    XCTAssertFalse(model.needsConnectionDetailsBeforeLoadingDevice)

    model.connection.password = ""
    model.internet.ipv4Address = "192.168.4.45"
    XCTAssertFalse(model.needsConnectionDetailsBeforeLoadingDevice)
  }

  func testDevicePopoverShowsConnectionPromptUntilDetailsLoad() {
    let savedMockMode = getenv("AIRPORT_UTILITY_MOCK").map { String(cString: $0) }
    let savedPassword = getenv("AIRPORT_UTILITY_PASSWORD").map { String(cString: $0) }
    unsetenv("AIRPORT_UTILITY_MOCK")
    unsetenv("AIRPORT_UTILITY_PASSWORD")
    defer {
      if let savedMockMode {
        setenv("AIRPORT_UTILITY_MOCK", savedMockMode, 1)
      }
      if let savedPassword {
        setenv("AIRPORT_UTILITY_PASSWORD", savedPassword, 1)
      }
    }

    let model = AirportAppModel()

    XCTAssertTrue(model.shouldShowDeviceConnectionPrompt)
    XCTAssertFalse(model.shouldShowDeviceLoading)

    model.connection.password = "wrong-password"
    XCTAssertTrue(model.shouldShowDeviceConnectionPrompt)
    XCTAssertFalse(model.shouldShowDeviceLoading)

    model.isBusy = true
    XCTAssertFalse(model.shouldShowDeviceConnectionPrompt)
    XCTAssertTrue(model.shouldShowDeviceLoading)

    model.isBusy = false
    model.status = "Authentication failed"
    XCTAssertTrue(model.shouldShowDeviceConnectionPrompt)
    XCTAssertFalse(model.shouldShowDeviceLoading)

    model.baseStation.serialNumber = "C86TEST123"
    XCTAssertFalse(model.shouldShowDeviceConnectionPrompt)
    XCTAssertFalse(model.shouldShowDeviceLoading)
  }

  func testDevicePopoverKeepsLoadingWhileDisplayedRowsAreIncomplete() {
    let savedMockMode = getenv("AIRPORT_UTILITY_MOCK").map { String(cString: $0) }
    let savedPassword = getenv("AIRPORT_UTILITY_PASSWORD").map { String(cString: $0) }
    unsetenv("AIRPORT_UTILITY_MOCK")
    unsetenv("AIRPORT_UTILITY_PASSWORD")
    defer {
      if let savedMockMode {
        setenv("AIRPORT_UTILITY_MOCK", savedMockMode, 1)
      }
      if let savedPassword {
        setenv("AIRPORT_UTILITY_PASSWORD", savedPassword, 1)
      }
    }

    let model = AirportAppModel()
    model.connection.host = "192.168.4.45"
    model.connection.password = "secret"
    model.isBusy = true
    model.wireless.networkName = "codex-ui-0626"
    model.internet.ipv4Address = "192.168.4.45"
    model.network.lanIPAddress = "192.168.4.45"

    XCTAssertTrue(model.hasDevicePopoverDetails)
    XCTAssertFalse(model.hasCompleteDevicePopoverDetails)
    XCTAssertFalse(model.shouldShowDeviceConnectionPrompt)
    XCTAssertTrue(model.shouldShowDeviceLoading)

    model.baseStation.serialNumber = "C86TEST123"
    model.baseStation.version = "7.9.1"

    XCTAssertTrue(model.hasCompleteDevicePopoverDetails)
    XCTAssertFalse(model.shouldShowDeviceLoading)
  }

  func testInternetPopoverUsesHostInternetSettings() {
    let savedMockMode = getenv("AIRPORT_UTILITY_MOCK").map { String(cString: $0) }
    let savedPassword = getenv("AIRPORT_UTILITY_PASSWORD").map { String(cString: $0) }
    unsetenv("AIRPORT_UTILITY_MOCK")
    unsetenv("AIRPORT_UTILITY_PASSWORD")
    defer {
      if let savedMockMode {
        setenv("AIRPORT_UTILITY_MOCK", savedMockMode, 1)
      }
      if let savedPassword {
        setenv("AIRPORT_UTILITY_PASSWORD", savedPassword, 1)
      }
    }

    let model = AirportAppModel()
    model.hostInternet = HostInternetState(isLoading: true)

    XCTAssertFalse(model.hasInternetPopoverDetails)
    XCTAssertFalse(model.hasCompleteInternetPopoverDetails)
    XCTAssertTrue(model.shouldShowInternetLoading)
    XCTAssertFalse(model.isHostInternetConnected)
    XCTAssertEqual(model.internetTopologyAccessibilityTitle, "Internet inactive")

    model.hostInternet = HostInternetState(
      connectionStatus: "Connected",
      routerAddress: "192.168.4.1",
      dnsServers: "192.168.1.1")

    XCTAssertEqual(model.internetPopoverConnectionStatus, "Connected")
    XCTAssertTrue(model.isHostInternetConnected)
    XCTAssertEqual(model.internetTopologyAccessibilityTitle, "Internet working normally")
    XCTAssertTrue(model.hasInternetPopoverDetails)
    XCTAssertTrue(model.hasCompleteInternetPopoverDetails)
    XCTAssertFalse(model.shouldShowInternetLoading)
  }

  func testHostInternetSettingsPreferScopedDNSForDefaultInterface() {
    let settings = AirportAppModel.hostInternetSettings(
      routeOutput: """
             route to: default
        destination: default
            gateway: 192.168.4.1
          interface: en0
        """,
      dnsOutput: """
        DNS configuration

        resolver #1
          search domain[0] : tail88a818.ts.net
          nameserver[0] : 100.100.100.100
          nameserver[1] : fd7a:115c:a1e0::53
          if_index : 22 (utun4)
          flags    : Supplemental, Request A records, Request AAAA records

        resolver #2
          nameserver[0] : 192.168.1.1
          if_index : 6 (en0)
          flags    : Request A records

        DNS configuration (for scoped queries)

        resolver #1
          nameserver[0] : 192.168.1.1
          if_index : 6 (en0)
          flags    : Scoped, Request A records
        """)

    XCTAssertEqual(settings.connectionStatus, "Connected")
    XCTAssertEqual(settings.routerAddress, "192.168.4.1")
    XCTAssertEqual(settings.dnsServers, "192.168.1.1")
  }

  func testHostInternetSettingsTreatDNSWithoutDefaultRouteAsDisconnected() {
    let settings = AirportAppModel.hostInternetSettings(
      routeOutput: """
        route: writing to routing socket: not in table
        """,
      dnsOutput: """
        DNS configuration

        resolver #1
          search domain[0] : tail88a818.ts.net
          nameserver[0] : 100.100.100.100
          nameserver[1] : fd7a:115c:a1e0::53
          if_index : 22 (utun4)
          flags    : Supplemental, Request A records, Request AAAA records
        """)

    XCTAssertEqual(settings.connectionStatus, "Disconnected")
    XCTAssertEqual(settings.routerAddress, "")
    XCTAssertEqual(settings.dnsServers, "")
  }

  func testMockDevicePopoverNeverRequestsConnectionDetails() {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let model = AirportAppModel()

    XCTAssertFalse(model.needsConnectionDetailsBeforeLoadingDevice)
    XCTAssertFalse(model.shouldShowDeviceConnectionPrompt)
    XCTAssertFalse(model.shouldShowDeviceLoading)
    XCTAssertTrue(model.hasDevicePopoverDetails)
  }

  func testWirelessClientsContinuePollingAfterDevicePopoverCloses() async throws {
    let model = AirportAppModel(passwordStore: MemoryAirportPasswordStore())
    let device = AirportDiscoveredDevice(
      id: "modern-extreme",
      name: "airport extreme",
      hostName: "airport-extreme.local.",
      productID: "120")
    model.connection = AirportConnection(
      host: "airport-extreme.local", password: "secret", repoPath: "/repo")
    model.hasTrustedConnectionPassword = true
    model.hasLoadedSettings = true
    model.discoveredDevices = [device]
    model.selectedTopologyDeviceID = device.id
    model.wirelessClientPollIntervalNanoseconds = 10_000_000
    var fetchCount = 0
    let initialFetchGate = TestAsyncGate()
    model.wirelessClientFetchOverride = { connection, legacy, community in
      fetchCount += 1
      XCTAssertEqual(connection.host, "airport-extreme.local")
      XCTAssertFalse(legacy)
      XCTAssertEqual(community, "")
      try await initialFetchGate.wait()
      return [
        WirelessClient(
          macAddress: "C8:BC:C8:30:CD:3B",
          ipAddress: "192.168.4.41",
          hostname: "iphone.local",
          rssi: -39,
          noise: -92,
          dataRateMbps: 866,
          phyMode: "802.11a/n/ac")
      ]
    }

    model.isDevicePopoverPresented = true
    XCTAssertFalse(model.hasLoadedWirelessClients)
    XCTAssertTrue(model.shouldShowDeviceLoading)
    await initialFetchGate.release()
    for _ in 0..<20 where !model.hasLoadedWirelessClients {
      try await Task.sleep(nanoseconds: 5_000_000)
    }

    XCTAssertTrue(model.hasLoadedWirelessClients)
    XCTAssertFalse(model.shouldShowDeviceLoading)
    XCTAssertEqual(model.wirelessClients.map(\.displayName), ["iphone.local"])
    XCTAssertEqual(model.wirelessClients.first?.rssi, -39)
    XCTAssertEqual(model.wirelessClients.first?.dataRateMbps, 866)
    XCTAssertEqual(model.wirelessClients.first?.phyMode, "802.11a/n/ac")
    XCTAssertGreaterThanOrEqual(fetchCount, 1)

    model.isDevicePopoverPresented = false
    XCTAssertEqual(model.wirelessClients.map(\.displayName), ["iphone.local"])
    XCTAssertTrue(model.hasLoadedWirelessClients)
    XCTAssertNotNil(model.wirelessClientPollTask)
    model.stopWirelessClientPolling(clearClients: true)
  }

  func testWirelessClientPollingDefaultsToTwoSeconds() {
    let model = AirportAppModel(passwordStore: MemoryAirportPasswordStore())

    XCTAssertEqual(model.wirelessClientPollIntervalNanoseconds, 2_000_000_000)
  }

  func testSuccessfulEmptyWirelessClientRefreshCompletesInitialPopoverLoad() async throws {
    let model = AirportAppModel(passwordStore: MemoryAirportPasswordStore())
    let device = AirportDiscoveredDevice(
      id: "modern-extreme",
      name: "airport extreme",
      hostName: "airport-extreme.local.",
      productID: "120")
    model.connection = AirportConnection(
      host: "airport-extreme.local", password: "secret", repoPath: "/repo")
    model.hasTrustedConnectionPassword = true
    model.hasLoadedSettings = true
    model.discoveredDevices = [device]
    model.selectedTopologyDeviceID = device.id
    model.wirelessClientFetchOverride = { _, _, _ in [] }

    model.isDevicePopoverPresented = true
    for _ in 0..<20 where !model.hasLoadedWirelessClients {
      try await Task.sleep(nanoseconds: 5_000_000)
    }

    XCTAssertTrue(model.hasLoadedWirelessClients)
    XCTAssertTrue(model.wirelessClients.isEmpty)
    XCTAssertFalse(model.shouldShowDeviceLoading)
  }

  func testInitialWirelessClientFailureReleasesPopoverAndRetries() async throws {
    let model = AirportAppModel(passwordStore: MemoryAirportPasswordStore())
    let device = AirportDiscoveredDevice(
      id: "modern-extreme",
      name: "airport extreme",
      hostName: "airport-extreme.local.",
      productID: "120")
    model.connection = AirportConnection(
      host: "airport-extreme.local", password: "secret", repoPath: "/repo")
    model.hasTrustedConnectionPassword = true
    model.hasLoadedSettings = true
    model.discoveredDevices = [device]
    model.selectedTopologyDeviceID = device.id
    model.wirelessClientPollIntervalNanoseconds = 5_000_000
    let retryGate = TestAsyncGate()
    var fetchCount = 0
    model.wirelessClientFetchOverride = { _, _, _ in
      fetchCount += 1
      if fetchCount == 1 {
        throw WirelessClientTestError.unavailable
      }
      try await retryGate.wait()
      return [
        WirelessClient(
          macAddress: "C8:BC:C8:30:CD:3B",
          ipAddress: "192.168.4.41",
          hostname: "iphone.local")
      ]
    }

    model.isDevicePopoverPresented = true
    for _ in 0..<20 where !model.hasLoadedWirelessClients {
      try await Task.sleep(nanoseconds: 2_000_000)
    }

    XCTAssertTrue(model.hasLoadedWirelessClients)
    XCTAssertFalse(model.shouldShowDeviceLoading)
    XCTAssertTrue(model.wirelessClients.isEmpty)

    await retryGate.release()
    for _ in 0..<20 where model.wirelessClients.isEmpty {
      try await Task.sleep(nanoseconds: 2_000_000)
    }

    XCTAssertGreaterThanOrEqual(fetchCount, 2)
    XCTAssertEqual(model.wirelessClients.map(\.displayName), ["iphone.local"])
  }

  func testDevicePopoverCapsUnifiedDetailsViewport() {
    XCTAssertEqual(
      DevicePopoverLayout.detailsViewportHeight(
        detailRowCount: 6,
        wirelessClientCount: 0),
      DevicePopoverLayout.minimumDetailsHeight)
    XCTAssertGreaterThan(
      DevicePopoverLayout.detailsContentHeight(
        detailRowCount: 6,
        wirelessClientCount: 30),
      DevicePopoverLayout.maximumDetailsHeight)
    XCTAssertEqual(
      DevicePopoverLayout.detailsViewportHeight(
        detailRowCount: 6,
        wirelessClientCount: 30),
      DevicePopoverLayout.maximumDetailsHeight)
  }

  func testLegacyWirelessClientPollingRequiresEnabledSNMPAndCommunity() async throws {
    let model = AirportAppModel(passwordStore: MemoryAirportPasswordStore())
    let device = AirportDiscoveredDevice(
      id: "legacy-express",
      name: "airport express",
      hostName: "airport-express.local.",
      productID: "102")
    model.connection = AirportConnection(
      host: "airport-express.local", password: "secret", repoPath: "/repo")
    model.hasTrustedConnectionPassword = true
    model.hasLoadedSettings = true
    model.usesLegacyACP = true
    model.advanced.allowSNMP = false
    model.legacySNMPCommunity = "public"
    model.discoveredDevices = [device]
    model.selectedTopologyDeviceID = device.id
    var fetchCount = 0
    model.wirelessClientFetchOverride = { _, _, _ in
      fetchCount += 1
      return []
    }

    model.isDevicePopoverPresented = true
    try await Task.sleep(nanoseconds: 20_000_000)

    XCTAssertEqual(fetchCount, 0)
    XCTAssertNil(model.wirelessClientPollTask)
    XCTAssertTrue(model.hasLoadedWirelessClients)
    XCTAssertFalse(model.shouldShowDeviceLoading)
  }

  func testMockOffWirelessStateDoesNotCarryHiddenWirelessFields() {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let model = AirportAppModel()

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

  func testTimeCapsuleClickAlwaysPresentsDeviceDetailsPopover() {
    XCTAssertTrue(DevicePopoverPresentationPolicy.shouldPresentDeviceDetails())
  }

  func testDeviceConnectionPromptOnlyRequestsPassword() {
    XCTAssertEqual(DevicePopoverPresentationPolicy.connectionPromptMode, .passwordOnly)
  }

  func testLiveTopologyStartsWithoutUndiscoveredDefaultDevice() {
    let savedMockMode = getenv("AIRPORT_UTILITY_MOCK").map { String(cString: $0) }
    unsetenv("AIRPORT_UTILITY_MOCK")
    defer {
      if let savedMockMode {
        setenv("AIRPORT_UTILITY_MOCK", savedMockMode, 1)
      }
    }

    let model = AirportAppModel()

    XCTAssertTrue(model.visibleTopologyDevices.isEmpty)
  }

  func testSelectingDiscoveredDeviceUsesBonjourHost() {
    let model = AirportAppModel()
    model.connection.host = "old-airport.local"
    model.connection.password = "old-secret"
    model.rememberConnectionPassword = true
    let device = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Time Capsule",
      name: "Time Capsule",
      hostName: "time-capsule.local."
    )

    model.discoveredDevices = [device]
    model.selectTopologyDevice(device)

    XCTAssertEqual(model.selectedTopologyDeviceID, device.id)
    XCTAssertEqual(model.connection.host, "time-capsule.local")
    XCTAssertEqual(model.connection.password, "")
    XCTAssertFalse(model.rememberConnectionPassword)
    XCTAssertEqual(model.baseStation.name, "Time Capsule")
    XCTAssertTrue(model.shouldShowDeviceConnectionPrompt)
  }

  func testSelectingDifferentDeviceExitsEditingAndClearsPreview() {
    let model = AirportAppModel()
    model.connection.host = "old-airport.local"
    model.connection.password = "old-secret"
    model.baseStation.name = "Old AirPort"
    model.baseStation.serialNumber = "OLD123"
    model.beginEditing()
    model.preview = CommandPreview(
      title: "Internet",
      arguments: ["old command"],
      redactedArguments: ["old command"],
      output: "old output"
    )
    let device = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Time Capsule",
      name: "Time Capsule",
      hostName: "time-capsule.local."
    )

    model.selectTopologyDevice(device)

    XCTAssertFalse(model.isEditingDevice)
    XCTAssertNil(model.preview)
    XCTAssertEqual(model.connection.host, "time-capsule.local")
    XCTAssertEqual(model.baseStation.name, "Time Capsule")
    XCTAssertEqual(model.baseStation.serialNumber, "")
  }

  func testDiscoveredDeviceConnectionHostIsCanonicalized() {
    let device = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Time Capsule",
      name: "Time Capsule",
      hostName: " Time-Capsule.LOCAL. "
    )

    XCTAssertEqual(device.connectionHost, "time-capsule.local")
  }

  func testDiscoveredDeviceNameIsNotUsedAsConnectionHost() {
    let device = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Time Capsule",
      name: "Time Capsule",
      hostName: ""
    )

    XCTAssertEqual(device.displayName, "Time Capsule")
    XCTAssertEqual(device.connectionHost, "")
  }

  func testDiscoveredDeviceFallsBackToNumericAddressForConnectionHost() {
    let device = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Time Capsule",
      name: "Time Capsule",
      hostName: "",
      addresses: ["192.168.4.45"]
    )

    XCTAssertEqual(device.displayName, "Time Capsule")
    XCTAssertEqual(device.connectionHost, "192.168.4.45")
  }

  func testDiscoveredDeviceSkipsBlankFallbackAddresses() {
    let device = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Time Capsule",
      name: "Time Capsule",
      hostName: "",
      addresses: [" ", "192.168.4.45"]
    )

    XCTAssertEqual(device.connectionHost, "192.168.4.45")
  }

  func testDiscoveredDevicePrefersIPv4FallbackAddress() {
    let device = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Time Capsule",
      name: "Time Capsule",
      hostName: "",
      addresses: ["fe80::1%en0", "192.168.4.45"]
    )

    XCTAssertEqual(device.connectionHost, "192.168.4.45")
  }

  func testDiscoveredDevicePrefersInterfaceResolvedAddressOverAmbiguousHostname() {
    let device = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|AirPort Extreme",
      name: "AirPort Extreme",
      hostName: "airport-extreme.local.",
      addresses: ["fe80::211:24ff:fe6c:5054%en2", "10.0.1.1"]
    )

    XCTAssertEqual(device.connectionHost, "10.0.1.1")
    XCTAssertTrue(device.matchesConnectionHost("airport-extreme.local"))
  }

  func testDiscoveredDeviceMatchesAnyResolvedHostOrAddress() {
    let device = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Time Capsule",
      name: "Time Capsule",
      hostName: "time-capsule.local.",
      addresses: ["fe80::1%en0", "192.168.4.45"]
    )

    XCTAssertTrue(device.matchesConnectionHost("TIME-CAPSULE.LOCAL."))
    XCTAssertTrue(device.matchesConnectionHost(" 192.168.4.45 "))
    XCTAssertFalse(device.matchesConnectionHost("192.168.4.46"))
  }

  func testSelectingLoadedDeviceByResolvedAddressPreservesProductCapabilitiesAndSettings() {
    let model = AirportAppModel()
    model.connection.host = "spaceship.local"
    model.connection.password = "password"
    model.applyAuthoritativeBaseStationIdentity(
      readName: "AirPort Extreme",
      serialNumber: "SPACESHIP",
      version: "5.7",
      productID: "3")
    model.legacyDeviceOptions.baseStation.contact = "Network Operations"
    model.legacyDeviceOptions.baseStation.location = "Server Room"
    let device = AirportDiscoveredDevice(
      id: "spaceship",
      name: "AirPort Extreme",
      hostName: "spaceship.local.",
      addresses: ["10.0.1.1"],
      identifiers: ["wama:00-11-22-33-44-55"],
      modelName: "AirPort Extreme",
      productID: "3")

    model.selectTopologyDevice(device)

    XCTAssertEqual(model.connection.host, "10.0.1.1")
    XCTAssertEqual(model.baseStation.productID, "3")
    XCTAssertEqual(model.baseStation.serialNumber, "SPACESHIP")
    XCTAssertEqual(model.legacyDeviceOptions.baseStation.contact, "Network Operations")
    XCTAssertEqual(model.legacyDeviceOptions.baseStation.location, "Server Room")
    XCTAssertTrue(model.capabilities.supportsBaseStationMetadata)
    XCTAssertTrue(model.visiblePanes.contains(.advanced))
  }

  func testUnresolvedDiscoveredDevicesAreHiddenFromTopology() {
    let model = AirportAppModel()
    model.discoveredDevices = [
      AirportDiscoveredDevice(
        id: "local|_airport._tcp.|Unresolved",
        name: "Unresolved",
        hostName: ""
      ),
      AirportDiscoveredDevice(
        id: "local|_airport._tcp.|Resolved",
        name: "Resolved",
        hostName: "resolved.local."
      ),
    ]

    XCTAssertEqual(model.visibleTopologyDevices.map(\.displayName), ["Resolved"])
    XCTAssertEqual(model.visibleTopologyDevices.map(\.connectionHost), ["resolved.local"])
  }

  func testUnresolvedAirPortWithStableBonjourIdentityRemainsVisible() {
    let model = AirportAppModel()
    let express = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Garage APE",
      name: "Garage APE",
      hostName: "",
      identifiers: ["wama:d0-03-4b-5e-0c-2c", "rama:d0-03-4b-64-aa-4e"],
      modelName: "AirPort Express",
      productID: "115")
    model.discoveredDevices = [express]

    XCTAssertEqual(model.visibleTopologyDevices.map(\.id), [express.id])
    XCTAssertEqual(model.visibleTopologyDevices.map(\.displayName), ["Garage APE"])
  }

  func testSelectingDiscoveredDeviceLoadsSavedPassword() {
    let store = MemoryAirportPasswordStore()
    store.passwords["airport.local"] = "saved-secret"
    let model = AirportAppModel(passwordStore: store)
    let device = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Time Capsule",
      name: "Time Capsule",
      hostName: "airport.local."
    )

    model.selectTopologyDevice(device)

    XCTAssertEqual(model.connection.host, "airport.local")
    XCTAssertEqual(model.connection.password, "saved-secret")
    XCTAssertTrue(model.rememberConnectionPassword)
  }

  func testSelectingDiscoveredDeviceUsesEnvironmentPasswordWhenProvided() {
    setenv("AIRPORT_UTILITY_PASSWORD", "env-secret", 1)
    defer { unsetenv("AIRPORT_UTILITY_PASSWORD") }
    let store = MemoryAirportPasswordStore()
    let model = AirportAppModel(passwordStore: store)
    model.connection.host = "time-capsule.local"
    model.connection.password = "env-secret"
    model.hasTrustedConnectionPassword = true
    let device = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|AirPort Extreme",
      name: "AirPort Extreme",
      hostName: "guest-extreme.local."
    )

    model.selectTopologyDevice(device)

    XCTAssertEqual(model.connection.host, "guest-extreme.local")
    XCTAssertEqual(model.connection.password, "env-secret")
    XCTAssertTrue(model.hasTrustedConnectionPassword)
    XCTAssertFalse(model.shouldShowDeviceConnectionPrompt)
  }

  func testResetDiscoveredDeviceUsesDefaultSetupPasswordInsteadOfSavedPassword() {
    let store = MemoryAirportPasswordStore()
    store.passwords["base-station-21f58f.local"] = "old-secret"
    store.passwords["airport-device-id:wama:00-1b-63-21-f5-8e"] = "old-secret"
    let model = AirportAppModel(passwordStore: store)
    let device = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Base Station 21f58f",
      name: "Base Station 21f58f",
      hostName: "Base-Station-21f58f.local.",
      identifiers: ["wama:00-1B-63-21-F5-8E", "rama:00-1B-63-21-F5-8F"],
      txtFields: ["syfl": "0x00000A40", "syap": "102"])

    model.selectTopologyDevice(device)

    XCTAssertTrue(device.isNewAirPortDevice)
    XCTAssertEqual(model.connection.host, "base-station-21f58f.local")
    XCTAssertEqual(model.connection.password, "public")
    XCTAssertFalse(model.rememberConnectionPassword)
    XCTAssertFalse(model.shouldShowDeviceConnectionPrompt)
    XCTAssertEqual(model.deviceStatusText(for: device), "New AirPort base station")
    XCTAssertEqual(store.passwords["base-station-21f58f.local"], "old-secret")

    let sameHostModel = AirportAppModel(passwordStore: store)
    sameHostModel.connection.host = "base-station-21f58f.local"
    sameHostModel.connection.password = "old-secret"

    sameHostModel.selectTopologyDevice(device)

    XCTAssertEqual(sameHostModel.connection.host, "base-station-21f58f.local")
    XCTAssertEqual(sameHostModel.connection.password, "public")
    XCTAssertFalse(sameHostModel.rememberConnectionPassword)
  }

  func testDefaultPasswordProblemUsesPublicEvenAfterNewFlagClears() {
    let store = MemoryAirportPasswordStore()
    store.passwords["time-capsule.local"] = "password"
    store.passwords["airport-device-id:wama:00-1f-f3-c9-62-99"] = "password"
    let model = AirportAppModel(passwordStore: store)
    let device = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|time capsule",
      name: "time capsule",
      hostName: "time-capsule.local.",
      identifiers: ["wama:00-1F-F3-C9-62-99", "rama:00-21-E9-B9-2E-C3"],
      txtFields: ["syfl": "0x00008A2C", "prob": "waCF;opNW;pubP;+", "syap": "106"])

    model.selectTopologyDevice(device)

    XCTAssertFalse(device.isNewAirPortDevice)
    XCTAssertTrue(device.usesDefaultAdminPassword)
    XCTAssertEqual(model.connection.host, "time-capsule.local")
    XCTAssertEqual(model.connection.password, "public")
    XCTAssertFalse(model.rememberConnectionPassword)
    XCTAssertEqual(store.passwords["time-capsule.local"], "password")
  }

  func testSelectingRenamedStableDeviceLoadsSavedIdentityPassword() {
    let store = MemoryAirportPasswordStore()
    store.passwords["airport-device-id:wama:00-1f-f3-c9-62-99"] = "saved-secret"
    let model = AirportAppModel(passwordStore: store)
    model.connection.host = "old-airport.local"
    let device = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Renamed Capsule",
      name: "Renamed Capsule",
      hostName: "renamed-airport.local.",
      identifiers: ["wama:00-1F-F3-C9-62-99"]
    )

    model.selectTopologyDevice(device)

    XCTAssertEqual(model.connection.host, "renamed-airport.local")
    XCTAssertEqual(model.connection.password, "saved-secret")
    XCTAssertTrue(model.rememberConnectionPassword)
  }

  func testSelectingSameHostDeviceLoadsStableIdentityPassword() {
    let store = MemoryAirportPasswordStore()
    store.passwords["airport-device-id:wama:00-1f-f3-c9-62-99"] = "saved-secret"
    let model = AirportAppModel(passwordStore: store)
    model.connection.host = "renamed-airport.local"
    let device = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Renamed Capsule",
      name: "Renamed Capsule",
      hostName: "renamed-airport.local.",
      identifiers: ["wama:00-1F-F3-C9-62-99"]
    )

    model.selectTopologyDevice(device)

    XCTAssertEqual(model.connection.host, "renamed-airport.local")
    XCTAssertEqual(model.connection.password, "saved-secret")
    XCTAssertTrue(model.rememberConnectionPassword)
    XCTAssertFalse(model.shouldShowDeviceConnectionPrompt)
  }

  func testAutoLoadedSavedPasswordTracksDiscoveredDeviceIdentityAcrossRename() {
    let store = MemoryAirportPasswordStore()
    store.passwords["airport-device-id:wama:00-1f-f3-c9-62-99"] = "saved-secret"
    let model = AirportAppModel(passwordStore: store)
    model.isEditingDevice = true
    let oldDevice = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Old Capsule",
      name: "Old Capsule",
      hostName: "old-capsule.local.",
      identifiers: ["wama:00-1f-f3-c9-62-99"]
    )
    let renamedDevice = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Renamed Capsule",
      name: "Renamed Capsule",
      hostName: "renamed-capsule.local.",
      identifiers: ["wama:00-1f-f3-c9-62-99"]
    )

    model.updateDiscoveredDevices([oldDevice])
    model.baseStation.name = "Old Capsule"
    model.updateDiscoveredDevices([renamedDevice])

    XCTAssertEqual(model.connection.host, "old-capsule.local")
    XCTAssertEqual(model.connection.password, "saved-secret")
    XCTAssertEqual(model.visibleTopologyDevices.map(\.id), [renamedDevice.id])
  }

  func testSelectingRenamedStableDevicePreservesCurrentPassword() {
    let store = MemoryAirportPasswordStore()
    let model = AirportAppModel(passwordStore: store)
    model.connection.host = "old-airport.local"
    model.connection.password = "current-secret"
    model.rememberConnectionPassword = false
    let oldDevice = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Old Capsule",
      name: "Old Capsule",
      hostName: "old-airport.local.",
      identifiers: ["wama:00-1f-f3-c9-62-99"]
    )
    let renamedDevice = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Renamed Capsule",
      name: "Renamed Capsule",
      hostName: "renamed-airport.local.",
      identifiers: ["wama:00-1f-f3-c9-62-99"]
    )

    model.selectTopologyDevice(oldDevice)
    model.selectTopologyDevice(renamedDevice)

    XCTAssertEqual(model.connection.host, "renamed-airport.local")
    XCTAssertEqual(model.connection.password, "current-secret")
    XCTAssertFalse(model.rememberConnectionPassword)
    XCTAssertTrue(store.passwords.isEmpty)
  }

  func testSwitchingBetweenDevicesRestoresUnsavedSessionPassword() {
    let store = MemoryAirportPasswordStore()
    let model = AirportAppModel(passwordStore: store)
    let firstDevice = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|First Capsule",
      name: "First Capsule",
      hostName: "first-capsule.local.",
      identifiers: ["wama:00-1f-f3-c9-62-99"]
    )
    let secondDevice = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Second Capsule",
      name: "Second Capsule",
      hostName: "second-capsule.local.",
      identifiers: ["wama:00-1f-f3-c9-63-00"]
    )

    model.selectTopologyDevice(firstDevice)
    model.connection.password = "first-secret"
    model.rememberConnectionPassword = false
    model.selectTopologyDevice(secondDevice)
    model.connection.password = "second-secret"
    model.rememberConnectionPassword = false
    model.selectTopologyDevice(firstDevice)

    XCTAssertEqual(model.connection.host, "first-capsule.local")
    XCTAssertEqual(model.connection.password, "first-secret")
    XCTAssertFalse(model.rememberConnectionPassword)
    XCTAssertTrue(store.passwords.isEmpty)
  }

  func testSavingConnectionPasswordStoresStableDeviceIdentityAliases() {
    let store = MemoryAirportPasswordStore()
    let model = AirportAppModel(passwordStore: store)
    model.connection.host = "airport.local"
    model.connection.password = "saved-secret"
    model.rememberConnectionPassword = true
    let device = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Time Capsule",
      name: "Time Capsule",
      hostName: "airport.local.",
      identifiers: ["wama:00-1F-F3-C9-62-99", "raMA:00-21-E9-B9-2E-C3"]
    )

    model.selectTopologyDevice(device)
    model.saveConnectionPasswordIfRequested()

    XCTAssertEqual(store.passwords["airport.local"], "saved-secret")
    XCTAssertEqual(store.passwords["airport-device-id:wama:00-1f-f3-c9-62-99"], "saved-secret")
    XCTAssertEqual(store.passwords["airport-device-id:rama:00-21-e9-b9-2e-c3"], "saved-secret")
  }

  func testLoadingSavedPasswordCanonicalizesConnectionHost() {
    let store = MemoryAirportPasswordStore()
    store.passwords["time-capsule.local"] = "saved-secret"
    let model = AirportAppModel(passwordStore: store)
    model.connection.host = " Time-Capsule.LOCAL. "

    model.loadSavedPasswordForConnectionHost()

    XCTAssertEqual(model.connection.host, "time-capsule.local")
    XCTAssertEqual(model.connection.password, "saved-secret")
    XCTAssertTrue(model.rememberConnectionPassword)
  }

  func testConnectionPasswordIsSavedOnlyWhenRequested() {
    let store = MemoryAirportPasswordStore()
    let model = AirportAppModel(passwordStore: store)
    model.connection.host = "time-capsule.local"
    model.connection.password = "secret"

    model.saveConnectionPasswordIfRequested()
    XCTAssertNil(store.passwords["time-capsule.local"])

    model.rememberConnectionPassword = true
    model.saveConnectionPasswordIfRequested()

    XCTAssertEqual(store.passwords["time-capsule.local"], "secret")
  }

  func testConnectionPasswordRememberToggleRemovesAllPersistedAliases() {
    let store = MemoryAirportPasswordStore()
    let model = AirportAppModel(passwordStore: store)
    let device = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Time Capsule",
      name: "Time Capsule",
      hostName: "time-capsule.local.",
      identifiers: ["wama:00-1F-F3-C9-62-99"])
    store.passwords["time-capsule.local"] = "secret"
    store.passwords["airport-device-id:wama:00-1f-f3-c9-62-99"] = "secret"

    model.selectTopologyDevice(device)
    model.updateRememberConnectionPassword(false)

    XCTAssertFalse(model.rememberConnectionPassword)
    XCTAssertNil(store.passwords["time-capsule.local"])
    XCTAssertNil(store.passwords["airport-device-id:wama:00-1f-f3-c9-62-99"])
  }

  func testAuxiliaryPasswordsLoadOnlyForSupportedFeatures() {
    let store = MemoryAirportPasswordStore()
    store.passwords["airport-airplay:airport.local"] = "speaker-secret"
    store.passwords["airport-disk:airport.local"] = "disk-secret"
    let model = AirportAppModel(passwordStore: store)
    model.connection.host = "airport.local"
    model.capabilities.supportsAirPlay = true
    model.capabilities.supportsDisks = true
    model.disks.secureSharedDisks = "disk-password"
    model.airPlay.speakerPassword = ""
    model.airPlay.verifySpeakerPassword = ""
    model.disks.diskPassword = ""
    model.disks.verifyDiskPassword = ""

    model.loadAuxiliaryPasswordsFromStore()

    XCTAssertTrue(model.airPlay.rememberPassword)
    XCTAssertEqual(model.airPlay.speakerPassword, "speaker-secret")
    XCTAssertEqual(model.airPlay.verifySpeakerPassword, "speaker-secret")
    XCTAssertTrue(model.disks.rememberPassword)
    XCTAssertEqual(model.disks.diskPassword, "disk-secret")
    XCTAssertEqual(model.disks.verifyDiskPassword, "disk-secret")
  }

  func testDirtyAuxiliaryPasswordIsPersistedOnlyAfterSuccessfulApplySnapshot() {
    let store = MemoryAirportPasswordStore()
    let model = AirportAppModel(passwordStore: store)
    model.connection.host = "airport.local"
    model.capabilities.supportsAirPlay = true
    model.airPlay.enabled = true
    model.airPlay.speakerName = "Living Room"
    model.airPlay.speakerPassword = "old-secret"
    model.airPlay.verifySpeakerPassword = "old-secret"
    model.markClean()

    model.airPlay.speakerPassword = "new-secret"
    model.airPlay.verifySpeakerPassword = "new-secret"
    model.updateRememberAirPlayPassword(true)

    XCTAssertNil(store.passwords["airport-airplay:airport.local"])

    model.persistAuxiliaryPasswordPreferences(from: model.currentSnapshot)

    XCTAssertEqual(store.passwords["airport-airplay:airport.local"], "new-secret")
  }

  func testDevicePasswordDiskModeUsesConnectionPasswordPreference() {
    let store = MemoryAirportPasswordStore()
    let model = AirportAppModel(passwordStore: store)
    model.connection.host = "airport.local"
    model.connection.password = "admin-secret"
    model.disks.secureSharedDisks = "device-password"

    model.updateRememberCurrentDiskPassword(true)

    XCTAssertTrue(model.rememberConnectionPassword)
    XCTAssertTrue(model.remembersCurrentDiskPassword)
    XCTAssertEqual(store.passwords["airport.local"], "admin-secret")
    XCTAssertNil(store.passwords["airport-disk:airport.local"])
  }

  func testDefaultPasswordStoreDoesNotUseKeychainInsideXCTest() {
    XCTAssertTrue(AirportAppModel.defaultPasswordStore() is NoopAirportPasswordStore)
  }

  func testConnectionAttemptRequiresNonWhitespaceHostAndPassword() {
    let model = AirportAppModel()

    model.connection.host = "   "
    model.connection.password = "secret"
    XCTAssertFalse(model.canAttemptConnection)

    model.connection.host = "time-capsule.local"
    model.connection.password = "   "
    XCTAssertFalse(model.canAttemptConnection)

    model.connection.host = " time-capsule.local. "
    model.connection.password = " password "
    XCTAssertTrue(model.canAttemptConnection)
  }

  func testConnectionAttemptIsDisabledWhileBusy() {
    let model = AirportAppModel()
    model.connection.host = "time-capsule.local"
    model.connection.password = "password"

    XCTAssertTrue(model.canAttemptConnection)

    model.isBusy = true

    XCTAssertFalse(model.canAttemptConnection)
  }

  func testRefreshRejectsInvalidConnectionWithoutStartingWork() {
    let model = AirportAppModel()
    model.connection.host = " time-capsule.local. "
    model.connection.password = "   "
    model.preview = CommandPreview(
      title: "Existing",
      arguments: [],
      redactedArguments: [],
      output: "old preview"
    )

    model.refresh()

    XCTAssertEqual(model.connection.host, "time-capsule.local")
    XCTAssertFalse(model.isBusy)
    XCTAssertNil(model.preview)
    XCTAssertEqual(model.status, "Enter base station password to load settings.")
  }

  func testRefreshWhileBusyLeavesCurrentStateUntouched() {
    let model = AirportAppModel()
    model.connection.host = "time-capsule.local"
    model.connection.password = "password"
    model.isBusy = true
    model.status = "Refreshing settings"
    model.preview = CommandPreview(
      title: "Existing",
      arguments: [],
      redactedArguments: [],
      output: "old preview"
    )

    model.refresh()

    XCTAssertTrue(model.isBusy)
    XCTAssertEqual(model.status, "Refreshing settings")
    XCTAssertEqual(model.preview?.title, "Existing")
  }

  func testNetworkRefreshClosesDevicePopoverAndClearsSelection() {
    let model = AirportAppModel()
    model.mockMode = true
    let device = AirportDiscoveredDevice(
      id: "device", name: "Time Capsule", hostName: "time-capsule.local.",
      identifiers: ["wama:00-11-22-33-44-55"])
    model.updateDiscoveredDevices([device])
    model.selectTopologyDevice(device)
    model.isDevicePopoverPresented = true
    model.preview = CommandPreview(
      title: "Existing", arguments: [], redactedArguments: [], output: "preview")

    XCTAssertTrue(model.canRefreshNetwork)

    model.refreshNetwork()

    XCTAssertNil(model.selectedTopologyDeviceID)
    XCTAssertTrue(model.selectedTopologyDeviceIdentifiers.isEmpty)
    XCTAssertFalse(model.isDevicePopoverPresented)
    XCTAssertNil(model.preview)
    XCTAssertFalse(model.hasLoadedSettings)
    XCTAssertTrue(model.logs.contains("Mock network scan completed."))
  }

  func testNetworkRefreshIsDisabledByPopupsOtherThanDeviceDetails() {
    let model = AirportAppModel()
    model.isDevicePopoverPresented = true
    XCTAssertTrue(model.canRefreshNetwork)

    model.isInternetPopoverPresented = true
    XCTAssertFalse(model.canRefreshNetwork)
    model.isInternetPopoverPresented = false

    model.isConnectionPopoverPresented = true
    XCTAssertFalse(model.canRefreshNetwork)
    model.isConnectionPopoverPresented = false

    model.isShowingPreferences = true
    XCTAssertFalse(model.canRefreshNetwork)
    model.isShowingPreferences = false

    model.isShowingSetup = true
    XCTAssertFalse(model.canRefreshNetwork)
    model.isShowingSetup = false

    model.isShowingRestoreConfirmation = true
    XCTAssertFalse(model.canRefreshNetwork)
  }

  func testEditingSuppressesInitialRefresh() {
    let model = AirportAppModel()
    model.connection.host = "time-capsule.local"
    model.connection.password = "password"
    model.beginEditing()

    model.loadInitialSettingsIfPossible()

    XCTAssertFalse(model.isBusy)
  }

  func testRefreshAcceptsLegacyExtremeSnapshotWithoutSerialNumber() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("airport-legacy-identity-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let readScript = try backendScriptURL(in: temporaryDirectory)
    try """
    #!/bin/sh
    cat <<'JSON'
    {"errors":{"sySN":"ACP property sySN returned status -11"},"settings":{"syNm":{"value":"airport extreme spaceship"},"syVs":{"value":"5.7"},"syAP":{"value":"3"},"auRR":{"value":"0"},"auNN":{"value":"placeholder audio"},"Prof":{"decoded":{"restoreProfile":{"syNm":"airport extreme spaceship","raNm":"airport extreme spaceship net"}}},"MaSt":{"decoded":[]}}}
    JSON
    """.write(to: readScript, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: readScript.path)

    let model = AirportAppModel()
    model.connection.repoPath = temporaryDirectory.path
    model.connection.host = "10.0.1.1"
    model.connection.password = "password"

    model.refresh()
    try await waitForIdle(model)

    XCTAssertTrue(model.hasLoadedSettings)
    XCTAssertEqual(model.baseStation.name, "airport extreme spaceship")
    XCTAssertEqual(model.baseStation.serialNumber, "")
    XCTAssertEqual(model.baseStation.version, "5.7")
    XCTAssertEqual(model.baseStation.productID, "3")
    XCTAssertFalse(model.capabilities.supportsAirPlay)
    XCTAssertFalse(model.visiblePanes.contains(.airPlay))
    XCTAssertTrue(model.capabilities.supportsModem)
    XCTAssertTrue(model.showsModemControls)
    XCTAssertTrue(model.internetConnectUsingOptions.contains(.modem))
    XCTAssertFalse(model.isConnectionPopoverPresented)
    XCTAssertEqual(model.status, "Connected to 10.0.1.1")
  }

  func testLateRefreshResultDoesNotOverwriteDraftWhileEditing() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("airport-edit-refresh-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let readScript = try backendScriptURL(in: temporaryDirectory)
    try """
    #!/bin/sh
    sleep 0.05
    json=0
    setting=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --setting)
          shift
          setting="${1:-}"
          ;;
        --json)
          json=1
          ;;
      esac
      if [ "$#" -gt 0 ]; then
        shift
      fi
    done

    if [ "$json" = "1" ]; then
      cat <<'JSON'
    {"errors":{},"settings":{"syNm":{"value":"Fresh Capsule"},"sySN":{"value":"FRESH-SERIAL"},"syVs":{"value":"7.9.1"},"Prof":{"decoded":{"restoreProfile":{"waCV":"dhcp","syNm":"Fresh Capsule","raNm":"Fresh Wi-Fi"}}},"MaSt":{"decoded":[]}}}
    JSON
      exit 0
    fi

    case "$setting" in
      syNm)
        echo "Fresh Capsule"
        ;;
      sySN)
        echo "FRESH-SERIAL"
        ;;
      syVs)
        echo "7.9.1"
        ;;
      Prof)
        echo '{"restoreProfile":{"waCV":"dhcp","syNm":"Fresh Capsule","raNm":"Fresh Wi-Fi"}}'
        ;;
      MaSt)
        echo '[]'
        ;;
      *)
        echo '0'
        ;;
    esac
    """.write(to: readScript, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: readScript.path)

    let model = AirportAppModel()
    model.connection.repoPath = temporaryDirectory.path
    model.connection.host = "time-capsule.local"
    model.connection.password = "password"
    model.baseStation.name = "Old Capsule"
    model.markClean()

    model.refresh()
    model.beginEditing()
    model.baseStation.name = "Draft Capsule"

    try await waitForIdle(model)

    XCTAssertEqual(model.baseStation.name, "Draft Capsule")
    XCTAssertEqual(model.wireless.networkName, "")
    XCTAssertTrue(model.hasPendingChanges)
    XCTAssertTrue(model.canApplyPendingChanges)
    XCTAssertEqual(model.status, "Finish editing before refreshing settings.")
    XCTAssertTrue(model.logs.contains("Ignored settings refresh while editing."))
  }

  func testStaleRefreshFailureDoesNotOverwriteNewHostStatus() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("airport-stale-refresh-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let readScript = try backendScriptURL(in: temporaryDirectory)
    try """
    #!/bin/sh
    sleep 0.2
    echo "stale backend failure" >&2
    exit 1
    """.write(to: readScript, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: readScript.path)

    let model = AirportAppModel()
    model.connection.repoPath = temporaryDirectory.path
    model.connection.host = "old-capsule.local"
    model.connection.password = "password"

    model.refresh()
    model.connection.host = "new-capsule.local"

    try await waitForIdle(model)

    XCTAssertEqual(model.status, "Ready to connect to new-capsule.local")
    XCTAssertFalse(model.status.contains("stale backend failure"))
    XCTAssertTrue(
      model.logs.contains {
        $0.contains("Ignored Refreshing settings failure for stale host old-capsule.local")
      })
  }

  func testFailedRefreshReturnsToConnectableIdleState() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("airport-failed-refresh-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let readScript = try backendScriptURL(in: temporaryDirectory)
    try """
    #!/bin/sh
    echo "backend failure" >&2
    exit 1
    """.write(to: readScript, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: readScript.path)

    let model = AirportAppModel()
    model.connection.repoPath = temporaryDirectory.path
    model.connection.host = "time-capsule.local"
    model.connection.password = "password"

    model.refresh()
    try await waitForIdle(model)

    XCTAssertFalse(model.isBusy)
    XCTAssertTrue(model.canAttemptConnection)
    XCTAssertEqual(model.status, "backend failure")
    XCTAssertTrue(model.logs.contains("Error: backend failure"))
  }

  func testRefreshUsesSingleBatchForCurrentDNSFallback() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("airport-dns-batch-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let readScript = try backendScriptURL(in: temporaryDirectory)
    try """
    #!/bin/sh
    printf '%s\\n' "$*" >> calls.log
    cat <<'JSON'
    {"errors":{},"settings":{"syNm":{"value":"DNS Capsule"},"sySN":{"value":"DNS-SERIAL"},"syVs":{"value":"7.9.1"},"Prof":{"decoded":{"restoreProfile":{"waCV":33536,"syNm":"DNS Capsule","waD1":"0.0.0.0","waD2":"0.0.0.0","waD3":"0.0.0.0"}}},"MaSt":{"decoded":[]},"waD1":{"hex":"00000000","length":4,"value":"0"},"waD2":{"hex":"00000000","length":4,"value":"0"},"waD3":{"hex":"00000000","length":4,"value":"0"},"waC1":{"hex":"c0a80101","length":4,"value":"3232235777"},"waC2":{"hex":"00000000","length":4,"value":"0"},"waC3":{"hex":"00000000","length":4,"value":"0"}}}
    JSON
    """.write(to: readScript, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: readScript.path)

    let model = AirportAppModel()
    model.connection.repoPath = temporaryDirectory.path
    model.connection.host = "time-capsule.local"
    model.connection.password = "password"

    model.refresh()
    try await waitForIdle(model)

    let calls = try String(
      contentsOf: temporaryDirectory.appendingPathComponent("calls.log"),
      encoding: .utf8
    )
    let callLines = calls.split(whereSeparator: \.isNewline).map(String.init)

    XCTAssertEqual(callLines.count, 1)
    XCTAssertTrue(callLines[0].contains("--setting waC1"))
    XCTAssertFalse(callLines[0].contains("dhcpDNS1"))
    XCTAssertFalse(callLines[0].contains("currentDNS1"))
    XCTAssertFalse(callLines[0].contains("currentPrimaryDNSServer"))
    XCTAssertEqual(model.internet.dnsServerPreview, "192.168.1.1")
  }

  func testSelectingSavedPasswordDeviceWhileBusyRefreshesAfterStaleOperation() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("airport-busy-selection-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let readScript = try backendScriptURL(in: temporaryDirectory)
    try """
    #!/bin/sh
    host="$1"
    json=0
    setting=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --setting)
          shift
          setting="${1:-}"
          ;;
        --json)
          json=1
          ;;
      esac
      if [ "$#" -gt 0 ]; then
        shift
      fi
    done

    if [ "$host" = "old-capsule.local" ]; then
      sleep 0.2
      echo "old backend failure" >&2
      exit 1
    fi

    if [ "$json" = "1" ]; then
      cat <<'JSON'
    {"errors":{},"settings":{"syNm":{"value":"New Capsule"},"sySN":{"value":"NEW-SERIAL"},"syVs":{"value":"7.9.1"},"Prof":{"decoded":{"restoreProfile":{"waCV":"dhcp","syNm":"New Capsule","raNm":"New Wi-Fi","waD1":{"hex":"c0a80101","length":4,"value":"3232235777"},"6NS1":"2001:db8::1"}}},"MaSt":{"decoded":[]},"raSt":{"value":"0"},"raNm":{"value":"New Wi-Fi"},"raWM":{"value":"5"},"syRe":{"value":"0"},"raCl":{"value":"0"},"raMd":{"value":"6"},"raCh":{"value":"11"}}}
    JSON
      exit 0
    fi

    case "$setting" in
      syNm)
        echo "New Capsule"
        ;;
      sySN)
        echo "NEW-SERIAL"
        ;;
      syVs)
        echo "7.9.1"
        ;;
      raSt)
        echo "0"
        ;;
      raNm)
        echo "New Wi-Fi"
        ;;
      raWM)
        echo "5"
        ;;
      syRe)
        echo "0"
        ;;
      raCl)
        echo "00"
        ;;
      raMd)
        echo "0006"
        ;;
      raCh)
        echo "11"
        ;;
      Prof)
        echo '{"restoreProfile":{"waCV":"dhcp","syNm":"New Capsule","raNm":"New Wi-Fi","waD1":{"hex":"c0a80101","length":4,"value":"3232235777"},"6NS1":"2001:db8::1"}}'
        ;;
      MaSt)
        echo '[]'
        ;;
      *)
        echo '"0"'
        ;;
    esac
    """.write(to: readScript, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: readScript.path)

    let store = MemoryAirportPasswordStore()
    store.savePassword("saved-password", for: "new-capsule.local")
    let model = AirportAppModel(passwordStore: store)
    model.connection.repoPath = temporaryDirectory.path
    model.connection.host = "old-capsule.local"
    model.connection.password = "old-password"
    let newDevice = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|New Capsule",
      name: "New Capsule",
      hostName: "new-capsule.local."
    )

    model.refresh()
    model.selectTopologyDevice(newDevice)

    try await waitForIdle(model)

    XCTAssertEqual(model.connection.host, "new-capsule.local")
    XCTAssertEqual(model.connection.password, "saved-password")
    XCTAssertEqual(model.status, "Connected to new-capsule.local")
    XCTAssertEqual(model.baseStation.name, "New Capsule")
    XCTAssertEqual(model.baseStation.serialNumber, "NEW-SERIAL")
    XCTAssertEqual(model.baseStation.version, "7.9.1")
    XCTAssertEqual(model.wireless.networkName, "New Wi-Fi")
    XCTAssertTrue(model.logs.contains { $0.contains("Refresh completed.") })
  }

  func testSavingConnectionPasswordCanonicalizesConnectionHost() {
    let store = MemoryAirportPasswordStore()
    let model = AirportAppModel(passwordStore: store)
    model.connection.host = " Time-Capsule.LOCAL. "
    model.connection.password = "secret"
    model.rememberConnectionPassword = true

    model.saveConnectionPasswordIfRequested()

    XCTAssertEqual(model.connection.host, "time-capsule.local")
    XCTAssertEqual(store.passwords["time-capsule.local"], "secret")
  }

  func testStaleDNSFallbackDoesNotApplyPreviewToNewHost() {
    let model = AirportAppModel()
    model.connection.host = "new-capsule.local"

    let didApply = model.applyDNSPreviewFallbackIfConnectionStillMatches(
      requestHost: "old-capsule.local",
      ipv4Values: ["192.168.1.1"],
      ipv6Values: ["2001:db8::1"]
    )

    XCTAssertFalse(didApply)
    XCTAssertEqual(model.internet.dnsServerPreview, "")
    XCTAssertEqual(model.internet.ipv6DNSServerPreview, "")
  }

  func testCurrentDNSFallbackAppliesPreviewValues() {
    let model = AirportAppModel()
    model.connection.host = "time-capsule.local"

    let didApply = model.applyDNSPreviewFallbackIfConnectionStillMatches(
      requestHost: "TIME-CAPSULE.LOCAL.",
      ipv4Values: ["0", "192.168.1.1"],
      ipv6Values: ["::", "2001:db8::1"]
    )

    XCTAssertTrue(didApply)
    XCTAssertEqual(model.internet.dnsServerPreview, "192.168.1.1")
    XCTAssertEqual(model.internet.ipv6DNSServerPreview, "2001:db8::1")
  }

  func testDeselectingSelectedTopologyDeviceClearsSelection() {
    let model = AirportAppModel()
    let device = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Time Capsule",
      name: "Time Capsule",
      hostName: "time-capsule.local."
    )

    model.selectTopologyDevice(device)
    model.deselectTopologyDevice(device)

    XCTAssertNil(model.selectedTopologyDeviceID)
  }

  func testRemovedDiscoveredDeviceClearsSelectionAndPopover() {
    let model = AirportAppModel()
    let selectedDevice = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Selected",
      name: "Selected",
      hostName: "selected.local."
    )
    let remainingDevice = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Remaining",
      name: "Remaining",
      hostName: "remaining.local."
    )
    model.updateDiscoveredDevices([selectedDevice, remainingDevice])
    model.selectTopologyDevice(selectedDevice)
    model.isDevicePopoverPresented = true
    model.beginEditing()
    model.preview = CommandPreview(
      title: "Internet",
      arguments: ["selected command"],
      redactedArguments: ["selected command"],
      output: "selected output"
    )

    model.updateDiscoveredDevices([remainingDevice])

    XCTAssertNil(model.selectedTopologyDeviceID)
    XCTAssertFalse(model.isDevicePopoverPresented)
    XCTAssertFalse(model.isEditingDevice)
    XCTAssertNil(model.preview)
  }

  func testDiscoveryUpdatePreservesSelectionForEquivalentHostWithNewServiceID() {
    let model = AirportAppModel()
    let selectedDevice = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Old Name",
      name: "Old Name",
      hostName: "time-capsule.local."
    )
    let replacementDevice = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|New Name",
      name: "New Name",
      hostName: "Time-Capsule.LOCAL."
    )
    model.updateDiscoveredDevices([selectedDevice])
    model.selectTopologyDevice(selectedDevice)
    model.isDevicePopoverPresented = true
    model.preview = CommandPreview(
      title: "Internet",
      arguments: ["selected command"],
      redactedArguments: ["selected command"],
      output: "selected output"
    )

    model.updateDiscoveredDevices([replacementDevice])

    XCTAssertEqual(model.selectedTopologyDeviceID, replacementDevice.id)
    XCTAssertTrue(model.isDevicePopoverPresented)
    XCTAssertFalse(model.isEditingDevice)
    XCTAssertEqual(model.preview?.title, "Internet")
    XCTAssertEqual(model.connection.host, "time-capsule.local")
  }

  func testDiscoveryUpdatePreservesSelectionForEquivalentResolvedAddressWithNewServiceID() throws {
    let model = AirportAppModel()
    model.connection.host = "192.168.4.45"
    model.baseStation.name = "time capsule"
    model.baseStation.serialNumber = "C86TEST123"
    let connectedDevice = try XCTUnwrap(model.visibleTopologyDevices.first)
    model.selectTopologyDevice(connectedDevice)
    model.isDevicePopoverPresented = true
    let replacementDevice = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Time Capsule",
      name: "Time Capsule",
      hostName: "time-capsule.local.",
      addresses: ["192.168.4.45"]
    )

    model.updateDiscoveredDevices([replacementDevice])

    XCTAssertEqual(model.selectedTopologyDeviceID, replacementDevice.id)
    XCTAssertTrue(model.isDevicePopoverPresented)
    XCTAssertEqual(model.visibleTopologyDevices.map(\.id), [replacementDevice.id])
  }

  func testDiscoveryUpdateReplacesRenamedSelectedBonjourDeviceByStableIdentifier() {
    let model = AirportAppModel()
    let selectedDevice = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Old Capsule",
      name: "old capsule",
      hostName: "old-capsule.local.",
      identifiers: ["wama:00-1f-f3-c9-62-99"]
    )
    let replacementDevice = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|New Capsule",
      name: "new capsule",
      hostName: "new-capsule.local.",
      identifiers: ["wama:00-1f-f3-c9-62-99"]
    )
    model.updateDiscoveredDevices([selectedDevice])
    model.selectTopologyDevice(selectedDevice)
    model.baseStation.name = "new capsule"
    model.baseStation.serialNumber = "C86TEST123"
    model.isDevicePopoverPresented = true

    model.updateDiscoveredDevices([replacementDevice])

    XCTAssertEqual(model.selectedTopologyDeviceID, replacementDevice.id)
    XCTAssertTrue(model.isDevicePopoverPresented)
    XCTAssertEqual(model.connection.host, "new-capsule.local")
    XCTAssertEqual(model.visibleTopologyDevices.map(\.id), [replacementDevice.id])
    XCTAssertEqual(model.visibleTopologyDevices.map(\.displayName), ["new capsule"])
  }

  func testDiscoveryReplacementReusesSavedPasswordFromPreviousHostForStableRename() {
    let store = MemoryAirportPasswordStore()
    let model = AirportAppModel(passwordStore: store)
    let selectedDevice = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Old Capsule",
      name: "old capsule",
      hostName: "old-capsule.local.",
      identifiers: ["wama:00-1f-f3-c9-62-99"]
    )
    let replacementDevice = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|New Capsule",
      name: "new capsule",
      hostName: "new-capsule.local.",
      identifiers: ["wama:00-1f-f3-c9-62-99"]
    )
    model.updateDiscoveredDevices([selectedDevice])
    model.selectTopologyDevice(selectedDevice)
    store.passwords["old-capsule.local"] = "saved-secret"
    model.connection.password = ""

    model.updateDiscoveredDevices([replacementDevice])

    XCTAssertEqual(model.selectedTopologyDeviceID, replacementDevice.id)
    XCTAssertEqual(model.connection.host, "new-capsule.local")
    XCTAssertEqual(model.connection.password, "saved-secret")
    XCTAssertTrue(model.rememberConnectionPassword)
    XCTAssertFalse(model.shouldShowDeviceConnectionPrompt)
    XCTAssertEqual(store.passwords["airport-device-id:wama:00-1f-f3-c9-62-99"], "saved-secret")
    XCTAssertEqual(store.passwords["new-capsule.local"], "saved-secret")
  }

  func testDiscoveryUpdatePreservesSelectedConnectedDevice() throws {
    let model = AirportAppModel()
    model.connection.host = "192.168.4.45"
    model.baseStation.name = "time capsule"
    model.baseStation.serialNumber = "C86TEST123"
    let connectedDevice = try XCTUnwrap(model.visibleTopologyDevices.first)
    model.selectTopologyDevice(connectedDevice)
    model.isDevicePopoverPresented = true
    model.beginEditing()
    model.preview = CommandPreview(
      title: "Internet",
      arguments: ["connected command"],
      redactedArguments: ["connected command"],
      output: "connected output"
    )

    model.updateDiscoveredDevices([])

    XCTAssertEqual(model.selectedTopologyDeviceID, connectedDevice.id)
    XCTAssertTrue(model.isEditingDevice)
    XCTAssertEqual(model.preview?.title, "Internet")
  }

  func testSelectingInternetNodeClearsDeviceSelection() {
    let model = AirportAppModel()
    let device = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Time Capsule",
      name: "Time Capsule",
      hostName: "time-capsule.local."
    )

    model.selectTopologyDevice(device)
    model.isDevicePopoverPresented = true
    model.selectInternetNode()

    XCTAssertNil(model.selectedTopologyDeviceID)
    XCTAssertFalse(model.isDevicePopoverPresented)
    XCTAssertTrue(model.isInternetSelected)
  }

  func testSelectingInternetNodeCancelsDeviceEditingAndClearsPreview() {
    let model = AirportAppModel()
    let device = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Time Capsule",
      name: "Time Capsule",
      hostName: "time-capsule.local."
    )
    model.baseStation.name = "time capsule"
    model.markClean()
    model.selectTopologyDevice(device)
    model.beginEditing()
    model.baseStation.name = "unsaved name"
    model.preview = CommandPreview(
      title: "Base Station",
      arguments: ["old command"],
      redactedArguments: ["old command"],
      output: "old output"
    )

    model.selectInternetNode()

    XCTAssertNil(model.selectedTopologyDeviceID)
    XCTAssertFalse(model.isDevicePopoverPresented)
    XCTAssertFalse(model.isEditingDevice)
    XCTAssertTrue(model.isInternetSelected)
    XCTAssertNil(model.preview)
    XCTAssertEqual(model.baseStation.name, "time capsule")
    XCTAssertFalse(model.hasPendingChanges)
  }

  func testSelectingDeviceClearsInternetSelection() {
    let model = AirportAppModel()
    let device = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Time Capsule",
      name: "Time Capsule",
      hostName: "time-capsule.local."
    )

    model.selectInternetNode()
    model.isInternetPopoverPresented = true
    model.selectTopologyDevice(device)

    XCTAssertEqual(model.selectedTopologyDeviceID, device.id)
    XCTAssertFalse(model.isInternetSelected)
    XCTAssertFalse(model.isInternetPopoverPresented)
  }

  func testSelectingEquivalentCanonicalDeviceDoesNotClearLoadedDetails() {
    let model = AirportAppModel()
    model.connection.host = " Time-Capsule.LOCAL. "
    model.connection.password = "password"
    model.rememberConnectionPassword = true
    model.beginEditing()
    model.preview = CommandPreview(
      title: "Internet",
      arguments: ["current command"],
      redactedArguments: ["current command"],
      output: "current output"
    )
    model.baseStation.name = "time capsule 4"
    model.baseStation.serialNumber = "C86TEST123"
    model.wireless.networkName = "Network"
    let device = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Time Capsule",
      name: "Time Capsule",
      hostName: "time-capsule.local"
    )

    model.selectTopologyDevice(device)

    XCTAssertEqual(model.connection.host, "time-capsule.local")
    XCTAssertEqual(model.connection.password, "password")
    XCTAssertTrue(model.rememberConnectionPassword)
    XCTAssertTrue(model.isEditingDevice)
    XCTAssertEqual(model.preview?.title, "Internet")
    XCTAssertEqual(model.baseStation.name, "time capsule 4")
    XCTAssertEqual(model.baseStation.serialNumber, "C86TEST123")
    XCTAssertEqual(model.wireless.networkName, "Network")
  }

  func testVisibleTopologyDoesNotDuplicateEquivalentCanonicalConnectedHost() {
    let model = AirportAppModel()
    model.connection.host = " Time-Capsule.LOCAL. "
    model.baseStation.name = "time capsule 4"
    model.baseStation.serialNumber = "C86TEST123"
    model.discoveredDevices = [
      AirportDiscoveredDevice(
        id: "local|_airport._tcp.|Time Capsule",
        name: "Time Capsule",
        hostName: "time-capsule.local"
      )
    ]

    XCTAssertEqual(model.visibleTopologyDevices.map(\.id), ["local|_airport._tcp.|Time Capsule"])
  }

  func testVisibleTopologyDoesNotDuplicateResolvedAddressForConnectedHost() {
    let model = AirportAppModel()
    model.connection.host = "192.168.4.45"
    model.baseStation.name = "time capsule"
    model.baseStation.serialNumber = "C86TEST123"
    model.discoveredDevices = [
      AirportDiscoveredDevice(
        id: "local|_airport._tcp.|Time Capsule",
        name: "Time Capsule",
        hostName: "time-capsule.local.",
        addresses: ["fe80::1%en0", "192.168.4.45"]
      )
    ]

    XCTAssertEqual(model.visibleTopologyDevices.map(\.id), ["local|_airport._tcp.|Time Capsule"])
  }

  func testVisibleTopologyDeduplicatesOldAndNewBonjourNamesForSameAddress() {
    let model = AirportAppModel()
    model.connection.host = "192.168.4.45"
    model.baseStation.name = "new capsule"
    model.baseStation.serialNumber = "C86TEST123"
    model.discoveredDevices = [
      AirportDiscoveredDevice(
        id: "local|_airport._tcp.|Old Capsule",
        name: "old capsule",
        hostName: "old-capsule.local.",
        addresses: ["192.168.4.45"]
      ),
      AirportDiscoveredDevice(
        id: "local|_airport._tcp.|New Capsule",
        name: "new capsule",
        hostName: "new-capsule.local.",
        addresses: ["192.168.4.45"]
      ),
    ]

    XCTAssertEqual(model.visibleTopologyDevices.map(\.id), ["local|_airport._tcp.|New Capsule"])
    XCTAssertEqual(model.visibleTopologyDevices.map(\.displayName), ["new capsule"])
  }

  func testVisibleTopologyDeduplicatesRenamedBonjourRecordsByStableIdentifier() {
    let model = AirportAppModel()
    model.baseStation.name = "new capsule"
    model.discoveredDevices = [
      AirportDiscoveredDevice(
        id: "local|_airport._tcp.|Old Capsule",
        name: "old capsule",
        hostName: "old-capsule.local.",
        identifiers: ["wama:00-1f-f3-c9-62-99"]
      ),
      AirportDiscoveredDevice(
        id: "local|_airport._tcp.|New Capsule",
        name: "new capsule",
        hostName: "new-capsule.local.",
        identifiers: ["wama:00-1f-f3-c9-62-99"]
      ),
    ]

    XCTAssertEqual(model.visibleTopologyDevices.map(\.id), ["local|_airport._tcp.|New Capsule"])
    XCTAssertEqual(model.visibleTopologyDevices.map(\.displayName), ["new capsule"])
  }

  func testVisibleTopologyCollapsesConnectedDeviceDuringBonjourRenameChurn() {
    let model = AirportAppModel()
    model.connection.host = "time-capsule.local"
    model.baseStation.name = "renamed capsule"
    model.baseStation.productID = "106"
    let oldDevice = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Time Capsule",
      name: "time capsule",
      hostName: "time-capsule.local.",
      modelName: "AirPort Time Capsule",
      productID: "106")
    let renamedDevice = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Renamed Capsule",
      name: "renamed capsule",
      hostName: "renamed-capsule.local.",
      modelName: "AirPort Time Capsule",
      productID: "106")

    model.discoveredDevices = [oldDevice, renamedDevice]

    XCTAssertEqual(model.visibleTopologyDevices.map(\.id), [renamedDevice.id])
    XCTAssertEqual(model.visibleTopologyDevices.map(\.displayName), ["renamed capsule"])
  }

  func testVisibleTopologyKeepsSeparateSameModelDeviceWhenNeitherMatchesCurrentName() {
    let model = AirportAppModel()
    model.connection.host = "time-capsule.local"
    model.baseStation.name = "time capsule"
    model.baseStation.productID = "106"
    let connectedDevice = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Time Capsule",
      name: "time capsule",
      hostName: "time-capsule.local.",
      modelName: "AirPort Time Capsule",
      productID: "106")
    let otherDevice = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Guest Capsule",
      name: "guest capsule",
      hostName: "guest-capsule.local.",
      modelName: "AirPort Time Capsule",
      productID: "106")

    model.discoveredDevices = [connectedDevice, otherDevice]

    XCTAssertEqual(
      model.visibleTopologyDevices.map(\.id),
      [connectedDevice.id, otherDevice.id])
  }

  func testVisibleTopologyDoesNotAppendSyntheticDeviceWhenConnectedIdentityMatchesRenamedDiscovery()
  {
    let model = AirportAppModel()
    model.connection.host = "time-capsule-2.local"
    model.baseStation.name = "time capsule"
    model.baseStation.serialNumber = "6F8412DG32D"
    let oldIdentifiers = AirPortBonjourBrowser.stableIdentifiers(fromTXTRecord: [
      "waMA": Data(
        "00-1F-F3-C9-62-99,raMA=00-21-E9-B9-2E-C3,raCh=1,syVs=7.8.1,bjSd=12".utf8)
    ])
    let newIdentifiers = AirPortBonjourBrowser.stableIdentifiers(fromTXTRecord: [
      "waMA": Data(
        "00-1F-F3-C9-62-99,raMA=00-21-E9-B9-2E-C3,raCh=1,syVs=7.8.1,bjSd=13".utf8)
    ])
    let oldDevice = AirportDiscoveredDevice(
      id: "local.|_airport._tcp.|time capsule 2",
      name: "time capsule 2",
      hostName: "time-capsule-2.local.",
      addresses: ["192.168.4.45"],
      identifiers: oldIdentifiers
    )
    let newDevice = AirportDiscoveredDevice(
      id: "local.|_airport._tcp.|time capsule",
      name: "time capsule",
      hostName: "time-capsule.local.",
      addresses: ["192.168.4.45"],
      identifiers: newIdentifiers
    )

    model.updateDiscoveredDevices([oldDevice])
    model.updateDiscoveredDevices([newDevice])

    XCTAssertEqual(model.visibleTopologyDevices.map(\.id), [newDevice.id])
    XCTAssertEqual(model.visibleTopologyDevices.map(\.displayName), ["time capsule"])
  }

  func testVisibleTopologyClearsStaleConnectedStableIdentityAfterHostChange() {
    let model = AirportAppModel()
    let oldDevice = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Old Capsule",
      name: "old capsule",
      hostName: "old-capsule.local.",
      identifiers: ["wama:00-1f-f3-c9-62-99"]
    )
    model.connection.host = "old-capsule.local"
    model.updateDiscoveredDevices([oldDevice])

    model.connection.host = "new-capsule.local"
    model.baseStation.name = "new capsule"
    model.baseStation.serialNumber = "NEW123"
    model.updateDiscoveredDevices([oldDevice])

    XCTAssertEqual(
      model.visibleTopologyDevices.map(\.id),
      ["local|_airport._tcp.|Old Capsule", "connected-new-capsule.local"])
    XCTAssertEqual(model.visibleTopologyDevices.map(\.displayName), ["old capsule", "new capsule"])
  }

  func testTopologyDisplayLogSnapshotIncludesDisplayedAndDiscoveredDeviceDetails() throws {
    let model = AirportAppModel()
    model.connection.host = "old-capsule.local"
    model.baseStation.name = "old capsule"
    model.baseStation.serialNumber = "C86TEST123"
    let device = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Old Capsule",
      name: "old capsule",
      hostName: "old-capsule.local.",
      addresses: ["fe80::1%en0", "192.168.4.45"],
      identifiers: ["wama:00-1f-f3-c9-62-99", "rama:00-21-e9-b9-2e-c3"]
    )
    model.updateDiscoveredDevices([device])
    model.selectTopologyDevice(device)

    let data = try XCTUnwrap(model.topologyDisplayLogSnapshot().data(using: .utf8))
    let root = try XCTUnwrap(
      JSONSerialization.jsonObject(with: data) as? [String: Any])
    let displayed = try XCTUnwrap(root["displayedTopologyDevices"] as? [[String: Any]])
    let discovered = try XCTUnwrap(root["rawDiscoveredDevices"] as? [[String: Any]])
    let displayedDevice = try XCTUnwrap(displayed.first)
    let discoveredDevice = try XCTUnwrap(discovered.first)

    XCTAssertEqual(displayedDevice["bonjourName"] as? String, "old capsule")
    XCTAssertEqual(displayedDevice["dnsName"] as? String, "old-capsule.local.")
    XCTAssertEqual(displayedDevice["ipAddresses"] as? [String], ["fe80::1%en0", "192.168.4.45"])
    XCTAssertEqual(
      displayedDevice["normalizedStableIdentifiers"] as? [String],
      ["wama:00-1f-f3-c9-62-99", "rama:00-21-e9-b9-2e-c3"])
    XCTAssertEqual(discoveredDevice["connectionHost"] as? String, "192.168.4.45")
  }

  func testBonjourStableIdentifiersComeFromAirportTXTRecord() {
    let identifiers = AirPortBonjourBrowser.stableIdentifiers(fromTXTRecord: [
      "waMA": Data("00-1F-F3-C9-62-99".utf8),
      "raMA": Data("00-21-E9-B9-2E-C3".utf8),
      "syVs": Data("7.8.1".utf8),
    ])

    XCTAssertEqual(
      identifiers,
      ["wama:00-1f-f3-c9-62-99", "rama:00-21-e9-b9-2e-c3"]
    )
  }

  func testBonjourTXTRecordDetectsResetSetupDevice() {
    let fields = AirPortBonjourBrowser.airportTXTFields(from: [
      "waMA": Data("00-1B-63-21-F5-8E".utf8),
      "raMA": Data("00-1B-63-21-F5-8F".utf8),
      "syDs": Data("Apple\\ Base\\ Station\\ V6.3".utf8),
      "syFl": Data("0x00000A40".utf8),
      "syAP": Data("102".utf8),
    ])
    let resetDevice = AirportDiscoveredDevice(
      id: "reset-express",
      name: "Base Station 21f58f",
      hostName: "Base-Station-21f58f.local.",
      txtFields: fields)
    let configuredDevice = AirportDiscoveredDevice(
      id: "configured-capsule",
      name: "time capsule",
      hostName: "time-capsule.local.",
      txtFields: ["syfl": "0xA0C", "syvs": "7.6.9", "srcv": "76900.11"])

    XCTAssertEqual(fields["syfl"], "0x00000A40")
    XCTAssertTrue(resetDevice.isNewAirPortDevice)
    XCTAssertFalse(configuredDevice.isNewAirPortDevice)

    let unresolvedDefaultNameDevice = AirportDiscoveredDevice(
      id: "unresolved-default-name",
      name: "Base Station 21f58f",
      hostName: "Base-Station-21f58f.local.")
    XCTAssertFalse(unresolvedDefaultNameDevice.isNewAirPortDevice)
  }

  func testBonjourStableIdentifiersParseCommaSeparatedAirportTXTRecord() {
    let firstIdentifiers = AirPortBonjourBrowser.stableIdentifiers(fromTXTRecord: [
      "waMA": Data(
        "00-1F-F3-C9-62-99,raMA=00-21-E9-B9-2E-C3,raCh=1,syVs=7.8.1,bjSd=12".utf8)
    ])
    let secondIdentifiers = AirPortBonjourBrowser.stableIdentifiers(fromTXTRecord: [
      "waMA": Data(
        "00-1F-F3-C9-62-99,raMA=00-21-E9-B9-2E-C3,raCh=1,syVs=7.8.1,bjSd=13".utf8)
    ])

    XCTAssertEqual(
      firstIdentifiers,
      ["wama:00-1f-f3-c9-62-99", "rama:00-21-e9-b9-2e-c3"]
    )
    XCTAssertEqual(secondIdentifiers, firstIdentifiers)
  }

  func testVisibleTopologyPreservesSelectedDuplicateWhenCurrentNameIsUnknown() {
    let model = AirportAppModel()
    let selectedDevice = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Selected Capsule",
      name: "selected capsule",
      hostName: "selected-capsule.local.",
      addresses: ["192.168.4.45"]
    )
    let duplicateDevice = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Duplicate Capsule",
      name: "duplicate capsule",
      hostName: "duplicate-capsule.local.",
      addresses: ["192.168.4.45"]
    )
    model.discoveredDevices = [selectedDevice, duplicateDevice]
    model.selectTopologyDevice(selectedDevice)

    XCTAssertEqual(model.visibleTopologyDevices.map(\.id), [selectedDevice.id])
  }

  func testManuallyConnectedDeviceAppearsInTopologyAfterDetailsLoad() {
    let model = AirportAppModel()
    model.connection.host = "192.168.4.45"

    XCTAssertTrue(model.visibleTopologyDevices.isEmpty)

    model.baseStation.name = "time capsule"
    model.baseStation.serialNumber = "C86TEST123"

    XCTAssertEqual(model.visibleTopologyDevices.map(\.connectionHost), ["192.168.4.45"])
    XCTAssertEqual(model.visibleTopologyDevices.first?.displayName, "time capsule")
  }

  func testDirectBaseStationNameOverridesStaleProfileNameAfterRefresh() {
    let model = AirportAppModel()
    model.baseStation.name = "stale profile name"

    model.applyAuthoritativeBaseStationIdentity(
      readName: "time capsule 4",
      serialNumber: "C86TEST123",
      version: "7.9.1"
    )

    XCTAssertEqual(model.baseStation.name, "time capsule 4")
    XCTAssertEqual(model.baseStation.serialNumber, "C86TEST123")
    XCTAssertEqual(model.baseStation.version, "7.9.1")
  }

  func testUnavailableIdentityReadDoesNotOverwriteExistingSerialOrVersion() {
    let model = AirportAppModel()
    model.baseStation.name = "time capsule"
    model.baseStation.serialNumber = "C86TEST123"
    model.baseStation.version = "7.9.1"

    model.applyAuthoritativeBaseStationIdentity(
      readName: "time capsule",
      serialNumber: "--",
      version: "4294967286"
    )

    XCTAssertEqual(model.baseStation.serialNumber, "C86TEST123")
    XCTAssertEqual(model.baseStation.version, "7.9.1")
  }

  func testValidIdentityReadPopulatesMissingSerialAndVersion() {
    let model = AirportAppModel()

    model.applyAuthoritativeBaseStationIdentity(
      readName: "time capsule",
      serialNumber: "6F8412DG32D",
      version: "7.8.1"
    )

    XCTAssertEqual(model.baseStation.serialNumber, "6F8412DG32D")
    XCTAssertEqual(model.baseStation.version, "7.8.1")
  }

  func testSelectedBonjourNameOverridesStaleProfileAndDirectNameAfterRefresh() {
    let model = AirportAppModel()
    let device = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|time capsule 4",
      name: "time capsule 4",
      hostName: "time-capsule.local."
    )
    model.discoveredDevices = [device]
    model.selectTopologyDevice(device)
    model.baseStation.name = "stale profile name"

    model.applyAuthoritativeBaseStationIdentity(
      readName: "time capsule",
      serialNumber: "C86TEST123",
      version: "7.9.1"
    )

    XCTAssertEqual(model.baseStation.name, "time capsule 4")
    XCTAssertEqual(model.baseStation.serialNumber, "C86TEST123")
    XCTAssertEqual(model.baseStation.version, "7.9.1")
  }

  func testStaleHostIdentityRefreshIsIgnored() {
    let model = AirportAppModel()
    model.connection.host = "new-time-capsule.local"
    model.baseStation.name = "new time capsule"
    model.baseStation.serialNumber = "NEW123"
    model.baseStation.version = "7.9.1"

    model.applyIdentityIfConnectionStillMatches(
      requestHost: "old-time-capsule.local",
      readName: "old time capsule",
      serialNumber: "OLD123",
      version: "7.8.1"
    )

    XCTAssertEqual(model.baseStation.name, "new time capsule")
    XCTAssertEqual(model.baseStation.serialNumber, "NEW123")
    XCTAssertEqual(model.baseStation.version, "7.9.1")
    XCTAssertTrue(model.logs.contains { $0.contains("stale host old-time-capsule.local") })
  }

  func testStaleHostIdentityRefreshFailureDoesNotLogBackendError() {
    let model = AirportAppModel()
    model.connection.host = "new-time-capsule.local"

    model.appendIdentityRefreshFailureIfConnectionStillMatches(
      requestHost: "old-time-capsule.local",
      errorDescription: "old backend failure"
    )

    XCTAssertFalse(model.logs.contains { $0.contains("old backend failure") })
    XCTAssertTrue(
      model.logs.contains {
        $0.contains("Ignored identity refresh failure for stale host old-time-capsule.local")
      })
  }

  func testCurrentHostIdentityRefreshFailureIsLoggedWithFriendlyMessage() {
    let model = AirportAppModel()
    model.connection.host = "time-capsule.local"

    model.appendIdentityRefreshFailureIfConnectionStillMatches(
      requestHost: "TIME-CAPSULE.LOCAL.",
      errorDescription: "backend identity failure"
    )

    XCTAssertEqual(model.logs.first, "Identity refresh failed: backend identity failure")
  }

  func testConnectionStillMatchesUsesCanonicalHost() {
    let model = AirportAppModel()
    model.connection.host = " time-capsule.local. "

    XCTAssertTrue(model.connectionStillMatches("TIME-CAPSULE.LOCAL"))
    XCTAssertFalse(model.connectionStillMatches("other-capsule.local"))
  }

  func testIdentityRefreshHostMatchUsesCanonicalHost() {
    let model = AirportAppModel()
    model.connection.host = " time-capsule.local. "

    model.applyIdentityIfConnectionStillMatches(
      requestHost: "TIME-CAPSULE.LOCAL",
      readName: "time capsule",
      serialNumber: "C86TEST123",
      version: "7.9.1"
    )

    XCTAssertEqual(model.baseStation.name, "time capsule")
    XCTAssertEqual(model.baseStation.serialNumber, "C86TEST123")
    XCTAssertEqual(model.baseStation.version, "7.9.1")
  }

  func testUpdateAppliesAllPendingPaneChanges() async throws {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let model = AirportAppModel()
    model.beginEditing()
    model.selectedPane = .disks
    model.internet.domainName = "example.test"
    model.network.routerMode = .dhcpAndNat

    model.applyPendingChanges()
    try await waitForIdle(model)

    XCTAssertFalse(model.hasPendingChanges)
    XCTAssertFalse(model.isEditingDevice)
    XCTAssertTrue(
      model.logs.contains { $0.contains("--domain-name") && $0.contains("example.test") })
    XCTAssertTrue(
      model.logs.contains { $0.contains("--router-mode") && $0.contains("dhcp-and-nat") })
  }

  func testUpdateClosesSheetAndShowsBaseStationUpdatingUntilApplyCompletes() async throws {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let model = AirportAppModel()
    let device = try XCTUnwrap(model.visibleTopologyDevices.first)
    model.selectTopologyDevice(device)
    model.beginEditing()
    model.internet.domainName = "example.test"

    model.applyPendingChanges()

    XCTAssertFalse(model.isEditingDevice)
    XCTAssertTrue(model.isTopologyDeviceUpdating(device))

    try await waitForIdle(model)

    XCTAssertFalse(model.isTopologyDeviceUpdating(device))
  }

  func testActiveRestartPreservesTowerExtremeIconAgainstPlausibleOlderProductRecord()
    throws
  {
    let model = AirportAppModel()
    model.connection.host = "192.168.4.20"
    let stableIdentifiers = [
      "wama:80-ea-96-e7-9e-e3",
      "rama:80-ea-96-ed-08-ad",
    ]
    let towerExtreme = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|airport-extreme",
      name: "airport extreme",
      hostName: "airport-extreme.local",
      addresses: ["192.168.4.20"],
      identifiers: stableIdentifiers,
      modelName: "AirPort Extreme",
      productID: "120")
    model.updateDiscoveredDevices([towerExtreme])
    model.selectTopologyDevice(towerExtreme)
    model.beginBaseStationUpdate(requestHost: "192.168.4.20")

    let transientOlderExtreme = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|airport-extreme-restarting",
      name: "airport extreme",
      hostName: "airport-extreme.local",
      addresses: ["192.168.4.20"],
      identifiers: stableIdentifiers,
      modelName: "AirPort Extreme",
      productID: "117")
    model.updateDiscoveredDevices([transientOlderExtreme])

    let updatingDevice = try XCTUnwrap(model.visibleTopologyDevices.first)
    XCTAssertTrue(model.isTopologyDeviceUpdating(updatingDevice))
    XCTAssertEqual(updatingDevice.productID, "120")
    XCTAssertEqual(updatingDevice.topologyImageName, "AirPort-8-3D-cropped~mac.tiff")

    model.clearBaseStationUpdate(requestHost: "192.168.4.20")
    model.updateDiscoveredDevices([towerExtreme])

    let recoveredDevice = try XCTUnwrap(model.visibleTopologyDevices.first)
    XCTAssertFalse(model.isTopologyDeviceUpdating(recoveredDevice))
    XCTAssertEqual(recoveredDevice.productID, "120")
    XCTAssertEqual(recoveredDevice.topologyImageName, "AirPort-8-3D-cropped~mac.tiff")
  }

  func testActiveRestartPreservesTowerExtremeIconWhenBonjourDeviceDisappears() throws {
    let model = AirportAppModel()
    model.connection.host = "192.168.4.20"
    model.applyAuthoritativeBaseStationIdentity(
      readName: "airport extreme",
      serialNumber: "C86TEST123",
      version: "7.9.1",
      productID: "120")
    let towerExtreme = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|airport-extreme",
      name: "airport extreme",
      hostName: "airport-extreme.local",
      addresses: ["192.168.4.20"],
      identifiers: [
        "wama:80-ea-96-e7-9e-e3",
        "rama:80-ea-96-ed-08-ad",
      ],
      modelName: "AirPort Extreme",
      productID: "120")
    model.updateDiscoveredDevices([towerExtreme])
    model.selectTopologyDevice(towerExtreme)
    model.beginBaseStationUpdate(requestHost: "192.168.4.20")

    model.updateDiscoveredDevices([])

    let connectedDevice = try XCTUnwrap(model.visibleTopologyDevices.first)
    XCTAssertEqual(connectedDevice.id, "connected-192.168.4.20")
    XCTAssertTrue(model.isTopologyDeviceUpdating(connectedDevice))
    XCTAssertEqual(connectedDevice.displayName, "airport extreme")
    XCTAssertEqual(connectedDevice.modelName, "AirPort Extreme")
    XCTAssertEqual(connectedDevice.productID, "120")
    XCTAssertEqual(connectedDevice.topologyImageName, "AirPort-8-3D-cropped~mac.tiff")
  }

  func testUpdatingTopologyDevicePreservesIconAndPlacementDuringRestartDiscoveryChurn()
    async throws
  {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("airport-updating-topology-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let writeScript = try backendScriptURL(in: temporaryDirectory)
    try """
    #!/bin/sh
    sleep 0.5
    echo "changed: Prof, raSt"
    """.write(to: writeScript, atomically: true, encoding: .utf8)
    let readScript = try backendScriptURL(in: temporaryDirectory)
    try """
    #!/bin/sh
    echo '{"errors":{},"settings":{"syNm":{"value":"extreme"},"sySN":{"value":"EXTREME"},"syVs":{"value":"7.9.1"},"syAP":{"value":"120"},"Prof":{"decoded":{"restoreProfile":{"waCV":"dhcp","syNm":"extreme","raNm":"extreme"}}},"MaSt":{"decoded":[]}}}'
    """.write(to: readScript, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: writeScript.path)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: readScript.path)

    let model = AirportAppModel()
    model.connection.repoPath = temporaryDirectory.path
    model.connection.host = "extreme.local"
    model.connection.password = "password"
    model.applyAuthoritativeBaseStationIdentity(
      readName: "extreme",
      serialNumber: "EXTREME",
      version: "7.9.1",
      productID: "120")
    let express = AirportDiscoveredDevice(
      id: "express",
      name: "airport express",
      hostName: "airport-express.local",
      modelName: "AirPort Express",
      productID: "115")
    let extreme = AirportDiscoveredDevice(
      id: "extreme",
      name: "extreme",
      hostName: "extreme.local",
      addresses: ["192.168.4.49"],
      identifiers: ["wama:00-11-22-33-44-55"],
      modelName: "AirPort Extreme",
      productID: "120")
    let capsule = AirportDiscoveredDevice(
      id: "capsule",
      name: "time capsule",
      hostName: "time-capsule.local",
      modelName: "AirPort Time Capsule",
      productID: "106")
    model.updateDiscoveredDevices([express, extreme, capsule])
    let originalIndex = try XCTUnwrap(
      model.visibleTopologyDevices.firstIndex { $0.id == extreme.id })
    model.selectTopologyDevice(extreme)
    model.wireless.mode = "off"
    model.markClean()
    model.beginEditing()
    model.wireless.mode = "create"
    model.wireless.networkName = "codex-extreme"

    model.applyPendingChanges()

    let degradedExtreme = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|extreme-restarting",
      name: "extreme",
      hostName: "extreme-restarting.local",
      txtFields: ["prob": "waCF"],
      modelName: "AirPort Base Station",
      productID: "0")
    model.updateDiscoveredDevices([
      express,
      capsule,
      degradedExtreme,
    ])

    let visible = model.visibleTopologyDevices
    let updating = try XCTUnwrap(visible.first { $0.displayName == "extreme" })
    XCTAssertEqual(visible.firstIndex { $0.id == updating.id }, originalIndex)
    XCTAssertEqual(updating.displayName, "extreme")
    XCTAssertEqual(updating.displayModelName, "AirPort Extreme")
    XCTAssertEqual(updating.topologyImageName, "AirPort-8-3D-cropped~mac.tiff")

    try await waitForIdle(model)

    XCTAssertFalse(model.visibleTopologyDevices.contains { model.isTopologyDeviceUpdating($0) })
    model.updateDiscoveredDevices([
      express,
      capsule,
      degradedExtreme,
    ])
    let postUpdateVisible = model.visibleTopologyDevices
    let postUpdateExtreme = try XCTUnwrap(
      postUpdateVisible.first { $0.displayName == "extreme" })
    XCTAssertEqual(
      postUpdateVisible.firstIndex { $0.id == postUpdateExtreme.id }, originalIndex)
    XCTAssertEqual(postUpdateExtreme.displayModelName, "AirPort Extreme")
    XCTAssertEqual(postUpdateExtreme.topologyImageName, "AirPort-8-3D-cropped~mac.tiff")

    let renamedGenericExtreme = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|airport-base-station",
      name: "AirPort Base Station",
      hostName: "extreme.local",
      addresses: ["192.168.4.49"],
      txtFields: ["prob": "waCF"],
      modelName: "AirPort Base Station",
      productID: "0")
    model.updateDiscoveredDevices([
      express,
      capsule,
      renamedGenericExtreme,
    ])
    let renamedVisible = model.visibleTopologyDevices
    let renamedExtreme = try XCTUnwrap(
      renamedVisible.first { $0.connectionHost == "192.168.4.49" })
    XCTAssertEqual(
      renamedVisible.firstIndex { $0.id == renamedExtreme.id }, originalIndex)
    XCTAssertEqual(renamedExtreme.displayModelName, "AirPort Extreme")
    XCTAssertEqual(renamedExtreme.topologyImageName, "AirPort-8-3D-cropped~mac.tiff")

    let unmatchableGenericExtreme = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|airport-base-station-2",
      name: "AirPort Base Station",
      hostName: "airport-base-station.local",
      txtFields: ["prob": "waCF"],
      modelName: "AirPort Base Station",
      productID: "0")
    model.updateDiscoveredDevices([
      express,
      capsule,
      unmatchableGenericExtreme,
    ])
    XCTAssertFalse(
      model.visibleTopologyDevices.contains {
        $0.id == unmatchableGenericExtreme.id
          || $0.displayModelName == "AirPort Base Station"
      })
  }

  func testTransientGenericRestartRecordIsHiddenAfterWirelessCreateToOffChange()
    async throws
  {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("airport-create-off-topology-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let writeScript = try backendScriptURL(in: temporaryDirectory)
    try """
    #!/bin/sh
    sleep 0.5
    echo "changed: Prof, raSt"
    """.write(to: writeScript, atomically: true, encoding: .utf8)
    let readScript = try backendScriptURL(in: temporaryDirectory)
    try """
    #!/bin/sh
    echo '{"errors":{},"settings":{"syNm":{"value":"extreme"},"sySN":{"value":"EXTREME"},"syVs":{"value":"7.9.1"},"syAP":{"value":"120"},"Prof":{"decoded":{"restoreProfile":{"waCV":"dhcp","syNm":"extreme","raSt":3,"raNm":"Off"}}},"MaSt":{"decoded":[]}}}'
    """.write(to: readScript, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: writeScript.path)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: readScript.path)

    let model = AirportAppModel()
    model.connection.repoPath = temporaryDirectory.path
    model.connection.host = "extreme.local"
    model.connection.password = "password"
    model.applyAuthoritativeBaseStationIdentity(
      readName: "extreme",
      serialNumber: "EXTREME",
      version: "7.9.1",
      productID: "120")
    let express = AirportDiscoveredDevice(
      id: "express",
      name: "airport express",
      hostName: "airport-express.local",
      modelName: "AirPort Express",
      productID: "115")
    let extreme = AirportDiscoveredDevice(
      id: "extreme",
      name: "extreme",
      hostName: "extreme.local",
      addresses: ["192.168.4.49"],
      identifiers: ["wama:00-11-22-33-44-55"],
      modelName: "AirPort Extreme",
      productID: "120")
    let capsule = AirportDiscoveredDevice(
      id: "capsule",
      name: "time capsule",
      hostName: "time-capsule.local",
      modelName: "AirPort Time Capsule",
      productID: "106")
    model.updateDiscoveredDevices([express, extreme, capsule])
    model.selectTopologyDevice(extreme)
    model.wireless.mode = "create"
    model.wireless.networkName = "codex-extreme"
    model.markClean()
    model.beginEditing()
    model.wireless.mode = "off"

    model.applyPendingChanges()

    let transientGenericExtreme = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|airport-base-station",
      name: "AirPort Base Station",
      hostName: "airport-base-station.local",
      txtFields: ["prob": "waCF"],
      modelName: "AirPort Base Station",
      productID: "0")
    model.updateDiscoveredDevices([
      express,
      capsule,
      transientGenericExtreme,
    ])

    XCTAssertFalse(
      model.visibleTopologyDevices.contains {
        $0.id == transientGenericExtreme.id
          || $0.displayModelName == "AirPort Base Station"
      })

    let recoveredExtreme = AirportDiscoveredDevice(
      id: "extreme-recovered",
      name: "extreme",
      hostName: "extreme.local",
      addresses: ["192.168.4.49"],
      identifiers: ["wama:00-11-22-33-44-55"],
      modelName: "AirPort Extreme",
      productID: "120")
    model.updateDiscoveredDevices([express, recoveredExtreme, capsule])

    let visible = model.visibleTopologyDevices
    let visibleExtreme = try XCTUnwrap(visible.first { $0.displayName == "extreme" })
    XCTAssertEqual(visibleExtreme.displayModelName, "AirPort Extreme")
    XCTAssertEqual(visibleExtreme.topologyImageName, "AirPort-8-3D-cropped~mac.tiff")
  }

  func testPostApplyStatusNameUsesLoadedProductID() {
    let model = AirportAppModel()

    XCTAssertEqual(model.postApplyDeviceNameForStatus, "base station")

    model.baseStation.productID = "115"
    XCTAssertEqual(model.postApplyDeviceNameForStatus, "AirPort Express")

    model.baseStation.productID = "106"
    XCTAssertEqual(model.postApplyDeviceNameForStatus, "Time Capsule")

    model.baseStation.productID = "117"
    XCTAssertEqual(model.postApplyDeviceNameForStatus, "AirPort Extreme")
  }

  func testUpdateAppliesAdminPasswordLast() async throws {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let model = AirportAppModel()
    model.beginEditing()
    model.baseStation.name = "time capsule 2"
    model.baseStation.newAdminPassword = "new-admin"
    model.baseStation.verifyAdminPassword = "new-admin"
    model.internet.domainName = "example.test"

    model.applyPendingChanges()
    try await waitForIdle(model)

    let commandLogs = model.logs.filter { $0.hasPrefix("$ ") }
    let chronologicalCommandLogs = commandLogs.reversed()

    XCTAssertTrue(commandLogs.contains { $0.contains("--setting syNm") })
    XCTAssertTrue(commandLogs.contains { $0.contains("--domain-name example.test") })
    XCTAssertTrue(
      chronologicalCommandLogs.last?.contains("--setting syPW") == true,
      commandLogs.joined(separator: "\n"))
    XCTAssertEqual(model.connection.password, "new-admin")
    XCTAssertFalse(model.hasPendingChanges)
  }

  func testUpdateSavesChangedAdminPasswordWhenRemembered() async throws {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let store = MemoryAirportPasswordStore()
    store.passwords["time-capsule.local"] = "old-admin"
    let model = AirportAppModel(passwordStore: store)
    model.connection.host = " Time-Capsule.LOCAL. "
    model.connection.password = "old-admin"
    model.rememberConnectionPassword = true
    model.beginEditing()
    model.baseStation.name = "time capsule 2"
    model.baseStation.newAdminPassword = "new-admin"
    model.baseStation.verifyAdminPassword = "new-admin"
    model.internet.domainName = "example.test"

    model.applyPendingChanges()
    try await waitForIdle(model)

    XCTAssertEqual(model.connection.host, "time-capsule.local")
    XCTAssertEqual(model.connection.password, "new-admin")
    XCTAssertEqual(store.passwords["time-capsule.local"], "new-admin")
    XCTAssertFalse(model.hasPendingChanges)
  }

  func testUpdateButtonStateTracksPendingChangesAndBusyState() {
    let model = AirportAppModel()
    model.baseStation.name = "time capsule"
    model.markClean()

    XCTAssertFalse(model.canApplyPendingChanges)

    model.internet.domainName = "example.test"

    XCTAssertTrue(model.canApplyPendingChanges)

    model.isBusy = true

    XCTAssertFalse(model.canApplyPendingChanges)
  }

  func testUpdateButtonIsDisabledOnFirmwarePaneEvenWithPendingChanges() {
    let model = AirportAppModel()
    model.baseStation.name = "time capsule"
    model.markClean()

    model.internet.domainName = "example.test"
    model.selectedPane = .firmware

    XCTAssertTrue(model.hasPendingChanges)
    XCTAssertFalse(model.canApplyPendingChanges)

    model.selectedPane = .internet

    XCTAssertTrue(model.canApplyPendingChanges)
  }

  func testUpdateButtonStateAllowsInvalidPendingChangesToSurface() {
    let model = AirportAppModel()
    model.baseStation.name = "time capsule"
    model.markClean()

    model.baseStation.name = " "

    XCTAssertTrue(model.canApplyPendingChanges)

    model.applyPendingChanges()

    XCTAssertEqual(model.status, "Base Station Name cannot be empty.")
    XCTAssertFalse(model.isBusy)
  }

  func testUpdateButtonWiresBaseStationNameTextFieldToPythonScript() async throws {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let model = AirportAppModel()
    model.beginEditing()
    model.baseStation.name = "Live Test Capsule"

    model.applyPendingChanges()
    try await waitForIdle(model)

    let command = try XCTUnwrap(onlyCommandLine(in: model))
    assertCommand(
      command,
      contains: [
        "./backend/airport_backend.py",
        "time-capsule.local",
        "--password <password>",
        "--setting syNm",
        "--value 'Live Test Capsule'",
      ])
    XCTAssertFalse(model.hasPendingChanges)
  }

  func testUpdateButtonWiresInternetDHCPFieldsAndOptionsToPythonScript() async throws {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let model = AirportAppModel()
    model.internet.connectUsing = .static
    model.internet.ipv4Address = "192.168.4.45"
    model.internet.subnetMask = "255.255.252.0"
    model.internet.routerAddress = "192.168.4.1"
    model.markClean()
    model.beginEditing()

    model.internet.connectUsing = .dhcp
    model.internet.dnsServers = "1.1.1.1, 8.8.8.8"
    model.internet.ipv6DNSServers = "2606:4700:4700::1111, 2001:4860:4860::8888"
    model.internet.domainName = "example.test"
    model.internet.configureIPv6 = "manual"
    model.internet.dynamicGlobalHostname = true
    model.internet.globalHostname = "capsule.example.test"
    model.internet.globalHostnameUser = "airport-live"
    model.internet.globalHostnamePassword = "hostname#543210"

    model.applyPendingChanges()
    try await waitForIdle(model)

    let command = try XCTUnwrap(onlyCommandLine(in: model))
    assertCommand(
      command,
      contains: [
        "./backend/airport_backend.py",
        "--connect-using dhcp",
        "--dns-server-1 1.1.1.1",
        "--dns-server-2 8.8.8.8",
        "--ipv6-dns-server 2606:4700:4700::1111",
        "--ipv6-dns-server 2001:4860:4860::8888",
        "--domain-name example.test",
        "--configure-ipv6 manual",
        "--dynamic-global-hostname",
        "--global-hostname capsule.example.test",
        "--global-hostname-user airport-live",
        "--global-hostname-password <password>",
      ])
    XCTAssertFalse(model.hasPendingChanges)
  }

  func testUpdateButtonWiresInternetConnectUsingDropdownOptionsToPythonScript() async throws {
    let cases: [(ConnectUsing, [String], (AirportAppModel) -> Void)] = [
      (
        .dhcp,
        ["--connect-using dhcp"],
        { model in
          model.internet.connectUsing = .static
          model.internet.ipv4Address = "192.168.4.45"
          model.internet.subnetMask = "255.255.252.0"
          model.internet.routerAddress = "192.168.4.1"
          model.markClean()
          model.internet.connectUsing = .dhcp
        }
      ),
      (
        .static,
        [
          "--connect-using static",
          "--ipv4-address 192.168.4.46",
        ],
        { model in
          model.internet.connectUsing = .static
          model.internet.ipv4Address = "192.168.4.46"
          model.internet.subnetMask = "255.255.252.0"
          model.internet.routerAddress = "192.168.4.1"
        }
      ),
      (
        .pppoe,
        [
          "--connect-using pppoe",
          "--pppoe-account live-test@example.com",
          "--pppoe-password <password>",
          "--pppoe-service airport-live",
        ],
        { model in
          model.internet.connectUsing = .pppoe
          model.internet.pppoeAccount = "live-test@example.com"
          model.internet.pppoePassword = "pppoe#543210"
          model.internet.pppoeService = "airport-live"
        }
      ),
    ]

    for (option, fragments, configure) in cases {
      setenv("AIRPORT_UTILITY_MOCK", "1", 1)
      defer { unsetenv("AIRPORT_UTILITY_MOCK") }
      let model = AirportAppModel()
      model.beginEditing()
      configure(model)

      model.applyPendingChanges()
      try await waitForIdle(model)

      let command = try XCTUnwrap(onlyCommandLine(in: model), "option: \(option.rawValue)")
      assertCommand(command, contains: fragments)
      XCTAssertFalse(model.hasPendingChanges, option.rawValue)
    }
  }

  func testUpdateButtonWiresInternetConfigureIPv6DropdownOptionsToPythonScript() async throws {
    for option in ["link-local", "automatic", "manual"] {
      setenv("AIRPORT_UTILITY_MOCK", "1", 1)
      defer { unsetenv("AIRPORT_UTILITY_MOCK") }

      let model = AirportAppModel()
      model.internet.configureIPv6 = option == "link-local" ? "manual" : "link-local"
      model.markClean()
      model.beginEditing()
      model.internet.configureIPv6 = option

      model.applyPendingChanges()
      try await waitForIdle(model)

      let command = try XCTUnwrap(onlyCommandLine(in: model))
      assertCommand(command, contains: ["--configure-ipv6 \(option)"])
      XCTAssertFalse(model.hasPendingChanges)
    }
  }

  func testUpdateButtonWiresPPPoEConnectionDropdownOptionsToPythonScript() async throws {
    for option in PPPoEConnectionOption.allCases.map(\.value) {
      setenv("AIRPORT_UTILITY_MOCK", "1", 1)
      defer { unsetenv("AIRPORT_UTILITY_MOCK") }

      let model = AirportAppModel()
      model.internet.connectUsing = .pppoe
      model.internet.pppoeAccount = "account@example.test"
      model.internet.pppoeConnection = option == "always-on" ? "manual" : "always-on"
      model.markClean()
      model.beginEditing()
      model.internet.pppoeConnection = option

      model.applyPendingChanges()
      try await waitForIdle(model)

      let command = try XCTUnwrap(onlyCommandLine(in: model), "PPPoE policy: \(option)")
      assertCommand(command, contains: ["--pppoe-connection \(option)"])
      XCTAssertFalse(model.hasPendingChanges, option)
    }
  }

  func testPPPoEConnectionMenuIncludesAllSupportedPolicies() {
    XCTAssertEqual(
      PPPoEConnectionOption.allCases.map(\.value),
      ["always-on", "automatic", "manual"])
  }

  func testUpdateButtonWiresDynamicGlobalHostnameDisableToPythonScript() async throws {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let model = AirportAppModel()
    model.internet.dynamicGlobalHostname = true
    model.internet.globalHostname = "capsule.example.test"
    model.internet.globalHostnameUser = "airport-live"
    model.internet.globalHostnamePassword = "hostname#543210"
    model.markClean()
    model.beginEditing()
    model.internet.dynamicGlobalHostname = false

    model.applyPendingChanges()
    try await waitForIdle(model)

    let command = try XCTUnwrap(onlyCommandLine(in: model))
    assertCommand(command, contains: ["--no-dynamic-global-hostname"])
    XCTAssertFalse(command.contains("--global-hostname "))
    XCTAssertFalse(model.hasPendingChanges)
  }

  func testRenewDHCPLeaseButtonRunsRefreshPath() async throws {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let model = AirportAppModel()
    model.logs = []

    model.renewDHCPLease()
    try await waitForIdle(model)

    XCTAssertTrue(model.logs.contains("Mock refresh completed."))
    XCTAssertEqual(model.status, "Connected to time-capsule.local. Mock mode.")
  }

  func testUpdateButtonWiresSecuredWirelessFieldsAndOptionsToPythonScript() async throws {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let model = AirportAppModel()
    model.beginEditing()
    model.wireless.mode = "create"
    model.wireless.networkName = "airport-live-test"
    model.wireless.security = "wpa2-personal"
    model.wireless.password = "airport#543210"
    model.wireless.verifyPassword = "airport#543210"
    model.wireless.regionCode = "0"
    model.wireless.hiddenNetwork = true
    model.wireless.radioMode = "80211n-bg"
    model.wireless.radioChannel = "automatic"

    model.applyPendingChanges()
    try await waitForIdle(model)

    let command = try XCTUnwrap(onlyCommandLine(in: model))
    assertCommand(
      command,
      contains: [
        "./backend/airport_backend.py",
        "--wireless-mode create",
        "--wireless-name airport-live-test",
        "--wireless-security wpa2-personal",
        "--wireless-password <password>",
        "--region-code 0",
        "--hidden-network",
        "--radio-mode 80211n-bg",
        "--radio-channel automatic",
      ])
    XCTAssertFalse(model.hasPendingChanges)
  }

  func testUpdateButtonWiresOpenWirelessSecurityToPythonScript() async throws {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let model = AirportAppModel()
    model.wireless.mode = "off"
    model.wireless.security = "wpa2-personal"
    model.markClean()
    model.beginEditing()
    model.wireless.mode = "create"
    model.wireless.networkName = "airport-live-open"
    model.wireless.security = "none"

    model.applyPendingChanges()
    try await waitForIdle(model)

    let command = try XCTUnwrap(onlyCommandLine(in: model))
    assertCommand(
      command,
      contains: [
        "--wireless-mode create",
        "--wireless-name airport-live-open",
        "--wireless-security none",
      ])
    XCTAssertFalse(command.contains("--wireless-password"))
    XCTAssertFalse(model.hasPendingChanges)
  }

  func testUpdateButtonWiresWirelessModeDropdownOptionsToPythonScript() async throws {
    let cases: [(String, [String], (AirportAppModel) -> Void)] = [
      (
        "create",
        [
          "--wireless-mode create",
          "--wireless-name airport-create",
        ],
        { model in
          model.wireless.mode = "create"
          model.wireless.networkName = "airport-create"
          model.wireless.security = "none"
        }
      ),
      (
        "extend",
        [
          "--wireless-mode extend",
          "--wireless-name upstream-network",
          "--wireless-security wpa2-personal",
          "--wireless-password <password>",
        ],
        { model in
          model.wireless.mode = "extend"
          model.wireless.networkName = "upstream-network"
          model.wireless.security = "wpa2-personal"
          model.wireless.password = "airport#543210"
          model.wireless.verifyPassword = "airport#543210"
        }
      ),
      (
        "off",
        ["--wireless-mode off"],
        { model in
          model.wireless.mode = "create"
          model.wireless.networkName = "airport-create"
          model.wireless.security = "none"
          model.markClean()
          model.wireless.mode = "off"
          model.wireless.networkName = "Off"
          model.wireless.security = "none"
        }
      ),
    ]

    for (mode, fragments, configure) in cases {
      setenv("AIRPORT_UTILITY_MOCK", "1", 1)
      defer { unsetenv("AIRPORT_UTILITY_MOCK") }
      let model = AirportAppModel()
      model.beginEditing()
      configure(model)

      model.applyPendingChanges()
      try await waitForIdle(model)

      let command = try XCTUnwrap(onlyCommandLine(in: model), "mode: \(mode)")
      assertCommand(command, contains: fragments)
      XCTAssertFalse(model.hasPendingChanges, mode)
    }
  }

  func testUpdateButtonWiresWirelessSecurityDropdownOptionsToPythonScript() async throws {
    let options = [
      ("none", "wpa2-personal", []),
      ("wep-128", "none", ["--wireless-password <password>"]),
      ("wpa-wpa2-personal", "none", ["--wireless-password <password>"]),
      ("wpa2-personal", "none", ["--wireless-password <password>"]),
      ("wpa-wpa2-enterprise", "none", ["--wireless-password <password>"]),
      ("wpa2-enterprise", "none", ["--wireless-password <password>"]),
    ]

    for (security, cleanSecurity, extraFragments) in options {
      setenv("AIRPORT_UTILITY_MOCK", "1", 1)
      defer { unsetenv("AIRPORT_UTILITY_MOCK") }
      let model = AirportAppModel()
      model.wireless.mode = "create"
      model.wireless.networkName = "airport-security"
      model.wireless.security = cleanSecurity
      model.wireless.password = cleanSecurity == "none" ? "" : "old#543210"
      model.wireless.verifyPassword = model.wireless.password
      model.markClean()
      model.beginEditing()
      model.wireless.security = security
      if security != "none" {
        model.wireless.password = "airport#543210"
        model.wireless.verifyPassword = "airport#543210"
      }

      model.applyPendingChanges()
      try await waitForIdle(model)

      let command = try XCTUnwrap(onlyCommandLine(in: model), "security: \(security)")
      assertCommand(command, contains: ["--wireless-security \(security)"] + extraFragments)
      if security == "none" {
        XCTAssertFalse(command.contains("--wireless-password"))
      }
      XCTAssertFalse(model.hasPendingChanges, security)
    }
  }

  func testUpdateButtonWiresWirelessOptionsDropdownsToPythonScript() async throws {
    let radioModes = WirelessRadioModeOption.allCases.map(\.value)
    for radioMode in radioModes {
      setenv("AIRPORT_UTILITY_MOCK", "1", 1)
      defer { unsetenv("AIRPORT_UTILITY_MOCK") }
      let model = AirportAppModel()
      model.wireless.mode = "create"
      model.wireless.networkName = "airport-radio"
      model.wireless.security = "none"
      model.wireless.radioMode = radioMode == "80211n-bg" ? "80211g" : "80211n-bg"
      model.markClean()
      model.beginEditing()
      model.wireless.radioMode = radioMode

      model.applyPendingChanges()
      try await waitForIdle(model)

      let command = try XCTUnwrap(onlyCommandLine(in: model), "radio mode: \(radioMode)")
      assertCommand(command, contains: ["--radio-mode \(radioMode)"])
      XCTAssertFalse(model.hasPendingChanges, radioMode)
    }

    for channel in ["automatic"] + (1...11).map(String.init) {
      setenv("AIRPORT_UTILITY_MOCK", "1", 1)
      defer { unsetenv("AIRPORT_UTILITY_MOCK") }
      let model = AirportAppModel()
      model.wireless.mode = "create"
      model.wireless.networkName = "airport-channel"
      model.wireless.security = "none"
      model.wireless.radioChannel = channel == "automatic" ? "11" : "automatic"
      model.markClean()
      model.beginEditing()
      model.wireless.radioChannel = channel

      model.applyPendingChanges()
      try await waitForIdle(model)

      let command = try XCTUnwrap(onlyCommandLine(in: model), "radio channel: \(channel)")
      assertCommand(command, contains: ["--radio-channel \(channel)"])
      XCTAssertFalse(model.hasPendingChanges, channel)
    }
  }

  func testWirelessOptionsRadioModeMenuIncludesAllSupportedModesAndPreservesUnknownCurrentMode() {
    XCTAssertEqual(
      WirelessRadioModeOption.allCases.map(\.value),
      [
        "80211b",
        "80211bg",
        "80211g",
        "80211a",
        "80211n-a",
        "80211n-bg",
        "80211n-only-24",
        "80211n-only-5",
      ])

    XCTAssertEqual(
      WirelessOptionsSheet.radioModeOptions(for: "80211bg").map(\.value),
      WirelessRadioModeOption.allCases.map(\.value))
    XCTAssertEqual(
      WirelessOptionsSheet.radioModeOptions(for: "80211future").map(\.value).first,
      "80211future")
  }

  func testUpdateButtonWiresHiddenNetworkToggleBothWaysToPythonScript() async throws {
    for hidden in [true, false] {
      setenv("AIRPORT_UTILITY_MOCK", "1", 1)
      defer { unsetenv("AIRPORT_UTILITY_MOCK") }
      let model = AirportAppModel()
      model.wireless.mode = "create"
      model.wireless.networkName = "airport-hidden"
      model.wireless.security = "none"
      model.wireless.hiddenNetwork = !hidden
      model.markClean()
      model.beginEditing()
      model.wireless.hiddenNetwork = hidden

      model.applyPendingChanges()
      try await waitForIdle(model)

      let command = try XCTUnwrap(onlyCommandLine(in: model), "hidden: \(hidden)")
      assertCommand(command, contains: [hidden ? "--hidden-network" : "--no-hidden-network"])
      XCTAssertFalse(model.hasPendingChanges, "\(hidden)")
    }
  }

  func testUpdateButtonWiresNetworkRouterModeDropdownOptionsToPythonScript() async throws {
    let cases: [(RouterMode, [String])] = [
      (.dhcpAndNat, ["--router-mode dhcp-and-nat"]),
      (.dhcpOnly, ["--router-mode dhcp-only"]),
      (.natOnly, ["--router-mode nat-only"]),
      (.bridge, ["--router-mode bridge"]),
    ]

    for (mode, fragments) in cases {
      setenv("AIRPORT_UTILITY_MOCK", "1", 1)
      defer { unsetenv("AIRPORT_UTILITY_MOCK") }
      let model = AirportAppModel()
      model.beginEditing()
      if mode == .bridge {
        model.network.routerMode = .dhcpAndNat
        model.network.dhcpRangeStart = "10.0.1.2"
        model.network.dhcpRangeEnd = "10.0.1.200"
        model.network.dhcpLease = "1"
        model.network.dhcpLeaseUnit = "days"
        model.markClean()
      }
      model.network.routerMode = mode

      model.applyPendingChanges()
      try await waitForIdle(model)

      let command = try XCTUnwrap(onlyCommandLine(in: model), "router mode: \(mode.rawValue)")
      assertCommand(command, contains: fragments)
      XCTAssertFalse(model.hasPendingChanges, mode.rawValue)
    }
  }

  func testUpdateButtonWiresNetworkOptionsDropdownsAndTogglesToPythonScript() async throws {
    for (leaseValue, leaseUnit) in [
      ("45", "seconds"), ("15", "minutes"), ("12", "hours"), ("1", "days"), ("1", "weeks"),
    ] {
      setenv("AIRPORT_UTILITY_MOCK", "1", 1)
      defer { unsetenv("AIRPORT_UTILITY_MOCK") }
      let model = AirportAppModel()
      model.network.routerMode = .dhcpAndNat
      model.network.dhcpRangeStart = "10.0.1.2"
      model.network.dhcpRangeEnd = "10.0.1.200"
      model.network.dhcpLease = leaseValue == "1" ? "2" : "1"
      model.network.dhcpLeaseUnit = leaseUnit == "days" ? "hours" : "days"
      model.markClean()
      model.beginEditing()
      model.network.dhcpLease = leaseValue
      model.network.dhcpLeaseUnit = leaseUnit

      model.applyPendingChanges()
      try await waitForIdle(model)

      let command = try XCTUnwrap(onlyCommandLine(in: model), "lease unit: \(leaseUnit)")
      assertCommand(
        command,
        contains: ["--dhcp-lease \(leaseValue)", "--dhcp-lease-unit \(leaseUnit)"])
      XCTAssertFalse(model.hasPendingChanges, leaseUnit)
    }

    for (prefix, start, end) in [
      ("10.0", "10.0.1.2", "10.0.1.200"),
      ("172.16", "172.16.1.2", "172.16.1.200"),
      ("192.168", "192.168.4.2", "192.168.4.200"),
    ] {
      setenv("AIRPORT_UTILITY_MOCK", "1", 1)
      defer { unsetenv("AIRPORT_UTILITY_MOCK") }
      let model = AirportAppModel()
      model.network.routerMode = .dhcpAndNat
      model.network.dhcpRangeStart = "10.0.2.2"
      model.network.dhcpRangeEnd = "10.0.2.200"
      model.network.dhcpLease = "1"
      model.network.dhcpLeaseUnit = "days"
      model.markClean()
      model.beginEditing()
      model.network.dhcpRangeStart = start
      model.network.dhcpRangeEnd = end

      model.applyPendingChanges()
      try await waitForIdle(model)

      let command = try XCTUnwrap(onlyCommandLine(in: model), "range prefix: \(prefix)")
      assertCommand(
        command,
        contains: ["--dhcp-range-start \(start)", "--dhcp-range-end \(end)"])
      XCTAssertFalse(model.hasPendingChanges, prefix)
    }

    for natPMP in [true, false] {
      setenv("AIRPORT_UTILITY_MOCK", "1", 1)
      defer { unsetenv("AIRPORT_UTILITY_MOCK") }
      let model = AirportAppModel()
      model.network.routerMode = .natOnly
      model.network.natPMP = !natPMP
      model.markClean()
      model.beginEditing()
      model.network.natPMP = natPMP

      model.applyPendingChanges()
      try await waitForIdle(model)

      let command = try XCTUnwrap(onlyCommandLine(in: model), "nat-pmp: \(natPMP)")
      assertCommand(command, contains: [natPMP ? "--nat-pmp" : "--no-nat-pmp"])
      XCTAssertFalse(model.hasPendingChanges, "\(natPMP)")
    }

    for defaultHost in ["10.0.1.253", ""] {
      setenv("AIRPORT_UTILITY_MOCK", "1", 1)
      defer { unsetenv("AIRPORT_UTILITY_MOCK") }
      let model = AirportAppModel()
      model.network.routerMode = .natOnly
      model.network.defaultHost = defaultHost.isEmpty ? "10.0.1.253" : ""
      model.markClean()
      model.beginEditing()
      model.network.defaultHost = defaultHost

      model.applyPendingChanges()
      try await waitForIdle(model)

      let command = try XCTUnwrap(onlyCommandLine(in: model), "default host: \(defaultHost)")
      assertCommand(
        command,
        contains: [defaultHost.isEmpty ? "--clear-default-host" : "--default-host \(defaultHost)"])
      XCTAssertFalse(model.hasPendingChanges, defaultHost)
    }
  }

  func testNetworkOptionsDHCPLeaseUnitMenuIncludesAllSupportedUnits() {
    XCTAssertEqual(
      DHCPLeaseUnitOption.allCases.map(\.value),
      ["seconds", "minutes", "hours", "days", "weeks"])
  }

  func testEraseDiskButtonsWireRunnableMethodsToPythonScript() async throws {
    for method in [EraseMethod.quick, .zero] {
      setenv("AIRPORT_UTILITY_MOCK", "1", 1)
      defer { unsetenv("AIRPORT_UTILITY_MOCK") }

      let model = AirportAppModel()

      model.applyErase(method: method)
      try await waitForIdle(model)

      let command = try XCTUnwrap(onlyCommandLine(in: model))
      assertCommand(
        command,
        contains: [
          "./backend/airport_backend.py",
          "--erase-disk",
          "--erase-method \(method.rawValue)",
          "--i-know-this-erases-the-disk",
        ])
    }
  }

  func testEraseDiskNameFieldWiresVolumeNameToPythonScript() async throws {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let model = AirportAppModel()

    model.applyErase(method: .quick, volumeName: " Live Test Disk ")
    try await waitForIdle(model)

    let command = try XCTUnwrap(onlyCommandLine(in: model))
    assertCommand(
      command,
      contains: [
        "--erase-disk",
        "--erase-method quick",
        "--volume-name 'Live Test Disk'",
        "--i-know-this-erases-the-disk",
      ])
  }

  func testLongEraseDiskButtonsAreSkippedWithoutExplicitOptIn() async throws {
    guard ProcessInfo.processInfo.environment["RUN_LONG_DESTRUCTIVE_DISK_TESTS"] == "1" else {
      throw XCTSkip("Set RUN_LONG_DESTRUCTIVE_DISK_TESTS=1 to assert long erase command paths.")
    }

    for method in [EraseMethod.sevenPass, .thirtyFivePass] {
      setenv("AIRPORT_UTILITY_MOCK", "1", 1)
      defer { unsetenv("AIRPORT_UTILITY_MOCK") }
      let model = AirportAppModel()

      model.applyErase(method: method, volumeName: "Long Erase Test Disk")
      try await waitForIdle(model)

      let command = try XCTUnwrap(onlyCommandLine(in: model), "method: \(method.rawValue)")
      assertCommand(
        command,
        contains: [
          "--erase-disk",
          "--erase-method \(method.rawValue)",
          "--volume-name 'Long Erase Test Disk'",
          "--i-know-this-erases-the-disk",
        ])
    }
  }

  func testArchiveDiskButtonWiresRunnablePathToPythonScript() async throws {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let model = AirportAppModel()

    model.applyArchive(name: "")
    try await waitForIdle(model)

    let command = try XCTUnwrap(onlyCommandLine(in: model))
    assertCommand(
      command,
      contains: [
        "./backend/airport_backend.py",
        "--archive-disk",
        "--i-know-this-starts-the-archive",
      ])
    XCTAssertFalse(command.contains("--archive-name"))
  }

  func testUpdateButtonWiresDiskFileSharingToggleBothWaysToPythonScript() async throws {
    for enabled in [true, false] {
      setenv("AIRPORT_UTILITY_MOCK", "1", 1)
      defer { unsetenv("AIRPORT_UTILITY_MOCK") }
      let model = AirportAppModel()
      model.disks.fileSharing = !enabled
      model.markClean()
      model.beginEditing()
      model.disks.fileSharing = enabled

      model.applyPendingChanges()
      try await waitForIdle(model)

      let command = try XCTUnwrap(onlyCommandLine(in: model), "file sharing: \(enabled)")
      assertCommand(
        command,
        contains: [enabled ? "--usb-file-sharing-flags 1104" : "--usb-file-sharing-flags 1044"])
      XCTAssertFalse(model.hasPendingChanges, "\(enabled)")
    }
  }

  func testUpdateButtonWiresDiskSecurityDropdownOptionsToPythonScript() async throws {
    let cases: [(String, [String], (AirportAppModel) -> Void)] = [
      (
        "accounts",
        ["--usb-file-sharing-flags 1040"],
        { model in
          model.disks.secureSharedDisks = "accounts"
        }
      ),
      (
        "disk-password",
        ["--disk-security disk-password", "--disk-password <password>"],
        { model in
          model.disks.secureSharedDisks = "disk-password"
          model.disks.diskPassword = "disk#543210"
          model.disks.verifyDiskPassword = "disk#543210"
        }
      ),
      (
        "device-password",
        ["--disk-security device-password"],
        { model in
          model.disks.secureSharedDisks = "accounts"
          model.markClean()
          model.disks.secureSharedDisks = "device-password"
        }
      ),
    ]

    for (security, fragments, configure) in cases {
      setenv("AIRPORT_UTILITY_MOCK", "1", 1)
      defer { unsetenv("AIRPORT_UTILITY_MOCK") }
      let model = AirportAppModel()
      model.beginEditing()
      configure(model)

      model.applyPendingChanges()
      try await waitForIdle(model)

      let command = try XCTUnwrap(onlyCommandLine(in: model), "disk security: \(security)")
      assertCommand(command, contains: fragments)
      XCTAssertFalse(model.hasPendingChanges, security)
    }
  }

  func testSharedCancelRestoresAllPaneEditsAndExitsEditing() {
    let model = AirportAppModel()
    model.baseStation.name = "time capsule"
    model.internet.domainName = "clean.test"
    model.wireless.mode = "create"
    model.wireless.networkName = "Clean Network"
    model.network.routerMode = .bridge
    model.disks.fileSharing = false
    model.markClean()
    model.beginEditing()
    model.selectedPane = .disks
    model.baseStation.name = "changed capsule"
    model.internet.domainName = "dirty.test"
    model.wireless.networkName = "Dirty Network"
    model.network.routerMode = .dhcpAndNat
    model.disks.fileSharing = true

    model.cancelEditing()

    XCTAssertFalse(model.isEditingDevice)
    XCTAssertEqual(model.selectedPane, .baseStation)
    XCTAssertEqual(model.baseStation.name, "time capsule")
    XCTAssertEqual(model.internet.domainName, "clean.test")
    XCTAssertEqual(model.wireless.networkName, "Clean Network")
    XCTAssertEqual(model.network.routerMode, .bridge)
    XCTAssertFalse(model.disks.fileSharing)
    XCTAssertFalse(model.hasPendingChanges)
  }

  func testBaseStationCommandsIncludePasswordOnlyWhenProvided() {
    let model = AirportAppModel()
    model.baseStation.name = "time capsule"

    var commands = model.baseStationCommands(dryRun: true)
    XCTAssertEqual(commands?.count, 1)
    XCTAssertTrue(commands?.first?.1.contains("syNm") == true)
    XCTAssertTrue(commands?.first?.1.contains("--dry-run") == true)

    model.baseStation.newAdminPassword = "new-secret"
    model.baseStation.verifyAdminPassword = "new-secret"
    commands = model.baseStationCommands(dryRun: false)

    XCTAssertEqual(commands?.count, 2)
    XCTAssertTrue(commands?[0].1.contains("syNm") == true)
    XCTAssertTrue(commands?[1].1.contains("syPW") == true)
    XCTAssertFalse(commands?[1].1.contains("--dry-run") == true)
  }

  func testDirectBaseStationNameApplyTrimsOutgoingValue() async throws {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let model = AirportAppModel()
    model.baseStation.name = " time capsule 2 "

    model.applyBaseStationName()
    try await waitForIdle(model)

    XCTAssertTrue(model.logs.contains { $0.contains("--value 'time capsule 2'") })
    XCTAssertFalse(model.logs.contains { $0.contains("--value ' time capsule 2 '") })
  }

  func testDirectAdminPasswordApplyUpdatesConnectionPassword() async throws {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let model = AirportAppModel()
    model.connection.password = "old-admin"
    model.baseStation.newAdminPassword = " new-admin "
    model.baseStation.verifyAdminPassword = "new-admin"

    model.applyAdminPassword()
    try await waitForIdle(model)

    XCTAssertEqual(model.connection.password, "new-admin")
    XCTAssertEqual(model.baseStation.newAdminPassword, "")
    XCTAssertEqual(model.baseStation.verifyAdminPassword, "")
    XCTAssertFalse(model.hasPendingChanges)
  }

  func testDirectAdminPasswordApplyPreservesNewPasswordEditMadeWhileRunning() async throws {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let model = AirportAppModel()
    model.connection.password = "old-admin"
    model.baseStation.newAdminPassword = "applied-admin"
    model.baseStation.verifyAdminPassword = "applied-admin"

    model.applyAdminPassword()
    model.baseStation.newAdminPassword = "later-admin"
    model.baseStation.verifyAdminPassword = "later-admin"
    try await waitForIdle(model)

    XCTAssertEqual(model.connection.password, "applied-admin")
    XCTAssertEqual(model.baseStation.newAdminPassword, "later-admin")
    XCTAssertEqual(model.baseStation.verifyAdminPassword, "later-admin")
    XCTAssertTrue(model.hasPendingChanges)
    XCTAssertTrue(
      model.baseStationCommands(dryRun: false, changesOnly: true)?.first?.1.contains("syPW")
        == true)
  }

  func testDirectAdminPasswordApplyUpdatesSavedConnectionPasswordWhenRemembered() async throws {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let store = MemoryAirportPasswordStore()
    store.passwords["time-capsule.local"] = "old-admin"
    let model = AirportAppModel(passwordStore: store)
    model.connection.host = " Time-Capsule.LOCAL. "
    model.connection.password = "old-admin"
    model.rememberConnectionPassword = true
    model.baseStation.newAdminPassword = " new-admin "
    model.baseStation.verifyAdminPassword = "new-admin"

    model.applyAdminPassword()
    try await waitForIdle(model)

    XCTAssertEqual(model.connection.host, "time-capsule.local")
    XCTAssertEqual(model.connection.password, "new-admin")
    XCTAssertEqual(store.passwords["time-capsule.local"], "new-admin")
  }

  func testDirectAdminPasswordApplyDoesNotSaveConnectionPasswordWhenNotRemembered() async throws {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let store = MemoryAirportPasswordStore()
    store.passwords["time-capsule.local"] = "old-admin"
    let model = AirportAppModel(passwordStore: store)
    model.connection.host = "time-capsule.local"
    model.connection.password = "old-admin"
    model.rememberConnectionPassword = false
    model.baseStation.newAdminPassword = "new-admin"
    model.baseStation.verifyAdminPassword = "new-admin"

    model.applyAdminPassword()
    try await waitForIdle(model)

    XCTAssertEqual(model.connection.password, "new-admin")
    XCTAssertEqual(store.passwords["time-capsule.local"], "old-admin")
  }

  func testBaseStationPaneApplySavesChangedAdminPasswordWhenRemembered() async throws {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let store = MemoryAirportPasswordStore()
    store.passwords["time-capsule.local"] = "old-admin"
    let model = AirportAppModel(passwordStore: store)
    model.connection.host = " Time-Capsule.LOCAL. "
    model.connection.password = "old-admin"
    model.rememberConnectionPassword = true
    model.baseStation.name = "time capsule 2"
    model.baseStation.newAdminPassword = "new-admin"
    model.baseStation.verifyAdminPassword = "new-admin"

    model.applyBaseStation()
    try await waitForIdle(model)

    XCTAssertEqual(model.connection.host, "time-capsule.local")
    XCTAssertEqual(model.connection.password, "new-admin")
    XCTAssertEqual(store.passwords["time-capsule.local"], "new-admin")
    XCTAssertFalse(model.hasPendingChanges)
  }

  func testDirectPaneApplyPreservesUnappliedPendingChanges() async throws {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let model = AirportAppModel()
    model.internet.domainName = "example.test"
    model.wireless.mode = "create"
    model.wireless.networkName = "Pending Network"

    model.applyInternet()
    try await waitForIdle(model)

    XCTAssertTrue(
      model.logs.contains { $0.contains("--domain-name") && $0.contains("example.test") })
    XCTAssertTrue(model.hasPendingChanges)
    XCTAssertEqual(
      model.wirelessFlags(changesOnly: true)?.map(\.0),
      ["--wireless-mode", "--wireless-name"])
    XCTAssertEqual(model.internetFlags(changesOnly: true)?.count, 0)
  }

  func testDirectPaneApplyPreservesEditsMadeWhileApplyIsRunning() async throws {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let model = AirportAppModel()
    model.internet.domainName = "applied.test"

    model.applyInternet()
    model.internet.domainName = "later.test"
    try await waitForIdle(model)

    XCTAssertTrue(model.logs.contains { $0.contains("--domain-name applied.test") })
    XCTAssertTrue(model.hasPendingChanges)
    XCTAssertTrue(
      model.internetFlags(changesOnly: true)?.contains { $0 == ("--domain-name", "later.test") }
        == true)
  }

  func testUpdatePreservesEditsMadeWhileApplyIsRunning() async throws {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let model = AirportAppModel()
    model.internet.domainName = "applied.test"

    model.applyPendingChanges()
    model.internet.domainName = "later.test"
    try await waitForIdle(model)

    XCTAssertTrue(model.logs.contains { $0.contains("--domain-name applied.test") })
    XCTAssertTrue(model.hasPendingChanges)
    XCTAssertTrue(
      model.internetFlags(changesOnly: true)?.contains { $0 == ("--domain-name", "later.test") }
        == true)
  }

  func testUpdatePreservesAdminPasswordEditMadeWhileApplyIsRunning() async throws {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let model = AirportAppModel()
    model.baseStation.newAdminPassword = "applied-admin"
    model.baseStation.verifyAdminPassword = "applied-admin"
    model.internet.domainName = "example.test"

    model.applyPendingChanges()
    model.baseStation.newAdminPassword = "later-admin"
    model.baseStation.verifyAdminPassword = "later-admin"
    try await waitForIdle(model)

    XCTAssertEqual(model.connection.password, "applied-admin")
    XCTAssertEqual(model.baseStation.newAdminPassword, "later-admin")
    XCTAssertEqual(model.baseStation.verifyAdminPassword, "later-admin")
    XCTAssertTrue(model.hasPendingChanges)
    XCTAssertEqual(model.internetFlags(changesOnly: true)?.count, 0)
    XCTAssertTrue(
      model.baseStationCommands(dryRun: false, changesOnly: true)?.first?.1.contains("syPW")
        == true)
  }

  func testBaseStationNameApplyPreservesPendingAdminPasswordChange() async throws {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let model = AirportAppModel()
    model.baseStation.name = "time capsule 2"
    model.baseStation.newAdminPassword = "new-admin"
    model.baseStation.verifyAdminPassword = "new-admin"

    model.applyBaseStationName()
    try await waitForIdle(model)

    XCTAssertTrue(model.hasPendingChanges)
    XCTAssertEqual(model.baseStationCommands(dryRun: false, changesOnly: true)?.count, 1)
    XCTAssertTrue(
      model.baseStationCommands(dryRun: false, changesOnly: true)?.first?.1.contains("syPW")
        == true)
  }

  func testDiskOperationDoesNotClearPendingSettingsChanges() async throws {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let model = AirportAppModel()
    model.internet.domainName = "example.test"

    model.applyErase(method: .quick)
    try await waitForIdle(model)

    XCTAssertTrue(model.logs.contains { $0.contains("--erase-disk") })
    XCTAssertTrue(model.hasPendingChanges)
    XCTAssertEqual(model.internetFlags(changesOnly: true)?.map(\.0), ["--domain-name"])
  }

  func testEraseDiskInvalidatesLoadedDiskInventory() async throws {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let model = AirportAppModel()
    XCTAssertTrue(model.disks.didLoadInventory)
    XCTAssertFalse(model.disks.inventory.isEmpty)

    model.applyErase(method: .quick)
    try await waitForIdle(model)

    XCTAssertEqual(model.disks.rawInventory, "")
    XCTAssertEqual(model.disks.inventory, [])
    XCTAssertFalse(model.disks.didLoadInventory)
  }

  func testArchiveDiskInvalidatesLoadedDiskInventory() async throws {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let model = AirportAppModel()
    XCTAssertTrue(model.disks.didLoadInventory)
    XCTAssertFalse(model.disks.inventory.isEmpty)

    model.applyArchive(name: "")
    try await waitForIdle(model)

    XCTAssertEqual(model.disks.rawInventory, "")
    XCTAssertEqual(model.disks.inventory, [])
    XCTAssertFalse(model.disks.didLoadInventory)
  }

  func testArchiveDiskReportsCompletionInMockMode() async throws {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let model = AirportAppModel()

    model.applyArchive(name: "")
    try await waitForIdle(model)
    XCTAssertTrue(
      [
        "Archive Disk started. Waiting for archive to complete.",
        "Archive Disk complete.",
      ].contains(model.status))

    try await waitForStatus(model, "Archive Disk complete.")

    XCTAssertTrue(model.logs.contains("Archive Disk complete."))
    XCTAssertTrue(model.disks.didLoadInventory)
    XCTAssertTrue(model.disks.inventory.contains { !$0.builtIn })
  }

  func testArchiveStatusReaderDetectsArcIProblemCode() throws {
    let inProgressReader = try reader(
      """
      {
        "settings": {
          "sySt": {
            "decoded": {
              "problems": ["ArcI"]
            }
          }
        }
      }
      """)
    let completeReader = try reader(
      """
      {
        "settings": {
          "sySt": {
            "decoded": {
              "problems": []
            }
          }
        }
      }
      """)

    XCTAssertTrue(AirportAppModel.archiveIsInProgress(reader: inProgressReader))
    XCTAssertFalse(AirportAppModel.archiveIsInProgress(reader: completeReader))
  }

  func testExportConfigurationWritesImportableSnapshot() throws {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let model = AirportAppModel()
    model.baseStation.name = "capsule/export:test"
    model.internet.domainName = "example.test"
    model.wireless.mode = "create"
    model.wireless.networkName = "Imported Network"

    let url = temporaryConfigurationURL()
    defer { try? FileManager.default.removeItem(at: url) }

    try model.exportConfiguration(to: url)

    let data = try Data(contentsOf: url)
    let text = String(data: data, encoding: .utf8) ?? ""
    XCTAssertTrue(text.contains("\"format\" : \"AirPortUtility.Configuration\""))
    XCTAssertEqual(model.status, "Exported configuration to \(url.lastPathComponent).")

    let imported = AirportAppModel()
    imported.baseStation.name = "different"
    imported.isShowingPasswords = true
    imported.isShowingPreferences = true
    imported.isShowingConfigureOther = true
    try imported.importConfiguration(from: url)

    XCTAssertTrue(imported.isEditingDevice)
    XCTAssertFalse(imported.isShowingPasswords)
    XCTAssertFalse(imported.isShowingPreferences)
    XCTAssertFalse(imported.isShowingConfigureOther)
    XCTAssertEqual(imported.selectedPane, .baseStation)
    XCTAssertEqual(imported.baseStation.name, "capsule/export:test")
    XCTAssertEqual(imported.internet.domainName, "example.test")
    XCTAssertEqual(imported.wireless.mode, "create")
    XCTAssertEqual(imported.wireless.networkName, "Imported Network")
    XCTAssertTrue(imported.hasPendingChanges)
  }

  func testImportConfigurationRecomputesVisiblePanesFromImportedProductID() throws {
    let source = AirportAppModel()
    source.applyAuthoritativeBaseStationIdentity(
      readName: "Studio Express",
      serialNumber: "EXPRESS",
      version: "7.8.1",
      productID: "115")

    let url = temporaryConfigurationURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try source.exportConfiguration(to: url)

    let imported = AirportAppModel()
    XCTAssertFalse(imported.visiblePanes.contains(.airPlay))

    try imported.importConfiguration(from: url)

    XCTAssertTrue(imported.visiblePanes.contains(.airPlay))
    XCTAssertFalse(imported.visiblePanes.contains(.disks))
    XCTAssertTrue(imported.visiblePanes.contains(.firmware))
  }

  func testCancelImportRestoresPreviousDeviceCapabilities() throws {
    let model = AirportAppModel()
    model.applyAuthoritativeBaseStationIdentity(
      readName: "Studio Capsule",
      serialNumber: "CAPSULE",
      version: "7.8.1",
      productID: "106")
    model.markClean()
    XCTAssertFalse(model.visiblePanes.contains(.airPlay))
    XCTAssertTrue(model.visiblePanes.contains(.disks))
    XCTAssertEqual(model.firmware.productID, "106")

    let source = AirportAppModel()
    source.applyAuthoritativeBaseStationIdentity(
      readName: "Studio Express",
      serialNumber: "EXPRESS",
      version: "7.8.1",
      productID: "115")
    let url = temporaryConfigurationURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try source.exportConfiguration(to: url)

    try model.importConfiguration(from: url)
    XCTAssertTrue(model.visiblePanes.contains(.airPlay))
    XCTAssertFalse(model.visiblePanes.contains(.disks))
    XCTAssertEqual(model.firmware.productID, "115")

    model.cancelEditing()

    XCTAssertFalse(model.visiblePanes.contains(.airPlay))
    XCTAssertTrue(model.visiblePanes.contains(.disks))
    XCTAssertEqual(model.firmware.productID, "106")
  }

  func testBaseConfigurationExportOmitsUnsupportedInternetFeatureKeys() throws {
    let model = AirportAppModel()
    model.applyAuthoritativeBaseStationIdentity(
      readName: "Legacy Express",
      serialNumber: "EXPRESS",
      version: "6.3",
      productID: "102",
      supportsIPv6: false,
      supportsDynamicGlobalHostname: false)
    model.internet.configureIPv6 = "manual"
    model.internet.ipv6DNSServers = "2001:db8::1"
    model.internet.ipv6Address = "2001:db8::2"
    model.internet.dynamicGlobalHostname = true
    model.internet.globalHostname = "legacy.example.test"

    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("baseconfig")
    defer { try? FileManager.default.removeItem(at: url) }

    try model.exportConfiguration(to: url)

    let plist = try XCTUnwrap(
      PropertyListSerialization.propertyList(
        from: Data(contentsOf: url), options: [], format: nil) as? [String: Any])
    XCTAssertNil(plist["6cfg"])
    XCTAssertNil(plist["6aut"])
    XCTAssertNil(plist["6NS1"])
    XCTAssertNil(plist["6Wad"])
    XCTAssertNil(plist["wbEn"])
    XCTAssertNil(plist["wbHN"])
  }

  func testImportedIPv6OnlyConfigurationDoesNotEnableDynamicHostnameExport() throws {
    let source = AirportAppModel()
    source.baseStation.productID = "106"
    source.internet.configureIPv6 = "manual"
    source.internet.ipv6DNSServers = "2001:db8::1"

    let jsonURL = temporaryConfigurationURL()
    defer { try? FileManager.default.removeItem(at: jsonURL) }
    try source.exportConfiguration(to: jsonURL)

    let imported = AirportAppModel()
    try imported.importConfiguration(from: jsonURL)

    XCTAssertTrue(imported.showsIPv6InternetControls)
    XCTAssertFalse(imported.showsDynamicGlobalHostnameControls)

    let baseConfigURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("baseconfig")
    defer { try? FileManager.default.removeItem(at: baseConfigURL) }
    try imported.exportConfiguration(to: baseConfigURL)

    let plist = try XCTUnwrap(
      PropertyListSerialization.propertyList(
        from: Data(contentsOf: baseConfigURL), options: [], format: nil) as? [String: Any])
    XCTAssertEqual(plist["6cfg"] as? Int, 1)
    XCTAssertEqual(plist["6NS1"] as? String, "2001:db8::1")
    XCTAssertNil(plist["wbEn"])
    XCTAssertNil(plist["wbHN"])
  }

  func testImportedDynamicHostnameOnlyConfigurationDoesNotEnableIPv6Export() throws {
    let source = AirportAppModel()
    source.baseStation.productID = "106"
    source.internet.dynamicGlobalHostname = true
    source.internet.globalHostname = "capsule.example.test"

    let jsonURL = temporaryConfigurationURL()
    defer { try? FileManager.default.removeItem(at: jsonURL) }
    try source.exportConfiguration(to: jsonURL)

    let imported = AirportAppModel()
    try imported.importConfiguration(from: jsonURL)

    XCTAssertFalse(imported.showsIPv6InternetControls)
    XCTAssertTrue(imported.showsDynamicGlobalHostnameControls)

    let baseConfigURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("baseconfig")
    defer { try? FileManager.default.removeItem(at: baseConfigURL) }
    try imported.exportConfiguration(to: baseConfigURL)

    let plist = try XCTUnwrap(
      PropertyListSerialization.propertyList(
        from: Data(contentsOf: baseConfigURL), options: [], format: nil) as? [String: Any])
    XCTAssertNil(plist["6cfg"])
    XCTAssertNil(plist["6NS1"])
    XCTAssertEqual(plist["wbEn"] as? Bool, true)
    XCTAssertEqual(plist["wbHN"] as? String, "capsule.example.test")
  }

  func testImportConfigurationAcceptsDecodedProfileJSON() throws {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let url = temporaryConfigurationURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let profileJSON = """
      {
        "decoded": {
          "syNm": "Profile Capsule",
          "waCV": 33536,
          "raNm": "Profile Network",
          "bsNM": 0,
          "bsRM": 3
        }
      }
      """
    try Data(profileJSON.utf8).write(to: url)

    let model = AirportAppModel()
    try model.importConfiguration(from: url)

    XCTAssertTrue(model.isEditingDevice)
    XCTAssertEqual(model.baseStation.name, "Profile Capsule")
    XCTAssertEqual(model.internet.connectUsing, .dhcp)
    XCTAssertEqual(model.wireless.mode, "create")
    XCTAssertEqual(model.wireless.networkName, "Profile Network")
  }

  func testStaleAdminPasswordApplyDoesNotUpdateCurrentConnection() async throws {
    let savedMockMode = getenv("AIRPORT_UTILITY_MOCK").map { String(cString: $0) }
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer {
      if let savedMockMode {
        setenv("AIRPORT_UTILITY_MOCK", savedMockMode, 1)
      } else {
        unsetenv("AIRPORT_UTILITY_MOCK")
      }
    }

    let model = AirportAppModel()
    model.baseStation.newAdminPassword = "new-admin"
    model.baseStation.verifyAdminPassword = "new-admin"

    model.applyAdminPassword()
    model.connection.host = "other-capsule.local"
    try await waitForIdle(model)

    XCTAssertEqual(model.connection.password, "mock-password")
    XCTAssertEqual(model.baseStation.newAdminPassword, "new-admin")
    XCTAssertTrue(model.logs.contains { $0.contains("stale host time-capsule.local") })
    XCTAssertFalse(model.logs.contains { $0.contains("$ ./backend/airport_backend.py") })
  }

  func testStaleDryRunDoesNotReplacePreview() async throws {
    let savedMockMode = getenv("AIRPORT_UTILITY_MOCK").map { String(cString: $0) }
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer {
      if let savedMockMode {
        setenv("AIRPORT_UTILITY_MOCK", savedMockMode, 1)
      } else {
        unsetenv("AIRPORT_UTILITY_MOCK")
      }
    }

    let model = AirportAppModel()
    model.preview = CommandPreview(
      title: "Existing",
      arguments: [],
      redactedArguments: [],
      output: "keep"
    )
    model.baseStation.name = "new name"

    model.previewBaseStationName()
    model.connection.host = "other-capsule.local"
    try await waitForIdle(model)

    XCTAssertEqual(model.preview?.title, "Existing")
    XCTAssertTrue(model.logs.contains { $0.contains("stale host time-capsule.local") })
  }

  func testStaleDryRunSequenceDoesNotLogCommandOutput() async throws {
    let savedMockMode = getenv("AIRPORT_UTILITY_MOCK").map { String(cString: $0) }
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer {
      if let savedMockMode {
        setenv("AIRPORT_UTILITY_MOCK", savedMockMode, 1)
      } else {
        unsetenv("AIRPORT_UTILITY_MOCK")
      }
    }

    let model = AirportAppModel()
    model.baseStation.name = "new name"
    model.baseStation.newAdminPassword = "new-admin"
    model.baseStation.verifyAdminPassword = "new-admin"

    model.previewBaseStation()
    model.connection.host = "other-capsule.local"
    try await waitForIdle(model)

    XCTAssertNil(model.preview)
    XCTAssertTrue(model.logs.contains { $0.contains("stale host time-capsule.local") })
    XCTAssertFalse(model.logs.contains { $0.contains("$ ./backend/airport_backend.py") })
  }

  func testValidationFailureClearsExistingPreview() {
    let model = AirportAppModel()
    model.preview = CommandPreview(
      title: "Existing",
      arguments: [],
      redactedArguments: [],
      output: "old preview"
    )
    model.internet.connectUsing = .static
    model.internet.ipv4Address = ""

    model.previewInternet()

    XCTAssertNil(model.preview)
    XCTAssertEqual(model.status, "IPv4 Address cannot be empty.")
  }

  func testPendingChangesValidationFailureClearsExistingPreview() {
    let model = AirportAppModel()
    model.network.routerMode = .dhcpAndNat
    model.network.dhcpRangeStart = "10.0.0.2"
    model.network.dhcpRangeEnd = "10.0.0.200"
    model.network.dhcpLease = "1"
    model.markClean()
    model.preview = CommandPreview(
      title: "Existing",
      arguments: [],
      redactedArguments: [],
      output: "old preview"
    )

    model.network.dhcpRangeStart = " "
    model.applyPendingChanges()

    XCTAssertNil(model.preview)
    XCTAssertEqual(model.status, "DHCP Range Beginning cannot be empty.")
  }

  func testApplyPendingChangesWithNoChangesClearsStalePreview() {
    let model = AirportAppModel()
    model.baseStation.name = "time capsule"
    model.markClean()
    model.status = "Old status"
    model.preview = CommandPreview(
      title: "Existing",
      arguments: [],
      redactedArguments: [],
      output: "old preview"
    )

    model.applyPendingChanges()

    XCTAssertNil(model.preview)
    XCTAssertEqual(model.status, "No pending changes to apply.")
    XCTAssertFalse(model.isBusy)
  }

  func testUpdateWithoutCredentialsShowsPasswordPromptInsteadOfStartingWork() {
    let model = AirportAppModel()
    model.connection.password = ""
    model.preview = CommandPreview(
      title: "Existing",
      arguments: [],
      redactedArguments: [],
      output: "old preview"
    )
    model.internet.domainName = "example.test"

    model.applyPendingChanges()

    XCTAssertNil(model.preview)
    XCTAssertEqual(model.status, "Enter base station password to load settings.")
    XCTAssertTrue(model.showConnectionDetails)
    XCTAssertFalse(model.isBusy)
  }

  func testUpdateUsesNormalizedDiskSecurityModeWhenBuildingCommands() async throws {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let model = AirportAppModel()
    model.beginEditing()
    model.disks.secureSharedDisks = " disk-password "
    model.disks.diskPassword = "disk-secret"
    model.disks.verifyDiskPassword = "disk-secret"

    model.applyPendingChanges()
    try await waitForIdle(model)

    XCTAssertTrue(model.logs.contains { $0.contains("--disk-security disk-password") })
    XCTAssertTrue(model.logs.contains { $0.contains("--disk-password") })
    XCTAssertFalse(model.hasPendingChanges)
  }

  func testSelectingDiskInventoryRowDoesNotCreatePendingChanges() {
    let model = AirportAppModel()
    model.disks.inventory = [
      DiskRecord(
        deviceName: "time capsule",
        name: "Data",
        format: "HFS+",
        uuid: "disk-one",
        size: 1_000_000,
        sizeFree: 500_000,
        builtIn: true),
      DiskRecord(
        deviceName: "time capsule",
        name: "Backup",
        format: "HFS+",
        uuid: "disk-two",
        size: 2_000_000,
        sizeFree: 1_000_000,
        builtIn: true),
    ]
    model.markClean()

    model.disks.selectedDiskID = "disk-two"

    XCTAssertFalse(model.hasPendingChanges)
  }

  func testEraseDiskSheetPrefillsSelectedDiskName() {
    var disks = DisksState()
    disks.inventory = [
      DiskRecord(
        deviceName: "time capsule",
        name: "Data",
        format: "HFS+",
        uuid: "disk-one",
        size: 1_000_000,
        sizeFree: 500_000,
        builtIn: true),
      DiskRecord(
        deviceName: "time capsule",
        name: "Untitled 2",
        format: "HFS+",
        uuid: "disk-two",
        size: 2_000_000,
        sizeFree: 1_000_000,
        builtIn: false),
    ]
    disks.selectedDiskID = "disk-two"

    XCTAssertEqual(EraseDiskSheet.initialDiskName(disks: disks), "Untitled 2")
  }

  func testDiskActionAvailabilityTracksInventoryTargets() {
    var disks = DisksState()

    XCTAssertNil(DisksPane.selectedDisk(in: disks))
    XCTAssertFalse(DisksPane.canArchiveDisk(in: disks))

    disks.inventory = [
      DiskRecord(
        deviceName: "time capsule",
        name: "Data",
        format: "HFS+",
        uuid: "disk-one",
        size: 1_000_000,
        sizeFree: 500_000,
        builtIn: true)
    ]
    disks.selectedDiskID = "disk-one"

    XCTAssertEqual(DisksPane.selectedDisk(in: disks)?.name, "Data")
    XCTAssertFalse(DisksPane.canArchiveDisk(in: disks))

    disks.inventory.append(
      DiskRecord(
        deviceName: "time capsule",
        name: "Untitled 2",
        format: "HFS+",
        uuid: "disk-two",
        size: 2_000_000,
        sizeFree: 1_000_000,
        builtIn: false))

    XCTAssertTrue(DisksPane.canArchiveDisk(in: disks))
  }

  func testSelectingMockDiskInventoryRowDuringEditingDoesNotCreatePendingChanges() throws {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let model = AirportAppModel()
    model.beginEditing()

    model.disks.selectedDiskID = try XCTUnwrap(model.disks.inventory.first?.id)

    XCTAssertFalse(model.hasPendingChanges)
    XCTAssertFalse(model.canApplyPendingChanges)
  }

  func testEditingFileSharingAccountsCreatesPendingBackendChanges() {
    let model = AirportAppModel()
    XCTAssertTrue(model.supportsDiskFileSharingAccountEditing)

    model.disks.fileSharing = true
    model.disks.secureSharedDisks = "accounts"
    model.markClean()

    model.disks.fileSharingAccounts = [
      DiskAccount(
        name: "backup-user", password: "secret", verifyPassword: "secret", access: "read-only")
    ]
    model.disks.selectedFileSharingAccountID = model.disks.fileSharingAccounts.first?.id ?? ""

    XCTAssertTrue(model.hasPendingChanges)
    XCTAssertEqual(
      model.diskSharingFlags(changesOnly: true)?.map { "\($0.0)=\($0.1 ?? "")" },
      [
        "--usb-file-sharing-flags=1040",
        #"--disk-account-json={"fileSharingAccess":1,"name":"backup-user","password":"secret"}"#,
      ])
  }

  func testPrefilledAdminPasswordIsNotRewrittenWithUnrelatedBaseStationChange() {
    let model = AirportAppModel()
    model.baseStation.name = "time capsule"
    model.baseStation.newAdminPassword = "current-secret"
    model.baseStation.verifyAdminPassword = "current-secret"
    model.markClean()

    model.baseStation.name = "time capsule 2"
    let commands = model.baseStationCommands(dryRun: false)

    XCTAssertEqual(commands?.count, 1)
    XCTAssertTrue(commands?.first?.1.contains("syNm") == true)
    XCTAssertFalse(commands?.first?.1.contains("syPW") == true)
  }

  func testBaseStationCommandsIncludeSetupOverWANOnlyWhenChanged() {
    let model = AirportAppModel()
    model.baseStation.name = "time capsule"
    model.markClean()

    XCTAssertEqual(model.baseStationCommands(dryRun: false, changesOnly: true)?.count, 0)

    model.baseStation.allowSetupOverWAN = true
    var commands = model.baseStationCommands(dryRun: true, changesOnly: true)

    XCTAssertEqual(commands?.count, 1)
    XCTAssertEqual(commands?.first?.0, "Setup Over Ethernet WAN")
    XCTAssertTrue(commands?.first?.1.contains("--allow-setup-over-wan") == true)
    XCTAssertTrue(commands?.first?.1.contains("--dry-run") == true)

    model.markClean()
    model.baseStation.allowSetupOverWAN = false
    commands = model.baseStationCommands(dryRun: false, changesOnly: true)

    XCTAssertEqual(commands?.count, 1)
    XCTAssertTrue(commands?.first?.1.contains("--no-allow-setup-over-wan") == true)
    XCTAssertFalse(commands?.first?.1.contains("--dry-run") == true)
  }

  func testWhitespaceOnlyAdminPasswordEditsDoNotCreatePendingChanges() {
    let model = AirportAppModel()
    model.baseStation.name = "time capsule"
    model.baseStation.newAdminPassword = "current-secret"
    model.baseStation.verifyAdminPassword = "current-secret"
    model.markClean()

    model.baseStation.newAdminPassword = " current-secret "
    model.baseStation.verifyAdminPassword = "current-secret"

    XCTAssertFalse(model.hasPendingChanges)
    XCTAssertEqual(model.baseStationCommands(dryRun: false, changesOnly: true)?.count, 0)
  }

  func testChangedAdminPasswordTrimsOutgoingValue() {
    let model = AirportAppModel()
    model.baseStation.name = "time capsule"
    model.baseStation.newAdminPassword = "current-secret"
    model.baseStation.verifyAdminPassword = "current-secret"
    model.markClean()

    model.baseStation.newAdminPassword = " new-secret "
    model.baseStation.verifyAdminPassword = "new-secret"

    let commands = model.baseStationCommands(dryRun: false, changesOnly: true)

    XCTAssertEqual(commands?.count, 1)
    XCTAssertTrue(commands?.first?.1.contains("syPW") == true)
    XCTAssertTrue(commands?.first?.1.contains("new-secret") == true)
    XCTAssertFalse(commands?.first?.1.contains(" new-secret ") == true)
  }

  func testLegacyAdvancedACPCommandsIncludeBaseStationNameEvenWhenUnchanged() {
    let model = AirportAppModel()
    model.usesLegacyACP = true
    model.connection.host = "airport-express.local"
    model.connection.password = "password"
    model.baseStation.name = "airport express"
    model.baseStation.newAdminPassword = "password"
    model.baseStation.verifyAdminPassword = "password"
    model.markClean()

    model.baseStation.newAdminPassword = "new-password"
    model.baseStation.verifyAdminPassword = "new-password"
    model.baseStation.advancedACPSettingsJSON =
      #"{"raPo":{"hex":"0032","length":2,"type":"bytes"}}"#

    let commands = model.baseStationCommands(dryRun: false, changesOnly: true)

    XCTAssertEqual(commands?.count, 3)
    XCTAssertEqual(commands?.first?.0, "Base Station Name")
    XCTAssertTrue(commands?.first?.1.contains("syNm") == true)
    XCTAssertTrue(commands?.dropFirst().first?.1.contains("syPW") == true)
    XCTAssertTrue(commands?.dropFirst(2).first?.1.contains("raPo") == true)
  }

  func testLegacyExpressWritesUseAtomicBaseSnapshot() {
    let model = AirportAppModel()
    model.usesLegacyACP = true
    model.capabilities = DeviceCapabilities.forProductID("102")
    model.legacyACPSettingsValuesJSON =
      #"{"syNm":{"type":"bytes","hex":"616972706f72742065787072657373"}}"#
    model.connection.host = "airport-express.local"
    model.connection.password = "password"

    let arguments = model.appliedWriteArguments(
      AirportCommand.friendlyWrite(
        connection: model.connection,
        flags: [("--domain-name", "example.test")],
        dryRun: false))

    XCTAssertTrue(model.usesLegacyFullSnapshotWrites)
    XCTAssertEqual(arguments.first, "legacy-write")
    XCTAssertTrue(arguments.contains("--base-values-json"))
    XCTAssertTrue(arguments.contains(model.legacyACPSettingsValuesJSON))
    XCTAssertTrue(arguments.contains("--apply"))
    XCTAssertFalse(arguments.contains("--restart"))
  }

  func testDefaultPasswordStatusAllowsChangingPublicToPassword() {
    let model = AirportAppModel()
    model.baseStation.name = "time capsule"
    model.connection.password = "password"
    model.baseStation.newAdminPassword = "password"
    model.baseStation.verifyAdminPassword = "password"

    model.applyDeviceStatus(problemCodes: ["pubP"])
    model.markClean()
    model.baseStation.newAdminPassword = "password"
    model.baseStation.verifyAdminPassword = "password"

    let commands = model.baseStationCommands(dryRun: false, changesOnly: true)

    XCTAssertEqual(commands?.count, 1)
    XCTAssertTrue(commands?.first?.1.contains("syPW") == true)
    XCTAssertTrue(commands?.first?.1.contains("password") == true)
  }

  func testChangedAdminPasswordDoesNotRequireUnchangedMissingBaseStationName() {
    let model = AirportAppModel()
    model.baseStation.name = ""
    model.baseStation.newAdminPassword = "current-secret"
    model.baseStation.verifyAdminPassword = "current-secret"
    model.markClean()

    model.baseStation.newAdminPassword = "new-secret"
    model.baseStation.verifyAdminPassword = "new-secret"

    let commands = model.baseStationCommands(dryRun: false, changesOnly: true)

    XCTAssertEqual(commands?.count, 1)
    XCTAssertTrue(commands?.first?.1.contains("syPW") == true)
  }

  func testClearingBaseStationNameStillFailsWhenChanged() {
    let model = AirportAppModel()
    model.baseStation.name = "time capsule"
    model.markClean()

    model.baseStation.name = ""

    XCTAssertNil(model.baseStationCommands(dryRun: false, changesOnly: true))
    XCTAssertEqual(model.status, "Base Station Name cannot be empty.")
  }

  func testBaseStationPanePreviewWithNoChangesDoesNotRunBackend() {
    let model = AirportAppModel()
    model.baseStation.name = ""
    model.markClean()

    model.previewBaseStation()

    XCTAssertNil(model.preview)
    XCTAssertEqual(model.status, "No pending Base Station changes to preview.")
    XCTAssertFalse(model.logs.contains { $0.hasPrefix("$ ") })
  }

  func testBaseStationPaneApplyWithNoChangesDoesNotRunBackend() {
    let model = AirportAppModel()
    model.baseStation.name = ""
    model.markClean()

    model.applyBaseStation()

    XCTAssertNil(model.preview)
    XCTAssertEqual(model.status, "No pending Base Station changes to apply.")
    XCTAssertFalse(model.logs.contains { $0.hasPrefix("$ ") })
  }

  func testRememberPasswordDoesNotCreatePendingBackendChange() {
    let model = AirportAppModel()
    model.baseStation.name = "time capsule"
    model.disks.rawInventory = "loaded inventory"
    model.disks.didLoadInventory = true
    model.markClean()

    model.baseStation.rememberPassword.toggle()
    model.disks.rememberPassword.toggle()
    model.disks.rawInventory = "refreshed inventory"
    model.disks.didLoadInventory = false

    XCTAssertFalse(model.hasPendingChanges)
    XCTAssertEqual(model.baseStationCommands(dryRun: false, changesOnly: true)?.count, 0)
    XCTAssertEqual(model.diskSharingFlags(changesOnly: true)?.count, 0)
  }

  func testReadOnlyBaseStationIdentityDoesNotCreatePendingChanges() {
    let model = AirportAppModel()
    model.baseStation.name = "time capsule"
    model.baseStation.serialNumber = "C86TEST123"
    model.baseStation.version = "7.9.1"
    model.markClean()

    model.baseStation.serialNumber = "C86TEST456"
    model.baseStation.version = "7.9.2"

    XCTAssertFalse(model.hasPendingChanges)
    XCTAssertEqual(model.baseStationCommands(dryRun: false, changesOnly: true)?.count, 0)
  }

  func testChangedPrefilledAdminPasswordIsWritten() {
    let model = AirportAppModel()
    model.baseStation.name = "time capsule"
    model.baseStation.newAdminPassword = "current-secret"
    model.baseStation.verifyAdminPassword = "current-secret"
    model.markClean()

    model.baseStation.newAdminPassword = "new-secret"
    model.baseStation.verifyAdminPassword = "new-secret"
    let commands = model.baseStationCommands(dryRun: false)

    XCTAssertEqual(commands?.count, 2)
    XCTAssertTrue(commands?[1].1.contains("syPW") == true)
  }

  func testInternetFlagsIncludeVisibleFieldsAndOptions() {
    let model = AirportAppModel()
    detectInternetOptionsSupport(model)
    model.internet.connectUsing = .static
    model.internet.ipv4Address = "192.168.4.45"
    model.internet.subnetMask = "255.255.252.0"
    model.internet.routerAddress = "192.168.4.1"
    model.internet.dnsServers = "1.1.1.1, 8.8.8.8"
    model.internet.ipv6DNSServers = "2001:4860:4860::8888"
    model.internet.domainName = "example.test"
    model.internet.ipv6Address = "2001:db8::10"
    model.internet.configureIPv6 = "automatic"
    model.internet.dynamicGlobalHostname = true
    model.internet.globalHostname = "capsule.example.test"

    XCTAssertEqual(
      model.internetFlags()?.map(\.0),
      [
        "--connect-using",
        "--ipv4-address",
        "--subnet-mask",
        "--router-address",
        "--dns-server",
        "--dns-server",
        "--ipv6-dns-server",
        "--domain-name",
        "--ipv6-address",
        "--configure-ipv6",
        "--dynamic-global-hostname",
        "--global-hostname",
      ])
  }

  func testInternetFlagsSkipInactiveConnectionModeFields() {
    let model = AirportAppModel()
    model.internet.connectUsing = .dhcp
    model.internet.ipv4Address = "192.168.4.45"
    model.internet.subnetMask = "255.255.252.0"
    model.internet.routerAddress = "192.168.4.1"
    model.internet.pppoeAccount = "account"
    model.internet.pppoePassword = "pppoe-secret"
    model.internet.pppoeService = "service"

    let flags = model.internetFlags()

    XCTAssertFalse(flags?.contains { $0.0 == "--ipv4-address" } == true)
    XCTAssertFalse(flags?.contains { $0.0 == "--subnet-mask" } == true)
    XCTAssertFalse(flags?.contains { $0.0 == "--router-address" } == true)
    XCTAssertFalse(flags?.contains { $0.0 == "--pppoe-account" } == true)
    XCTAssertFalse(flags?.contains { $0.0 == "--pppoe-password" } == true)
    XCTAssertFalse(flags?.contains { $0.0 == "--pppoe-service" } == true)
    XCTAssertFalse(flags?.contains { $0.0 == "--pppoe-connection" } == true)
  }

  func testInternetFlagsSkipUnsupportedRuntimeFeatures() {
    let model = AirportAppModel()
    model.applyAuthoritativeBaseStationIdentity(
      readName: "Legacy Express",
      serialNumber: "EXPRESS",
      version: "6.3",
      productID: "102",
      supportsIPv6: false,
      supportsDynamicGlobalHostname: false)
    model.internet.ipv6DNSServers = "not-ipv6"
    model.internet.ipv6Address = "not-ipv6"
    model.internet.configureIPv6 = "manual"
    model.internet.dynamicGlobalHostname = true
    model.internet.globalHostname = ""

    let flags = model.internetFlags()

    XCTAssertNotNil(flags)
    XCTAssertFalse(flags?.contains { $0.0 == "--ipv6-dns-server" } == true)
    XCTAssertFalse(flags?.contains { $0.0 == "--clear-ipv6-dns" } == true)
    XCTAssertFalse(flags?.contains { $0.0 == "--ipv6-address" } == true)
    XCTAssertFalse(flags?.contains { $0.0 == "--configure-ipv6" } == true)
    XCTAssertFalse(flags?.contains { $0.0 == "--dynamic-global-hostname" } == true)
    XCTAssertFalse(flags?.contains { $0.0 == "--global-hostname" } == true)
  }

  func testChangedInternetModeClearsWANIPv4WithoutWritingStalePPPoEFields() {
    let model = AirportAppModel()
    model.internet.connectUsing = .pppoe
    model.internet.pppoeAccount = "account"
    model.internet.pppoePassword = "pppoe-secret"
    model.internet.pppoeService = "service"
    model.markClean()

    model.internet.connectUsing = .dhcp

    XCTAssertEqual(
      model.internetFlags(changesOnly: true)?.map { "\($0.0)=\($0.1 ?? "")" },
      [
        "--connect-using=dhcp",
        "--ipv4-address=0.0.0.0",
        "--subnet-mask=0.0.0.0",
        "--router-address=0.0.0.0",
      ])
  }

  func testHiddenPPPoEEditsDoNotCreatePendingChangesWhenInactive() {
    let model = AirportAppModel()
    model.internet.connectUsing = .dhcp
    model.internet.pppoeAccount = "account"
    model.internet.pppoePassword = "pppoe-secret"
    model.internet.pppoeService = "service"
    model.internet.pppoeConnection = "always-on"
    model.markClean()

    model.internet.pppoeAccount = "other-account"
    model.internet.pppoePassword = "other-secret"
    model.internet.pppoeService = "other-service"
    model.internet.pppoeConnection = "manual"

    XCTAssertFalse(model.hasPendingChanges)
    XCTAssertEqual(model.internetFlags(changesOnly: true)?.count, 0)
  }

  func testHiddenStaticAddressEditsDoNotCreatePendingChangesWhenInactive() {
    let dhcpModel = AirportAppModel()
    dhcpModel.internet.connectUsing = .dhcp
    dhcpModel.internet.ipv4Address = "192.168.4.45"
    dhcpModel.internet.subnetMask = "255.255.252.0"
    dhcpModel.internet.routerAddress = "192.168.4.1"
    dhcpModel.markClean()

    dhcpModel.internet.ipv4Address = "192.168.4.46"
    dhcpModel.internet.subnetMask = "255.255.255.0"
    dhcpModel.internet.routerAddress = "192.168.4.254"

    XCTAssertFalse(dhcpModel.hasPendingChanges)
    XCTAssertEqual(dhcpModel.internetFlags(changesOnly: true)?.count, 0)

    let pppoeModel = AirportAppModel()
    pppoeModel.internet.connectUsing = .pppoe
    pppoeModel.internet.pppoeAccount = "account"
    pppoeModel.internet.ipv4Address = "192.168.4.45"
    pppoeModel.internet.subnetMask = "255.255.252.0"
    pppoeModel.internet.routerAddress = "192.168.4.1"
    pppoeModel.markClean()

    pppoeModel.internet.ipv4Address = "192.168.4.46"
    pppoeModel.internet.subnetMask = "255.255.255.0"
    pppoeModel.internet.routerAddress = "192.168.4.254"

    XCTAssertFalse(pppoeModel.hasPendingChanges)
    XCTAssertEqual(pppoeModel.internetFlags(changesOnly: true)?.count, 0)
  }

  func testInternetFlagsIncludePPPoEPasswordWhenProvided() {
    let model = AirportAppModel()
    model.internet.connectUsing = .pppoe
    model.internet.pppoeAccount = "account"
    model.internet.pppoePassword = "pppoe-secret"
    model.internet.pppoeService = "service"

    let flags = model.internetFlags()

    XCTAssertTrue(flags?.contains { $0 == ("--pppoe-account", "account") } == true)
    XCTAssertTrue(flags?.contains { $0 == ("--pppoe-password", "pppoe-secret") } == true)
    XCTAssertTrue(flags?.contains { $0 == ("--pppoe-service", "service") } == true)
  }

  func testStaticInternetIPv4AddressCannotBeEmpty() {
    let model = AirportAppModel()
    model.internet.connectUsing = .static
    model.internet.ipv4Address = " "
    model.internet.subnetMask = "255.255.252.0"
    model.internet.routerAddress = "192.168.4.1"

    XCTAssertNil(model.internetFlags())
    XCTAssertEqual(model.status, "IPv4 Address cannot be empty.")
  }

  func testStaticInternetIPv4AddressMustBeValidIPv4() {
    let model = AirportAppModel()
    model.internet.connectUsing = .static
    model.internet.ipv4Address = "192.168.4.999"
    model.internet.subnetMask = "255.255.252.0"
    model.internet.routerAddress = "192.168.4.1"

    XCTAssertNil(model.internetFlags())
    XCTAssertEqual(model.status, "IPv4 Address must be an IPv4 address.")
  }

  func testStaticInternetIPv4AddressRejectsLeadingZeroOctets() {
    let model = AirportAppModel()
    model.internet.connectUsing = .static
    model.internet.ipv4Address = "192.168.004.45"
    model.internet.subnetMask = "255.255.252.0"
    model.internet.routerAddress = "192.168.4.1"

    XCTAssertNil(model.internetFlags())
    XCTAssertEqual(model.status, "IPv4 Address must be an IPv4 address.")
  }

  func testStaticInternetSubnetMaskCannotBeEmpty() {
    let model = AirportAppModel()
    model.internet.connectUsing = .static
    model.internet.ipv4Address = "192.168.4.45"
    model.internet.subnetMask = " "
    model.internet.routerAddress = "192.168.4.1"

    XCTAssertNil(model.internetFlags())
    XCTAssertEqual(model.status, "Subnet Mask cannot be empty.")
  }

  func testStaticInternetSubnetMaskMustBeContiguous() {
    let model = AirportAppModel()
    model.internet.connectUsing = .static
    model.internet.ipv4Address = "192.168.4.45"
    model.internet.subnetMask = "255.0.255.0"
    model.internet.routerAddress = "192.168.4.1"

    XCTAssertNil(model.internetFlags())
    XCTAssertEqual(model.status, "Subnet Mask must contain contiguous one bits.")
  }

  func testStaticInternetSubnetMaskRejectsLeadingZeroOctets() {
    let model = AirportAppModel()
    model.internet.connectUsing = .static
    model.internet.ipv4Address = "192.168.4.45"
    model.internet.subnetMask = "255.255.004.0"
    model.internet.routerAddress = "192.168.4.1"

    XCTAssertNil(model.internetFlags())
    XCTAssertEqual(model.status, "Subnet Mask must contain contiguous one bits.")
  }

  func testStaticInternetSubnetMaskCannotBeAllZeros() {
    let model = AirportAppModel()
    model.internet.connectUsing = .static
    model.internet.ipv4Address = "192.168.4.45"
    model.internet.subnetMask = "0.0.0.0"
    model.internet.routerAddress = "192.168.4.1"

    XCTAssertNil(model.internetFlags())
    XCTAssertEqual(
      model.status, "Subnet Mask must be between 255.0.0.0 and 255.255.255.254.")
  }

  func testStaticInternetSubnetMaskCannotBeAllOnes() {
    let model = AirportAppModel()
    model.internet.connectUsing = .static
    model.internet.ipv4Address = "192.168.4.45"
    model.internet.subnetMask = "255.255.255.255"
    model.internet.routerAddress = "192.168.4.1"

    XCTAssertNil(model.internetFlags())
    XCTAssertEqual(
      model.status, "Subnet Mask must be between 255.0.0.0 and 255.255.255.254.")
  }

  func testStaticInternetRouterAddressCannotBeEmpty() {
    let model = AirportAppModel()
    model.internet.connectUsing = .static
    model.internet.ipv4Address = "192.168.4.45"
    model.internet.subnetMask = "255.255.252.0"
    model.internet.routerAddress = " "

    XCTAssertNil(model.internetFlags())
    XCTAssertEqual(model.status, "Router Address cannot be empty.")
  }

  func testStaticInternetRouterAddressMustBeValidIPv4() {
    let model = AirportAppModel()
    model.internet.connectUsing = .static
    model.internet.ipv4Address = "192.168.4.45"
    model.internet.subnetMask = "255.255.252.0"
    model.internet.routerAddress = "router.local"

    XCTAssertNil(model.internetFlags())
    XCTAssertEqual(model.status, "Router Address must be an IPv4 address.")
  }

  func testPPPoEAccountNameCannotBeEmpty() {
    let model = AirportAppModel()
    model.internet.connectUsing = .pppoe
    model.internet.pppoeAccount = " "

    XCTAssertNil(model.internetFlags())
    XCTAssertEqual(model.status, "PPPoE Account Name cannot be empty.")
  }

  func testChangedInternetFlagsClearDNSAndPreserveUnchangedValues() {
    let model = AirportAppModel()
    detectInternetOptionsSupport(model)
    model.internet.dnsServers = "1.1.1.1, 8.8.8.8"
    model.internet.ipv6DNSServers = "2001:4860:4860::8888"
    model.internet.domainName = "example.test"
    model.markClean()

    model.internet.dnsServers = ""
    model.internet.ipv6DNSServers = ""

    let flags = model.internetFlags(changesOnly: true)

    XCTAssertEqual(flags?.map(\.0), ["--clear-dns", "--clear-ipv6-dns"])
    XCTAssertFalse(flags?.contains { $0.0 == "--domain-name" } == true)
  }

  func testChangedInternetFlagsAllowUnchangedIncompleteStaticFields() {
    let model = AirportAppModel()
    model.internet.connectUsing = .static
    model.internet.ipv4Address = ""
    model.internet.subnetMask = ""
    model.internet.routerAddress = ""
    model.markClean()

    model.internet.domainName = "example.test"

    XCTAssertEqual(model.internetFlags(changesOnly: true)?.map(\.0), ["--domain-name"])
  }

  func testChangedInternetFlagsAllowUnchangedMissingPPPoEAccount() {
    let model = AirportAppModel()
    model.internet.connectUsing = .pppoe
    model.internet.pppoeAccount = ""
    model.internet.pppoeConnection = "always-on"
    model.markClean()

    model.internet.domainName = "example.test"

    XCTAssertEqual(model.internetFlags(changesOnly: true)?.map(\.0), ["--domain-name"])
  }

  func testChangedInternetFlagsAllowUnchangedMalformedDNSList() {
    let model = AirportAppModel()
    model.internet.dnsServers = "1.1.1.1,,8.8.8.8"
    model.internet.ipv6DNSServers = "2001:4860:4860::8888,"
    model.markClean()

    model.internet.domainName = "example.test"

    XCTAssertEqual(model.internetFlags(changesOnly: true)?.map(\.0), ["--domain-name"])
  }

  func testInternetPanePreviewWithNoChangesDoesNotRunBackend() {
    let model = AirportAppModel()
    model.internet.connectUsing = .pppoe
    model.internet.pppoeAccount = ""
    model.markClean()

    model.previewInternet()

    XCTAssertNil(model.preview)
    XCTAssertEqual(model.status, "No pending Internet changes to preview.")
    XCTAssertFalse(model.logs.contains { $0.hasPrefix("$ ") })
  }

  func testInternetPaneApplyWithNoChangesDoesNotRunBackend() {
    let model = AirportAppModel()
    model.internet.connectUsing = .static
    model.internet.ipv4Address = ""
    model.internet.subnetMask = ""
    model.internet.routerAddress = ""
    model.markClean()

    model.applyInternet()

    XCTAssertNil(model.preview)
    XCTAssertEqual(model.status, "No pending Internet changes to apply.")
    XCTAssertFalse(model.logs.contains { $0.hasPrefix("$ ") })
  }

  func testWirelessPanePreviewWithNoChangesDoesNotRunBackend() {
    let model = AirportAppModel()
    model.wireless.mode = "create"
    model.wireless.networkName = ""
    model.markClean()

    model.previewWireless()

    XCTAssertNil(model.preview)
    XCTAssertEqual(model.status, "No pending Wireless changes to preview.")
    XCTAssertFalse(model.logs.contains { $0.hasPrefix("$ ") })
  }

  func testWirelessPaneApplyWithNoChangesDoesNotRunBackend() {
    let model = AirportAppModel()
    model.wireless.mode = "create"
    model.wireless.networkName = ""
    model.markClean()

    model.applyWireless()

    XCTAssertNil(model.preview)
    XCTAssertEqual(model.status, "No pending Wireless changes to apply.")
    XCTAssertFalse(model.logs.contains { $0.hasPrefix("$ ") })
  }

  func testChangedWirelessFlagsAllowUnchangedMissingNetworkName() {
    let model = AirportAppModel()
    model.wireless.mode = "create"
    model.wireless.networkName = ""
    model.markClean()

    model.wireless.hiddenNetwork = true

    XCTAssertEqual(model.wirelessFlags(changesOnly: true)?.map(\.0), ["--hidden-network"])
  }

  func testNetworkPanePreviewWithNoChangesDoesNotRunBackend() {
    let model = AirportAppModel()
    model.network.routerMode = .dhcpAndNat
    model.network.dhcpRangeStart = ""
    model.network.dhcpRangeEnd = ""
    model.network.dhcpLease = ""
    model.markClean()

    model.previewNetwork()

    XCTAssertNil(model.preview)
    XCTAssertEqual(model.status, "No pending Network changes to preview.")
    XCTAssertFalse(model.logs.contains { $0.hasPrefix("$ ") })
  }

  func testNetworkPaneApplyWithNoChangesDoesNotRunBackend() {
    let model = AirportAppModel()
    model.network.routerMode = .dhcpAndNat
    model.network.dhcpRangeStart = ""
    model.network.dhcpRangeEnd = ""
    model.network.dhcpLease = ""
    model.markClean()

    model.applyNetwork()

    XCTAssertNil(model.preview)
    XCTAssertEqual(model.status, "No pending Network changes to apply.")
    XCTAssertFalse(model.logs.contains { $0.hasPrefix("$ ") })
  }

  func testChangedNetworkFlagsAllowUnchangedIncompleteDHCPFields() {
    let model = AirportAppModel()
    model.network.routerMode = .dhcpAndNat
    model.network.dhcpRangeStart = ""
    model.network.dhcpRangeEnd = ""
    model.network.dhcpLease = ""
    model.network.natPMP = false
    model.markClean()

    model.network.natPMP = true

    XCTAssertEqual(model.networkFlags(changesOnly: true)?.map(\.0), ["--nat-pmp"])
  }

  func testDNSServersMustBeValidIPv4() {
    let model = AirportAppModel()
    model.internet.dnsServers = "1.1.1.1, dns.local"

    XCTAssertNil(model.internetFlags())
    XCTAssertEqual(model.status, "DNS Server must be an IPv4 address.")
  }

  func testDNSServersRejectLeadingZeroOctets() {
    let model = AirportAppModel()
    model.internet.dnsServers = "001.1.1.1"

    XCTAssertNil(model.internetFlags())
    XCTAssertEqual(model.status, "DNS Server must be an IPv4 address.")
  }

  func testDNSServersAcceptAtMostTwoIPv4Addresses() {
    let model = AirportAppModel()
    model.internet.dnsServers = "1.1.1.1, 8.8.8.8, 9.9.9.9"

    XCTAssertNil(model.internetFlags())
    XCTAssertEqual(model.status, "DNS Servers accepts at most two IPv4 DNS servers.")
  }

  func testDNSServersRejectEmptyCommaSeparatedValues() {
    let model = AirportAppModel()
    model.internet.dnsServers = "1.1.1.1,,8.8.8.8"

    XCTAssertNil(model.internetFlags())
    XCTAssertEqual(model.status, "DNS Servers contains an empty value.")
  }

  func testIPv6DNSServersMustBeValidIPv6() {
    let model = AirportAppModel()
    detectInternetOptionsSupport(model)
    model.internet.ipv6DNSServers = "2001:4860:4860::8888, dns.local"

    XCTAssertNil(model.internetFlags())
    XCTAssertEqual(model.status, "IPv6 DNS Server must be an IPv6 address.")
  }

  func testIPv6DNSServersAcceptAtMostTwoIPv6Addresses() {
    let model = AirportAppModel()
    detectInternetOptionsSupport(model)
    model.internet.ipv6DNSServers =
      "2001:4860:4860::8888, 2001:4860:4860::8844, 2001:db8::1"

    XCTAssertNil(model.internetFlags())
    XCTAssertEqual(model.status, "IPv6 DNS Servers accepts at most two IPv6 DNS servers.")
  }

  func testIPv6DNSServersRejectEmptyCommaSeparatedValues() {
    let model = AirportAppModel()
    detectInternetOptionsSupport(model)
    model.internet.ipv6DNSServers = "2001:4860:4860::8888,"

    XCTAssertNil(model.internetFlags())
    XCTAssertEqual(model.status, "IPv6 DNS Servers contains an empty value.")
  }

  func testIPv6AddressMustBeValidIPv6() {
    let model = AirportAppModel()
    detectInternetOptionsSupport(model)
    model.internet.ipv6Address = "not-an-ipv6-address"

    XCTAssertNil(model.internetFlags())
    XCTAssertEqual(model.status, "IPv6 Address must be an IPv6 address.")
  }

  func testIPv6AddressFormattingOnlyChangesDoNotCreatePendingChanges() {
    let model = AirportAppModel()
    detectInternetOptionsSupport(model)
    model.internet.ipv6Address = "2001:db8::1"
    model.markClean()

    model.internet.ipv6Address = "2001:0DB8:0000:0000:0000:0000:0000:0001"

    XCTAssertFalse(model.hasPendingChanges)
    XCTAssertEqual(model.internetFlags(changesOnly: true)?.count, 0)
  }

  func testIPv6AddressFlagsNormalizeOutgoingValue() {
    let model = AirportAppModel()
    detectInternetOptionsSupport(model)
    model.internet.ipv6Address = "2001:0DB8:0000:0000:0000:0000:0000:0001"

    XCTAssertTrue(
      model.internetFlags()?.contains { $0 == ("--ipv6-address", "2001:db8::1") } == true)
  }

  func testInternetOptionValuesMustBeSupported() {
    let model = AirportAppModel()
    detectInternetOptionsSupport(model)
    model.internet.configureIPv6 = "native"

    XCTAssertNil(model.internetFlags())
    XCTAssertEqual(model.status, "Configure IPv6 must be link-local, automatic, or manual.")

    model.internet.configureIPv6 = "automatic"
    model.internet.connectUsing = .pppoe
    model.internet.pppoeAccount = "account"
    model.internet.pppoeConnection = "dial-on-demand"

    XCTAssertNil(model.internetFlags())
    XCTAssertEqual(model.status, "PPPoE Connection must be always-on, automatic, or manual.")
  }

  func testDNSPreviewOnlyChangesDoNotCreatePendingChanges() {
    let model = AirportAppModel()
    model.internet.connectUsing = .dhcp
    model.internet.dnsServerPreview = "192.168.1.1"
    model.internet.ipv6DNSServerPreview = "fe80::1"
    model.markClean()

    model.internet.dnsServerPreview = "192.168.4.1"
    model.internet.ipv6DNSServerPreview = "fe80::2"

    XCTAssertFalse(model.hasPendingChanges)
    XCTAssertEqual(model.internetFlags(changesOnly: true)?.count, 0)
  }

  func testDNSServerSeparatorOnlyChangesDoNotCreatePendingChanges() {
    let model = AirportAppModel()
    detectInternetOptionsSupport(model)
    model.internet.dnsServers = "1.1.1.1, 8.8.8.8"
    model.internet.ipv6DNSServers = "2001:4860:4860::8888, 2001:4860:4860::8844"
    model.markClean()

    model.internet.dnsServers = "1.1.1.1\n8.8.8.8"
    model.internet.ipv6DNSServers = "2001:4860:4860::8888 2001:4860:4860::8844"

    XCTAssertFalse(model.hasPendingChanges)
    XCTAssertEqual(model.internetFlags(changesOnly: true)?.count, 0)
  }

  func testIPv6DNSServerFormattingOnlyChangesDoNotCreatePendingChanges() {
    let model = AirportAppModel()
    detectInternetOptionsSupport(model)
    model.internet.ipv6DNSServers = "2001:db8::1, 2001:db8::2"
    model.markClean()

    model.internet.ipv6DNSServers =
      "2001:0DB8:0000:0000:0000:0000:0000:0001 2001:0DB8:0000:0000:0000:0000:0000:0002"

    XCTAssertFalse(model.hasPendingChanges)
    XCTAssertEqual(model.internetFlags(changesOnly: true)?.count, 0)
  }

  func testIPv6DNSFlagsNormalizeOutgoingValues() {
    let model = AirportAppModel()
    detectInternetOptionsSupport(model)
    model.internet.ipv6DNSServers =
      "2001:0DB8:0000:0000:0000:0000:0000:0001, 2001:0DB8:0000:0000:0000:0000:0000:0002"

    XCTAssertEqual(
      model.internetFlags()?.filter { $0.0 == "--ipv6-dns-server" }.map(\.1),
      ["2001:db8::1", "2001:db8::2"]
    )
  }

  func testDNSServerOrderChangesRemainPending() {
    let model = AirportAppModel()
    model.internet.dnsServers = "1.1.1.1, 8.8.8.8"
    model.markClean()

    model.internet.dnsServers = "8.8.8.8, 1.1.1.1"

    XCTAssertTrue(model.hasPendingChanges)
    let flags = model.internetFlags(changesOnly: true)
    XCTAssertEqual(flags?.first { $0.0 == "--dns-server-1" }?.1, "8.8.8.8")
    XCTAssertEqual(flags?.first { $0.0 == "--dns-server-2" }?.1, "1.1.1.1")
    XCTAssertFalse(flags?.contains { $0.0 == "--dns-server" } == true)
  }

  func testSwitchingFromDHCPKeepsPreviewDNSServersEditable() {
    let model = AirportAppModel()
    model.internet.connectUsing = .dhcp
    model.internet.dnsServers = ""
    model.internet.dnsServerPreview = "192.168.1.1"
    model.internet.ipv6DNSServers = ""
    model.internet.ipv6DNSServerPreview = "2001:db8::1"
    model.markClean()

    model.internet.connectUsing = .pppoe
    model.handleInternetConnectUsingChanged(.pppoe)
    model.internet.pppoeAccount = "account"

    XCTAssertEqual(model.internet.dnsServers, "192.168.1.1")
    XCTAssertEqual(model.internet.dnsServerPreview, "")
    XCTAssertEqual(model.internet.ipv6DNSServers, "2001:db8::1")
    XCTAssertEqual(model.internet.ipv6DNSServerPreview, "")

    model.internet.dnsServers = "192.168.1.1, 192.168.1.2"
    let flags = model.internetFlags(changesOnly: true)
    XCTAssertFalse(flags?.contains { $0.0 == "--dns-server-1" } == true)
    XCTAssertEqual(flags?.first { $0.0 == "--dns-server-2" }?.1, "192.168.1.2")
  }

  func testSwitchingFromDHCPToStaticWritesPreviewDNSServer() {
    let model = AirportAppModel()
    model.internet.connectUsing = .dhcp
    model.internet.dnsServers = ""
    model.internet.dnsServerPreview = "192.168.1.1"
    model.markClean()

    model.internet.connectUsing = .static
    model.handleInternetConnectUsingChanged(.static)
    model.internet.ipv4Address = "192.168.4.45"
    model.internet.subnetMask = "255.255.252.0"
    model.internet.routerAddress = "192.168.4.1"

    let flags = model.internetFlags(changesOnly: true)

    XCTAssertEqual(flags?.first { $0.0 == "--dns-server-1" }?.1, "192.168.1.1")
  }

  func testChangedInternetFlagsCanClearTextFields() {
    let model = AirportAppModel()
    model.internet.domainName = "example.test"
    model.internet.dynamicGlobalHostname = true
    model.internet.globalHostname = "capsule.example.test"
    model.markClean()

    model.internet.domainName = ""

    let flags = model.internetFlags(changesOnly: true)

    XCTAssertTrue(flags?.contains { $0 == ("--domain-name", "") } == true)
    XCTAssertFalse(flags?.contains { $0.0 == "--global-hostname" } == true)
  }

  func testEnabledDynamicGlobalHostnameRequiresHostname() {
    let model = AirportAppModel()
    detectInternetOptionsSupport(model)
    model.internet.dynamicGlobalHostname = true
    model.internet.globalHostname = " "

    XCTAssertNil(model.internetFlags())
    XCTAssertEqual(model.status, "Global Hostname cannot be empty.")
  }

  func testEnablingDynamicGlobalHostnameRequiresHostname() {
    let model = AirportAppModel()
    detectInternetOptionsSupport(model)
    model.internet.dynamicGlobalHostname = false
    model.internet.globalHostname = ""
    model.markClean()

    model.internet.dynamicGlobalHostname = true

    XCTAssertNil(model.internetFlags(changesOnly: true))
    XCTAssertEqual(model.status, "Global Hostname cannot be empty.")
  }

  func testClearingActiveGlobalHostnameRequiresHostname() {
    let model = AirportAppModel()
    detectInternetOptionsSupport(model)
    model.internet.dynamicGlobalHostname = true
    model.internet.globalHostname = "capsule.example.test"
    model.markClean()

    model.internet.globalHostname = ""

    XCTAssertNil(model.internetFlags(changesOnly: true))
    XCTAssertEqual(model.status, "Global Hostname cannot be empty.")
  }

  func testChangedInternetFlagsAllowUnchangedMissingGlobalHostname() {
    let model = AirportAppModel()
    detectInternetOptionsSupport(model)
    model.internet.dynamicGlobalHostname = true
    model.internet.globalHostname = ""
    model.markClean()

    model.internet.domainName = "example.test"

    XCTAssertEqual(model.internetFlags(changesOnly: true)?.map(\.0), ["--domain-name"])
  }

  func testDisabledDynamicGlobalHostnameDoesNotWriteStaleHiddenFields() {
    let model = AirportAppModel()
    detectInternetOptionsSupport(model)
    model.internet.dynamicGlobalHostname = true
    model.internet.globalHostname = "capsule.example.test"
    model.internet.globalHostnameUser = "host-user"
    model.internet.globalHostnamePassword = "host-secret"
    model.markClean()

    model.internet.dynamicGlobalHostname = false

    XCTAssertEqual(
      model.internetFlags(changesOnly: true)?.map(\.0),
      ["--no-dynamic-global-hostname"])
  }

  func testHiddenDynamicGlobalHostnameEditsDoNotCreatePendingChangesWhenDisabled() {
    let model = AirportAppModel()
    detectInternetOptionsSupport(model)
    model.internet.dynamicGlobalHostname = false
    model.internet.globalHostname = "capsule.example.test"
    model.internet.globalHostnameUser = "host-user"
    model.internet.globalHostnamePassword = "host-secret"
    model.markClean()

    model.internet.globalHostname = "other.example.test"
    model.internet.globalHostnameUser = "other-user"
    model.internet.globalHostnamePassword = "other-secret"

    XCTAssertFalse(model.hasPendingChanges)
    XCTAssertEqual(model.internetFlags(changesOnly: true)?.count, 0)
  }

  func testChangedScalarFlagsTrimOutgoingValues() {
    let model = AirportAppModel()
    detectInternetOptionsSupport(model)

    model.internet.domainName = " example.test "
    model.internet.dynamicGlobalHostname = true
    model.internet.globalHostname = " capsule.example.test "
    model.network.routerMode = .dhcpAndNat
    model.network.dhcpRangeStart = "10.0.0.2"
    model.network.dhcpRangeEnd = "10.0.0.200"
    model.network.dhcpLease = " 12 "

    XCTAssertTrue(
      model.internetFlags()?.contains { $0 == ("--domain-name", "example.test") } == true)
    XCTAssertTrue(
      model.internetFlags()?.contains { $0 == ("--global-hostname", "capsule.example.test") }
        == true)
    XCTAssertTrue(model.networkFlags()?.contains { $0 == ("--dhcp-lease", "12") } == true)
  }

  func testWhitespaceOnlyScalarEditsDoNotCreatePendingChanges() {
    let model = AirportAppModel()
    model.baseStation.name = "time capsule"
    model.internet.domainName = "example.test"
    model.internet.dynamicGlobalHostname = true
    model.internet.globalHostname = "capsule.example.test"
    model.wireless.networkName = "Network"
    model.network.dhcpLease = "12"
    model.network.defaultHost = "192.168.1.20"
    model.disks.winsServer = "192.168.1.30"
    model.disks.windowsWorkgroup = "WORKGROUP"
    model.markClean()

    model.baseStation.name = " time capsule "
    model.internet.domainName = " example.test "
    model.internet.globalHostname = " capsule.example.test "
    model.wireless.networkName = " Network "
    model.network.dhcpLease = " 12 "
    model.network.defaultHost = " 192.168.1.20 "
    model.disks.winsServer = " 192.168.1.30 "
    model.disks.windowsWorkgroup = " WORKGROUP "

    XCTAssertFalse(model.hasPendingChanges)
    XCTAssertEqual(model.baseStationCommands(dryRun: false, changesOnly: true)?.count, 0)
    XCTAssertEqual(model.internetFlags(changesOnly: true)?.count, 0)
    XCTAssertEqual(model.wirelessFlags(changesOnly: true)?.count, 0)
    XCTAssertEqual(model.networkFlags(changesOnly: true)?.count, 0)
    XCTAssertEqual(model.diskSharingFlags(changesOnly: true)?.count, 0)
  }

  func testDNSServerFieldsSplitAndJoinVisibleRows() {
    XCTAssertEqual(DNSServerFields.servers(from: "1.1.1.1, 8.8.8.8"), ["1.1.1.1", "8.8.8.8"])
    XCTAssertEqual(
      DNSServerFields.servers(from: "2001:4860:4860::8888\n2001:4860:4860::8844"),
      [
        "2001:4860:4860::8888",
        "2001:4860:4860::8844",
      ])
    XCTAssertEqual(DNSServerFields.combined([" 1.1.1.1 ", "", "8.8.8.8"]), "1.1.1.1, 8.8.8.8")
  }

  func testDHCPRangeFieldsParseAndNormalizeValidRanges() {
    let fields = DHCPRangeFields.fields(
      start: " 192.168.4.2 ",
      end: "192.168.4.200"
    )

    XCTAssertEqual(fields?.prefix, "192.168")
    XCTAssertEqual(fields?.subnet, "4")
    XCTAssertEqual(fields?.startHost, "2")
    XCTAssertEqual(fields?.endHost, "200")
    XCTAssertEqual(
      DHCPRangeFields.range(
        prefix: " 10.0 ",
        subnet: " 1 ",
        startHost: " 2 ",
        endHost: " 200 "
      )?.start,
      "10.0.1.2"
    )
    XCTAssertEqual(
      DHCPRangeFields.range(
        prefix: " 10.0 ",
        subnet: " 1 ",
        startHost: " 2 ",
        endHost: " 200 "
      )?.end,
      "10.0.1.200"
    )
  }

  func testDHCPRangeFieldsRejectMalformedRanges() {
    XCTAssertNil(DHCPRangeFields.fields(start: "10.0.1.2", end: "10.0.2.200"))
    XCTAssertNil(DHCPRangeFields.fields(start: "169.254.1.2", end: "169.254.1.200"))
    XCTAssertNil(DHCPRangeFields.fields(start: "10.0.1.200", end: "10.0.1.2"))
    XCTAssertNil(DHCPRangeFields.range(prefix: "10.0", subnet: "1", startHost: "2", endHost: "999"))
    XCTAssertNil(DHCPRangeFields.range(prefix: "10.0", subnet: "", startHost: "2", endHost: "200"))
    XCTAssertNil(DHCPRangeFields.range(prefix: "10.0", subnet: "1", startHost: "200", endHost: "2"))
  }

  func testNetworkOptionsSaveRejectsInvalidSegmentedDHCPRange() {
    XCTAssertTrue(
      NetworkOptionsSheet.canSave(
        dhcpRangePrefix: "10.0",
        dhcpRangeSubnet: "1",
        dhcpRangeStartHost: "2",
        dhcpRangeEndHost: "200"))
    XCTAssertFalse(
      NetworkOptionsSheet.canSave(
        dhcpRangePrefix: "10.0",
        dhcpRangeSubnet: "1",
        dhcpRangeStartHost: "2",
        dhcpRangeEndHost: "999"))
    XCTAssertFalse(
      NetworkOptionsSheet.canSave(
        dhcpRangePrefix: "10.0",
        dhcpRangeSubnet: "",
        dhcpRangeStartHost: "2",
        dhcpRangeEndHost: "200"))
    XCTAssertFalse(
      NetworkOptionsSheet.canSave(
        dhcpRangePrefix: "10.0",
        dhcpRangeSubnet: "1",
        dhcpRangeStartHost: "200",
        dhcpRangeEndHost: "2"))
  }

  func testWirelessFlagsIncludeOptionsAndPasswordValidation() {
    let model = AirportAppModel()
    model.wireless.networkName = "Network"
    model.markClean()
    model.wireless.password = "secret"
    model.wireless.verifyPassword = "secret"
    model.wireless.regionCode = "0"
    model.wireless.hiddenNetwork = true
    model.wireless.radioMode = "80211n-bg"
    model.wireless.radioChannel = "automatic"

    let flags = model.wirelessFlags()
    XCTAssertEqual(
      flags?.map(\.0),
      [
        "--wireless-mode",
        "--wireless-name",
        "--wireless-security",
        "--no-allow-network-extension",
        "--wireless-password",
        "--region-code",
        "--hidden-network",
        "--radio-mode",
        "--radio-channel",
      ])
  }

  func testWirelessFlagsIncludeWDSPeers() {
    let model = AirportAppModel()
    detectInternetOptionsSupport(model, supportsClassicWDS: true)
    model.wireless.mode = "wds"
    model.wireless.networkName = "Network"
    model.wireless.security = "none"
    model.wireless.wdsPeerAirPortIDs = "00:21:E9:B9:2E:C3"
    model.markClean()
    model.wireless.wdsPeerAirPortIDs = "00:1B:63:21:F5:8F"

    let flags = model.wirelessFlags(changesOnly: true)
    XCTAssertEqual(flags?.map(\.0), ["--wds-peer-airport-id"])
    XCTAssertEqual(flags?.map(\.1), ["00:1B:63:21:F5:8F"])
  }

  func testWirelessFlagsIncludeWDSMode() {
    let model = AirportAppModel()
    detectInternetOptionsSupport(model, supportsClassicWDS: true)
    model.wireless.mode = "wds"
    model.wireless.networkName = "Network"
    model.wireless.security = "none"
    model.wireless.wdsPeerAirPortIDs = "00:21:E9:B9:2E:C3"
    model.markClean()
    model.wireless.wdsMode = "main"

    let flags = model.wirelessFlags(changesOnly: true)
    XCTAssertEqual(flags?.map(\.0), ["--wds-mode"])
    XCTAssertEqual(flags?.map(\.1), ["main"])
  }

  func testWirelessFlagsRejectInvalidWDSPeers() {
    let model = AirportAppModel()
    detectInternetOptionsSupport(model, supportsClassicWDS: true)
    model.wireless.mode = "wds"
    model.wireless.networkName = "Network"
    model.wireless.security = "none"
    model.wireless.wdsPeerAirPortIDs = "not-a-mac"

    XCTAssertNil(model.wirelessFlags())
    XCTAssertEqual(model.status, "WDS peer AirPort IDs must be one or two MAC addresses.")
  }

  func testWirelessRegionCodeMustBeInRangeWhenProvided() {
    let model = AirportAppModel()
    model.wireless.networkName = "Network"
    model.wireless.regionCode = "300"

    XCTAssertNil(model.wirelessFlags())
    XCTAssertEqual(model.status, "Region code must be between 0 and 255.")
  }

  func testWirelessRadioChannelMustBeAutomaticOrChannelNumber() {
    let model = AirportAppModel()
    model.wireless.networkName = "Network"
    model.wireless.radioChannel = "channel 11"

    XCTAssertNil(model.wirelessFlags())
    XCTAssertEqual(model.status, "Radio channel must be 'automatic' or a channel number.")
  }

  func testWirelessOptionValuesMustBeSupported() {
    let model = AirportAppModel()
    model.wireless.mode = "roam"

    XCTAssertNil(model.wirelessFlags())
    XCTAssertEqual(model.status, "Wireless Mode must be create, extend, off.")

    model.wireless.mode = "create"
    model.wireless.networkName = "Network"
    model.wireless.security = "wpa3-personal"

    XCTAssertNil(model.wirelessFlags())
    XCTAssertEqual(model.status, "Wireless Security is not supported.")

    model.wireless.security = "wpa2-personal"
    model.wireless.password = "password"
    model.wireless.verifyPassword = "password"
    model.wireless.radioMode = "80211ax"

    XCTAssertNil(model.wirelessFlags())
    XCTAssertEqual(model.status, "Radio Mode is not supported.")
  }

  func testWirelessSecurityMenuMatchesAirPortUtilityVisibleOptions() {
    XCTAssertEqual(
      WirelessSecurityOption.allCases.map(\.label),
      [
        "None",
        "WEP 40-bit",
        "WEP (Transitional Security Network)",
        "WPA Personal",
        "WPA/WPA2 Personal",
        "WPA2 Personal",
        "WPA/WPA2 Enterprise",
        "WPA2 Enterprise",
      ])
    XCTAssertEqual(
      WirelessSecurityOption.allCases.map(\.rawValue),
      [
        "none",
        "wep-40",
        "wep-128",
        "wpa-personal",
        "wpa-wpa2-personal",
        "wpa2-personal",
        "wpa-wpa2-enterprise",
        "wpa2-enterprise",
      ])
  }

  func testUnchangedUnsupportedChoiceValuesDoNotBlockRelatedPaneChanges() {
    let internetModel = AirportAppModel()
    internetModel.internet.configureIPv6 = "native"
    internetModel.markClean()
    internetModel.internet.domainName = "example.test"

    XCTAssertEqual(internetModel.internetFlags(changesOnly: true)?.map(\.0), ["--domain-name"])

    let wirelessModel = AirportAppModel()
    wirelessModel.wireless.networkName = "Network"
    wirelessModel.wireless.security = "wpa3-personal"
    wirelessModel.wireless.radioMode = "80211ax"
    wirelessModel.markClean()
    wirelessModel.wireless.networkName = "Network 2"

    XCTAssertEqual(wirelessModel.wirelessFlags(changesOnly: true)?.map(\.0), ["--wireless-name"])

    let disksModel = AirportAppModel()
    disksModel.disks.secureSharedDisks = "unknown-mode"
    disksModel.disks.guestAccess = "admin-only"
    disksModel.markClean()
    disksModel.disks.winsServer = "192.168.1.30"

    XCTAssertEqual(disksModel.diskSharingFlags(changesOnly: true)?.map(\.0), ["--wins-server"])
  }

  func testUnchangedInvalidWirelessOptionsDoNotBlockChangedWirelessName() {
    let model = AirportAppModel()
    model.wireless.networkName = "Network"
    model.wireless.regionCode = "300"
    model.wireless.radioChannel = "channel 11"
    model.markClean()

    model.wireless.networkName = "Network 2"

    XCTAssertEqual(model.wirelessFlags(changesOnly: true)?.map(\.0), ["--wireless-name"])
  }

  func testWirelessPasswordFlagTrimsOutgoingValue() {
    let model = AirportAppModel()
    model.wireless.networkName = "Network"
    model.wireless.security = "wpa2-personal"
    model.wireless.password = " wifi-secret "
    model.wireless.verifyPassword = "wifi-secret"

    XCTAssertTrue(
      model.wirelessFlags()?.contains { $0 == ("--wireless-password", "wifi-secret") } == true)
  }

  func testWirelessFlagsUseNormalizedModeAndSecurityForPasswordDecisions() {
    let model = AirportAppModel()
    model.wireless.mode = " create "
    model.wireless.networkName = "Network"
    model.wireless.security = " wpa2-personal "
    model.wireless.password = "wifi-secret"
    model.wireless.verifyPassword = "wifi-secret"

    XCTAssertTrue(
      model.wirelessFlags()?.contains { $0 == ("--wireless-password", "wifi-secret") } == true)

    model.wireless.mode = " off "
    model.wireless.password = ""
    model.wireless.verifyPassword = ""

    XCTAssertFalse(model.wirelessFlags()?.contains { $0.0 == "--wireless-password" } == true)
  }

  func testWirelessNumericFormattingOnlyChangesDoNotCreatePendingChanges() {
    let model = AirportAppModel()
    model.wireless.mode = "create"
    model.wireless.networkName = "Network"
    model.wireless.regionCode = "1"
    model.wireless.radioChannel = "11"
    model.markClean()

    model.wireless.regionCode = "001"
    model.wireless.radioChannel = "011"

    XCTAssertFalse(model.hasPendingChanges)
    XCTAssertEqual(model.wirelessFlags(changesOnly: true)?.count, 0)
  }

  func testWirelessNumericValueChangesRemainPending() {
    let model = AirportAppModel()
    model.wireless.mode = "create"
    model.wireless.networkName = "Network"
    model.wireless.regionCode = "1"
    model.wireless.radioChannel = "11"
    model.markClean()

    model.wireless.regionCode = "002"
    model.wireless.radioChannel = "012"

    XCTAssertTrue(model.hasPendingChanges)
    XCTAssertEqual(
      model.wirelessFlags(changesOnly: true)?.map(\.0),
      ["--region-code", "--radio-channel"]
    )
  }

  func testWirelessFlagsNormalizeNumericOutgoingValues() {
    let model = AirportAppModel()
    model.wireless.mode = "create"
    model.wireless.networkName = "Network"
    model.wireless.regionCode = "001"
    model.wireless.radioChannel = "011"

    let flags = model.wirelessFlags()

    XCTAssertTrue(flags?.contains { $0 == ("--region-code", "1") } == true)
    XCTAssertTrue(flags?.contains { $0 == ("--radio-channel", "11") } == true)
  }

  func testWirelessNetworkNameCannotBeEmptyWhenWirelessIsEnabled() {
    let model = AirportAppModel()
    model.wireless.mode = "create"
    model.wireless.networkName = " \n "

    XCTAssertNil(model.wirelessFlags())
    XCTAssertEqual(model.status, "Wireless Network Name cannot be empty.")
  }

  func testSwitchingToSecuredWirelessRequiresWirelessPassword() {
    let model = AirportAppModel()
    model.wireless.mode = "create"
    model.wireless.networkName = "Network"
    model.wireless.security = "none"
    model.wireless.password = ""
    model.wireless.verifyPassword = ""
    model.markClean()

    model.wireless.security = "wpa2-personal"

    XCTAssertNil(model.wirelessFlags(changesOnly: true))
    XCTAssertEqual(model.status, "Wireless Password cannot be empty.")
  }

  func testSwitchingToSecuredWirelessRewritesCachedWirelessPassword() {
    let model = AirportAppModel()
    model.wireless.mode = "create"
    model.wireless.networkName = "Network"
    model.wireless.security = "none"
    model.wireless.password = "wifi-secret"
    model.wireless.verifyPassword = "wifi-secret"
    model.markClean()

    model.wireless.security = "wpa2-personal"

    let flags = model.wirelessFlags(changesOnly: true)
    XCTAssertEqual(
      flags?.map(\.0), ["--wireless-security", "--wireless-name", "--wireless-password"])
    XCTAssertEqual(flags?.compactMap(\.1), ["wpa2-personal", "Network", "wifi-secret"])
  }

  func testChangingSecuredWirelessNameRewritesCachedWirelessPassword() {
    let model = AirportAppModel()
    model.wireless.mode = "create"
    model.wireless.networkName = "Network"
    model.wireless.security = "wpa2-personal"
    model.wireless.password = "wifi-secret"
    model.wireless.verifyPassword = "wifi-secret"
    model.markClean()

    model.wireless.networkName = "Network 2"

    let flags = model.wirelessFlags(changesOnly: true)
    XCTAssertEqual(flags?.map(\.0), ["--wireless-name", "--wireless-password"])
    XCTAssertEqual(flags?.compactMap(\.1), ["Network 2", "wifi-secret"])
  }

  func testWirelessModeDefaultsRestoreCreateNetworkFromOffName() {
    var wireless = WirelessState(
      mode: "create",
      networkName: "Off",
      security: "wpa2-personal",
      password: "current-wifi",
      verifyPassword: "current-wifi"
    )

    WirelessModeDefaults.restoreIfNeeded(
      wireless: &wireless,
      previousMode: "create",
      newMode: "create"
    )

    XCTAssertEqual(wireless.networkName, "Apple Network b92ec3")
    XCTAssertEqual(wireless.security, "none")
    XCTAssertEqual(wireless.password, "")
    XCTAssertEqual(wireless.verifyPassword, "")
  }

  func testPrefilledWirelessAndDiskPasswordsAreNotRewrittenUnlessChanged() {
    let model = AirportAppModel()
    model.wireless.networkName = "Network"
    model.wireless.password = "current-wifi"
    model.wireless.verifyPassword = "current-wifi"
    model.disks.secureSharedDisks = "disk-password"
    model.disks.diskPassword = "current-disk"
    model.disks.verifyDiskPassword = "current-disk"
    model.markClean()

    model.wireless.hiddenNetwork = true
    model.disks.fileSharing = true

    XCTAssertFalse(model.wirelessFlags()?.contains { $0.0 == "--wireless-password" } == true)
    XCTAssertFalse(model.diskSharingFlags()?.contains { $0.0 == "--disk-password" } == true)

    model.wireless.password = "new-wifi"
    model.wireless.verifyPassword = "new-wifi"
    model.disks.diskPassword = "new-disk"
    model.disks.verifyDiskPassword = "new-disk"

    XCTAssertTrue(
      model.wirelessFlags()?.contains { $0.0 == "--wireless-password" && $0.1 == "new-wifi" }
        == true)
    XCTAssertTrue(
      model.diskSharingFlags()?.contains { $0.0 == "--disk-password" && $0.1 == "new-disk" } == true
    )
  }

  func testHiddenDiskPasswordMismatchDoesNotBlockDiskFlags() {
    let model = AirportAppModel()
    model.disks.secureSharedDisks = "device-password"
    model.disks.diskPassword = "hidden-password"
    model.disks.verifyDiskPassword = "different-hidden-password"
    model.disks.fileSharing = true

    let flags = model.diskSharingFlags()

    XCTAssertNotNil(flags)
    XCTAssertEqual(flags?.first { $0.0 == "--usb-file-sharing-flags" }?.1, "1104")
    XCTAssertFalse(flags?.contains { $0.0 == "--disk-password" } == true)
  }

  func testHiddenDiskPasswordEditsDoNotCreatePendingChanges() {
    let model = AirportAppModel()
    model.disks.secureSharedDisks = "device-password"
    model.disks.diskPassword = "hidden-password"
    model.disks.verifyDiskPassword = "hidden-password"
    model.markClean()

    model.disks.diskPassword = "stale"
    model.disks.verifyDiskPassword = "mismatch"

    XCTAssertFalse(model.hasPendingChanges)
    XCTAssertEqual(model.diskSharingFlags(changesOnly: true)?.count, 0)
  }

  func testActiveDiskPasswordMismatchStillBlocksDiskFlags() {
    let model = AirportAppModel()
    model.disks.secureSharedDisks = "disk-password"
    model.disks.diskPassword = "disk-secret"
    model.disks.verifyDiskPassword = "different-secret"

    XCTAssertNil(model.diskSharingFlags())
    XCTAssertEqual(model.status, "Disk passwords do not match.")
  }

  func testSwitchingToDiskPasswordRequiresDiskPassword() {
    let model = AirportAppModel()
    model.disks.secureSharedDisks = "device-password"
    model.markClean()

    model.disks.secureSharedDisks = "disk-password"
    model.disks.diskPassword = ""
    model.disks.verifyDiskPassword = ""

    XCTAssertNil(model.diskSharingFlags(changesOnly: true))
    XCTAssertEqual(model.status, "Disk Password cannot be empty.")
  }

  func testClearingExistingDiskPasswordIsBlocked() {
    let model = AirportAppModel()
    model.disks.secureSharedDisks = "disk-password"
    model.disks.diskPassword = "disk-secret"
    model.disks.verifyDiskPassword = "disk-secret"
    model.markClean()

    model.disks.diskPassword = ""
    model.disks.verifyDiskPassword = ""

    XCTAssertNil(model.diskSharingFlags(changesOnly: true))
    XCTAssertEqual(model.status, "Disk Password cannot be empty.")
  }

  func testUnchangedUnknownDiskPasswordDoesNotBlockUnrelatedDiskFlags() {
    let model = AirportAppModel()
    model.disks.secureSharedDisks = "disk-password"
    model.disks.diskPassword = ""
    model.disks.verifyDiskPassword = ""
    model.markClean()

    model.disks.guestAccess = "read-only"

    XCTAssertEqual(model.diskSharingFlags(changesOnly: true)?.map(\.0), ["--guest-disk-access"])
  }

  func testDiskPaneApplyDoesNotRewriteUnchangedUnknownDiskPasswordMode() async throws {
    setenv("AIRPORT_UTILITY_MOCK", "1", 1)
    defer { unsetenv("AIRPORT_UTILITY_MOCK") }

    let model = AirportAppModel()
    model.disks.secureSharedDisks = "disk-password"
    model.disks.diskPassword = ""
    model.disks.verifyDiskPassword = ""
    model.markClean()

    model.disks.guestAccess = "read-only"
    model.applyDiskSharing()
    try await waitForIdle(model)

    XCTAssertTrue(model.logs.contains { $0.contains("--guest-disk-access read-only") })
    XCTAssertFalse(model.logs.contains { $0.contains("--disk-security disk-password") })
    XCTAssertFalse(model.logs.contains { $0.contains("--disk-password") })
    XCTAssertFalse(model.hasPendingChanges)
  }

  func testDiskPanePreviewWithNoDiskChangesDoesNotRunBackend() {
    let model = AirportAppModel()
    model.disks.secureSharedDisks = "disk-password"
    model.disks.diskPassword = ""
    model.disks.verifyDiskPassword = ""
    model.markClean()

    model.previewDiskSharing()

    XCTAssertNil(model.preview)
    XCTAssertEqual(model.status, "No pending Disk Sharing changes to preview.")
    XCTAssertFalse(model.logs.contains { $0.hasPrefix("$ ") })
  }

  func testUnchangedInvalidWINSServerDoesNotBlockUnrelatedDiskFlags() {
    let model = AirportAppModel()
    model.disks.winsServer = "wins.local"
    model.markClean()

    model.disks.guestAccess = "read-only"

    XCTAssertEqual(model.diskSharingFlags(changesOnly: true)?.map(\.0), ["--guest-disk-access"])
  }

  func testActiveDiskPasswordEditsStillCreatePendingChanges() {
    let model = AirportAppModel()
    model.disks.secureSharedDisks = "disk-password"
    model.disks.diskPassword = "disk-secret"
    model.disks.verifyDiskPassword = "disk-secret"
    model.markClean()

    model.disks.diskPassword = "new-disk-secret"
    model.disks.verifyDiskPassword = "new-disk-secret"

    XCTAssertTrue(model.hasPendingChanges)
    XCTAssertTrue(
      model.diskSharingFlags(changesOnly: true)?.contains {
        $0 == ("--disk-password", "new-disk-secret")
      } == true)
  }

  func testDiskPasswordFlagTrimsOutgoingValue() {
    let model = AirportAppModel()
    model.disks.secureSharedDisks = "disk-password"
    model.disks.diskPassword = " disk-secret "
    model.disks.verifyDiskPassword = "disk-secret"

    XCTAssertTrue(
      model.diskSharingFlags()?.contains { $0 == ("--disk-password", "disk-secret") } == true)
  }

  func testDiskFlagsUseNormalizedSecurityModeForPasswordDecisions() {
    let model = AirportAppModel()
    model.disks.secureSharedDisks = " disk-password "
    model.disks.diskPassword = "disk-secret"
    model.disks.verifyDiskPassword = "disk-secret"

    XCTAssertTrue(
      model.diskSharingFlags()?.contains { $0 == ("--disk-password", "disk-secret") } == true)

    model.markClean()
    model.disks.diskPassword = ""
    model.disks.verifyDiskPassword = ""

    XCTAssertNil(model.diskSharingFlags(changesOnly: true))
    XCTAssertEqual(model.status, "Disk Password cannot be empty.")
  }

  func testWINSServerMustBeValidIPv4WhenProvided() {
    let model = AirportAppModel()
    model.disks.winsServer = "wins.local"

    XCTAssertNil(model.diskSharingFlags())
    XCTAssertEqual(model.status, "WINS Server must be an IPv4 address.")
  }

  func testWINSServerRejectsLeadingZeroOctets() {
    let model = AirportAppModel()
    model.disks.winsServer = "192.168.001.30"

    XCTAssertNil(model.diskSharingFlags())
    XCTAssertEqual(model.status, "WINS Server must be an IPv4 address.")
  }

  func testDiskSharingOptionValuesMustBeSupported() {
    let model = AirportAppModel()
    model.disks.secureSharedDisks = "none"

    XCTAssertNil(model.diskSharingFlags())
    XCTAssertEqual(model.status, "Secure Shared Disks mode is not supported.")

    model.disks.secureSharedDisks = "device-password"
    model.disks.guestAccess = "admin-only"

    XCTAssertNil(model.diskSharingFlags())
    XCTAssertEqual(model.status, "Guest Disk Access is not supported.")
  }

  func testClearingWINSServerIsAllowed() {
    let model = AirportAppModel()
    model.disks.winsServer = "192.168.1.30"
    model.markClean()
    model.disks.winsServer = ""

    XCTAssertEqual(model.diskSharingFlags(changesOnly: true)?.map(\.0), ["--wins-server"])
  }

  func testMockPreviewOutputReportsSensitiveSettingKeysWithoutValues() {
    let args = AirportCommand.friendlyWrite(
      connection: AirportConnection(host: "time-capsule.local", password: "secret"),
      flags: [
        ("--wireless-password", "wifi-secret"),
        ("--global-hostname-password", "host-secret"),
      ],
      dryRun: true
    )

    let output = AirportMockBackend.output(for: args, dryRun: true)

    XCTAssertTrue(output.contains("raCr/raWE"))
    XCTAssertTrue(output.contains("wbHP"))
    XCTAssertFalse(output.contains("wifi-secret"))
    XCTAssertFalse(output.contains("host-secret"))
  }

  func testMockPreviewOutputReportsClearDNSKeys() {
    let args = AirportCommand.friendlyWrite(
      connection: AirportConnection(host: "time-capsule.local", password: "secret"),
      flags: [
        ("--clear-dns", nil),
        ("--clear-ipv6-dns", nil),
      ],
      dryRun: true
    )

    let output = AirportMockBackend.output(for: args, dryRun: true)

    XCTAssertTrue(output.contains("waD1/waD2"))
    XCTAssertTrue(output.contains("6NS1/6NS2"))
    XCTAssertFalse(output.contains("syNm"))
  }

  func testNetworkAndDiskFlagsIncludeVisibleFields() {
    let model = AirportAppModel()
    model.network.routerMode = .dhcpAndNat
    model.network.dhcpRangeStart = "10.0.0.2"
    model.network.dhcpRangeEnd = "10.0.0.200"
    model.network.natPMP = true
    model.network.dhcpLease = "1"
    model.network.dhcpLeaseUnit = "days"
    model.network.defaultHost = "10.0.0.10"

    XCTAssertEqual(
      model.networkFlags()?.map(\.0),
      [
        "--router-mode",
        "--dhcp-range-start",
        "--dhcp-range-end",
        "--dhcp-lease",
        "--dhcp-lease-unit",
        "--nat-pmp",
        "--default-host",
      ])

    model.disks.fileSharing = true
    model.disks.secureSharedDisks = "disk-password"
    model.disks.guestAccess = "not-allowed"
    model.disks.shareOverWAN = true
    model.disks.diskPassword = "disk-secret"

    model.disks.verifyDiskPassword = "disk-secret"

    XCTAssertTrue(
      model.diskSharingFlags()?.contains { $0.0 == "--disk-password" && $0.1 == "disk-secret" }
        == true)
  }

  func testNetworkFlagsSkipInactiveRouterModeFields() {
    let model = AirportAppModel()
    model.network.routerMode = .bridge
    model.network.dhcpRangeStart = "10.0.0.2"
    model.network.dhcpRangeEnd = "10.0.0.200"
    model.network.natPMP = true
    model.network.dhcpLease = "12"
    model.network.defaultHost = "10.0.0.10"

    XCTAssertEqual(model.networkFlags()?.map(\.0), ["--router-mode"])

    model.network.routerMode = .dhcpOnly
    let dhcpOnlyFlags = model.networkFlags()?.map(\.0) ?? []
    XCTAssertTrue(dhcpOnlyFlags.contains("--dhcp-range-start"))
    XCTAssertTrue(dhcpOnlyFlags.contains("--dhcp-lease"))
    XCTAssertFalse(dhcpOnlyFlags.contains("--nat-pmp"))
    XCTAssertFalse(dhcpOnlyFlags.contains("--default-host"))

    model.network.routerMode = .natOnly
    let natOnlyFlags = model.networkFlags()?.map(\.0) ?? []
    XCTAssertTrue(natOnlyFlags.contains("--nat-pmp"))
    XCTAssertTrue(natOnlyFlags.contains("--default-host"))
    XCTAssertFalse(natOnlyFlags.contains("--dhcp-range-start"))
    XCTAssertFalse(natOnlyFlags.contains("--dhcp-lease"))
  }

  func testChangedNetworkModeDoesNotWriteStaleHiddenFields() {
    let model = AirportAppModel()
    model.network.routerMode = .dhcpAndNat
    model.network.dhcpRangeStart = "10.0.0.2"
    model.network.dhcpRangeEnd = "10.0.0.200"
    model.network.natPMP = true
    model.network.dhcpLease = "12"
    model.network.defaultHost = "10.0.0.10"
    model.markClean()

    model.network.routerMode = .bridge

    XCTAssertEqual(model.networkFlags(changesOnly: true)?.map(\.0), ["--router-mode"])
  }

  func testHiddenNetworkFieldsDoNotCreatePendingChangesWhenInactive() {
    let bridgeModel = AirportAppModel()
    bridgeModel.network.routerMode = .bridge
    bridgeModel.network.dhcpRangeStart = "10.0.0.2"
    bridgeModel.network.dhcpRangeEnd = "10.0.0.200"
    bridgeModel.network.dhcpLease = "12"
    bridgeModel.network.dhcpLeaseUnit = "hours"
    bridgeModel.network.natPMP = true
    bridgeModel.network.defaultHost = "10.0.0.10"
    bridgeModel.markClean()

    bridgeModel.network.dhcpRangeStart = "10.0.1.2"
    bridgeModel.network.dhcpRangeEnd = "10.0.1.200"
    bridgeModel.network.dhcpLease = "1"
    bridgeModel.network.dhcpLeaseUnit = "days"
    bridgeModel.network.natPMP = false
    bridgeModel.network.defaultHost = "10.0.1.10"

    XCTAssertFalse(bridgeModel.hasPendingChanges)
    XCTAssertEqual(bridgeModel.networkFlags(changesOnly: true)?.count, 0)

    let dhcpOnlyModel = AirportAppModel()
    dhcpOnlyModel.network.routerMode = .dhcpOnly
    dhcpOnlyModel.network.dhcpRangeStart = "10.0.0.2"
    dhcpOnlyModel.network.dhcpRangeEnd = "10.0.0.200"
    dhcpOnlyModel.network.dhcpLease = "12"
    dhcpOnlyModel.network.natPMP = true
    dhcpOnlyModel.network.defaultHost = "10.0.0.10"
    dhcpOnlyModel.markClean()

    dhcpOnlyModel.network.natPMP = false
    dhcpOnlyModel.network.defaultHost = "10.0.1.10"

    XCTAssertFalse(dhcpOnlyModel.hasPendingChanges)
    XCTAssertEqual(dhcpOnlyModel.networkFlags(changesOnly: true)?.count, 0)

    let natOnlyModel = AirportAppModel()
    natOnlyModel.network.routerMode = .natOnly
    natOnlyModel.network.dhcpRangeStart = "10.0.0.2"
    natOnlyModel.network.dhcpRangeEnd = "10.0.0.200"
    natOnlyModel.network.dhcpLease = "12"
    natOnlyModel.network.dhcpLeaseUnit = "hours"
    natOnlyModel.markClean()

    natOnlyModel.network.dhcpRangeStart = "10.0.1.2"
    natOnlyModel.network.dhcpRangeEnd = "10.0.1.200"
    natOnlyModel.network.dhcpLease = "1"
    natOnlyModel.network.dhcpLeaseUnit = "days"

    XCTAssertFalse(natOnlyModel.hasPendingChanges)
    XCTAssertEqual(natOnlyModel.networkFlags(changesOnly: true)?.count, 0)
  }

  func testLANIPAddressCreatesPendingNetworkChange() {
    let model = AirportAppModel()
    model.network.lanIPAddress = "10.0.1.1"
    model.markClean()

    model.network.lanIPAddress = "192.168.4.1"

    XCTAssertTrue(model.hasPendingChanges)
    XCTAssertEqual(
      model.networkFlags(changesOnly: true)?.map { "\($0.0)=\($0.1 ?? "")" },
      ["--lan-ip-address=192.168.4.1"])
  }

  func testDHCPLeaseFormattingOnlyChangesDoNotCreatePendingChanges() {
    let model = AirportAppModel()
    model.network.routerMode = .dhcpAndNat
    model.network.dhcpRangeStart = "10.0.0.2"
    model.network.dhcpRangeEnd = "10.0.0.200"
    model.network.dhcpLease = "1"
    model.network.dhcpLeaseUnit = "hour"
    model.markClean()

    model.network.dhcpLease = "01"
    model.network.dhcpLeaseUnit = "hours"

    XCTAssertFalse(model.hasPendingChanges)
    XCTAssertEqual(model.networkFlags(changesOnly: true)?.count, 0)
  }

  func testDHCPLeaseValueChangesRemainPending() {
    let model = AirportAppModel()
    model.network.routerMode = .dhcpAndNat
    model.network.dhcpRangeStart = "10.0.0.2"
    model.network.dhcpRangeEnd = "10.0.0.200"
    model.network.dhcpLease = "1"
    model.network.dhcpLeaseUnit = "hour"
    model.markClean()

    model.network.dhcpLease = "2"
    model.network.dhcpLeaseUnit = "hours"

    XCTAssertTrue(model.hasPendingChanges)
    XCTAssertEqual(model.networkFlags(changesOnly: true)?.map(\.0), ["--dhcp-lease"])
  }

  func testNetworkFlagsNormalizeDHCPLeaseOutgoingValues() {
    let model = AirportAppModel()
    model.network.routerMode = .dhcpAndNat
    model.network.dhcpRangeStart = "10.0.0.2"
    model.network.dhcpRangeEnd = "10.0.0.200"
    model.network.dhcpLease = "01"
    model.network.dhcpLeaseUnit = "hour"

    let flags = model.networkFlags()

    XCTAssertTrue(flags?.contains { $0 == ("--dhcp-lease", "1") } == true)
    XCTAssertTrue(flags?.contains { $0 == ("--dhcp-lease-unit", "hours") } == true)
  }

  func testNetworkDefaultHostFlagTrimsOutgoingValue() {
    let model = AirportAppModel()
    model.network.routerMode = .dhcpAndNat
    model.network.dhcpRangeStart = "10.0.0.2"
    model.network.dhcpRangeEnd = "10.0.0.200"
    model.network.defaultHost = " 10.0.0.10 "

    XCTAssertTrue(model.networkFlags()?.contains { $0 == ("--default-host", "10.0.0.10") } == true)
  }

  func testChangedNetworkFlagsOnlyClearDefaultHostWhenChanged() {
    let model = AirportAppModel()
    model.network.routerMode = .dhcpAndNat
    model.network.dhcpRangeStart = "10.0.0.2"
    model.network.dhcpRangeEnd = "10.0.0.200"
    model.network.defaultHost = ""
    model.markClean()

    model.network.natPMP = true

    XCTAssertEqual(model.networkFlags(changesOnly: true)?.map(\.0), ["--nat-pmp"])

    model.network.defaultHost = "10.0.0.10"
    model.markClean()
    model.network.defaultHost = ""

    XCTAssertEqual(model.networkFlags(changesOnly: true)?.map(\.0), ["--clear-default-host"])
  }

  func testNetworkDHCPRangeBeginningCannotBeEmptyWhenDHCPIsEnabled() {
    let model = AirportAppModel()
    model.network.routerMode = .dhcpAndNat
    model.network.dhcpRangeStart = " "

    XCTAssertNil(model.networkFlags())
    XCTAssertEqual(model.status, "DHCP Range Beginning cannot be empty.")
  }

  func testNetworkDHCPRangeBeginningMustBeValidIPv4() {
    let model = AirportAppModel()
    model.network.routerMode = .dhcpAndNat
    model.network.dhcpRangeStart = "10.0.0.999"
    model.network.dhcpRangeEnd = "10.0.0.200"
    model.network.dhcpLease = "1"

    XCTAssertNil(model.networkFlags())
    XCTAssertEqual(model.status, "DHCP Range Beginning must be an IPv4 address.")
  }

  func testNetworkDHCPRangeEndingCannotBeEmptyWhenDHCPIsEnabled() {
    let model = AirportAppModel()
    model.network.routerMode = .dhcpOnly
    model.network.dhcpRangeStart = "10.0.0.2"
    model.network.dhcpRangeEnd = " "

    XCTAssertNil(model.networkFlags())
    XCTAssertEqual(model.status, "DHCP Range Ending cannot be empty.")
  }

  func testNetworkDHCPRangeEndingMustBeValidIPv4() {
    let model = AirportAppModel()
    model.network.routerMode = .dhcpOnly
    model.network.dhcpRangeStart = "10.0.0.2"
    model.network.dhcpRangeEnd = "10.0.0.999"
    model.network.dhcpLease = "1"

    XCTAssertNil(model.networkFlags())
    XCTAssertEqual(model.status, "DHCP Range Ending must be an IPv4 address.")
  }

  func testNetworkDHCPRangeMustUseSameSupportedSubnet() {
    let model = AirportAppModel()
    model.network.routerMode = .dhcpOnly
    model.network.dhcpRangeStart = "10.0.1.2"
    model.network.dhcpRangeEnd = "10.0.2.200"
    model.network.dhcpLease = "1"

    XCTAssertNil(model.networkFlags())
    XCTAssertEqual(
      model.status,
      "DHCP Range Beginning and Ending must use the same supported private subnet, with Ending not before Beginning."
    )

    model.network.dhcpRangeEnd = "169.254.1.200"

    XCTAssertNil(model.networkFlags())
    XCTAssertEqual(
      model.status,
      "DHCP Range Beginning and Ending must use the same supported private subnet, with Ending not before Beginning."
    )
  }

  func testNetworkDHCPRangeEndingCannotBeBeforeBeginning() {
    let model = AirportAppModel()
    model.network.routerMode = .dhcpAndNat
    model.network.dhcpRangeStart = "192.168.4.200"
    model.network.dhcpRangeEnd = "192.168.4.2"
    model.network.dhcpLease = "1"

    XCTAssertNil(model.networkFlags())
    XCTAssertEqual(
      model.status,
      "DHCP Range Beginning and Ending must use the same supported private subnet, with Ending not before Beginning."
    )
  }

  func testNetworkDHCPLeaseCannotBeEmptyWhenDHCPIsEnabled() {
    let model = AirportAppModel()
    model.network.routerMode = .dhcpAndNat
    model.network.dhcpRangeStart = "10.0.0.2"
    model.network.dhcpRangeEnd = "10.0.0.200"
    model.network.dhcpLease = " "

    XCTAssertNil(model.networkFlags())
    XCTAssertEqual(model.status, "DHCP Lease cannot be empty.")
  }

  func testNetworkDHCPLeaseMustBeNumericWhenDHCPIsEnabled() {
    let model = AirportAppModel()
    model.network.routerMode = .dhcpAndNat
    model.network.dhcpRangeStart = "10.0.0.2"
    model.network.dhcpRangeEnd = "10.0.0.200"
    model.network.dhcpLease = "twelve"

    XCTAssertNil(model.networkFlags())
    XCTAssertEqual(model.status, "DHCP Lease must be a positive number.")
  }

  func testNetworkDHCPLeaseMustBePositiveWhenDHCPIsEnabled() {
    let model = AirportAppModel()
    model.network.routerMode = .dhcpAndNat
    model.network.dhcpRangeStart = "10.0.0.2"
    model.network.dhcpRangeEnd = "10.0.0.200"
    model.network.dhcpLease = "0"

    XCTAssertNil(model.networkFlags())
    XCTAssertEqual(model.status, "DHCP Lease must be a positive number.")
  }

  func testNetworkDHCPLeaseAcceptsTenYearDurationLimit() {
    let model = AirportAppModel()
    model.network.routerMode = .dhcpAndNat
    model.network.dhcpRangeStart = "10.0.0.2"
    model.network.dhcpRangeEnd = "10.0.0.200"
    model.network.dhcpLease = "3650"
    model.network.dhcpLeaseUnit = "days"

    XCTAssertNotNil(model.networkFlags())
  }

  func testNetworkDHCPLeaseMustFitBackendDurationLimit() {
    let model = AirportAppModel()
    model.network.routerMode = .dhcpAndNat
    model.network.dhcpRangeStart = "10.0.0.2"
    model.network.dhcpRangeEnd = "10.0.0.200"
    model.network.dhcpLease = "522"
    model.network.dhcpLeaseUnit = "weeks"

    XCTAssertNil(model.networkFlags())
    XCTAssertEqual(model.status, "DHCP Lease duration must be between 1 second and 10 years.")
  }

  func testNetworkDHCPLeaseRejectsOverflowingDuration() {
    let model = AirportAppModel()
    model.network.routerMode = .dhcpAndNat
    model.network.dhcpRangeStart = "10.0.0.2"
    model.network.dhcpRangeEnd = "10.0.0.200"
    model.network.dhcpLease = String(Int.max)
    model.network.dhcpLeaseUnit = "weeks"

    XCTAssertNil(model.networkFlags())
    XCTAssertEqual(model.status, "DHCP Lease duration must be between 1 second and 10 years.")
  }

  func testNetworkDHCPLeaseUnitMustBeSupportedWhenDHCPIsEnabled() {
    let model = AirportAppModel()
    model.network.routerMode = .dhcpAndNat
    model.network.dhcpRangeStart = "10.0.0.2"
    model.network.dhcpRangeEnd = "10.0.0.200"
    model.network.dhcpLease = "1"
    model.network.dhcpLeaseUnit = "fortnights"

    XCTAssertNil(model.networkFlags())
    XCTAssertEqual(model.status, "DHCP Lease unit is not supported.")
  }

  func testNetworkNATOnlyDoesNotRequireDHCPRangeFields() {
    let model = AirportAppModel()
    model.network.routerMode = .natOnly
    model.network.dhcpRangeStart = ""
    model.network.dhcpRangeEnd = ""
    model.network.dhcpLease = ""

    XCTAssertNotNil(model.networkFlags())
  }

  func testNetworkDefaultHostMustBeValidIPv4() {
    let model = AirportAppModel()
    model.network.routerMode = .dhcpAndNat
    model.network.dhcpRangeStart = "10.0.0.2"
    model.network.dhcpRangeEnd = "10.0.0.200"
    model.network.dhcpLease = "1"
    model.network.defaultHost = "host.local"

    XCTAssertNil(model.networkFlags())
    XCTAssertEqual(model.status, "Default Host must be an IPv4 address.")
  }

  func testWirelessOffDoesNotWriteSyntheticOffNetworkName() {
    let model = AirportAppModel()
    model.wireless.mode = "create"
    model.wireless.networkName = "Network"
    model.markClean()

    model.wireless.mode = "off"
    model.wireless.networkName = "Off"

    XCTAssertEqual(model.wirelessFlags(changesOnly: true)?.map(\.0), ["--wireless-mode"])
  }

  func testWirelessOffDoesNotWriteHiddenOptionFields() {
    let model = AirportAppModel()
    model.wireless.mode = "create"
    model.wireless.networkName = "Network"
    model.wireless.security = "wpa2-personal"
    model.wireless.regionCode = "0"
    model.wireless.hiddenNetwork = true
    model.wireless.radioMode = "80211n-bg"
    model.wireless.radioChannel = "automatic"
    model.markClean()

    model.wireless.mode = "off"
    model.wireless.networkName = "Off"
    model.wireless.security = "none"
    model.wireless.regionCode = "1"
    model.wireless.hiddenNetwork = false
    model.wireless.radioMode = "80211a"
    model.wireless.radioChannel = "11"

    XCTAssertEqual(model.wirelessFlags(changesOnly: true)?.map(\.0), ["--wireless-mode"])
  }

  func testHiddenWirelessFieldsDoNotCreatePendingChanges() {
    let model = AirportAppModel()
    model.wireless.mode = "off"
    model.wireless.networkName = "Off"
    model.wireless.security = "wpa2-personal"
    model.wireless.password = "hidden-password"
    model.wireless.verifyPassword = "hidden-password"
    model.wireless.regionCode = "0"
    model.wireless.hiddenNetwork = true
    model.wireless.radioMode = "80211n-bg"
    model.wireless.radioChannel = "automatic"
    model.markClean()

    model.wireless.networkName = "Hidden Network"
    model.wireless.security = "none"
    model.wireless.password = "stale"
    model.wireless.verifyPassword = "mismatch"
    model.wireless.regionCode = "1"
    model.wireless.hiddenNetwork = false
    model.wireless.radioMode = "80211a"
    model.wireless.radioChannel = "11"

    XCTAssertFalse(model.hasPendingChanges)
    XCTAssertEqual(model.wirelessFlags(changesOnly: true)?.count, 0)
  }

  func testWirelessSecurityNoneIgnoresHiddenPasswordEdits() {
    let model = AirportAppModel()
    model.wireless.mode = "create"
    model.wireless.networkName = "Network"
    model.wireless.security = "none"
    model.wireless.password = ""
    model.wireless.verifyPassword = ""
    model.markClean()

    model.wireless.password = "stale"
    model.wireless.verifyPassword = "mismatch"

    XCTAssertFalse(model.hasPendingChanges)
    XCTAssertEqual(model.wirelessFlags(changesOnly: true)?.count, 0)
  }

  func testWhitespaceOnlyWirelessPasswordEditDoesNotCreatePendingChanges() {
    let model = AirportAppModel()
    model.wireless.mode = "create"
    model.wireless.networkName = "Network"
    model.wireless.security = "wpa2-personal"
    model.wireless.password = "wifi-secret"
    model.wireless.verifyPassword = "wifi-secret"
    model.markClean()

    model.wireless.password = " wifi-secret "
    model.wireless.verifyPassword = "wifi-secret"

    XCTAssertFalse(model.hasPendingChanges)
    XCTAssertEqual(model.wirelessFlags(changesOnly: true)?.count, 0)
  }

  private func commandLines(in model: AirportAppModel) -> [String] {
    model.logs.compactMap { entry in
      guard entry.hasPrefix("$ ") else { return nil }
      let firstLine =
        entry.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        .first
        .map(String.init) ?? entry
      return String(firstLine.dropFirst(2))
    }
  }

  private func onlyCommandLine(
    in model: AirportAppModel,
    file: StaticString = #filePath,
    line: UInt = #line
  ) -> String? {
    let commands = commandLines(in: model)
    XCTAssertEqual(commands.count, 1, commands.joined(separator: "\n"), file: file, line: line)
    return commands.first
  }

  private func assertCommand(
    _ command: String,
    contains fragments: [String],
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    for fragment in fragments {
      XCTAssertTrue(
        command.contains(fragment),
        "Expected command to contain \(fragment), got:\n\(command)",
        file: file,
        line: line)
    }
  }

  private func waitForIdle(_ model: AirportAppModel) async throws {
    for _ in 0..<3000 where model.isBusy {
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTAssertFalse(model.isBusy)
  }

  private func waitForStatus(_ model: AirportAppModel, _ status: String) async throws {
    for _ in 0..<300 where model.status != status {
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTAssertEqual(model.status, status)
  }

  private func backendScriptURL(in directory: URL) throws -> URL {
    let backendDirectory = directory.appendingPathComponent("backend", isDirectory: true)
    try FileManager.default.createDirectory(at: backendDirectory, withIntermediateDirectories: true)
    return backendDirectory.appendingPathComponent("airport_backend.py")
  }

  private func makeFirmwareInstallScriptRepo(
    reportedVersion: String,
    readFailuresBeforeVersion: Int = 0,
    firmwareUploadResultJSON: String? = PaneFlagTests.defaultFirmwareUploadResultJSON
  ) throws -> (
    directory: URL, writeLog: URL
  ) {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("airport-firmware-install-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let backendScript = try backendScriptURL(in: directory)
    let writeLog = directory.appendingPathComponent("firmware-write.log")
    let uploadResultOutput: String
    if let firmwareUploadResultJSON {
      uploadResultOutput = """
        echo "firmware-upload result:"
        cat <<'JSON'
        \(firmwareUploadResultJSON)
        JSON
        """
    } else {
      uploadResultOutput = ""
    }

    try """
    #!/bin/sh
    command="$1"
    shift
    case "$command" in
      write)
        printf '%s\\n' "$command $*" >> firmware-write.log
        echo "firmware-upload options:"
        echo '{"source":"test.basebinary"}'
        echo 'firmware-upload progress: {"complete":false,"current":50,"phase":"upload","total":100}'
        echo 'firmware-upload progress: {"complete":true,"current":100,"phase":"upload","total":100}'
        echo 'firmware-upload progress: {"complete":true,"current":96,"phase":"program","raw":"96/96","total":96}'
        \(uploadResultOutput)
        echo "firmware upload started: test.basebinary"
        ;;
      read)
        count_file=firmware-read-count
        count=0
        if [ -f "$count_file" ]; then
          count=$(cat "$count_file")
        fi
        if [ "$count" -lt \(readFailuresBeforeVersion) ]; then
          count=$((count + 1))
          printf '%s' "$count" > "$count_file"
          echo "base station restarting" >&2
          exit 1
        fi
        cat <<'JSON'
    {"errors":{},"settings":{"syNm":{"value":"Lab Capsule"},"sySN":{"value":"LAB-SERIAL"},"syVs":{"value":"\(reportedVersion)"},"syAP":{"value":"106"}}}
    JSON
        ;;
      *)
        echo "unexpected backend command: $command" >&2
        exit 2
        ;;
    esac
    """.write(to: backendScript, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: backendScript.path)

    return (directory, writeLog)
  }

  private func configureFirmwareInstallModel(
    _ model: AirportAppModel,
    repoDirectory: URL,
    selectedImage: FirmwareImage,
    downloadRecorder: FirmwareDownloadRecorder
  ) {
    model.connection.repoPath = repoDirectory.path
    model.connection.host = "time-capsule.local"
    model.connection.password = "password"
    model.applyAuthoritativeBaseStationIdentity(
      readName: "Lab Capsule",
      serialNumber: "LAB-SERIAL",
      version: "7.8.1",
      productID: "106")
    model.firmware.images = FirmwareCatalog.mockImages(forProductID: "106")
    model.firmware.selectedImageID = selectedImage.id
    model.firmware.hasLoadedImages = true
    let device = AirportDiscoveredDevice(
      id: "local|_airport._tcp.|Lab Capsule",
      name: "Lab Capsule",
      hostName: "time-capsule.local.",
      identifiers: ["LAB-SERIAL"],
      productID: "106")
    model.updateDiscoveredDevices([device])
    model.selectTopologyDevice(device)
    model.beginEditing()
    model.selectedPane = .firmware
    model.firmwareInstallVerificationAttempts = 2
    model.firmwareInstallVerificationDelayNanoseconds = 60_000_000_000
    model.firmwareDownloadService = FirmwareDownloadService(
      root: repoDirectory,
      download: { url, progress in
        try await downloadRecorder.download(url, progress: progress)
      })
  }

  private static let defaultFirmwareUploadResultJSON = """
    {
      "method": "property-stream",
      "progress": {
        "available": true,
        "complete": true,
        "current": 96,
        "raw": "96/96",
        "total": 96
      },
      "rebootCommand": {
        "property": "acRB",
        "sent": true
      },
      "uploadHost": "fe80::21f:f3ff:fec9:6299%en0"
    }
    """

  private func reader(_ json: String) throws -> ProfileReader {
    let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    return ProfileReader(value)
  }

  private func temporaryConfigurationURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("json")
  }
}

private final class FirmwareDownloadRecorder: @unchecked Sendable {
  private let temporaryDirectory: URL
  private let lock = NSLock()
  private var lockedRequestedLocations: [URL] = []

  var requestedLocations: [URL] {
    lock.lock()
    defer { lock.unlock() }
    return lockedRequestedLocations
  }

  init(temporaryDirectory: URL) {
    self.temporaryDirectory = temporaryDirectory
  }

  func download(
    _ location: URL,
    progress: @escaping @Sendable (Int64, Int64?) async -> Void = { _, _ in }
  ) async throws -> URL {
    record(location)
    let temporaryURL =
      temporaryDirectory
      .appendingPathComponent("download-\(UUID().uuidString)")
      .appendingPathExtension("basebinary")
    let payload = "firmware payload from \(location.absoluteString)"
    await progress(Int64(payload.utf8.count / 2), Int64(payload.utf8.count))
    try payload.write(
      to: temporaryURL,
      atomically: true,
      encoding: .utf8)
    await progress(Int64(payload.utf8.count), Int64(payload.utf8.count))
    return temporaryURL
  }

  private func record(_ location: URL) {
    lock.lock()
    lockedRequestedLocations.append(location)
    lock.unlock()
  }
}

private struct FirmwareProgressEvent: Equatable, Sendable {
  var completed: Int64
  var total: Int64?
}

private actor FirmwareProgressRecorder {
  private var recordedEvents: [FirmwareProgressEvent] = []

  var events: [FirmwareProgressEvent] {
    recordedEvents
  }

  func record(completed: Int64, total: Int64?) {
    recordedEvents.append(FirmwareProgressEvent(completed: completed, total: total))
  }
}
