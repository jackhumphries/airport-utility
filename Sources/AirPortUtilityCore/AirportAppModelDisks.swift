import Foundation

extension AirportAppModel {
  func previewDiskSharing() {
    previewFriendlySettings(
      title: "Disk Sharing",
      noChangesStatus: "No pending Disk Sharing changes to preview."
    ) {
      diskSharingFlags(changesOnly: true)
    }
  }

  func applyDiskSharing() {
    applyFriendlySettings(
      title: "Disk Sharing",
      noChangesStatus: "No pending Disk Sharing changes to apply.",
      cleanScope: .disks,
      completion: { self.persistAuxiliaryPasswordPreferences(from: $0) }
    ) {
      diskSharingFlags(changesOnly: true)
    }
  }

  func dryRunErase(method: EraseMethod, volumeName: String? = nil) {
    let connection = connection
    dryRun(
      title: "Erase Disk",
      args: AirportCommand.eraseDisk(
        connection: connection, method: method, volumeName: volumeName,
        partitionUUID: selectedEraseDiskUUID(),
        message: Self.eraseDiskWarningMessage,
        confirmed: false, dryRun: true),
      connection: connection)
  }

  func applyErase(method: EraseMethod, volumeName: String? = nil) {
    let connection = connection
    apply(
      title: "Erase Disk",
      args: AirportCommand.eraseDisk(
        connection: connection, method: method, volumeName: volumeName,
        partitionUUID: selectedEraseDiskUUID(),
        message: Self.eraseDiskWarningMessage,
        confirmed: true, dryRun: false),
      connection: connection,
      cleanScope: .none,
      completion: invalidateDiskInventory)
  }

  func dryRunArchive(name: String) {
    let connection = connection
    dryRun(
      title: "Archive Disk",
      args: AirportCommand.archiveDisk(
        connection: connection, archiveName: name, confirmed: false, dryRun: true),
      connection: connection)
  }

  func applyArchive(name: String) {
    let connection = connection
    let args = AirportCommand.archiveDisk(
      connection: connection, archiveName: name, confirmed: true, dryRun: false)
    applyArchive(args: args, connection: connection)
  }

  private static let eraseDiskWarningMessage = "All users will be disconnected from this disk."
  private static let archiveStatusACPSettings = ["sySt"]
  private static let archiveCompletionPollIntervalNanoseconds: UInt64 = 15_000_000_000
  private static let archiveCompletionPollLimit = 5_760
  private static let mockArchiveCompletionDelayNanoseconds: UInt64 = 750_000_000

