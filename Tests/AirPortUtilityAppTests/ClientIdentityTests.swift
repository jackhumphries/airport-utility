// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

import Foundation
import XCTest
@testable import AirPortUtilityCore

final class ClientIdentityTests: XCTestCase {
  // MARK: - MACVendorLookup

  func testRecognisesRealVendorsFromCuratedTable() {
    XCTAssertEqual(MACVendorLookup.vendor(forMACAddress: "00:03:93:aa:bb:cc"), "Apple")
    XCTAssertEqual(MACVendorLookup.vendor(forMACAddress: "00:0e:58:aa:bb:cc"), "Sonos")
    XCTAssertEqual(MACVendorLookup.vendor(forMACAddress: "00:00:48:aa:bb:cc"), "Epson")
  }

  func testUnrecognisedOUIReturnsNilRatherThanAGuess() {
    // 0x10's second-least-significant bit is 0 - genuinely
    // universally-administered, just not in the curated vendor table
    // (distinct from the locally-administered/private case below).
    XCTAssertFalse(MACVendorLookup.isLocallyAdministered("10:00:00:00:00:04"))
    XCTAssertNil(MACVendorLookup.vendor(forMACAddress: "10:00:00:00:00:04"))
  }

  func testLocallyAdministeredAddressIsDetectedAndSkipsVendorLookup() {
    // 0x02 set on the first octet is the locally-administered bit.
    XCTAssertTrue(MACVendorLookup.isLocallyAdministered("02:00:00:00:00:05"))
    XCTAssertNil(MACVendorLookup.vendor(forMACAddress: "02:03:93:00:00:05"))
  }

  func testUniversallyAdministeredAddressIsNotFlaggedAsPrivate() {
    XCTAssertFalse(MACVendorLookup.isLocallyAdministered("00:03:93:aa:bb:cc"))
  }

  func testVendorLookupIsCaseAndSeparatorInsensitive() {
    XCTAssertEqual(MACVendorLookup.vendor(forMACAddress: "00-03-93-AA-BB-CC"), "Apple")
    XCTAssertEqual(MACVendorLookup.vendor(forMACAddress: "000393aabbcc"), "Apple")
  }

  // MARK: - ClientDeviceType

  func testHostnamePatternsAreTrustedFirst() {
    XCTAssertEqual(ClientDeviceType.guess(hostname: "Grahams-iPhone", vendor: nil), .iPhone)
    XCTAssertEqual(ClientDeviceType.guess(hostname: "Living-Room-iPad", vendor: nil), .iPad)
    XCTAssertEqual(ClientDeviceType.guess(hostname: "Grahams-MacBook-Pro", vendor: nil), .mac)
    XCTAssertEqual(ClientDeviceType.guess(hostname: "Office-Mac-Mini", vendor: nil), .mac)
    XCTAssertEqual(ClientDeviceType.guess(hostname: "Living-Room-Apple-TV", vendor: nil), .appleTV)
    XCTAssertEqual(ClientDeviceType.guess(hostname: "Kitchen-HomePod", vendor: nil), .homePod)
    XCTAssertEqual(ClientDeviceType.guess(hostname: "Grahams-Apple-Watch", vendor: nil), .appleWatch)
  }

  func testConservativeVendorOnlyGuessesForSinglePurposeVendors() {
    XCTAssertEqual(ClientDeviceType.guess(hostname: nil, vendor: "Sonos"), .smartSpeaker)
    XCTAssertEqual(ClientDeviceType.guess(hostname: nil, vendor: "Nintendo"), .gameConsole)
    XCTAssertEqual(ClientDeviceType.guess(hostname: nil, vendor: "Epson"), .printer)
    XCTAssertEqual(ClientDeviceType.guess(hostname: nil, vendor: "Brother"), .printer)
    XCTAssertEqual(ClientDeviceType.guess(hostname: nil, vendor: "Ubiquiti"), .networkDevice)
    XCTAssertEqual(ClientDeviceType.guess(hostname: nil, vendor: "eero"), .networkDevice)
  }

