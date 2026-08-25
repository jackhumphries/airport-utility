import AppKit
import XCTest

@testable import AirPortUtilityCore

@MainActor
final class WirelessClientDetailsTests: XCTestCase {
  func testModernClientDetailRowsMatchAirPortUtilityTrace() {
    let client = WirelessClient(
      macAddress: "f6:41:d9:e3:b6:17",
      ipAddress: "192.168.4.41",
      hostname: "iphone.local",
      rssi: -39,
      noise: -92,
      dataRateMbps: 866,
      phyMode: "802.11a/n/ac")

    XCTAssertEqual(
      client.detailRows,
      [
        WirelessClientDetailRow(
          label: "hardware address", value: "F6:41:D9:E3:B6:17"),
        WirelessClientDetailRow(label: "quality", value: "Excellent"),
        WirelessClientDetailRow(label: "data rate", value: "866 Mb/s"),
        WirelessClientDetailRow(label: "RSSI", value: "-39 dBm"),
        WirelessClientDetailRow(label: "SNR", value: "53 dB"),
        WirelessClientDetailRow(label: "PHY mode", value: "802.11a/n/ac"),
        WirelessClientDetailRow(label: "band", value: "5 GHz"),
      ])
  }

  func testLegacyClientUsesAvailableTraceTelemetryAndUnknownPHYMode() {
    let client = WirelessClient(
      macAddress: "74:1B:B2:F1:BB:9D",
      ipAddress: "",
      hostname: "",
      rssi: -42,
      noise: -98,
      dataRateMbps: 36,
      phyMode: nil)

    XCTAssertEqual(
      client.detailRows.map(\.value),
      [
        "74:1B:B2:F1:BB:9D",
        "Excellent",
        "36 Mb/s",
        "-42 dBm",
        "56 dB",
        "Unknown",
        "Unknown",
      ])
  }

  func testBandIsDerivedOnlyFromExclusiveBandPHYMarkers() {
    let cases: [(String?, String)] = [
      ("802.11a/n/ac", "5 GHz"),
      ("802.11b/g/n", "2.4 GHz"),
      ("802.11g", "2.4 GHz"),
      ("802.11ac", "5 GHz"),
      // 802.11n and 802.11ax are dual-band standards - ambiguous alone.
      ("802.11n", "Unknown"),
      ("802.11ax", "Unknown"),
      (nil, "Unknown"),
      ("", "Unknown"),
    ]

    for (phyMode, expectedBand) in cases {
      let client = WirelessClient(
        macAddress: "00:11:22:33:44:55",
        ipAddress: "",
        hostname: "",
        phyMode: phyMode)
      XCTAssertEqual(
        client.detailRows.last?.value, expectedBand, "phyMode \(phyMode ?? "nil")")
    }
  }

  func testSNRIsOnlyComputedWhenBothSignalAndNoiseAreKnown() {
    let withBoth = WirelessClient(
      macAddress: "00:11:22:33:44:55", ipAddress: "", hostname: "", rssi: -39, noise: -92)
    let withoutNoise = WirelessClient(
      macAddress: "00:11:22:33:44:55", ipAddress: "", hostname: "", rssi: -39)
    let withoutRSSI = WirelessClient(
      macAddress: "00:11:22:33:44:55", ipAddress: "", hostname: "", noise: -92)

    XCTAssertEqual(withBoth.detailRows[4].value, "53 dB")
    XCTAssertEqual(withoutNoise.detailRows[4].value, "Unknown")
    XCTAssertEqual(withoutRSSI.detailRows[4].value, "Unknown")
  }

  func testQualityBucketsMatchAirPortUtilityBarsForRSSI() {
    let cases = [
      (-100, "Poor"),
      (-99, "Fair"),
      (-90, "Fair"),
      (-89, "Average"),
      (-83, "Average"),
      (-82, "Good"),
      (-71, "Good"),
      (-70, "Excellent"),
      (-39, "Excellent"),
    ]

    for (rssi, expected) in cases {
      let client = WirelessClient(
        macAddress: "00:11:22:33:44:55",
        ipAddress: "",
        hostname: "",
        rssi: rssi)
      XCTAssertEqual(client.detailRows[1].value, expected, "RSSI \(rssi)")
    }
  }

