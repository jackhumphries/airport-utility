import Foundation

enum AirportCommand {
  static let backendScript = "./backend/airport_backend.py"
  static let readScript = backendScript
  static let legacyReadScript = backendScript
  static let writeScript = backendScript
  static let legacyWriteScript = backendScript
  private static let adminPasswordSetting = "sypw"
  private static let sensitiveFlags: Set<String> = [
    "--password",
    "--pppoe-password",
    "--wireless-password",
    "--disk-password",
    "--disk-account-json",
    "--global-hostname-password",
    "--airplay-speaker-password",
    "--values-json",
    "--base-values-json",
    "--modem-password",
    "--ppp-dial-in-password",
    "--radius-primary-secret",
    "--radius-secondary-secret",
    "--snmp-community",
  ]

  static func redact(_ arguments: [String]) -> [String] {
    var redacted = arguments
    let rawSetting = rawSettingName(in: arguments)
    var index = 0
    while index < redacted.count {
      if let redactedValue = redactedInlineArgument(redacted[index], rawSetting: rawSetting) {
        redacted[index] = redactedValue
        index += 1
        continue
      }
      if shouldRedact(flag: redacted[index], rawSetting: rawSetting),
        index + 1 < redacted.count
      {
        redacted[index + 1] = "<password>"
        index += 2
      } else {
        index += 1
      }
    }
    return redacted
  }

  private static func redactedInlineArgument(
    _ argument: String, rawSetting: String?
  ) -> String? {
    guard let separator = argument.firstIndex(of: "=") else { return nil }
    let flag = String(argument[..<separator])
    guard shouldRedact(flag: flag, rawSetting: rawSetting) else {
      return nil
    }
    return "\(flag)=<password>"
  }

  private static func rawSettingName(in arguments: [String]) -> String? {
    guard let settingIndex = arguments.firstIndex(of: "--setting"),
      settingIndex + 1 < arguments.count
    else {
      return normalizedRawSettingName(inlineValue(for: "--setting", in: arguments))
    }
    return normalizedRawSettingName(arguments[settingIndex + 1])
  }

  private static func inlineValue(for flag: String, in arguments: [String]) -> String? {
    let prefix = "\(flag)="
    return arguments.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
  }

  private static func shouldRedact(flag: String, rawSetting: String?) -> Bool {
    if sensitiveFlags.contains(flag) {
      return true
    }
    if flag == "--value" || flag == "--value-json" {
      return rawSetting == adminPasswordSetting
    }
    return false
  }

  private static func normalizedRawSettingName(_ setting: String?) -> String? {
    setting?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
  }

  static func display(_ script: String, _ arguments: [String]) -> String {
    ([script] + arguments).map(shellDisplayToken).joined(separator: " ")
  }

  static func readSetting(
    _ setting: String, connection: AirportConnection, json: Bool = false
  ) -> [String] {
    var args = [
      "read", normalizedHost(connection), "--password", connection.password, "--setting", setting,
    ]
    if json { args.append("--json") }
    return args
  }

  static func readSettings(
    _ settings: [String], connection: AirportConnection, json: Bool = false
  ) -> [String] {
    var args = ["read", normalizedHost(connection), "--password", connection.password]
    for setting in settings {
      args += ["--setting", setting]
    }
    if json { args.append("--json") }
    return args
  }

  static func readProfilePath(
    _ path: String, connection: AirportConnection, json: Bool = false
  ) -> [String] {
    var args = [
      "read", normalizedHost(connection), "--password", connection.password, "--profile-path", path,
    ]
    if json { args.append("--json") }
    return args
  }

  static func wirelessClients(
    connection: AirportConnection,
    usesLegacyACP: Bool,
    snmpCommunity: String,
    discoverIdentities: Bool = false
  ) -> [String] {
    var arguments = [
      "wireless-clients", normalizedHost(connection), "--json",
    ]
    if discoverIdentities {
      arguments.append("--discover-identities")
    }
    if usesLegacyACP {
      arguments += ["--legacy", "--snmp-community", snmpCommunity]
    } else {
      arguments += ["--password", connection.password]
    }
    return arguments
  }

