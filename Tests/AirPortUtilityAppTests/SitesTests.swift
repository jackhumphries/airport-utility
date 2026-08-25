// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

import XCTest

@testable import AirPortUtilityCore

private final class MemorySitePasswordStore: AirportPasswordStore {
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

final class SitesTests: XCTestCase {
  func testStoreLoadsEmptyArrayWhenNothingSaved() {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SiteStore(directory: directory)

    XCTAssertEqual(store.loadSites(), [])
  }

  func testStoreSavesAndReloadsSites() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SiteStore(directory: directory)
    let site = Site(
      id: UUID(), name: "Home", host: "192.168.1.1",
      stableIdentifiers: ["abc123"],
      lastConnectedDate: Date(timeIntervalSince1970: 1_700_000_000))

    try store.save([site])

    XCTAssertEqual(store.loadSites(), [site])
  }

  @MainActor
  func testSaveCurrentConnectionAsSiteCapturesStableIdentifiersWhenKnown() {
    let model = AirportAppModel(passwordStore: MemorySitePasswordStore())
    defer { try? FileManager.default.removeItem(at: SiteStore.defaultDirectory()) }
    let device = AirportDiscoveredDevice(
      id: "capsule", name: "Time Capsule", hostName: "time-capsule.local",
      addresses: ["192.168.1.5"], identifiers: ["serial-123"],
      modelName: "AirPort Time Capsule")
    model.updateDiscoveredDevices([device])
    model.selectTopologyDevice(device)

    model.saveCurrentConnectionAsSite(name: "Home")

    XCTAssertEqual(model.sites.count, 1)
    XCTAssertEqual(model.sites.first?.name, "Home")
    XCTAssertEqual(model.sites.first?.stableIdentifiers, ["serial-123"])
    XCTAssertEqual(model.sites.first?.host, "192.168.1.5")
  }

  @MainActor
  func testSaveCurrentConnectionAsSiteCapturesNoIdentifiersWhenNotDiscovered() {
    let model = AirportAppModel(passwordStore: MemorySitePasswordStore())
    defer { try? FileManager.default.removeItem(at: SiteStore.defaultDirectory()) }
    model.connection.host = "203.0.113.9"

    model.saveCurrentConnectionAsSite(name: "Remote")

    XCTAssertEqual(model.sites.first?.stableIdentifiers, [])
    XCTAssertEqual(model.sites.first?.host, "203.0.113.9")
  }

  @MainActor
  func testSaveCurrentConnectionAsSiteIgnoresBlankName() {
    let model = AirportAppModel(passwordStore: MemorySitePasswordStore())
    defer { try? FileManager.default.removeItem(at: SiteStore.defaultDirectory()) }
    model.connection.host = "203.0.113.9"

    model.saveCurrentConnectionAsSite(name: "   ")

    XCTAssertTrue(model.sites.isEmpty)
  }

  @MainActor
  func testConnectToSiteRoutesThroughSelectTopologyDeviceWhenBonjourMatchExists() {
    let model = AirportAppModel(passwordStore: MemorySitePasswordStore())
    defer { try? FileManager.default.removeItem(at: SiteStore.defaultDirectory()) }
    let site = Site(
      id: UUID(), name: "Home", host: "192.168.1.5",
      stableIdentifiers: ["serial-123"], lastConnectedDate: nil)
    model.sites = [site]
    // The device resurfaces at a new DHCP-assigned address.
    let device = AirportDiscoveredDevice(
      id: "capsule", name: "Time Capsule", hostName: "time-capsule.local",
      addresses: ["192.168.1.9"], identifiers: ["serial-123"],
      modelName: "AirPort Time Capsule")
    model.updateDiscoveredDevices([device])

    model.connectToSite(site)

    XCTAssertEqual(model.selectedTopologyDeviceID, device.id)
    XCTAssertEqual(model.connection.host, "192.168.1.9")
    XCTAssertEqual(model.sites.first?.host, "192.168.1.9")
    XCTAssertNotNil(model.sites.first?.lastConnectedDate)
  }

  @MainActor
  func testConnectToSiteFallsBackToStoredHostWithoutABonjourMatch() {
    let model = AirportAppModel(passwordStore: MemorySitePasswordStore())
    defer { try? FileManager.default.removeItem(at: SiteStore.defaultDirectory()) }
    let site = Site(
      id: UUID(), name: "Away", host: "100.64.0.5",
      stableIdentifiers: [], lastConnectedDate: nil)
    model.sites = [site]

    model.connectToSite(site)

    XCTAssertEqual(model.connection.host, "100.64.0.5")
    XCTAssertNotNil(model.sites.first?.lastConnectedDate)
  }

  @MainActor
  func testUpdateSiteHostsFromDiscoveredDevicesSelfHeals() {
    let model = AirportAppModel(passwordStore: MemorySitePasswordStore())
    defer { try? FileManager.default.removeItem(at: SiteStore.defaultDirectory()) }
    let site = Site(
      id: UUID(), name: "Home", host: "192.168.1.5",
      stableIdentifiers: ["serial-123"], lastConnectedDate: nil)
    model.sites = [site]
    let device = AirportDiscoveredDevice(
      id: "capsule", name: "Time Capsule", hostName: "time-capsule.local",
      addresses: ["192.168.1.20"], identifiers: ["serial-123"],
      modelName: "AirPort Time Capsule")

    model.updateDiscoveredDevices([device])

    XCTAssertEqual(model.sites.first?.host, "192.168.1.20")
  }

  @MainActor
  func testRenameSiteTrimsAndIgnoresBlankNames() {
    let model = AirportAppModel(passwordStore: MemorySitePasswordStore())
    defer { try? FileManager.default.removeItem(at: SiteStore.defaultDirectory()) }
    let site = Site(
      id: UUID(), name: "Home", host: "192.168.1.5", stableIdentifiers: [],
      lastConnectedDate: nil)
    model.sites = [site]

    model.renameSite(site, to: "  Office  ")
    XCTAssertEqual(model.sites.first?.name, "Office")

    model.renameSite(site, to: "   ")
    XCTAssertEqual(model.sites.first?.name, "Office")
  }

  @MainActor
  func testRemoveSiteDeletesIt() {
    let model = AirportAppModel(passwordStore: MemorySitePasswordStore())
    defer { try? FileManager.default.removeItem(at: SiteStore.defaultDirectory()) }
    let site = Site(
      id: UUID(), name: "Home", host: "192.168.1.5", stableIdentifiers: [],
      lastConnectedDate: nil)
    model.sites = [site]

    model.removeSite(site)

    XCTAssertTrue(model.sites.isEmpty)
  }
}
