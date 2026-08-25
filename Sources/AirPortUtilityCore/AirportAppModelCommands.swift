import Foundation

extension AirportAppModel {
  enum ConfigurationVerification {
    case unreachable, reachable, matched
  }

  private func shouldTrackBaseStationUpdate(cleanScope: CleanScope) -> Bool {
    cleanScope != .none
  }

  @discardableResult
  func refreshSettingsAfterApply(
    requestHost: String,
    expectedSnapshot: AirportSettingsSnapshot? = nil,
    cleanScope: CleanScope? = nil
  ) async -> ConfigurationVerification {
    defer {
      clearBaseStationUpdate(requestHost: requestHost)
    }
    let deviceName = postApplyDeviceNameForStatus
    status = "Waiting for \(deviceName) to restart."
    var lastError: Error?
    let maxAttempts = usesLegacyACP ? 18 : 12
    for attempt in 1...maxAttempts {
      do {
        try await Task.sleep(nanoseconds: 5_000_000_000)
      } catch {
        lastError = error
        break
      }
      guard connectionStillMatches(requestHost) else {
        ignoreStaleOperation("Stopped post-apply refresh for stale host \(requestHost).")
        return .unreachable
      }
      do {
        status = "Waiting for \(deviceName) to come back online."
        try await refreshSettings()
        guard connectionStillMatches(requestHost) else { return .unreachable }
        clearBaseStationUpdate(requestHost: requestHost)
        guard let expectedSnapshot, let cleanScope else { return .reachable }
        return configurationMatches(expectedSnapshot, scope: cleanScope) ? .matched : .reachable
      } catch {
        lastError = error
        appendLog(
          "Post-apply refresh attempt \(attempt) failed: \(Self.userFacingErrorDescription(error.localizedDescription))"
        )
      }
    }
    // The retry operation is over even when the base station could not be
    // reached. Do not leave its topology node permanently marked Restarting;
    // a later Bonjour rediscovery should use the device's advertised status.
    clearBaseStationUpdate(requestHost: requestHost)
    if let lastError {
      let errorDescription = Self.userFacingErrorDescription(lastError.localizedDescription)
      status = "Could not confirm \(deviceName) came back online: \(errorDescription)"
      appendLog("Post-apply refresh failed: \(errorDescription)")
    }
    return .unreachable
  }

  var postApplyDeviceNameForStatus: String {
    if usesLegacyACP {
      return "AirPort Express"
    }
    switch baseStation.productID.trimmingCharacters(in: .whitespacesAndNewlines) {
    case "102", "107", "115":
      return "AirPort Express"
    case "106", "109", "113", "116", "119":
      return "Time Capsule"
    case "3", "104", "105", "108", "114", "117", "120":
      return "AirPort Extreme"
    default:
      return "base station"
    }
  }

  func ignoreStaleOperation(_ message: String) {
    appendLog(message)
    updateIdleConnectionStatus()
  }

  func clearPreviewAfterValidationFailure() {
    preview = nil
  }

  private func writeScriptForCurrentConnection() -> String {
    usesLegacyACP ? AirportCommand.legacyWriteScript : AirportCommand.writeScript
  }

  private func writeArgumentsForCurrentConnection(_ args: [String]) -> [String] {
    guard usesLegacyACP else { return args }
    var arguments = args.usingAirPortBackendSubcommand("legacy-write")
    if usesLegacyACP17, !arguments.contains("--acp17") {
      arguments.append("--acp17")
    }
    if usesLegacyFullSnapshotWrites,
      !legacyACPSettingsValuesJSON.isEmpty,
      !arguments.contains("--base-values-json")
    {
      arguments += ["--base-values-json", legacyACPSettingsValuesJSON, "--apply"]
    }
    return arguments
  }

  var usesLegacyFullSnapshotWrites: Bool {
    usesLegacyACP
  }

  var usesLegacyACP17: Bool {
    let selectedProductID =
      selectedTopologyDevice()?.productID.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let productID =
      selectedProductID.isEmpty
      ? baseStation.productID.trimmingCharacters(in: .whitespacesAndNewlines)
      : selectedProductID
    // Both of these models are confirmed by captured AirPort Utility traffic
    // to negotiate the command-0x17 DH/AES transport. Product 102 is the
    // original 802.11g AirPort Express; product 3 is the "spaceship" Extreme.
    return productID == "3" || productID == "102"
  }

