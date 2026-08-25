// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

import Foundation

@MainActor
extension AirportAppModel {
  private static let smbPort: UInt16 = 445
  private static let storageProbeTimeout: TimeInterval = 2

  func refreshStorageHealthAndInventoryIfPossible() {
    guard isDashboardVisible, hasLoadedSettings, capabilities.supportsDisks else {
      refreshStorageHealthIfPossible()
      return
    }
    let requestConnection = connection
    let requestHost = AirportConnection.normalizedHost(requestConnection.host)
    guard !requestHost.isEmpty else { return }

    storageInventoryHealthRefreshTask?.cancel()
    let inventoryOverride = storageInventoryRefreshOverride
    appendLog("Storage inventory refresh started for \(requestHost).")
    storageInventoryHealthRefreshTask = Task { [weak self] in
      let result: (raw: String, records: [DiskRecord])?
      if let inventoryOverride {
        result = await inventoryOverride(requestConnection)
      } else {
        result = await self?.readDiskInventoryBestEffort(connection: requestConnection)
      }
      guard let self, !Task.isCancelled else { return }
      guard AirportConnection.normalizedHost(connection.host) == requestHost else { return }
      if let result {
        applyDiskInventoryRefreshResult(result)
        appendLog(
          "Storage inventory refresh completed for \(requestHost): \(result.records.count) volume(s).")
      } else {
        disks.didLoadInventory = false
        appendLog(
          "Storage inventory refresh unavailable for \(requestHost); previous inventory is retained for reference.")
      }
      refreshStorageHealthIfPossible()
    }
  }

  func refreshStorageHealthIfPossible() {
    guard isDashboardVisible else { return }
    refreshTimeMachineBackupsIfPossible()

    let diskState = StorageHealthAssessment.diskState(
      supportsDisks: capabilities.supportsDisks,
      didLoadInventory: disks.didLoadInventory,
      records: disks.inventory,
      smartStatuses: storageSMARTStatuses)

    if mockMode {
      applyStorageHealthState(StorageHealthState(
        diskCondition: diskState.diskCondition,
        diskDetail: diskState.diskDetail,
        totalBytes: diskState.totalBytes,
        freeBytes: diskState.freeBytes,
        smbAvailability: .reachable,
        smbDetail: "SMB file sharing is reachable",
        lastChecked: Date()), host: AirportConnection.normalizedHost(connection.host))
      return
    }

    guard hasLoadedSettings else { return }
    guard capabilities.supportsDisks else {
      applyStorageHealthState(StorageHealthState(
        diskCondition: diskState.diskCondition,
        diskDetail: diskState.diskDetail,
        smbAvailability: .notAvailable,
        smbDetail: "SMB check is not applicable",
        lastChecked: Date()), host: AirportConnection.normalizedHost(connection.host))
      return
    }
    guard !hasReportedDiskFileSharingSetting || disks.fileSharing else {
      applyStorageHealthState(StorageHealthState(
        diskCondition: diskState.diskCondition,
        diskDetail: diskState.diskDetail,
        totalBytes: diskState.totalBytes,
        freeBytes: diskState.freeBytes,
        smbAvailability: .disabled,
        smbDetail: "Disk file sharing is turned off",
        lastChecked: Date()), host: AirportConnection.normalizedHost(connection.host))
      return
    }

    let requestHost = AirportConnection.normalizedHost(connection.host)
    guard !requestHost.isEmpty else { return }

    storageHealthRefreshTask?.cancel()
    storageHealth = StorageHealthState(
      diskCondition: diskState.diskCondition,
      diskDetail: diskState.diskDetail,
      totalBytes: diskState.totalBytes,
      freeBytes: diskState.freeBytes,
      smbAvailability: .checking,
      smbDetail: "Checking SMB file sharing…")
    let override = storageHealthProbeOverride
    let started = Date()
    appendLog(
      "Storage health check started for \(requestHost): disk=\(diskState.diskCondition.rawValue), SMB port=\(Self.smbPort).")

    storageHealthRefreshTask = Task { [weak self] in
      let reachable: Bool
      if let override {
        reachable = await override(requestHost, Self.smbPort, Self.storageProbeTimeout)
      } else {
        reachable = await StoragePortProbe.canConnect(
          host: requestHost,
          port: Self.smbPort,
          timeout: Self.storageProbeTimeout)
      }

      guard let self, !Task.isCancelled else { return }
      guard AirportConnection.normalizedHost(connection.host) == requestHost else { return }

      let elapsed = Date().timeIntervalSince(started)
      let completedState = StorageHealthState(
        diskCondition: diskState.diskCondition,
        diskDetail: diskState.diskDetail,
        totalBytes: diskState.totalBytes,
        freeBytes: diskState.freeBytes,
        smbAvailability: reachable ? .reachable : .unreachable,
        smbDetail: reachable
          ? hasReportedDiskFileSharingSetting
            ? "SMB file sharing is accepting connections"
            : "SMB is reachable; the AirPort did not report its file-sharing setting"
          : hasReportedDiskFileSharingSetting
            ? "SMB service is unreachable or blocked; disk condition is unchanged"
            : "SMB is unreachable and the AirPort did not report its file-sharing setting",
        lastChecked: Date())
      applyStorageHealthState(completedState, host: requestHost)
      let elapsedText = String(format: "%.2f", elapsed)
      appendLog(
        "Storage health check completed for \(requestHost) in \(elapsedText)s: disk=\(completedState.diskCondition.rawValue), SMB=\(completedState.smbAvailability.rawValue).")
    }
  }

