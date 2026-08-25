// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

import Foundation

@MainActor
extension AirportAppModel {
  func updateHealthNotificationPreference(
    _ keyPath: WritableKeyPath<HealthNotificationPreferences, Bool>,
    enabled: Bool
  ) {
    healthNotificationPreferences[keyPath: keyPath] = enabled
    persistHealthNotificationState()
    evaluateHealthAlerts()
  }

  func clearHealthAlertHistory() {
    healthAlertHistory = []
    persistHealthNotificationState()
  }

  func evaluateHealthAlerts() {
    let host = AirportConnection.normalizedHost(connection.host)
    let candidates = HealthAlertAssessment.candidates(
      host: host,
      storage: storageHealth,
      backups: timeMachineBackups,
      preferences: healthNotificationPreferences)
    let currentSignatures = Dictionary(uniqueKeysWithValues: candidates.map { ($0.key, $0.signature) })
    let transitions = candidates.filter {
      activeHealthAlertSignatures[$0.key] != $0.signature
    }
    activeHealthAlertSignatures = currentSignatures
    guard !transitions.isEmpty else {
      persistHealthNotificationState()
      return
    }

    for candidate in transitions {
      let event = HealthAlertEvent(
        id: UUID(), date: Date(), kind: candidate.kind,
        title: candidate.title, detail: candidate.detail, host: host)
      healthAlertHistory.insert(event, at: 0)
      healthAlertHistory = Array(healthAlertHistory.prefix(100))
      appendLog("Health alert raised for \(host): \(event.title) — \(event.detail)")
      let deliveryOverride = healthNotificationDeliveryOverride
      Task { [weak self] in
        let delivered = if let deliveryOverride {
          await deliveryOverride(event)
        } else {
          await HealthNotificationCenter.deliver(event)
        }
        guard let self else { return }
        appendLog(
          delivered
            ? "Health notification delivered: \(event.title)"
            : "Health notification was not delivered; check notification permission in System Settings.")
      }
    }
    persistHealthNotificationState()
  }

  func loadHealthNotificationState() {
    let defaults = UserDefaults.standard
    let decoder = JSONDecoder()
    if let data = defaults.data(forKey: Self.healthNotificationPreferencesKey),
      let preferences = try? decoder.decode(HealthNotificationPreferences.self, from: data)
    {
      healthNotificationPreferences = preferences
    }
    if let data = defaults.data(forKey: Self.healthAlertHistoryKey),
      let history = try? decoder.decode([HealthAlertEvent].self, from: data)
    {
      healthAlertHistory = Array(history.prefix(100))
    }
    if let data = defaults.data(forKey: Self.activeHealthAlertSignaturesKey),
      let signatures = try? decoder.decode([String: String].self, from: data)
    {
      activeHealthAlertSignatures = signatures
    }
  }

  private func persistHealthNotificationState() {
    let defaults = UserDefaults.standard
    let encoder = JSONEncoder()
    defaults.set(
      try? encoder.encode(healthNotificationPreferences),
      forKey: Self.healthNotificationPreferencesKey)
    defaults.set(
      try? encoder.encode(healthAlertHistory),
      forKey: Self.healthAlertHistoryKey)
    defaults.set(
      try? encoder.encode(activeHealthAlertSignatures),
      forKey: Self.activeHealthAlertSignaturesKey)
  }
}
