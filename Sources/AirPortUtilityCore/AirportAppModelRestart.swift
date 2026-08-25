import Foundation

@MainActor
extension AirportAppModel {
  public var canRequestRestartBaseStation: Bool {
    !isBusy && !isRestorePending && !isRestoringDefaults && !isShowingSetup
      && !isShowingRestoreConfirmation && selectedTopologyDevice() != nil
      && !(selectedTopologyDevice().map(isTopologyDeviceRestarting) ?? false)
  }

  public func requestRestartBaseStation() {
    guard canRequestRestartBaseStation else { return }
    guard mockMode || liveCredentialsAvailable else {
      presentSelectedDeviceConnectionPrompt()
      return
    }
    // Present the confirmation before dismissing the device popover. SwiftUI
    // reports the popover dismissal through its binding, and that callback
    // must be able to distinguish this handoff from an ordinary deselection.
    isShowingRestartConfirmation = true
    isDevicePopoverPresented = false
    isInternetPopoverPresented = false
    clearAuxiliarySheets()
  }

  public func restartBaseStation() {
    guard isShowingRestartConfirmation, canRequestRestartBaseStation,
      let selectedDevice = selectedTopologyDevice()
    else {
      isShowingRestartConfirmation = false
      return
    }
    guard mockMode || liveCredentialsAvailable else {
      presentSelectedDeviceConnectionPrompt()
      return
    }

    let activeConnection = connection
    let requestHost = AirportConnection.normalizedHost(activeConnection.host)
    let usesLegacyRestartTransport = usesLegacyACP || usesLegacyACP17
    let usesACP17RestartTransport = usesLegacyACP17
    let command = restartCommand(connection: activeConnection)
    let deviceName = selectedDevice.displayName
    let restartID = beginBaseStationRestartTracking(
      device: selectedDevice, requestHost: requestHost)

    isShowingRestartConfirmation = false
    runTask("Restarting \(deviceName)", requestHost: requestHost) {
      if self.mockMode {
        let redacted = AirportCommand.redact(command)
        let output = AirportMockBackend.output(for: command, dryRun: false)
        self.appendLog(
          "$ \(AirportCommand.display(AirportCommand.legacyWriteScript, redacted))\n\(output)")
        self.status = "\(deviceName) restarted. Mock mode."
        self.clearBaseStationRestartTracking(id: restartID)
        return
      }

      let result: CommandResult
      do {
        result = try await self.runner.run(
          script: AirportCommand.legacyWriteScript,
          arguments: command,
          connection: activeConnection,
          timeout: 90)
      } catch {
        self.clearBaseStationRestartTracking(id: restartID)
        throw error
      }

      let output = Self.userFacingCommandOutput(result.combinedOutput)
      self.appendLog(
        "$ \(AirportCommand.display(AirportCommand.legacyWriteScript, result.redactedArguments))\n\(output)"
      )
      self.markBaseStationRestartCommandAccepted(id: restartID, requestHost: requestHost)
      self.startBaseStationRestartRecoveryPolling(
        id: restartID,
        connection: activeConnection,
        usesLegacyTransport: usesLegacyRestartTransport,
        usesACP17Transport: usesACP17RestartTransport)
    }
  }

  @discardableResult
  func beginBaseStationRestartTracking(
    device: AirportDiscoveredDevice,
    requestHost: String
  ) -> UUID {
    let restartID = UUID()
    let rootIndex = visibleTopologyDevices.firstIndex { $0.id == device.id }
    let connectionHosts = Self.uniqueNonEmptyValues(
      device.normalizedConnectionHosts + [AirportConnection.normalizedHost(requestHost)])
    let snapshot = TopologyDeviceDisplaySnapshot(
      displayName: device.displayName,
      stableIdentifiers: device.normalizedStableIdentifiers,
      connectionHosts: connectionHosts,
      modelName: device.modelName,
      productID: device.productID,
      rootIndex: rootIndex,
      expiresAt: nil)
    var trackers = baseStationRestartTrackers
    trackers[restartID] = BaseStationRestartTracker(
      id: restartID,
      deviceID: device.id,
      stableIdentifiers: device.normalizedStableIdentifiers,
      connectionHosts: connectionHosts,
      displaySnapshot: snapshot,
      didDisappearFromBonjour: false,
      didFailActiveProbe: false)
    baseStationRestartTrackers = trackers
    scheduleBaseStationRestartTimeout(id: restartID, deviceName: device.displayName)
    isDevicePopoverPresented = false
    return restartID
  }

