import Foundation

enum AirportServiceReadError: LocalizedError {
  case missingSetting(String)

  var errorDescription: String? {
    switch self {
    case .missingSetting(let setting):
      "The base station response did not include \(setting)."
    }
  }
}

enum FirmwareInstallError: LocalizedError {
  case restartNotObserved(expected: String)
  case uploadIncomplete(String)
  case rebootNotSent
  case versionMismatch(expected: String, actual: String)
  case versionUnavailable(expected: String, lastError: String?)

  var errorDescription: String? {
    switch self {
    case .restartNotObserved(let expected):
      return
        "Firmware install completed, but the base station did not restart before version \(expected) was confirmed."
    case .uploadIncomplete(let progress):
      return "Firmware upload did not complete. Last reported progress: \(progress)."
    case .rebootNotSent:
      return localized("Firmware upload completed, but the base station reboot command was not sent.")
    case .versionMismatch(let expected, let actual):
      return
        "Firmware install completed, but the base station reports version \(actual) instead of \(expected)."
    case .versionUnavailable(let expected, let lastError):
      if let lastError, !lastError.isEmpty {
        return
          "Firmware install completed, but the installed version could not be confirmed as \(expected): \(lastError)"
      }
      return
        "Firmware install completed, but the installed version could not be confirmed as \(expected)."
    }
  }
}