  func appliedWriteArguments(_ args: [String]) -> [String] {
    var applied = writeArgumentsForCurrentConnection(args)
    if usesLegacyACP && !usesLegacyFullSnapshotWrites {
      applied.append("--restart")
    }
    if needsSetupCompletion() {
      applied.append("--setup-complete")
    }
    return applied
  }

  func appliedFinalCommand(_ commands: [(String, [String])]) -> [(String, [String])] {
    guard !commands.isEmpty else { return commands }
    let shouldMarkFinal = usesLegacyACP || needsSetupCompletion()
    guard usesLegacyACP || shouldMarkFinal else { return commands }

    var applied = commands
    if usesLegacyACP {
      applied = applied.map { ($0.0, writeArgumentsForCurrentConnection($0.1)) }
    }
    guard shouldMarkFinal else { return applied }

    var final = applied[applied.count - 1]
    if usesLegacyACP && !usesLegacyFullSnapshotWrites {
      final.1.append("--restart")
    } else {
      final.1 = writeArgumentsForCurrentConnection(final.1)
    }
    if needsSetupCompletion() {
      final.1.append("--setup-complete")
    }
    applied[applied.count - 1] = final
    return applied
  }

  private func needsSetupCompletion() -> Bool {
    let host = AirportConnection.normalizedHost(connection.host)
    return visibleTopologyDevices.contains { device in
      guard device.requiresSetup else { return false }
      if !host.isEmpty, device.matchesConnectionHost(host) {
        return true
      }
      return device.sharesStableIdentity(with: selectedTopologyDeviceIdentifiers)
        || device.sharesStableIdentity(with: connectedTopologyDeviceIdentifiers)
    }
  }

  func dryRun(title: String, args: [String], connection: AirportConnection) {
    let args = writeArgumentsForCurrentConnection(args)
    let requestHost = AirportConnection.normalizedHost(connection.host)
    let writeScript = writeScriptForCurrentConnection()
    runTask("Running \(title) dry-run", requestHost: requestHost) {
      if self.mockMode {
        let redacted = AirportCommand.redact(args)
        let output = AirportMockBackend.output(for: args, dryRun: true)
        guard self.connectionStillMatches(requestHost) else {
          self.ignoreStaleOperation("Ignored \(title) dry-run for stale host \(requestHost).")
          return
        }
        self.preview = CommandPreview(
          title: title, arguments: args, redactedArguments: redacted, output: output)
        self.appendLog(
          "$ \(AirportCommand.display(writeScript, redacted))\n\(output)")
        if output.localizedCaseInsensitiveContains("failed") {
          self.status = output
        } else {
          self.status = "\(title) dry-run succeeded. Mock mode."
        }
        return
      }
      let result = try await self.runner.run(
        script: writeScript, arguments: args, connection: connection)
      guard self.connectionStillMatches(requestHost) else {
        self.ignoreStaleOperation("Ignored \(title) dry-run for stale host \(requestHost).")
        return
      }
      let output = Self.userFacingCommandOutput(result.combinedOutput)
      self.preview = CommandPreview(
        title: title,
        arguments: args,
        redactedArguments: result.redactedArguments,
        output: output
      )
      self.appendLog(
        "$ \(AirportCommand.display(writeScript, result.redactedArguments))\n\(output)"
      )
      self.status = "\(title) dry-run succeeded."
    }
  }