  func testAmbiguousMultiCategoryVendorsAreNotGuessed() {
    // Samsung, Canon, and ASUS all make products across many device
    // categories, so a vendor-only guess for them would carry real risk of
    // being confidently wrong - this must stay .unknown.
    XCTAssertEqual(ClientDeviceType.guess(hostname: nil, vendor: "Samsung"), .unknown)
    XCTAssertEqual(ClientDeviceType.guess(hostname: nil, vendor: "Canon"), .unknown)
    XCTAssertEqual(ClientDeviceType.guess(hostname: nil, vendor: "ASUS"), .unknown)
  }

  func testUnknownWithNoHostnameOrVendorSignal() {
    XCTAssertEqual(ClientDeviceType.guess(hostname: "some-device", vendor: nil), .unknown)
    XCTAssertEqual(ClientDeviceType.guess(hostname: nil, vendor: nil), .unknown)
  }

  // MARK: - WirelessClient extension

  func testWirelessClientExposesVendorAndDeviceTypeAndPrivateAddress() {
    let iphone = WirelessClient(
      macAddress: "00:03:93:aa:bb:01", ipAddress: "192.168.1.2", hostname: "Grahams-iPhone")
    XCTAssertEqual(iphone.vendorName, "Apple")
    XCTAssertEqual(iphone.guessedDeviceType, .iPhone)
    XCTAssertFalse(iphone.isPrivateAddress)

    let randomized = WirelessClient(
      macAddress: "02:00:00:00:00:05", ipAddress: "192.168.1.3", hostname: "")
    XCTAssertNil(randomized.vendorName)
    XCTAssertTrue(randomized.isPrivateAddress)
  }

  // MARK: - ClientIdentityStore persistence

  @MainActor
  func testStoreRoundTripsCustomNamesThroughDisk() {
    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
      .appendingPathComponent("client-names.json")
    defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

    let store = ClientIdentityStore(fileURL: fileURL)
    XCTAssertEqual(store.load(), [:])

    store.save(["AA:BB:CC:DD:EE:FF": "Graham's Mac Mini"])
    let reloaded = ClientIdentityStore(fileURL: fileURL)
    XCTAssertEqual(reloaded.load(), ["AA:BB:CC:DD:EE:FF": "Graham's Mac Mini"])
  }

  @MainActor
  func testMissingFileLoadsAsEmpty() {
    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
      .appendingPathComponent("does-not-exist.json")

    XCTAssertEqual(ClientIdentityStore(fileURL: fileURL).load(), [:])
  }

  // MARK: - AirportAppModel integration

  @MainActor
  func testCustomClientNameSetGetClearAndNormalization() {
    // AirportAppModel()'s ClientIdentityStore uses the real Application
    // Support path (matching this codebase's existing test convention for
    // health/configuration history) - clean up afterward rather than
    // leaving test data behind for a real user of this Mac.
    defer { try? FileManager.default.removeItem(at: ClientIdentityStore.defaultFileURL()) }
    let model = AirportAppModel()

    XCTAssertNil(model.customClientName(forMACAddress: "aa:bb:cc:dd:ee:ff"))

    model.setCustomClientName("  Graham's Mac Mini  ", forMACAddress: "aa:bb:cc:dd:ee:ff")
    XCTAssertEqual(
      model.customClientName(forMACAddress: "AA:BB:CC:DD:EE:FF"), "Graham's Mac Mini")

    model.setCustomClientName("", forMACAddress: "aa:bb:cc:dd:ee:ff")
    XCTAssertNil(model.customClientName(forMACAddress: "aa:bb:cc:dd:ee:ff"))
  }

  @MainActor
  func testDisplayNamePrefersCustomNameOverAdvertisedHostname() {
    defer { try? FileManager.default.removeItem(at: ClientIdentityStore.defaultFileURL()) }
    let model = AirportAppModel()
    let client = WirelessClient(
      macAddress: "aa:bb:cc:dd:ee:ff", ipAddress: "192.168.1.5", hostname: "raw-hostname")

    XCTAssertEqual(model.displayName(for: client), "raw-hostname")

    model.setCustomClientName("Nickname", forMACAddress: client.macAddress)
    XCTAssertEqual(model.displayName(for: client), "Nickname")
  }
}