  static func rawWrite(
    setting: String, value: String, connection: AirportConnection, dryRun: Bool
  ) -> [String] {
    var args = [
      "write", normalizedHost(connection), "--password", connection.password, "--setting", setting,
      "--value", value,
    ]
    if dryRun { args.append("--dry-run") }
    return args
  }

  static func rawWriteJSON(
    setting: String, valueJSON: String, connection: AirportConnection, dryRun: Bool
  ) -> [String] {
    var args = [
      "write", normalizedHost(connection), "--password", connection.password, "--setting", setting,
      "--value-json", valueJSON,
    ]
    if dryRun { args.append("--dry-run") }
    return args
  }

  static func rawWriteValuesJSON(
    _ valuesJSON: String, connection: AirportConnection, dryRun: Bool
  ) -> [String] {
    var args = [
      "write", normalizedHost(connection), "--password", connection.password,
      "--values-json", valuesJSON,
    ]
    if dryRun { args.append("--dry-run") }
    return args
  }

  static func friendlyWrite(
    connection: AirportConnection, flags: [(String, String?)], dryRun: Bool
  ) -> [String] {
    friendlyWrite(connection: connection, flags: flags.map(BackendFlag.init), dryRun: dryRun)
  }

  static func friendlyWrite(
    connection: AirportConnection, flags: [BackendFlag], dryRun: Bool
  ) -> [String] {
    var args = ["write", normalizedHost(connection), "--password", connection.password]
    if dryRun { args.append("--dry-run") }
    args += flags.commandArguments
    return args
  }

  static func eraseDisk(
    connection: AirportConnection, method: EraseMethod = .quick, volumeName: String? = nil,
    partitionUUID: String? = nil, message: String? = nil, confirmed: Bool = false, dryRun: Bool
  ) -> [String] {
    var args = ["write", normalizedHost(connection), "--password", connection.password, "--erase-disk"]
    if dryRun { args.append("--dry-run") }
    args += ["--erase-method", method.rawValue]
    if let volumeName {
      let volumeName = volumeName.trimmingCharacters(in: .whitespacesAndNewlines)
      if !volumeName.isEmpty {
        args += ["--volume-name", volumeName]
      }
    }
    if let partitionUUID {
      let partitionUUID = partitionUUID.trimmingCharacters(in: .whitespacesAndNewlines)
      if !partitionUUID.isEmpty {
        args += ["--partition-uuid", partitionUUID]
      }
    }
    if let message {
      let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
      if !message.isEmpty {
        args += ["--erase-message", message]
      }
    }
    if confirmed { args.append("--i-know-this-erases-the-disk") }
    return args
  }

  static func archiveDisk(
    connection: AirportConnection, archiveName: String? = nil, confirmed: Bool = false, dryRun: Bool
  ) -> [String] {
    var args = ["write", normalizedHost(connection), "--password", connection.password, "--archive-disk"]
    if dryRun { args.append("--dry-run") }
    if let archiveName {
      let archiveName = archiveName.trimmingCharacters(in: .whitespacesAndNewlines)
      if !archiveName.isEmpty {
        args += ["--archive-name", archiveName]
      }
    }
    if confirmed { args.append("--i-know-this-starts-the-archive") }
    return args
  }

  static func installFirmware(
    connection: AirportConnection, firmwarePath: String, dryRun: Bool
  ) -> [String] {
    var args = [
      "write", normalizedHost(connection), "--password", connection.password, "--upload-firmware",
      firmwarePath,
    ]
    if dryRun { args.append("--dry-run") }
    if !dryRun { args.append("--i-know-this-updates-firmware") }
    return args
  }

  private static func normalizedHost(_ connection: AirportConnection) -> String {
    AirportConnection.normalizedHost(connection.host)
  }

  private static func shellDisplayToken(_ token: String) -> String {
    if token.rangeOfCharacter(
      from: CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: "\"'"))) == nil
    {
      return token
    }
    return "'" + token.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }
}

extension Array where Element == String {
  func usingAirPortBackendSubcommand(_ subcommand: String) -> [String] {
    guard !isEmpty else { return self }
    var arguments = self
    arguments[0] = subcommand
    return arguments
  }
}