  func dryRunSequence(
    title: String, commands: [(String, [String])], connection: AirportConnection
  ) {
    let commands = commands.map { ($0.0, writeArgumentsForCurrentConnection($0.1)) }
    let requestHost = AirportConnection.normalizedHost(connection.host)
    let writeScript = writeScriptForCurrentConnection()
    runTask("Running \(title) dry-run", requestHost: requestHost) {
      if self.mockMode {
        guard self.connectionStillMatches(requestHost) else {
          self.ignoreStaleOperation("Ignored \(title) dry-run for stale host \(requestHost).")
          return
        }
        var outputParts: [String] = []
        var firstArgs: [String] = []
        var firstRedacted: [String] = []
        for (commandTitle, args) in commands {
          let redacted = AirportCommand.redact(args)
          if firstArgs.isEmpty {
            firstArgs = args
            firstRedacted = redacted
          }
          let output = AirportMockBackend.output(for: args, dryRun: true)
          outputParts.append("\(commandTitle): \(output)")
          self.appendLog(
            "$ \(AirportCommand.display(writeScript, redacted))\n\(output)")
        }
        guard self.connectionStillMatches(requestHost) else {
          self.ignoreStaleOperation("Ignored \(title) dry-run for stale host \(requestHost).")
          return
        }
        let output = outputParts.joined(separator: "\n")
        self.preview = CommandPreview(
          title: title, arguments: firstArgs, redactedArguments: firstRedacted, output: output)
        self.status = "\(title) dry-run succeeded. Mock mode."
        return
      }

      var outputParts: [String] = []
      var firstResult: CommandResult?
      for (commandTitle, args) in commands {
        guard self.connectionStillMatches(requestHost) else {
          self.ignoreStaleOperation("Stopped \(title) dry-run for stale host \(requestHost).")
          return
        }
        let result = try await self.runner.run(
          script: writeScript, arguments: args, connection: connection)
        guard self.connectionStillMatches(requestHost) else {
          self.ignoreStaleOperation(
            "Ignored \(title) dry-run result for stale host \(requestHost).")
          return
        }
        if firstResult == nil { firstResult = result }
        let output = Self.userFacingCommandOutput(result.combinedOutput)
        outputParts.append("\(commandTitle): \(output)")
        self.appendLog(
          "$ \(AirportCommand.display(writeScript, result.redactedArguments))\n\(output)"
        )
      }
      guard self.connectionStillMatches(requestHost) else {
        self.ignoreStaleOperation("Ignored \(title) dry-run for stale host \(requestHost).")
        return
      }
      if let firstResult {
        self.preview = CommandPreview(
          title: title,
          arguments: firstResult.arguments,
          redactedArguments: firstResult.redactedArguments,
          output: outputParts.joined(separator: "\n")
        )
      }
      self.status = "\(title) dry-run succeeded."
    }
  }

  func apply(
    title: String, args: [String], connection: AirportConnection,
    cleanScope: CleanScope = .all,
    appliedSnapshot: AirportSettingsSnapshot? = nil,
    appliedAdminPassword: String = "",
    completion: @escaping () -> Void = {}
  ) {
    guard !isBusy else { return }
    let args = writeArgumentsForCurrentConnection(args)
    let requestHost = AirportConnection.normalizedHost(connection.host)
    let writeScript = writeScriptForCurrentConnection()
    let appliedSnapshot = appliedSnapshot ?? currentSnapshot
    let tracksBaseStationUpdate = shouldTrackBaseStationUpdate(cleanScope: cleanScope)
    let shouldRecordChange = tracksBaseStationUpdate && !mockMode
    let changeID = shouldRecordChange
      ? prepareConfigurationChange(title: title, host: requestHost) : nil
    if shouldRecordChange, changeID == nil { return }
    if tracksBaseStationUpdate {
      beginBaseStationUpdate(requestHost: requestHost)
    }
    runTask("Applying \(title)", requestHost: requestHost) {
      if self.mockMode {
        let redacted = AirportCommand.redact(args)
        let output = AirportMockBackend.output(for: args, dryRun: false)
        guard self.connectionStillMatches(requestHost) else {
          self.ignoreStaleOperation("Ignored \(title) apply result for stale host \(requestHost).")
          return
        }
        self.appendLog(
          "$ \(AirportCommand.display(writeScript, redacted))\n\(output)")
        completion()
        self.status = "\(title) applied. Mock mode."
        self.preview = nil
        self.markClean(
          cleanScope, from: appliedSnapshot, appliedAdminPassword: appliedAdminPassword)
        self.updateConfigurationChange(changeID, status: .verifiedReachable)
        if tracksBaseStationUpdate {
          self.clearBaseStationUpdate(requestHost: requestHost)
        }
        return
      }
      let result: CommandResult
      do {
        result = try await self.runner.run(
          script: writeScript, arguments: args, connection: connection,
          timeout: 90)
      } catch {
        self.updateConfigurationChange(changeID, status: .writeFailed)
        if tracksBaseStationUpdate {
          self.clearBaseStationUpdate(requestHost: requestHost)
        }
        throw error
      }
      guard self.connectionStillMatches(requestHost) else {
        self.ignoreStaleOperation("Ignored \(title) apply result for stale host \(requestHost).")
        return
      }
      let output = Self.userFacingCommandOutput(result.combinedOutput)
      self.appendLog(
        "$ \(AirportCommand.display(writeScript, result.redactedArguments))\n\(output)"
      )
      completion()
      self.status = "\(title) applied."
      self.preview = nil
      self.markClean(
        cleanScope, from: appliedSnapshot, appliedAdminPassword: appliedAdminPassword)
      self.updateConfigurationChange(changeID, status: .applied)
      if tracksBaseStationUpdate {
        let verification = await self.refreshSettingsAfterApply(
          requestHost: requestHost, expectedSnapshot: appliedSnapshot, cleanScope: cleanScope)
        self.recordConfigurationVerification(changeID, verification: verification)
      }
    }
  }