  private func selectedEraseDiskUUID() -> String? {
    let selected = disks.inventory.first { $0.id == disks.selectedDiskID }
    return selected?.uuid.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func applyDiskInventoryRefreshResult(_ result: (raw: String, records: [DiskRecord])?) {
    guard let result else { return }
    guard !Self.isPendingDiskInventoryPlaceholder(result.raw) else {
      return
    }
    disks.rawInventory = result.raw
    disks.inventory = result.records
    disks.didLoadInventory = true
    storageSMARTStatuses = DiskInventoryParser.smartStatuses(stdout: result.raw)
    appendLog("Disk inventory fields: \(DiskInventoryParser.diagnosticFieldSummary(stdout: result.raw))")
    appendLog("Disk inventory metrics: \(DiskInventoryParser.diagnosticMetricSummary(stdout: result.raw))")
    appendLog("Disk inventory parsed: \(DiskInventoryParser.diagnosticRecordSummary(result.records))")
  }

  private func invalidateDiskInventory() {
    disks.rawInventory = ""
    disks.inventory = []
    disks.didLoadInventory = false
  }

  func readDiskInventoryBestEffort(connection: AirportConnection) async -> (
    raw: String, records: [DiskRecord]
  )? {
    do {
      let mast = try await runner.run(
        script: AirportCommand.readScript,
        arguments: AirportCommand.readSetting("MaSt", connection: connection, json: true),
        connection: connection,
        timeout: 15)
      if Self.isPendingDiskInventoryPlaceholder(mast.stdout) {
        return nil
      }
      return (mast.stdout, DiskInventoryParser.parse(stdout: mast.stdout))
    } catch {
      if Self.containsPendingDiskInventoryPlaceholder(error.localizedDescription) {
        return nil
      }
      if let message = Self.diskInventoryRefreshSkippedMessage(for: error.localizedDescription) {
        appendDeduplicatedLog(message)
      }
      return nil
    }
  }

  static func diskInventoryRefreshResult(from reader: ProfileReader, rawOutput: String) -> (
    raw: String, records: [DiskRecord]
  )? {
    guard reader.hasValue(at: "settings.MaSt") else { return nil }
    return (rawOutput, DiskInventoryParser.parse(stdout: rawOutput))
  }

  nonisolated static func diskInventoryRefreshSkippedMessage(for errorDescription: String)
    -> String?
  {
    DiskInventoryMessage.refreshSkippedMessage(for: errorDescription)
  }

  private nonisolated static func isPendingDiskInventoryPlaceholder(_ description: String) -> Bool {
    containsPendingDiskInventoryPlaceholder(description)
  }

  private nonisolated static func containsPendingDiskInventoryPlaceholder(_ description: String)
    -> Bool
  {
    DiskInventoryMessage.containsPendingPlaceholder(description)
  }

  private func applyArchive(args: [String], connection: AirportConnection) {
    guard !isBusy else { return }
    let requestHost = AirportConnection.normalizedHost(connection.host)
    runTask("Applying Archive Disk", requestHost: requestHost) {
      if self.mockMode {
        let redacted = AirportCommand.redact(args)
        let output = AirportMockBackend.output(for: args, dryRun: false)
        guard self.connectionStillMatches(requestHost) else {
          self.ignoreStaleOperation(
            "Ignored Archive Disk apply result for stale host \(requestHost).")
          return
        }
        self.appendLog(
          "$ \(AirportCommand.display(AirportCommand.writeScript, redacted))\n\(output)")
        self.archiveDiskStarted(connection: connection, requestHost: requestHost)
        return
      }

      let result = try await self.runner.run(
        script: AirportCommand.writeScript, arguments: args, connection: connection,
        timeout: 90)
      guard self.connectionStillMatches(requestHost) else {
        self.ignoreStaleOperation(
          "Ignored Archive Disk apply result for stale host \(requestHost).")
        return
      }
      let output = Self.userFacingCommandOutput(result.combinedOutput)
      self.appendLog(
        "$ \(AirportCommand.display(AirportCommand.writeScript, result.redactedArguments))\n\(output)"
      )
      self.archiveDiskStarted(connection: connection, requestHost: requestHost)
    }
  }

  private func archiveDiskStarted(connection: AirportConnection, requestHost: String) {
    invalidateDiskInventory()
    status = "Archive Disk started. Waiting for archive to complete."
    preview = nil
    archiveCompletionMonitorTask?.cancel()
    archiveCompletionMonitorTask = Task { @MainActor [weak self] in
      await self?.monitorArchiveCompletion(connection: connection, requestHost: requestHost)
    }
  }

  private func monitorArchiveCompletion(connection: AirportConnection, requestHost: String) async {
    if mockMode {
      try? await Task.sleep(nanoseconds: Self.mockArchiveCompletionDelayNanoseconds)
      guard !Task.isCancelled else { return }
      guard connectionStillMatches(requestHost) else {
        ignoreStaleOperation(
          "Ignored Archive Disk completion for stale host \(requestHost).")
        return
      }
      await finishArchiveCompletion(connection: connection, requestHost: requestHost)
      return
    }

    var sawArchiveInProgress = false
    for _ in 0..<Self.archiveCompletionPollLimit {
      try? await Task.sleep(nanoseconds: Self.archiveCompletionPollIntervalNanoseconds)
      guard !Task.isCancelled else { return }
      guard connectionStillMatches(requestHost) else {
        ignoreStaleOperation(
          "Stopped Archive Disk completion monitor for stale host \(requestHost).")
        return
      }

      do {
        let reader = try await readSettingsReader(
          Self.archiveStatusACPSettings, connection: connection)
        if Self.archiveIsInProgress(reader: reader) {
          sawArchiveInProgress = true
          status = "Archive Disk in progress."
          continue
        }
        if sawArchiveInProgress {
          await finishArchiveCompletion(connection: connection, requestHost: requestHost)
          return
        }
      } catch {
        let description = Self.userFacingErrorDescription(error.localizedDescription)
        appendDeduplicatedLog("Archive Disk status check failed: \(description)")
      }
    }

    guard connectionStillMatches(requestHost) else { return }
    status = "Archive Disk status check timed out."
    appendLog("Archive Disk status check timed out.")
  }

  private func finishArchiveCompletion(connection: AirportConnection, requestHost: String) async {
    guard connectionStillMatches(requestHost) else {
      ignoreStaleOperation("Ignored Archive Disk completion for stale host \(requestHost).")
      return
    }
    status = "Archive Disk complete."
    appendLog("Archive Disk complete.")
    if mockMode {
      applyDiskInventoryRefreshResult(AirportMockBackend.diskInventoryRefreshResult)
      return
    }
    let diskInventory = await readDiskInventoryBestEffort(connection: connection)
    guard connectionStillMatches(requestHost) else { return }
    applyDiskInventoryRefreshResult(diskInventory)
  }

  nonisolated static func archiveIsInProgress(reader: ProfileReader) -> Bool {
    reader.strings("settings.sySt.decoded.problems")
      .contains("ArcI")
  }
}