  func clearBaseStationRestartTracking(id: UUID) {
    var trackers = baseStationRestartTrackers
    trackers.removeValue(forKey: id)
    baseStationRestartTrackers = trackers
    if baseStationRestartStatusTrackerID == id {
      baseStationRestartStatusTrackerID = nil
    }
    var tasks = baseStationRestartTimeoutTasks
    tasks.removeValue(forKey: id)?.cancel()
    baseStationRestartTimeoutTasks = tasks
    var recoveryTasks = baseStationRestartRecoveryTasks
    recoveryTasks.removeValue(forKey: id)?.cancel()
    baseStationRestartRecoveryTasks = recoveryTasks
  }

  func reconcileBaseStationRestartTracking(with devices: [AirportDiscoveredDevice]) {
    guard !baseStationRestartTrackers.isEmpty else { return }
    var trackers = baseStationRestartTrackers
    var completedTrackers: [BaseStationRestartTracker] = []
    for (id, var tracker) in trackers {
      guard
        let returnedDevice = devices.first(where: {
          baseStationRestartTracker(tracker, matches: $0)
        })
      else {
        tracker.didDisappearFromBonjour = true
        trackers[id] = tracker
        continue
      }
      if tracker.didDisappearFromBonjour && !returnedDevice.problemCodes.contains("waNI") {
        completedTrackers.append(tracker)
      }
    }
    baseStationRestartTrackers = trackers
    for tracker in completedTrackers {
      completeBaseStationRestartTracking(id: tracker.id)
    }
  }

  func isTopologyDeviceRestarting(_ device: AirportDiscoveredDevice) -> Bool {
    baseStationRestartTrackers.values.contains {
      baseStationRestartTracker($0, matches: device)
    }
  }

  func baseStationRestartTracker(
    matching device: AirportDiscoveredDevice
  ) -> BaseStationRestartTracker? {
    baseStationRestartTrackers.values.first {
      baseStationRestartTracker($0, matches: device)
    }
  }

  func baseStationRestartTracker(
    _ tracker: BaseStationRestartTracker,
    matches device: AirportDiscoveredDevice
  ) -> Bool {
    if tracker.deviceID == device.id {
      return true
    }
    if device.sharesStableIdentity(with: tracker.stableIdentifiers) {
      return true
    }
    let trackerHosts = Set(
      tracker.connectionHosts.map(AirportConnection.normalizedHost).filter { !$0.isEmpty })
    return !trackerHosts.isEmpty
      && !Set(device.normalizedConnectionHosts).isDisjoint(with: trackerHosts)
  }

  private func scheduleBaseStationRestartTimeout(id: UUID, deviceName: String) {
    let timeout = baseStationRestartTimeoutNanoseconds
    var tasks = baseStationRestartTimeoutTasks
    tasks[id]?.cancel()
    tasks[id] = Task { [weak self] in
      do {
        try await Task.sleep(nanoseconds: timeout)
      } catch {
        return
      }
      guard let self, let tracker = self.baseStationRestartTrackers[id] else { return }
      let ownsWaitingStatus =
        self.baseStationRestartStatusTrackerID == id
        && self.status == self.baseStationRestartWaitingStatus(for: tracker)
      self.clearBaseStationRestartTracking(id: id)
      if ownsWaitingStatus {
        self.status = "Could not confirm \(deviceName) came back online."
      }
      self.appendLog("Stopped waiting for \(deviceName) to finish restarting.")
      self.recoveryGuidance = RecoveryGuidance(
        reason: .restartDidNotComplete,
        host: AirportConnection.normalizedHost(tracker.connectionHosts.first ?? ""),
        deviceName: deviceName,
        date: Date(),
        detail: "Could not confirm \(deviceName) came back online.")
    }
    baseStationRestartTimeoutTasks = tasks
  }

  func startBaseStationRestartRecoveryPolling(
    id: UUID,
    connection: AirportConnection,
    usesLegacyTransport: Bool,
    usesACP17Transport: Bool
  ) {
    guard baseStationRestartTrackers[id] != nil else { return }
    let interval = baseStationRestartPollIntervalNanoseconds
    var tasks = baseStationRestartRecoveryTasks
    tasks[id]?.cancel()
    tasks[id] = Task { [weak self] in
      while !Task.isCancelled {
        do {
          try await Task.sleep(nanoseconds: interval)
        } catch {
          return
        }
        guard let self, self.baseStationRestartTrackers[id] != nil else { return }
        let isReachable = await self.probeBaseStationRestartConnection(
          connection,
          usesLegacyTransport: usesLegacyTransport,
          usesACP17Transport: usesACP17Transport)
        guard !Task.isCancelled else { return }
        self.recordBaseStationRestartProbeResult(id: id, isReachable: isReachable)
      }
    }
    baseStationRestartRecoveryTasks = tasks
  }