  func refreshTimeMachineBackupsIfPossible() {
    guard isDashboardVisible, capabilities.supportsDisks else {
      timeMachineBackups = TimeMachineBackupState(
        detail: "Time Machine backups are not applicable to this AirPort",
        lastChecked: Date())
      return
    }
    guard hasLoadedSettings || mockMode else { return }

    let requestHost = AirportConnection.normalizedHost(connection.host)
    let volumeNames = Self.uniqueNonEmptyValues(
      disks.inventory.flatMap { [$0.name, $0.deviceName] })
    let scanOverride = timeMachineBackupScanOverride
    timeMachineBackupScanTask?.cancel()
    timeMachineBackups = TimeMachineBackupState(
      backups: timeMachineBackups.backups,
      detail: "Checking mounted Time Capsule shares…",
      lastChecked: timeMachineBackups.lastChecked,
      isScanning: true)
    appendLog("Time Machine backup scan started for \(requestHost).")

    timeMachineBackupScanTask = Task { [weak self] in
      let records: [TimeMachineBackupRecord]
      if let scanOverride {
        records = await scanOverride(volumeNames)
      } else {
        records = await Task.detached {
          TimeMachineBackupScanner.scan(volumeNames: volumeNames)
        }.value
      }
      guard let self, !Task.isCancelled else { return }
      guard AirportConnection.normalizedHost(connection.host) == requestHost else { return }
      let detail: String
      if records.isEmpty {
        detail = "No backup sparsebundles found on mounted Time Capsule shares"
      } else {
        let staleCount = records.filter { $0.condition == .stale }.count
        let warningCount = records.filter { $0.condition == .warning }.count
        if staleCount > 0 {
          detail = "\(staleCount) stale backup\(staleCount == 1 ? "" : "s") need attention"
        } else if warningCount > 0 {
          detail = "\(warningCount) backup\(warningCount == 1 ? "" : "s") may be overdue"
        } else {
          detail = "\(records.count) backup\(records.count == 1 ? "" : "s") found"
        }
      }
      timeMachineBackups = TimeMachineBackupState(
        backups: records, detail: detail, lastChecked: Date(), isScanning: false)
      evaluateHealthAlerts()
      recordHealthHistorySample()
      appendLog(
        "Time Machine backup scan completed for \(requestHost): \(records.count) sparsebundle(s), \(records.filter { $0.condition == .stale }.count) stale.")
    }
  }

  private func applyStorageHealthState(_ state: StorageHealthState, host: String) {
    storageHealth = state
    evaluateHealthAlerts()
    recordHealthHistorySample(at: state.lastChecked ?? Date())
    let summary = "Disk: \(state.diskDetail). SMB: \(state.smbDetail)."
    if let latest = storageHealthHistory.first,
      latest.host == host,
      latest.diskCondition == state.diskCondition,
      latest.totalBytes == state.totalBytes,
      latest.freeBytes == state.freeBytes,
      latest.smbAvailability == state.smbAvailability,
      latest.summary == summary
    {
      return
    }
    storageHealthHistory.insert(
      StorageHealthEvent(
        id: UUID(), date: state.lastChecked ?? Date(), host: host,
        diskCondition: state.diskCondition,
        totalBytes: state.totalBytes,
        freeBytes: state.freeBytes,
        smbAvailability: state.smbAvailability,
        summary: summary),
      at: 0)
    storageHealthHistory = Array(storageHealthHistory.prefix(50))
    appendLog("Storage health changed for \(host): \(summary)")
  }
}
