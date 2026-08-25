// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

import XCTest

@testable import AirPortUtilityCore

final class StorageHealthTests: XCTestCase {
  @MainActor
  func testDashboardStorageHealthReportsReachableSMBService() async {
    let model = AirportAppModel(passwordStore: NoopAirportPasswordStore())
    model.connection.host = "time-capsule.local"
    model.hasLoadedSettings = true
    model.capabilities.supportsDisks = true
    model.disks.fileSharing = true
    model.hasReportedDiskFileSharingSetting = true
    model.disks.didLoadInventory = true
    model.disks.inventory = [disk(size: 1_000_000_000_000, free: 500_000_000_000)]
    model.isDashboardVisible = true
    model.storageHealthProbeOverride = { host, port, timeout in
      XCTAssertEqual(host, "time-capsule.local")
      XCTAssertEqual(port, 445)
      XCTAssertEqual(timeout, 2)
      return true
    }

    model.refreshStorageHealthIfPossible()
    await model.storageHealthRefreshTask?.value

    XCTAssertEqual(model.storageHealth.smbAvailability, .reachable)
    XCTAssertEqual(model.storageHealth.smbDetail, "SMB file sharing is accepting connections")
    XCTAssertEqual(model.storageHealth.diskCondition, .healthy)
    XCTAssertNotNil(model.storageHealth.lastChecked)
    XCTAssertEqual(model.storageHealthHistory.count, 1)
  }

  @MainActor
  func testStorageHealthDoesNotProbeWithoutVisibleDashboard() async {
    let model = AirportAppModel(passwordStore: NoopAirportPasswordStore())
    model.connection.host = "time-capsule.local"
    model.hasLoadedSettings = true
    model.capabilities.supportsDisks = true
    model.disks.fileSharing = true
    var probeCount = 0
    model.storageHealthProbeOverride = { _, _, _ in
      probeCount += 1
      return true
    }

    model.refreshStorageHealthIfPossible()
    await Task.yield()

    XCTAssertEqual(probeCount, 0)
    XCTAssertEqual(model.storageHealth.smbAvailability, .unknown)
  }

  @MainActor
  func testDashboardStorageHealthReportsUnsupportedAirPort() {
    let model = AirportAppModel(passwordStore: NoopAirportPasswordStore())
    model.hasLoadedSettings = true
    model.isDashboardVisible = true

    model.refreshStorageHealthIfPossible()

    XCTAssertEqual(model.storageHealth.smbAvailability, .notAvailable)
    XCTAssertEqual(
      model.storageHealth.smbDetail, "SMB check is not applicable")
  }

  @MainActor
  func testDashboardStorageHealthReportsDisabledFileSharingWithoutProbe() async {
    let model = AirportAppModel(passwordStore: NoopAirportPasswordStore())
    model.hasLoadedSettings = true
    model.capabilities.supportsDisks = true
    model.hasReportedDiskFileSharingSetting = true
    model.isDashboardVisible = true
    var probeCount = 0
    model.storageHealthProbeOverride = { _, _, _ in
      probeCount += 1
      return true
    }

    model.refreshStorageHealthIfPossible()
    await Task.yield()

    XCTAssertEqual(probeCount, 0)
    XCTAssertEqual(model.storageHealth.smbAvailability, .disabled)
    XCTAssertEqual(model.storageHealth.smbDetail, "Disk file sharing is turned off")
  }

  @MainActor
  func testMissingFileSharingSettingStillProbesSMB() async {
    let model = AirportAppModel(passwordStore: NoopAirportPasswordStore())
    model.connection.host = "192.168.1.209"
    model.hasLoadedSettings = true
    model.capabilities.supportsDisks = true
    model.disks.didLoadInventory = true
    model.disks.inventory = [Self.disk(size: 1_000_000_000_000, free: 400_000_000_000)]
    model.isDashboardVisible = true
    model.storageHealthProbeOverride = { _, _, _ in true }

    model.refreshStorageHealthIfPossible()
    await model.storageHealthRefreshTask?.value

    XCTAssertEqual(model.storageHealth.smbAvailability, .reachable)
    XCTAssertEqual(
      model.storageHealth.smbDetail,
      "SMB is reachable; the AirPort did not report its file-sharing setting")
  }

  func testDiskAssessmentReportsHealthyCapacity() {
    let state = StorageHealthAssessment.diskState(
      supportsDisks: true,
      didLoadInventory: true,
      records: [Self.disk(size: 1_000_000_000_000, free: 500_000_000_000)])

    XCTAssertEqual(state.diskCondition, .healthy)
    XCTAssertEqual(
      state.diskDetail, "Capacity values look normal; hardware health is not reported")
    XCTAssertEqual(state.totalBytes, 1_000_000_000_000)
    XCTAssertEqual(state.freeBytes, 500_000_000_000)
  }

  func testDiskAssessmentWarnsWhenSpaceIsLow() {
    let state = StorageHealthAssessment.diskState(
      supportsDisks: true,
      didLoadInventory: true,
      records: [Self.disk(size: 1_000_000_000_000, free: 10_000_000_000)])

    XCTAssertEqual(state.diskCondition, .warning)
    XCTAssertEqual(state.diskDetail, "Disk space is low")
  }