  func testLegacyPositiveSignalOffsetIsDisplayedAsDBM() {
    let client = WirelessClient(
      macAddress: "74:1B:B2:F1:BB:9D",
      ipAddress: "",
      hostname: "",
      rssi: 58,
      dataRateMbps: 36)

    XCTAssertEqual(client.detailRows[1].value, "Excellent")
    XCTAssertEqual(client.detailRows[3].value, "-42 dBm")
  }

  func testOlderWirelessClientJSONDecodesWithUnknownOptionalDetails() throws {
    let client = try JSONDecoder().decode(
      WirelessClient.self,
      from: Data(
        """
        {
          "macAddress": "C8:BC:C8:30:CD:3B",
          "ipAddress": "192.168.4.41",
          "hostname": "iphone.local"
        }
        """.utf8))

    XCTAssertNil(client.rssi)
    XCTAssertNil(client.noise)
    XCTAssertNil(client.dataRateMbps)
    XCTAssertNil(client.phyMode)
    XCTAssertEqual(
      client.detailRows.map(\.value),
      [
        "C8:BC:C8:30:CD:3B",
        "Unknown",
        "Unknown",
        "Unknown",
        "Unknown",
        "Unknown",
        "Unknown",
      ])
  }

  func testDetailsContentViewWidensToShowFullMacAddress() {
    let client = WirelessClient(
      macAddress: "F6:41:D9:E3:B6:17",
      ipAddress: "",
      hostname: "",
      rssi: -39,
      noise: -92,
      dataRateMbps: 866,
      phyMode: "802.11a/n/ac")
    let view = WirelessClientDetailsContentView()

    view.configure(client: client)

    XCTAssertGreaterThan(view.frame.width, 253)
    XCTAssertEqual(view.frame.height, 159)
    let fields = view.subviews.compactMap { $0 as? NSTextField }
    XCTAssertEqual(
      fields.map(\.stringValue),
      [
        "hardware address", "F6:41:D9:E3:B6:17",
        "quality", "Excellent",
        "data rate", "866 Mb/s",
        "RSSI", "-39 dBm",
        "SNR", "53 dB",
        "PHY mode", "802.11a/n/ac",
        "band", "5 GHz",
      ])
    XCTAssertEqual(fields[0].frame.minX, 19)
    XCTAssertEqual(fields[0].frame.minY, 19)
    XCTAssertEqual(fields[0].frame.height, 16)
    XCTAssertEqual(
      fields[2].frame.minY - fields[0].frame.minY,
      DevicePopoverLayout.rowHeight)
    XCTAssertGreaterThanOrEqual(
      fields[0].frame.width,
      ceil(fields[0].intrinsicContentSize.width))
    XCTAssertEqual(fields[1].frame.minX, fields[0].frame.maxX + 6)
    XCTAssertGreaterThanOrEqual(
      fields[1].frame.width,
      ceil(fields[1].intrinsicContentSize.width))
    // Row index 6 of 7 (band) - the panel's last row.
    XCTAssertEqual(fields[12].frame.minX, 19)
    XCTAssertEqual(fields[12].frame.minY, 124)
    XCTAssertEqual(fields[12].frame.height, 16)
    XCTAssertEqual(fields[12].frame.width, fields[0].frame.width)
    XCTAssertEqual(fields[13].frame.minX, fields[12].frame.maxX + 6)
    XCTAssertEqual(fields[13].frame.width, fields[1].frame.width)
    XCTAssertEqual(
      fields[0].identifier?.rawValue,
      "popover.wirelessClients.details.label.hardware-address")
  }

