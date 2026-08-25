import Foundation

@MainActor
extension AirportAppModel {
  func refreshFirmwareImages() {
    guard supportsPane(.firmware) else {
      status = "This base station does not support firmware updates."
      return
    }
    guard !isBusy else { return }
    let productID = firmware.productID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !productID.isEmpty else {
      status = "The base station product ID is not available."
      return
    }
    let requestHost = AirportConnection.normalizedHost(connection.host)
    firmware.isLoading = true
    runTask("Loading firmware list", requestHost: requestHost) {
      defer {
        self.firmware.isLoading = false
      }
      try await self.loadFirmwareImages(
        productID: productID,
        requestHost: requestHost,
        updatesStatus: true)
    }
  }

  func chooseFirmwareImage(at url: URL) {
    let productID = firmware.productID.trimmingCharacters(in: .whitespacesAndNewlines)
    let effectiveProductID =
      productID.isEmpty
      ? baseStation.productID.trimmingCharacters(in: .whitespacesAndNewlines)
      : productID
    let version = Self.firmwareVersionName(from: url)
    let image = FirmwareImage(
      productID: effectiveProductID,
      version: version,
      sourceVersion: "chosen-\(Self.firmwareSourceIdentifier(for: url))",
      location: url,
      sizeInBytes: Self.fileSize(at: url),
      newest: false)
    firmware.images.removeAll { $0.id == image.id }
    firmware.images.insert(image, at: 0)
    firmware.selectedImageID = image.id
    firmware.hasLoadedImages = true
    firmware.lastError = ""
    firmware.installStatus = "Selected firmware image \(url.lastPathComponent)."
  }

  func chooseFirmwareImageFailed(_ error: Error) {
    firmware.lastError = error.localizedDescription
  }

  func previewSelectedFirmwareInstall() {
    guard supportsPane(.firmware) else {
      status = "This base station does not support firmware updates."
      clearPreviewAfterValidationFailure()
      return
    }
    if mockMode, firmware.images.isEmpty {
      loadMockFirmwareImagesIfNeeded(force: true)
    }
    guard let image = firmware.selectedImage else {
      preview = nil
      status = "No firmware image is selected."
      return
    }
    let args = AirportCommand.installFirmware(
      connection: connection,
      firmwarePath: image.location.absoluteString,
      dryRun: true)
    dryRun(title: "Firmware", args: args, connection: connection)
  }

