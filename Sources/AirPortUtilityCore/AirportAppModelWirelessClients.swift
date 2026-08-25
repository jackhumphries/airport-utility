import Foundation

private struct WirelessClientResponse: Decodable {
  var clients: [WirelessClient]
  var clientDiscoveryNote: String?
}

@MainActor
extension AirportAppModel {
  func devicePopoverPresentationDidChange() {
    if isDevicePopoverPresented {
      if mockMode {
        loadMockWirelessClientsIfNeeded()
        hasLoadedWirelessClients = true
      } else {
        restartWirelessClientPollingIfPossible()
      }
    }
  }

  func dashboardPresentationDidChange() {
    if isDashboardVisible {
      if mockMode {
        loadMockWirelessClientsIfNeeded()
        hasLoadedWirelessClients = true
      } else {
        restartWirelessClientPollingIfPossible()
      }
    }
  }

  private func loadMockWirelessClientsIfNeeded() {
    wirelessClientDiscoveryNote = nil
    guard wirelessClients.isEmpty else { return }
    wirelessClients = AirportMockBackend.sampleWirelessClients
  }

  func selectedDeviceForWirelessClientsDidChange() {
    // Selection changes are completed synchronously by selectTopologyDevice,
    // which restarts polling after it updates the connection target.
  }

  func restartWirelessClientPollingIfPossible() {
    guard isDashboardVisible || isDevicePopoverPresented else { return }
    guard !mockMode else { return }
    guard hasLoadedSettings, liveCredentialsAvailable else {
      return
    }
    if usesLegacyACP {
      guard advanced.allowSNMP else {
        stopWirelessClientPolling(clearClients: true)
        hasLoadedWirelessClients = true
        return
      }
      guard !legacySNMPCommunity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        stopWirelessClientPolling(clearClients: true)
        hasLoadedWirelessClients = true
        return
      }
    }

    stopWirelessClientPolling(clearClients: false)
    hasLoadedWirelessClients = false
    let generation = UUID()
    wirelessClientPollGeneration = generation
    let requestConnection = connection
    let requestHost = AirportConnection.normalizedHost(requestConnection.host)
    let requestUsesLegacyACP = usesLegacyACP
    let requestSNMPCommunity = legacySNMPCommunity
    let interval = wirelessClientPollIntervalNanoseconds

    wirelessClientPollTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        do {
          let clients: [WirelessClient]
          if let fetch = wirelessClientFetchOverride {
            clients = try await fetch(
              requestConnection, requestUsesLegacyACP, requestSNMPCommunity)
          } else {
            let discoverIdentities = wirelessClientIdentityDiscoveryIsDue(
              host: requestHost)
            let fetched = try await readWirelessClients(
              connection: requestConnection,
              usesLegacyACP: requestUsesLegacyACP,
              snmpCommunity: requestSNMPCommunity,
              discoverIdentities: discoverIdentities)
            clients = fetched.clients
            if discoverIdentities {
              wirelessClientIdentityDiscoveryHost = requestHost
              lastWirelessClientIdentityDiscoveryDate = Date()
              wirelessClientDiscoveryNote = fetched.discoveryNote
            }
          }
          guard
            wirelessClientPollStillMatches(
              generation: generation,
              host: requestHost)
          else { return }
          wirelessClients = clients.filter { !$0.displayName.isEmpty }
          hasLoadedWirelessClients = true
          lastWirelessClientError = ""
          recordHealthHistorySample()
        } catch is CancellationError {
          return
        } catch {
          guard
            wirelessClientPollStillMatches(
              generation: generation,
              host: requestHost)
          else { return }
          // Wireless clients are optional popover enrichment. Once the first
          // attempt finishes, show the normal device details even if it
          // failed, and let the polling loop retry in the background.
          hasLoadedWirelessClients = true
          let description = Self.userFacingErrorDescription(error.localizedDescription)
          if description != lastWirelessClientError {
            appendLog("Wireless client refresh failed: \(description)")
            lastWirelessClientError = description
          }
        }

        do {
          try await Task.sleep(nanoseconds: interval)
        } catch {
          return
        }
      }
    }
  }

  func stopWirelessClientPolling(clearClients: Bool) {
    wirelessClientPollGeneration = UUID()
    wirelessClientPollTask?.cancel()
    wirelessClientPollTask = nil
    lastWirelessClientError = ""
    if clearClients {
      wirelessClients = []
      hasLoadedWirelessClients = false
      wirelessClientDiscoveryNote = nil
    }
  }

  private func wirelessClientPollStillMatches(
    generation: UUID,
    host: String
  ) -> Bool {
    !Task.isCancelled
      && wirelessClientPollGeneration == generation
      && AirportConnection.normalizedHost(connection.host) == host
  }

  private func wirelessClientIdentityDiscoveryIsDue(
    host: String,
    now: Date = Date()
  ) -> Bool {
    guard wirelessClientIdentityDiscoveryHost == host,
      let lastWirelessClientIdentityDiscoveryDate
    else {
      return true
    }
    return now.timeIntervalSince(lastWirelessClientIdentityDiscoveryDate)
      >= wirelessClientIdentityDiscoveryInterval
  }

  private func readWirelessClients(
    connection: AirportConnection,
    usesLegacyACP: Bool,
    snmpCommunity: String,
    discoverIdentities: Bool
  ) async throws -> (clients: [WirelessClient], discoveryNote: String?) {
    let result = try await runner.run(
      script: AirportCommand.backendScript,
      arguments: AirportCommand.wirelessClients(
        connection: connection,
        usesLegacyACP: usesLegacyACP,
        snmpCommunity: snmpCommunity,
        discoverIdentities: discoverIdentities),
      connection: connection,
      timeout: 15)
    if discoverIdentities {
      for line in result.stderr.split(whereSeparator: \.isNewline) {
        let message = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
        if message.hasPrefix("identity discovery:") {
          appendLog(message)
        }
      }
    }
    let decoded = try JSONDecoder().decode(
      WirelessClientResponse.self, from: Data(result.stdout.utf8))
    return (decoded.clients, decoded.clientDiscoveryNote)
  }
}
