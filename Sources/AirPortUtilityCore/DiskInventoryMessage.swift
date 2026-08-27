import Foundation

enum DiskInventoryMessage {
  static func refreshSkippedMessage(for errorDescription: String) -> String? {
    guard !containsPendingPlaceholder(errorDescription) else {
      return nil
    }
    let description = friendlyErrorDescription(errorDescription)
    return "Disk inventory refresh skipped: \(description)"
  }

  static func containsPendingPlaceholder(_ description: String) -> Bool {
    let normalized = normalizedMessage(description)
    return normalized.contains("refresh to load disk inventory from mast")
      || normalized.contains("refresh to load disk inventory")
      || normalized.contains("disk information is not available yet")
  }

  static func containsSettingReference(_ description: String) -> Bool {
    normalizedMessage(description).contains("mast")
  }

  static func friendlyErrorDescription(_ description: String) -> String {
    let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return "could not load disk information."
    }

    if containsPendingPlaceholder(trimmed) {
      return "disk information is not available yet."
    }

    var friendly = trimmed.replacingOccurrences(
      of: "Refresh to load disk inventory from MaSt.",
      with: "Refresh to load disk information."
    )
    friendly = friendly.replacingOccurrences(of: "MaSt", with: "disk inventory")
    friendly = friendly.replacingOccurrences(
      of: "mast", with: "disk inventory", options: [.caseInsensitive])
    return friendly
  }

  static func userFacingErrorDescription(_ description: String) -> String {
    if containsPendingPlaceholder(description) {
      return localized("Disk information is not available yet.")
    }
    if containsSettingReference(description) {
      return friendlyErrorDescription(description)
    }
    return description
  }

  static func userFacingCommandOutput(_ output: String) -> String {
    if isOnlyPendingOutput(output) || looksLikePendingFailure(output) {
      return localized("Disk information is not available yet.")
    }
    let output = removingPendingLines(from: output)
    if containsSettingReference(output) {
      return friendlyErrorDescription(output)
    }
    return output
  }

  static func sanitizedLogMessage(_ message: String) -> String {
    guard containsPendingPlaceholder(message) else {
      if containsSettingReference(message) {
        return friendlyErrorDescription(message)
      }
      return message
    }
    if !isOnlyPendingOutput(message) && !looksLikePendingFailure(message) {
      let message = removingPendingLines(from: message)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !message.isEmpty else { return "" }
      if containsSettingReference(message) {
        return friendlyErrorDescription(message)
      }
      return message
    }
    if message.localizedCaseInsensitiveContains("error:") {
      return "Error: Disk information is not available yet."
    }
    return ""
  }

  private static func isOnlyPendingOutput(_ output: String) -> Bool {
    let stripped = removingPendingLines(from: output)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return stripped.isEmpty
  }

  private static func looksLikePendingFailure(_ output: String) -> Bool {
    guard containsPendingPlaceholder(output) else { return false }
    return output.localizedCaseInsensitiveContains("command failed")
      || output.localizedCaseInsensitiveContains("error:")
  }

  private static func removingPendingLines(from output: String) -> String {
    output
      .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
      .filter { line in
        !containsPendingPlaceholder(String(line))
      }
      .joined(separator: "\n")
  }

  private static func normalizedMessage(_ description: String) -> String {
    String(
      description
        .lowercased()
        .map { character -> Character in
          character.isLetter || character.isNumber ? character : " "
        }
        .split(separator: " ")
        .joined(separator: " "))
  }
}