  func applySequence(
    title: String, commands: [(String, [String])], connection: AirportConnection,
    cleanScope: CleanScope = .all,
    appliedSnapshot: AirportSettingsSnapshot? = nil,
    appliedAdminPassword: String = "",
    delayBetweenCommandsNanoseconds: UInt64 = 0,
    allowsConnectionHostChange: Bool = false,
    completion: @escaping () -> Void = {},
    failure: @escaping (String) -> Void = { _ in }
  ) {
    guard !isBusy else { return }
    let requestHost = AirportConnection.normalizedHost(connection.host)
    let writeScript = writeScriptForCurrentConnection()
    let appliedSnapshot = appliedSnapshot ?? currentSnapshot
    let tracksBaseStationUpdate = shouldTrackBaseStationUpdate(cleanScope: cleanScope)
    let shouldRecordChange = tracksBaseStationUpdate && !mockMode
    let changeID = shouldRecordChange
      ? prepareConfigurationChange(title: title, host: requestHost) : nil
    if shouldRecordChange, changeID == nil { return }
    if tracksBaseStationUpdate {
      beginBaseStationUpdate(requestHost: requestHost)
    }
    runTask("Applying \(title)", requestHost: requestHost) {
      if self.mockMode {
        guard allowsConnectionHostChange || self.connectionStillMatches(requestHost) else {
          self.ignoreStaleOperation("Ignored \(title) apply result for stale host \(requestHost).")
          return
        }
        for (_, args) in commands {
          let redacted = AirportCommand.redact(args)
          let output = AirportMockBackend.output(for: args, dryRun: false)
          self.appendLog(
            "$ \(AirportCommand.display(writeScript, redacted))\n\(output)")
        }
        guard allowsConnectionHostChange || self.connectionStillMatches(requestHost) else {
          self.ignoreStaleOperation("Ignored \(title) apply result for stale host \(requestHost).")
          return
        }
        completion()
        self.status = "\(title) applied. Mock mode."
        self.preview = nil
        self.markClean(
          cleanScope, from: appliedSnapshot, appliedAdminPassword: appliedAdminPassword)
        self.updateConfigurationChange(changeID, status: .verifiedReachable)
        if tracksBaseStationUpdate {
          self.clearBaseStationUpdate(requestHost: requestHost)
        }
        return
      }
      var didApplyCommand = false
      for (index, command) in commands.enumerated() {
        let (_, args) = command
        if index > 0, delayBetweenCommandsNanoseconds > 0 {
          try await Task.sleep(nanoseconds: delayBetweenCommandsNanoseconds)
        }
        guard allowsConnectionHostChange || self.connectionStillMatches(requestHost) else {
          self.ignoreStaleOperation("Stopped \(title) apply for stale host \(requestHost).")
          return
        }
        let result: CommandResult
        do {
          result = try await self.runner.run(
            script: writeScript, arguments: args, connection: connection,
            timeout: 90)
        } catch {
          self.updateConfigurationChange(changeID, status: .writeFailed)
          if tracksBaseStationUpdate && !didApplyCommand {
            self.clearBaseStationUpdate(requestHost: requestHost)
          }
          failure(Self.userFacingErrorDescription(error.localizedDescription))
          throw error
        }
        didApplyCommand = true
        guard allowsConnectionHostChange || self.connectionStillMatches(requestHost) else {
          self.ignoreStaleOperation("Ignored \(title) apply result for stale host \(requestHost).")
          return
        }
        let output = Self.userFacingCommandOutput(result.combinedOutput)
        self.appendLog(
          "$ \(AirportCommand.display(writeScript, result.redactedArguments))\n\(output)"
        )
      }
      guard allowsConnectionHostChange || self.connectionStillMatches(requestHost) else {
        self.ignoreStaleOperation("Ignored \(title) apply result for stale host \(requestHost).")
        return
      }
      completion()
      self.status = "\(title) applied."
      self.preview = nil
      self.markClean(
        cleanScope, from: appliedSnapshot, appliedAdminPassword: appliedAdminPassword)
      self.updateConfigurationChange(changeID, status: .applied)
      if tracksBaseStationUpdate {
        let verification = await self.refreshSettingsAfterApply(
          requestHost: requestHost, expectedSnapshot: appliedSnapshot, cleanScope: cleanScope)
        self.recordConfigurationVerification(changeID, verification: verification)
      }
    }
  }