  func testDetailsContentViewCapsLongValuesAndKeepsFullTooltip() {
    let longPHYMode = String(repeating: "802.11ax/", count: 80)
    let client = WirelessClient(
      macAddress: "F6:41:D9:E3:B6:17",
      ipAddress: "",
      hostname: "",
      rssi: -39,
      dataRateMbps: 866,
      phyMode: longPHYMode)
    let view = WirelessClientDetailsContentView()

    view.configure(client: client, maximumWidth: 310)

    XCTAssertEqual(view.frame.width, 310)
    let phyValue = view.subviews
      .compactMap { $0 as? NSTextField }
      .first {
        $0.identifier?.rawValue
          == "popover.wirelessClients.details.value.phy-mode"
      }
    XCTAssertEqual(phyValue?.toolTip, longPHYMode)
    if let phyValue {
      XCTAssertLessThan(
        phyValue.frame.width,
        ceil(phyValue.intrinsicContentSize.width))
    }
  }

  func testKeyboardPanelOriginUsesSourceRowInsteadOfPointer() {
    let panelSize = NSSize(width: 300, height: 124)
    let visibleFrame = NSRect(x: 0, y: 0, width: 1200, height: 800)
    let sourceRect = NSRect(x: 100, y: 400, width: 152, height: 19)
    let remotePointer = NSPoint(x: 1100, y: 50)

    let keyboardOrigin = WirelessClientDetailsLayout.panelOrigin(
      panelSize: panelSize,
      visibleFrame: visibleFrame,
      pointerLocation: remotePointer,
      sourceRect: sourceRect)
    let hoverOrigin = WirelessClientDetailsLayout.panelOrigin(
      panelSize: panelSize,
      visibleFrame: visibleFrame,
      pointerLocation: remotePointer,
      sourceRect: nil)

    XCTAssertEqual(keyboardOrigin.x, sourceRect.maxX + 12)
    XCTAssertEqual(
      keyboardOrigin.y,
      sourceRect.midY - panelSize.height / 2)
    XCTAssertNotEqual(keyboardOrigin, hoverOrigin)
  }

  func testHoverFieldReceivesPollingUpdatesWithoutChangingIdentity() {
    let original = WirelessClient(
      macAddress: "F6:41:D9:E3:B6:17",
      ipAddress: "",
      hostname: "",
      rssi: -82,
      dataRateMbps: 400)
    let field = WirelessClientHoverField(
      client: original,
      frame: NSRect(x: 0, y: 0, width: 152, height: 19))
    let updated = WirelessClient(
      macAddress: original.macAddress,
      ipAddress: "192.168.4.41",
      hostname: "iphone.local",
      rssi: -39,
      dataRateMbps: 866,
      phyMode: "802.11a/n/ac")

    field.client = updated

    XCTAssertEqual(field.client.id, original.id)
    XCTAssertEqual(field.stringValue, "iphone.local")
    XCTAssertEqual(field.toolTip, "iphone.local")
    XCTAssertEqual(field.accessibilityTitle(), "iphone.local")
    XCTAssertTrue(field.accessibilityHelp()?.contains("quality: Excellent") == true)
    XCTAssertTrue(field.accessibilityHelp()?.contains("data rate: 866 Mb/s") == true)
    XCTAssertEqual(field.client.detailRows[1].value, "Excellent")
    XCTAssertEqual(field.client.detailRows[2].value, "866 Mb/s")
  }