  func recordBaseStationRestartProbeResult(id: UUID, isReachable: Bool) {
    guard var tracker = baseStationRestartTrackers[id] else { return }
    if !isReachable {
      guard !tracker.didFailActiveProbe else { return }
      tracker.didFailActiveProbe = true
      var trackers = baseStationRestartTrackers
      trackers[id] = tracker
      baseStationRestartTrackers = trackers
      appendLog(
        "Confirmed \(tracker.displaySnapshot.displayName) went offline while restarting.")
      return
    }

    guard tracker.didFailActiveProbe || tracker.didDisappearFromBonjour else { return }
    guard
      let returnedDevice = discoveredDevices.first(where: {
        baseStationRestartTracker(tracker, matches: $0)
      }),
      !returnedDevice.problemCodes.contains("waNI")
    else { return }
    completeBaseStationRestartTracking(id: id)
  }

  private func probeBaseStationRestartConnection(
    _ connection: AirportConnection,
    usesLegacyTransport: Bool,
    usesACP17Transport: Bool
  ) async -> Bool {
    if let probe = baseStationRestartProbeOverride {
      return await probe(connection, usesLegacyTransport, usesACP17Transport)
    }

    var arguments = AirportCommand.readSettings(
      ["syNm", "syVs", "syAP"], connection: connection, json: true)
    let script: String
    if usesLegacyTransport {
      arguments = arguments.usingAirPortBackendSubcommand("legacy-read")
      if usesACP17Transport {
        arguments.append("--acp17")
      }
      script = AirportCommand.legacyReadScript
    } else {
      script = AirportCommand.readScript
    }

    do {
      let result = try await runner.run(
        script: script,
        arguments: arguments,
        connection: connection,
        timeout: baseStationRestartProbeTimeout)
      let value = try JSONDecoder().decode(JSONValue.self, from: Data(result.stdout.utf8))
      let reader = ProfileReader(value)
      return reader.string("settings.syNm") != nil
        && reader.string("settings.syVs") != nil
    } catch {
      return false
    }
  }

  func markBaseStationRestartCommandAccepted(id: UUID, requestHost: String) {
    guard connectionStillMatches(requestHost) else { return }
    guard let tracker = baseStationRestartTrackers[id] else {
      restoreConnectionStatusAfterRestart()
      return
    }
    baseStationRestartStatusTrackerID = id
    status = baseStationRestartWaitingStatus(for: tracker)
  }

  private func completeBaseStationRestartTracking(id: UUID) {
    guard let tracker = baseStationRestartTrackers[id] else { return }
    let ownsWaitingStatus =
      baseStationRestartStatusTrackerID == id
      && status == baseStationRestartWaitingStatus(for: tracker)
    clearBaseStationRestartTracking(id: id)
    if ownsWaitingStatus {
      restoreConnectionStatusAfterRestart()
    }
    appendLog("Confirmed \(tracker.displaySnapshot.displayName) came back online.")
    clearRecoveryGuidance(forHost: tracker.connectionHosts.first ?? "")
  }

  private func baseStationRestartWaitingStatus(
    for tracker: BaseStationRestartTracker
  ) -> String {
    "Waiting for \(tracker.displaySnapshot.displayName) to come back online."
  }

  private func restoreConnectionStatusAfterRestart() {
    if hasLoadedSettings, liveCredentialsAvailable {
      status = "Connected to \(connection.host)"
    } else {
      updateIdleConnectionStatus()
    }
  }

  func restartCommand(connection activeConnection: AirportConnection) -> [String] {
    let emptyBytes = #"{"type":"bytes","hex":""}"#
    let usesLegacyRestartTransport = usesLegacyACP || usesLegacyACP17
    var arguments =
      AirportCommand.rawWriteJSON(
        setting: "acRB", valueJSON: emptyBytes, connection: activeConnection, dryRun: false
      ).usingAirPortBackendSubcommand(
        usesLegacyRestartTransport ? "legacy-write" : "property-write"
      ) + ["--request-flags", "0"]
    if usesLegacyRestartTransport {
      arguments.append("--streaming")
      if usesLegacyACP17 {
        arguments.append("--acp17")
      }
    }
    return arguments
  }
}