  func installSelectedFirmware() {
    guard supportsPane(.firmware) else {
      status = "This base station does not support firmware updates."
      clearPreviewAfterValidationFailure()
      return
    }
    if mockMode, firmware.images.isEmpty {
      loadMockFirmwareImagesIfNeeded(force: true)
    }
    guard let image = firmware.selectedImage else {
      preview = nil
      status = "No firmware image is selected."
      return
    }
    guard mockMode || liveCredentialsAvailable else {
      clearPreviewAfterValidationFailure()
      updateIdleConnectionStatus()
      showConnectionDetails = true
      return
    }
    guard !isBusy else { return }

    let connection = connection
    let requestHost = AirportConnection.normalizedHost(connection.host)
    let wasReinstall =
      Self.normalizedFirmwareVersion(image.version)
      == Self.normalizedFirmwareVersion(firmware.currentVersion)
    firmwareCompletionMonitorTask?.cancel()
    firmware.installStatus = "Preparing firmware \(image.version)."
    resetFirmwareTransferProgress()
    runTask("Installing firmware \(image.version)", requestHost: requestHost) {
      let isAccessingLocalFirmware =
        image.isLocalFile && image.location.startAccessingSecurityScopedResource()
      defer {
        if isAccessingLocalFirmware {
          image.location.stopAccessingSecurityScopedResource()
        }
      }
      let firmwareSource: String
      if self.mockMode {
        firmwareSource = image.location.absoluteString
        self.updateFirmwareTransferProgress(
          phase: .download,
          completed: 1,
          total: 1,
          detail: "Using bundled mock firmware.")
      } else if image.isLocalFile {
        firmwareSource = image.location.path
        self.updateFirmwareTransferProgress(
          phase: .download,
          completed: 1,
          total: 1,
          detail: "Using selected firmware file.")
      } else {
        self.firmware.installStatus = "Downloading firmware \(image.version)."
        self.updateFirmwareTransferProgress(
          phase: .download,
          completed: 0,
          total: Double(max(image.sizeInBytes, 1)),
          detail: "Starting download from Apple.")
        let localURL = try await self.downloadFirmwareImage(image)
        firmwareSource = localURL.path
      }
      let args = AirportCommand.installFirmware(
        connection: connection,
        firmwarePath: firmwareSource,
        dryRun: false)
      if self.mockMode {
        let redacted = AirportCommand.redact(args)
        let output = AirportMockBackend.output(for: args, dryRun: false)
        self.appendLog(
          "$ \(AirportCommand.display(AirportCommand.writeScript, redacted))\n\(output)")
        self.preview = nil
        self.updateFirmwareTransferProgress(
          phase: .upload,
          completed: 1,
          total: 1,
          detail: "Mock firmware uploaded.")
        self.firmware.installStatus = "Mock firmware upload accepted. Restart requested."
        self.firmwareUploadRestartStarted(
          image: image,
          connection: connection,
          requestHost: requestHost,
          wasReinstall: wasReinstall,
          uploadResult: nil,
          suffix: " Mock mode.")
        return
      }

      self.firmware.installStatus = "Uploading firmware \(image.version)."
      self.resetFirmwareUploadProgressBuffer()
      self.updateFirmwareTransferProgress(
        phase: .upload,
        completed: 0,
        total: 1,
        detail: "Starting upload to AirPort.")
      let result = try await self.runner.run(
        script: AirportCommand.writeScript,
        arguments: args,
        connection: connection,
        timeout: 300
      ) { chunk in
        guard chunk.stream == .stdout else { return }
          Task { @MainActor in
            self.appendFirmwareUploadProgressOutput(chunk.text)
          }
      }
      guard self.connectionStillMatches(requestHost) else {
        self.ignoreStaleOperation("Ignored firmware install result for stale host \(requestHost).")
        return
      }
      self.flushFirmwareUploadProgressOutput()
      let output = Self.userFacingCommandOutput(result.combinedOutput)
      self.appendLog(
        "$ \(AirportCommand.display(AirportCommand.writeScript, result.redactedArguments))\n\(output)"
      )
      self.preview = nil
      let uploadResult = Self.firmwareUploadCommandResult(from: result.combinedOutput)
      if let uploadResult {
        let summary = Self.firmwareUploadStatusSummary(from: uploadResult)
        self.firmware.installStatus = summary
        self.applyFirmwareUploadResultProgress(uploadResult)
        try Self.validateFirmwareUploadResult(uploadResult)
        self.firmware.installStatus = "\(summary) Waiting for restart."
        if uploadResult.uploadHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          self.appendLog("Firmware upload: \(summary)")
        } else {
          self.appendLog("Firmware upload: \(summary) Host: \(uploadResult.uploadHost).")
        }
      } else {
        self.firmware.installStatus = "Firmware upload accepted. Waiting for restart."
        self.updateFirmwareTransferProgress(
          phase: .restart,
          completed: 1,
          total: 1,
          detail: "Restart command sent.")
      }
      let suffix: String
      if let uploadResult, uploadResult.progressComplete == true {
        suffix = " Upload reached \(uploadResult.progressText)."
      } else {
        suffix = ""
      }
      self.firmwareUploadRestartStarted(
        image: image,
        connection: connection,
        requestHost: requestHost,
        wasReinstall: wasReinstall,
        uploadResult: uploadResult,
        suffix: suffix)
    }
  }

  func applyFirmwareImages(_ images: [FirmwareImage]) {
    firmware.images = images
    firmware.hasLoadedImages = true
    firmware.lastError = ""
    updateConnectedFirmwareBadgeSnapshot()
    let currentVersion = Self.normalizedFirmwareVersion(firmware.currentVersion)
    if !firmware.selectedImageID.isEmpty,
      images.contains(where: { $0.id == firmware.selectedImageID })
    {
      return
    } else if let newest = images.first(where: \.newest) ?? images.first,
      Self.normalizedFirmwareVersion(newest.version) != currentVersion
    {
      firmware.selectedImageID = newest.id
    } else if let current = images.first(where: {
      Self.normalizedFirmwareVersion($0.version) == currentVersion
    }) {
      firmware.selectedImageID = current.id
    } else if let newest = images.first(where: \.newest) ?? images.first {
      firmware.selectedImageID = newest.id
    } else {
      firmware.selectedImageID = ""
    }
  }

  func loadMockFirmwareImagesIfNeeded(force: Bool = false) {
    guard capabilities.supportsFirmware else { return }
    if firmware.hasLoadedImages && !force { return }
    let productID =
      firmware.productID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? "106" : firmware.productID
    applyFirmwareImages(FirmwareCatalog.mockImages(forProductID: productID))
  }

  func scheduleAutomaticFirmwareCatalogRefreshIfNeeded(requestHost: String) {
    guard !mockMode, supportsPane(.firmware), liveCredentialsAvailable else { return }
    let productID = firmware.productID.trimmingCharacters(in: .whitespacesAndNewlines)
    let currentVersion = firmware.currentVersion.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !productID.isEmpty, !currentVersion.isEmpty else { return }
    guard !firmware.hasLoadedImages else { return }

    firmwareCatalogRefreshTask?.cancel()
    firmwareCatalogRefreshTask = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(nanoseconds: 150_000_000)
        guard let self else { return }
        guard self.connectionStillMatches(requestHost) else {
          self.ignoreStaleOperation(
            "Ignored automatic firmware list for stale host \(requestHost).")
          return
        }
        guard !self.firmware.hasLoadedImages else { return }
        try await self.loadFirmwareImages(
          productID: productID,
          requestHost: requestHost,
          updatesStatus: false)
      } catch is CancellationError {
      } catch {
        guard let self else { return }
        guard self.connectionStillMatches(requestHost) else { return }
        self.appendLog(
          "Automatic firmware list refresh failed: \(Self.userFacingErrorDescription(error.localizedDescription))"
        )
      }
    }
  }

  private func loadFirmwareImages(
    productID: String,
    requestHost: String,
    updatesStatus: Bool
  ) async throws {
    if mockMode {
      loadMockFirmwareImagesIfNeeded(force: true)
      if updatesStatus {
        status = "Firmware list loaded. Mock mode."
      }
      return
    }

    let (data, _) = try await URLSession.shared.data(from: FirmwareCatalog.manifestURL)
    guard connectionStillMatches(requestHost) else {
      ignoreStaleOperation("Ignored firmware list for stale host \(requestHost).")
      return
    }
    let images = try FirmwareCatalog.images(forProductID: productID, in: data)
    applyFirmwareImages(images)
    guard updatesStatus else { return }
    status =
      images.isEmpty
      ? "No Apple firmware images are listed for this base station."
      : "Firmware list loaded."
  }

  private func downloadFirmwareImage(_ image: FirmwareImage) async throws -> URL {
    try await firmwareDownloadService.downloadImage(image) { [weak self] completed, total in
      await MainActor.run {
        self?.updateFirmwareDownloadProgress(
          completed: completed,
          total: total,
          fallbackTotal: image.sizeInBytes)
      }
    }
  }

  private static func firmwareVersionName(from url: URL) -> String {
    let name = url.deletingPathExtension().lastPathComponent.trimmingCharacters(
      in: .whitespacesAndNewlines)
    if !name.isEmpty { return name }
    let fallback = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
    return fallback.isEmpty ? "Chosen Firmware" : fallback
  }

  private static func firmwareSourceIdentifier(for url: URL) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
    let source = url.path.isEmpty ? url.absoluteString : url.path
    let scalars = source.unicodeScalars.map { scalar in
      allowed.contains(scalar) ? Character(scalar) : "-"
    }
    return String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
  }

  private static func fileSize(at url: URL) -> Int {
    let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey])
    if let fileSize = resourceValues?.fileSize {
      return fileSize
    }
    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
    return attributes?[.size] as? Int ?? 0
  }

  private func resetFirmwareTransferProgress() {
    firmware.transferProgress = FirmwareTransferProgress()
  }

  private func updateFirmwareDownloadProgress(
    completed: Int64,
    total: Int64?,
    fallbackTotal: Int
  ) {
    let effectiveTotal = total ?? Int64(max(fallbackTotal, Int(completed), 1))
    firmware.transferProgress = FirmwareTransferProgress.byteProgress(
      phase: .download,
      completed: completed,
      total: effectiveTotal)
  }

  private func updateFirmwareTransferProgress(
    phase: FirmwareTransferPhase,
    completed: Double,
    total: Double,
    detail: String,
    isIndeterminate: Bool = false
  ) {
    if !isIndeterminate {
      firmware.transferProgress = FirmwareTransferProgress.determinate(
        phase: phase,
        completed: completed,
        total: total,
        detail: detail)
      return
    }
    firmware.transferProgress = FirmwareTransferProgress(
      phase: phase,
      completed: completed,
      total: max(total, 1),
      detail: detail,
      isIndeterminate: isIndeterminate)
  }

  private func resetFirmwareUploadProgressBuffer() {
    firmwareUploadProgressBuffer = ""
  }

  private func appendFirmwareUploadProgressOutput(_ text: String) {
    firmwareUploadProgressBuffer += text
    while let newline = firmwareUploadProgressBuffer.firstIndex(where: \.isNewline) {
      let line = String(firmwareUploadProgressBuffer[..<newline])
      firmwareUploadProgressBuffer.removeSubrange(
        ...newline)
      applyFirmwareUploadProgressLine(line)
    }
  }

  private func flushFirmwareUploadProgressOutput() {
    let line = firmwareUploadProgressBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
    firmwareUploadProgressBuffer = ""
    guard !line.isEmpty else { return }
    applyFirmwareUploadProgressLine(line)
  }

  private func applyFirmwareUploadProgressLine(_ line: String) {
    guard let event = Self.firmwareUploadProgressEvent(from: line) else { return }
    switch event.phase {
    case "program":
      updateFirmwareTransferProgress(
        phase: .program,
        completed: Double(event.current),
        total: Double(max(event.total, 1)),
        detail: event.raw.isEmpty ? "\(event.current)/\(event.total)" : event.raw)
    default:
      let total = max(event.total, 1)
      firmware.transferProgress = FirmwareTransferProgress.byteProgress(
        phase: .upload,
        completed: Int64(event.current),
        total: Int64(total))
    }
  }

  private func applyFirmwareUploadResultProgress(_ result: FirmwareUploadCommandResult) {
    guard let current = result.progressCurrent, let total = result.progressTotal else {
      return
    }
    updateFirmwareTransferProgress(
      phase: .program,
      completed: Double(current),
      total: Double(max(total, 1)),
      detail: result.progressText)
  }

  private nonisolated static func firmwareUploadProgressEvent(from line: String)
    -> FirmwareUploadProgressEvent?
  {
    FirmwareUploadParser.progressEvent(from: line)
  }

  private func firmwareUploadRestartStarted(
    image: FirmwareImage,
    connection: AirportConnection,
    requestHost: String,
    wasReinstall: Bool,
    uploadResult: FirmwareUploadCommandResult?,
    suffix: String
  ) {
    updateFirmwareTransferProgress(
      phase: .restart,
      completed: 1,
      total: 1,
      detail: "Restart command sent.")
    status = "Firmware uploaded. \(image.version) will install after restart."
    firmware.installStatus = "Firmware uploaded. Restart requested."
    preview = nil
    beginBaseStationUpdate(requestHost: requestHost)
    scheduleFirmwareCompletionMonitor(
      image: image,
      connection: connection,
      requestHost: requestHost,
      wasReinstall: wasReinstall,
      uploadResult: uploadResult,
      suffix: suffix)
  }

  private func scheduleFirmwareCompletionMonitor(
    image: FirmwareImage,
    connection: AirportConnection,
    requestHost: String,
    wasReinstall: Bool,
    uploadResult: FirmwareUploadCommandResult?,
    suffix: String
  ) {
    firmwareCompletionMonitorTask?.cancel()
    firmwareCompletionMonitorTask = Task { @MainActor [weak self] in
      await self?.monitorFirmwareCompletion(
        image: image,
        connection: connection,
        requestHost: requestHost,
        wasReinstall: wasReinstall,
        uploadResult: uploadResult,
        suffix: suffix)
    }
  }

  private func monitorFirmwareCompletion(
    image: FirmwareImage,
    connection: AirportConnection,
    requestHost: String,
    wasReinstall: Bool,
    uploadResult: FirmwareUploadCommandResult?,
    suffix initialSuffix: String
  ) async {
    do {
      try await Task.sleep(nanoseconds: firmwareInstallVerificationDelayNanoseconds)
    } catch {
      return
    }
    guard !Task.isCancelled else { return }
    if mockMode {
      applyInstalledFirmwareImage(image, reinstalled: wasReinstall, suffix: initialSuffix)
      clearBaseStationUpdate(requestHost: requestHost)
      resetFirmwareTransferProgress()
      clearRecoveryGuidance(forHost: requestHost)
      return
    }
    do {
      _ = try await confirmInstalledFirmwareVersion(
        expectedVersion: image.version,
        connection: connection,
        requireRestartBeforeAccepting: wasReinstall)
      guard connectionStillMatches(requestHost) else {
        ignoreStaleOperation(
          "Ignored firmware install verification for stale host \(requestHost).")
        return
      }
      let completionSuffix: String
      if let uploadResult, uploadResult.progressComplete == true {
        completionSuffix = " Upload reached \(uploadResult.progressText)."
      } else {
        completionSuffix = initialSuffix
      }
      applyInstalledFirmwareImage(image, reinstalled: wasReinstall, suffix: completionSuffix)
      clearBaseStationUpdate(requestHost: requestHost)
      resetFirmwareTransferProgress()
      clearRecoveryGuidance(forHost: requestHost)
    } catch {
      guard connectionStillMatches(requestHost) else { return }
      let errorDescription = Self.userFacingErrorDescription(error.localizedDescription)
      status = errorDescription
      appendLog("Firmware verification failed: \(errorDescription)")
      // postApplyDeviceNameForStatus reflects whatever's currently selected,
      // not necessarily this record's original device, if the user switches
      // base stations mid-flight - a pre-existing characteristic of that
      // property, not new here.
      recoveryGuidance = RecoveryGuidance(
        reason: .firmwareVerificationFailed,
        host: AirportConnection.normalizedHost(requestHost),
        deviceName: postApplyDeviceNameForStatus,
        date: Date(),
        detail: errorDescription)
    }
  }

  private func confirmInstalledFirmwareVersion(
    expectedVersion: String,
    connection: AirportConnection,
    requireRestartBeforeAccepting: Bool
  ) async throws -> String {
    let expectedVersion = Self.normalizedFirmwareVersion(expectedVersion)
    var sawRestart = false
    var lastVersion = ""
    var lastError: Error?
    let attempts = max(firmwareInstallVerificationAttempts, 1)

    for attempt in 1...attempts {
      if attempt > 1 {
        try await Task.sleep(nanoseconds: firmwareInstallVerificationDelayNanoseconds)
      }
      do {
        let identity = try await readBaseStationIdentity(connection: connection)
        let version = Self.normalizedFirmwareVersion(identity.version)
        if version == expectedVersion && (!requireRestartBeforeAccepting || sawRestart) {
          return version
        }
        lastVersion = version
      } catch {
        sawRestart = true
        lastError = error
      }
    }

    if requireRestartBeforeAccepting && !sawRestart && lastVersion == expectedVersion {
      throw FirmwareInstallError.restartNotObserved(expected: expectedVersion)
    }
    if !lastVersion.isEmpty {
      throw FirmwareInstallError.versionMismatch(expected: expectedVersion, actual: lastVersion)
    }
    throw FirmwareInstallError.versionUnavailable(
      expected: expectedVersion, lastError: lastError?.localizedDescription)
  }

  private func applyInstalledFirmwareImage(
    _ image: FirmwareImage, reinstalled: Bool, suffix: String = ""
  ) {
    baseStation.version = image.version
    firmware.currentVersion = image.version
    firmware.installStatus = "Verified installed firmware \(image.version)."
    applyFirmwareImages(firmware.images)
    status =
      reinstalled
      ? "Firmware \(image.version) reinstalled.\(suffix)"
      : "Firmware \(image.version) installed.\(suffix)"
  }

  static func normalizedFirmwareVersion(_ version: String) -> String {
    version.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  nonisolated static func firmwareUploadCommandResult(from output: String)
    -> FirmwareUploadCommandResult?
  {
    FirmwareUploadParser.commandResult(from: output)
  }

  nonisolated static func firmwareUploadStatusSummary(
    from result: FirmwareUploadCommandResult
  ) -> String {
    FirmwareUploadParser.statusSummary(from: result)
  }

  nonisolated static func validateFirmwareUploadResult(
    _ result: FirmwareUploadCommandResult
  ) throws {
    try FirmwareUploadParser.validateResult(result)
  }

  static func usableIdentityText(_ text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return ProfileReader.isUsableSettingText(trimmed) ? trimmed : nil
  }

}