  func testHoverFieldSupportsKeyboardClickAndAccessibilityPresentation() throws {
    let client = WirelessClient(
      macAddress: "F6:41:D9:E3:B6:17",
      ipAddress: "",
      hostname: "a-very-long-wireless-client-name.local",
      rssi: -39,
      dataRateMbps: 866,
      phyMode: "802.11a/n/ac")
    let field = WirelessClientHoverField(
      client: client,
      frame: NSRect(x: 0, y: 0, width: 152, height: 19))
    var presentations: [(shouldPresent: Bool, immediately: Bool)] = []
    field.presentationChanged = { _, shouldPresent, immediately in
      presentations.append((shouldPresent, immediately))
    }

    XCTAssertTrue(field.acceptsFirstResponder)
    XCTAssertEqual(field.accessibilityRole(), .button)
    XCTAssertEqual(field.accessibilityTitle(), client.hostname)
    XCTAssertEqual(field.toolTip, client.hostname)
    XCTAssertTrue(
      field.accessibilityHelp()?.contains(
        "hardware address: F6:41:D9:E3:B6:17") == true)
    XCTAssertEqual(field.accessibilityActionNames(), [.press])

    XCTAssertTrue(field.accessibilityPerformPress())
    XCTAssertEqual(presentations.last?.shouldPresent, true)
    XCTAssertEqual(presentations.last?.immediately, true)

    field.setAccessibilityFocused(false)
    XCTAssertEqual(presentations.last?.shouldPresent, false)
    XCTAssertEqual(presentations.last?.immediately, true)

    let keyEvent = try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: " ",
        charactersIgnoringModifiers: " ",
        isARepeat: false,
        keyCode: 49))
    field.keyDown(with: keyEvent)
    XCTAssertEqual(presentations.last?.shouldPresent, true)
    XCTAssertEqual(presentations.last?.immediately, true)

    let mouseEvent = try XCTUnwrap(
      NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: 1))
    field.mouseDown(with: mouseEvent)
    XCTAssertEqual(presentations.last?.shouldPresent, true)
    XCTAssertEqual(presentations.last?.immediately, true)

    XCTAssertTrue(field.accessibilityPerformPress())
    XCTAssertEqual(presentations.last?.shouldPresent, false)
    XCTAssertEqual(presentations.last?.immediately, true)
  }

  func testHoverFieldDismissesAfterPointerExits() throws {
    let field = WirelessClientHoverField(
      client: WirelessClient(
        macAddress: "F6:41:D9:E3:B6:17",
        ipAddress: "",
        hostname: "iphone.local"),
      frame: NSRect(x: 0, y: 0, width: 152, height: 19))
    var presentations: [(shouldPresent: Bool, immediately: Bool)] = []
    field.presentationChanged = { _, shouldPresent, immediately in
      presentations.append((shouldPresent, immediately))
    }
    let enteredEvent = try XCTUnwrap(
      NSEvent.enterExitEvent(
        with: .mouseEntered,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 0,
        trackingNumber: 1,
        userData: nil))
    let exitedEvent = try XCTUnwrap(
      NSEvent.enterExitEvent(
        with: .mouseExited,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 0,
        trackingNumber: 1,
        userData: nil))

    field.mouseEntered(with: enteredEvent)
    field.mouseExited(with: exitedEvent)

    XCTAssertEqual(presentations.count, 2)
    XCTAssertEqual(presentations[0].shouldPresent, true)
    XCTAssertEqual(presentations[0].immediately, false)
    XCTAssertEqual(presentations[1].shouldPresent, false)
    XCTAssertEqual(presentations[1].immediately, false)
  }

  func testIndependentPanelHideResetsFieldBeforeNextAccessibilityPress() throws {
    let client = WirelessClient(
      macAddress: "F6:41:D9:E3:B6:17",
      ipAddress: "",
      hostname: "iphone.local")
    let field = WirelessClientHoverField(
      client: client,
      frame: NSRect(x: 0, y: 0, width: 152, height: 19))
    let controller = WirelessClientDetailsPanelController()
    controller.hoverDelay = 60
    var presentations: [(shouldPresent: Bool, immediately: Bool)] = []
    field.presentationChanged = { _, shouldPresent, immediately in
      presentations.append((shouldPresent, immediately))
      if shouldPresent {
        controller.schedule(client: client, from: field)
      }
    }
    controller.presentationDidEnd = { clientID in
      if clientID == client.id {
        field.detailsPresentationDidEnd()
      }
    }
    let enteredEvent = try XCTUnwrap(
      NSEvent.enterExitEvent(
        with: .mouseEntered,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 0,
        trackingNumber: 1,
        userData: nil))

    field.mouseEntered(with: enteredEvent)
    controller.hide()
    XCTAssertEqual(presentations.count, 1)

    field.presentationChanged = { _, shouldPresent, immediately in
      presentations.append((shouldPresent, immediately))
    }
    XCTAssertTrue(field.accessibilityPerformPress())

    XCTAssertEqual(presentations.count, 2)
    XCTAssertEqual(presentations.last?.shouldPresent, true)
    XCTAssertEqual(presentations.last?.immediately, true)
  }
}
