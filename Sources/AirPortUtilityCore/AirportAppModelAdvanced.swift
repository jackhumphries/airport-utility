import Foundation

@MainActor
extension AirportAppModel {
  func previewAdvanced() {
    guard supportsPane(.advanced) else {
      status = localized("This base station does not support advanced settings.")
      clearPreviewAfterValidationFailure()
      return
    }
    previewFriendlySettings(
      title: "Advanced",
      noChangesStatus: localized("No pending Advanced changes to preview.")
    ) {
      advancedFlags(changesOnly: true)
    }
  }

  func applyAdvanced() {
    guard supportsPane(.advanced) else {
      status = localized("This base station does not support advanced settings.")
      clearPreviewAfterValidationFailure()
      return
    }
    applyFriendlySettings(
      title: "Advanced",
      noChangesStatus: localized("No pending Advanced changes to apply."),
      cleanScope: .advanced
    ) {
      advancedFlags(changesOnly: true)
    }
  }

  func advancedFlags(changesOnly: Bool = false) -> [(String, String?)]? {
    var flags: [(String, String?)] = []

    if capabilities.supportsLogging {
      let destination = normalized(advanced.syslogDestinationAddress)
      let cleanDestination = normalized(cleanSnapshot.advanced.syslogDestinationAddress)
      if !changesOnly || destination != cleanDestination {
        guard destination.isEmpty || isIPv4Address(destination) else {
          status = localized("Syslog Destination Address must be an IPv4 address.")
          return nil
        }
        flags.append(("--syslog-destination", destination.isEmpty ? "0.0.0.0" : destination))
      }
      if !changesOnly || advanced.syslogLevel != cleanSnapshot.advanced.syslogLevel {
        guard (0...7).contains(advanced.syslogLevel) else {
          status = localized("Syslog Level must be between 0 and 7.")
          return nil
        }
        flags.append(("--syslog-level", String(advanced.syslogLevel)))
      }
      let allowSNMPOverWAN = advanced.allowSNMP && advanced.allowSNMPOverWAN
      let cleanAllowSNMPOverWAN =
        cleanSnapshot.advanced.allowSNMP && cleanSnapshot.advanced.allowSNMPOverWAN
      if !changesOnly || advanced.allowSNMP != cleanSnapshot.advanced.allowSNMP
        || allowSNMPOverWAN != cleanAllowSNMPOverWAN
      {
        let accessFlags =
          (advanced.allowSNMP ? 0 : 0x2)
          | (allowSNMPOverWAN ? 0 : 0x1)
        flags.append(("--snmp-access-flags", String(accessFlags)))
      }
    }

    if capabilities.supportsPPPDialIn {
      let enabledChanged =
        advanced.pppDialInEnabled != cleanSnapshot.advanced.pppDialInEnabled
      appendChangedBoolean(
        &flags,
        trueFlag: "--ppp-dial-in-enabled",
        falseFlag: "--no-ppp-dial-in-enabled",
        value: advanced.pppDialInEnabled,
        cleanValue: cleanSnapshot.advanced.pppDialInEnabled,
        changesOnly: changesOnly
      )
      if advanced.pppDialInEnabled {
        guard internet.connectUsing != .modem && !internet.modemUseAOL else {
          status =
            localized("PPP Dial-in is not allowed when configured to connect to the Internet via the Modem or AOL.")
          return nil
        }
        guard network.routerMode != .dhcpOnly else {
          status = localized("PPP Dial-in is not allowed when configured to share a range of addresses.")
          return nil
        }
        guard advanced.pppDialInPassword == advanced.pppDialInVerifyPassword else {
          status = localized("PPP Dial-in passwords do not match.")
          return nil
        }
        guard (1...255).contains(advanced.pppDialInAnswerOnRing) else {
          status = localized("Answer on ring must be between 1 and 255.")
          return nil
        }
        let idleValues = Set(ModemIdleOption.allCases.map(\.seconds))
        guard idleValues.contains(advanced.pppDialInIdleSeconds) else {
          status = localized("Idle Disconnect After has an unsupported value.")
          return nil
        }
        let maximumValues = Set(PPPDialInMaximumConnectOption.allCases.map(\.seconds))
        guard maximumValues.contains(advanced.pppDialInMaximumConnectSeconds) else {
          status = localized("Maximum Connect Time has an unsupported value.")
          return nil
        }

        let diffOnly = changesOnly && !enabledChanged
        appendChanged(
          &flags, "--ppp-dial-in-account", advanced.pppDialInAccount,
          cleanSnapshot.advanced.pppDialInAccount, changesOnly: diffOnly)
        appendChanged(
          &flags, "--ppp-dial-in-password", advanced.pppDialInPassword,
          cleanSnapshot.advanced.pppDialInPassword, changesOnly: diffOnly)
        appendChanged(
          &flags, "--ppp-dial-in-answer-on-ring",
          String(advanced.pppDialInAnswerOnRing),
          String(cleanSnapshot.advanced.pppDialInAnswerOnRing),
          changesOnly: diffOnly)
        appendChanged(
          &flags, "--ppp-dial-in-idle-seconds",
          String(advanced.pppDialInIdleSeconds),
          String(cleanSnapshot.advanced.pppDialInIdleSeconds),
          changesOnly: diffOnly)
        appendChanged(
          &flags, "--ppp-dial-in-maximum-connect-seconds",
          String(advanced.pppDialInMaximumConnectSeconds),
          String(cleanSnapshot.advanced.pppDialInMaximumConnectSeconds),
          changesOnly: diffOnly)
      }
    }

    if capabilities.supportsAccessControl {
      let options = legacyDeviceOptions.accessControl
      let cleanOptions = cleanSnapshot.legacyDeviceOptions.accessControl
      let modeChanged = options.mode != cleanOptions.mode
      guard ["not-enabled", "local", "radius"].contains(options.mode) else {
        status = localized("Access Control mode is not supported.")
        return nil
      }
      appendChanged(
        &flags, "--access-control-mode", options.mode, cleanOptions.mode,
        changesOnly: changesOnly)

      if options.mode == "local" {
        guard let entriesJSON = accessControlEntriesJSON(options.entries) else { return nil }
        guard let cleanEntriesJSON = accessControlEntriesJSON(cleanOptions.entries) else {
          return nil
        }
        appendChanged(
          &flags, "--access-control-entries-json", entriesJSON, cleanEntriesJSON,
          changesOnly: changesOnly && !modeChanged)
      } else if options.mode == "radius" {
        guard ["default", "alternate"].contains(options.radiusType) else {
          status = localized("RADIUS type is not supported.")
          return nil
        }
        let primaryAddress = normalized(options.primaryAddress)
        let secondaryAddress = normalized(options.secondaryAddress)
        guard isIPv4Address(primaryAddress) else {
          status = localized("Primary RADIUS Server must be an IPv4 address.")
          return nil
        }
        guard options.primarySecret == options.primaryVerifySecret else {
          status = localized("Primary RADIUS shared secrets do not match.")
          return nil
        }
        guard !normalized(options.primarySecret).isEmpty else {
          status = localized("Primary RADIUS Shared Secret cannot be empty.")
          return nil
        }
        guard (1...65_535).contains(options.primaryPort) else {
          status = localized("Primary RADIUS port must be between 1 and 65535.")
          return nil
        }
        if !secondaryAddress.isEmpty {
          guard isIPv4Address(secondaryAddress) else {
            status = localized("Secondary RADIUS Server must be an IPv4 address.")
            return nil
          }
          guard options.secondarySecret == options.secondaryVerifySecret else {
            status = localized("Secondary RADIUS shared secrets do not match.")
            return nil
          }
          guard !normalized(options.secondarySecret).isEmpty else {
            status = localized("Secondary RADIUS Shared Secret cannot be empty.")
            return nil
          }
          guard (1...65_535).contains(options.secondaryPort) else {
            status = localized("Secondary RADIUS port must be between 1 and 65535.")
            return nil
          }
        }
        let diffOnly = changesOnly && !modeChanged
        appendChanged(
          &flags, "--radius-type", options.radiusType, cleanOptions.radiusType,
          changesOnly: diffOnly)
        appendChanged(
          &flags, "--radius-primary-address", primaryAddress, cleanOptions.primaryAddress,
          changesOnly: diffOnly)
        appendChanged(
          &flags, "--radius-primary-secret", options.primarySecret,
          cleanOptions.primarySecret, changesOnly: diffOnly)
        appendChanged(
          &flags, "--radius-primary-port", String(options.primaryPort),
          String(cleanOptions.primaryPort), changesOnly: diffOnly)
        appendChanged(
          &flags, "--radius-secondary-address", secondaryAddress,
          cleanOptions.secondaryAddress, changesOnly: diffOnly)
        appendChanged(
          &flags, "--radius-secondary-secret",
          secondaryAddress.isEmpty ? "" : options.secondarySecret,
          cleanOptions.secondaryAddress.isEmpty ? "" : cleanOptions.secondarySecret,
          changesOnly: diffOnly)
        appendChanged(
          &flags, "--radius-secondary-port", String(options.secondaryPort),
          String(cleanOptions.secondaryPort), changesOnly: diffOnly)
      }
    }

    return flags
  }

  private func accessControlEntriesJSON(_ entries: [AccessControlEntry]) -> String? {
    var objects: [[String: String]] = []
    for entry in entries {
      let macAddress = entry.macAddress.trimmingCharacters(
        in: .whitespacesAndNewlines).uppercased()
      let components = macAddress.split(separator: ":", omittingEmptySubsequences: false)
      guard
        components.count == 6,
        components.allSatisfy({
          $0.count == 2 && UInt8($0, radix: 16) != nil
        })
      else {
        status = localized("Each local access-control entry must contain a valid MAC address.")
        return nil
      }
      guard entry.description.lengthOfBytes(using: .utf8) <= 34 else {
        status = localized("Access-control descriptions may contain at most 34 UTF-8 bytes.")
        return nil
      }
      objects.append(["macAddress": macAddress, "description": entry.description])
    }
    guard JSONSerialization.isValidJSONObject(objects),
      let data = try? JSONSerialization.data(withJSONObject: objects, options: [.sortedKeys]),
      let text = String(data: data, encoding: .utf8)
    else {
      status = localized("Could not encode local access-control settings.")
      return nil
    }
    return text
  }
}