  private func recordConfigurationVerification(
    _ id: UUID?, verification: ConfigurationVerification
  ) {
    switch verification {
    case .matched:
      updateConfigurationChange(id, status: .verifiedExpected)
    case .reachable:
      updateConfigurationChange(id, status: .verificationMismatch)
    case .unreachable:
      updateConfigurationChange(id, status: .verificationFailed)
    }
  }

  func configurationMatches(_ expected: AirportSettingsSnapshot, scope: CleanScope) -> Bool {
    guard
      let expected = try? ConfigurationHistoryStore.omittingSensitiveValues(from: expected),
      let actual = try? ConfigurationHistoryStore.omittingSensitiveValues(from: currentSnapshot)
    else { return false }
    switch scope {
    case .all:
      return comparable(actual) == comparable(expected)
    case .none, .adminPassword:
      return true
    case .baseStation:
      return comparable(actual.baseStation) == comparable(expected.baseStation)
        && comparable(actual.legacyDeviceOptions).baseStation
          == comparable(expected.legacyDeviceOptions).baseStation
    case .baseStationName:
      return actual.baseStation.name == expected.baseStation.name
    case .internet:
      return comparable(actual.internet) == comparable(expected.internet)
    case .wireless:
      return comparable(actual.wireless) == comparable(expected.wireless)
        && comparable(actual.legacyDeviceOptions).wireless
          == comparable(expected.legacyDeviceOptions).wireless
    case .network:
      return comparable(actual.network) == comparable(expected.network)
        && comparable(actual.legacyDeviceOptions).dhcp
          == comparable(expected.legacyDeviceOptions).dhcp
    case .airPlay:
      return comparable(actual.airPlay) == comparable(expected.airPlay)
    case .disks:
      return comparable(actual.disks) == comparable(expected.disks)
    case .advanced:
      return actual.advanced == expected.advanced
        && comparable(actual.legacyDeviceOptions).accessControl
          == comparable(expected.legacyDeviceOptions).accessControl
    }
  }

  func runTask(
    _ busyStatus: String,
    requestHost: String? = nil,
    operation: @escaping () async throws -> Void
  ) {
    guard !isBusy else { return }
    isBusy = true
    status = busyStatus
    Task {
      defer {
        isBusy = false
        applyPendingTopologyConnectionHostIfNeeded()
        refreshAfterBusySelectionIfNeeded()
        startPendingRestoreIfNeeded()
      }
      do {
        try await operation()
      } catch {
        if let requestHost, !connectionStillMatches(requestHost) {
          ignoreStaleOperation("Ignored \(busyStatus) failure for stale host \(requestHost).")
        } else {
          let errorDescription = Self.userFacingErrorDescription(error.localizedDescription)
          if busyStatus == "Refreshing settings" {
            hasTrustedConnectionPassword = false
          }
          preview = nil
          status = errorDescription
          appendLog("Error: \(errorDescription)")
        }
      }
    }
  }

  private func refreshAfterBusySelectionIfNeeded() {
    guard shouldRefreshAfterBusySelection else { return }
    shouldRefreshAfterBusySelection = false
    refreshLiveSettingsIfPossible()
  }

  private func applyPendingTopologyConnectionHostIfNeeded() {
    guard let host = pendingTopologyConnectionHost else { return }
    pendingTopologyConnectionHost = nil
    connection.host = host
  }

  nonisolated static func userFacingErrorDescription(_ description: String) -> String {
    DiskInventoryMessage.userFacingErrorDescription(description)
  }

  nonisolated static func userFacingCommandOutput(_ output: String) -> String {
    DiskInventoryMessage.userFacingCommandOutput(output)
  }

    func appendLog(_ message: String) {
      let message = Self.sanitizedLogMessage(message)
      guard !message.isEmpty else { return }

      logs.insert(message, at: 0)
      logs = Array(logs.prefix(60))

      AppLogger.shared.info(
        message,
        category: .backend
      )
    }

  func appendDeduplicatedLog(_ message: String) {
    let message = Self.sanitizedLogMessage(message)
    guard !message.isEmpty else { return }
    if logs.first != message {
      logs.insert(message, at: 0)
      logs = Array(logs.prefix(60))
    }
  }

  nonisolated static func sanitizedLogMessage(_ message: String) -> String {
    DiskInventoryMessage.sanitizedLogMessage(message)
  }
}