  func testDiskAssessmentDisplaysVerifiedSMARTStatus() {
    let state = StorageHealthAssessment.diskState(
      supportsDisks: true,
      didLoadInventory: true,
      records: [Self.disk(size: 1_000_000_000_000, free: 500_000_000_000)],
      smartStatuses: ["verified"])

    XCTAssertEqual(state.diskCondition, .healthy)
    XCTAssertEqual(state.smartStatus, "verified")
    XCTAssertEqual(state.diskDetail, "Capacity values look normal; SMART status is verified")
  }

  func testDiskAssessmentSurfacesUnknownSMARTStatusWithoutInterpretingIt() {
    let state = StorageHealthAssessment.diskState(
      supportsDisks: true,
      didLoadInventory: true,
      records: [Self.disk(size: 1_000_000_000_000, free: 500_000_000_000)],
      smartStatuses: ["vendor-warning"])

    XCTAssertEqual(state.diskCondition, .warning)
    XCTAssertEqual(state.smartStatus, "vendor-warning")
    XCTAssertEqual(state.diskDetail, "The AirPort reported SMART status: vendor-warning")
  }

  func testDiskAssessmentDoesNotClaimHealthWithoutCapacity() {
    let state = StorageHealthAssessment.diskState(
      supportsDisks: true,
      didLoadInventory: true,
      records: [Self.disk(size: nil, free: nil)])

    XCTAssertEqual(state.diskCondition, .unavailable)
    XCTAssertEqual(
      state.diskDetail, "Disk volumes were reported, but capacity information is incomplete")
  }

  @MainActor
  func testUnreachableSMBDoesNotMarkHealthyDiskAsUnhealthy() async {
    let model = AirportAppModel(passwordStore: NoopAirportPasswordStore())
    model.connection.host = "192.168.1.209"
    model.hasLoadedSettings = true
    model.capabilities.supportsDisks = true
    model.disks.fileSharing = true
    model.hasReportedDiskFileSharingSetting = true
    model.disks.didLoadInventory = true
    model.disks.inventory = [Self.disk(size: 1_000_000_000_000, free: 500_000_000_000)]
    model.isDashboardVisible = true
    model.storageHealthProbeOverride = { _, _, _ in false }

    model.refreshStorageHealthIfPossible()
    await model.storageHealthRefreshTask?.value

    XCTAssertEqual(model.storageHealth.diskCondition, .healthy)
    XCTAssertEqual(model.storageHealth.smbAvailability, .unreachable)
    XCTAssertEqual(
      model.storageHealth.smbDetail,
      "SMB service is unreachable or blocked; disk condition is unchanged")
    XCTAssertTrue(model.logs.contains { $0.contains("SMB=unreachable") })
  }

  @MainActor
  func testManualRefreshReloadsInventoryBeforeCheckingSMB() async {
    let model = AirportAppModel(passwordStore: NoopAirportPasswordStore())
    model.connection.host = "192.168.1.209"
    model.hasLoadedSettings = true
    model.capabilities.supportsDisks = true
    model.disks.fileSharing = true
    model.isDashboardVisible = true
    model.storageInventoryRefreshOverride = { connection in
      XCTAssertEqual(connection.host, "192.168.1.209")
      return ("inventory", [Self.disk(size: 1_000_000_000_000, free: 400_000_000_000)])
    }
    model.storageHealthProbeOverride = { _, _, _ in true }

    model.refreshStorageHealthAndInventoryIfPossible()
    await model.storageInventoryHealthRefreshTask?.value
    await model.storageHealthRefreshTask?.value

    XCTAssertTrue(model.disks.didLoadInventory)
    XCTAssertEqual(model.storageHealth.diskCondition, .healthy)
    XCTAssertEqual(model.storageHealth.freeBytes, 400_000_000_000)
    XCTAssertTrue(model.logs.contains { $0.contains("1 volume(s)") })
  }

  @MainActor
  func testFailedManualInventoryRefreshDoesNotClaimDiskHealth() async {
    let model = AirportAppModel(passwordStore: NoopAirportPasswordStore())
    model.connection.host = "192.168.1.209"
    model.hasLoadedSettings = true
    model.capabilities.supportsDisks = true
    model.disks.fileSharing = true
    model.disks.didLoadInventory = true
    model.disks.inventory = [Self.disk(size: 1_000_000_000_000, free: 400_000_000_000)]
    model.isDashboardVisible = true
    model.storageInventoryRefreshOverride = { _ in nil }
    model.storageHealthProbeOverride = { _, _, _ in true }

    model.refreshStorageHealthAndInventoryIfPossible()
    await model.storageInventoryHealthRefreshTask?.value
    await model.storageHealthRefreshTask?.value

    XCTAssertFalse(model.disks.didLoadInventory)
    XCTAssertEqual(model.storageHealth.diskCondition, .unavailable)
    XCTAssertEqual(
      model.storageHealth.diskDetail, "Disk inventory is unavailable; disk condition is unknown")
  }

  private static func disk(size: Int64?, free: Int64?) -> DiskRecord {
    DiskRecord(
      deviceName: "wd0", name: "Data", format: "HFS+", uuid: "disk-1",
      size: size, sizeFree: free, builtIn: true)
  }

  private func disk(size: Int64?, free: Int64?) -> DiskRecord {
    Self.disk(size: size, free: free)
  }
}
