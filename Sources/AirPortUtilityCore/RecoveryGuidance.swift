// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

import Foundation

enum RecoveryGuidanceReason: Equatable, Sendable {
  case restartDidNotComplete
  case firmwareVerificationFailed
  case configurationWriteFailed
  case configurationVerificationFailed

  var headline: String {
    switch self {
    case .restartDidNotComplete: "Restart did not complete"
    case .firmwareVerificationFailed: "Firmware verification failed"
    case .configurationWriteFailed: "Configuration write failed"
    case .configurationVerificationFailed: "Configuration could not be verified"
    }
  }
}

struct RecoveryGuidance: Equatable, Sendable {
  var reason: RecoveryGuidanceReason
  var host: String
  var deviceName: String
  var date: Date
  var detail: String
}

@MainActor
extension AirportAppModel {
  func clearRecoveryGuidance(forHost host: String) {
    guard let recoveryGuidance,
      AirportConnection.normalizedHost(recoveryGuidance.host)
        == AirportConnection.normalizedHost(host)
    else { return }
    self.recoveryGuidance = nil
  }

  /// The most recent snapshot known to represent a working configuration for
  /// `host`, across both Configuration History and Automatic Backups.
  ///
  /// Automatic Backup records are always `.prepared` - they're taken from a
  /// live, already-connected session rather than paired with a write to
  /// verify, so existing at all is itself the confirmation. Configuration
  /// History records only qualify once actually verified.
  func mostRecentKnownGoodConfigurationRecord(
    forHost host: String
  ) -> (record: ConfigurationChangeRecord, isAutomaticBackup: Bool)? {
    let host = AirportConnection.normalizedHost(host)
    let goodStatuses: Set<ConfigurationChangeStatus> = [.verifiedReachable, .verifiedExpected]
    let historyCandidate = configurationChangeHistory
      .filter { AirportConnection.normalizedHost($0.host) == host && goodStatuses.contains($0.status) }
      .max { $0.date < $1.date }
      .map { (record: $0, isAutomaticBackup: false) }
    let backupCandidate = automaticConfigurationBackups
      .filter { AirportConnection.normalizedHost($0.host) == host }
      .max { $0.date < $1.date }
      .map { (record: $0, isAutomaticBackup: true) }
    return [historyCandidate, backupCandidate]
      .compactMap { $0 }
      .max { $0.record.date < $1.record.date }
  }
}
