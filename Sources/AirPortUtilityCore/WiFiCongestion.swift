// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

import Foundation
#if canImport(CoreWLAN)
@preconcurrency import CoreWLAN
#endif

enum WiFiCongestionCondition: String, Codable, Sendable {
  case unknown, scanning, clear, busy, unavailable
}

struct WiFiChannelObservation: Equatable, Sendable {
  let channel: Int
  let rssi: Int
}

struct WiFiBandRecommendation: Codable, Equatable, Sendable, Identifiable {
  var id: String { band }
  let band: String
  let currentChannel: Int?
  let recommendedChannel: Int?
  let nearbyNetworks: Int
  let summary: String
}

struct WiFiCongestionState: Codable, Equatable, Sendable {
  var condition: WiFiCongestionCondition = .unknown
  var summary = "Not scanned"
  var recommendations: [WiFiBandRecommendation] = []
  var lastChecked: Date?
  var isRunning = false
}

enum WiFiChannelAnalyzer {
  static func analyze(
    observations: [WiFiChannelObservation], currentChannel: Int?, allowedChannels: Set<Int>
  ) -> [WiFiBandRecommendation] {
    let twoFour = recommendation(
      band: "2.4 GHz", candidates: [1, 6, 11], observations: observations,
      currentChannel: currentChannel.flatMap { $0 <= 14 ? $0 : nil },
      allowedChannels: allowedChannels, overlap: true)
    let fiveCandidates = [36, 40, 44, 48, 149, 153, 157, 161]
    let five = recommendation(
      band: "5 GHz", candidates: fiveCandidates, observations: observations,
      currentChannel: currentChannel.flatMap { $0 > 14 ? $0 : nil },
      allowedChannels: allowedChannels, overlap: false)
    return [twoFour, five].compactMap { $0 }
  }

  private static func recommendation(
    band: String, candidates: [Int], observations: [WiFiChannelObservation],
    currentChannel: Int?, allowedChannels: Set<Int>, overlap: Bool
  ) -> WiFiBandRecommendation? {
    let legal = candidates.filter { allowedChannels.isEmpty || allowedChannels.contains($0) }
    guard !legal.isEmpty else { return nil }
    let bandObservations = observations.filter { band == "2.4 GHz" ? $0.channel <= 14 : $0.channel > 14 }
    let scores = legal.map { candidate in
      (candidate, bandObservations.reduce(0.0) { total, network in
        let distance = abs(candidate - network.channel)
        let overlapWeight = overlap
          ? Double(max(0, 5 - distance)) / 5.0
          : (distance == 0 ? 1.0 : 0.0)
        let signalWeight = pow(10.0, Double(network.rssi + 100) / 20.0)
        return total + overlapWeight * signalWeight
      })
    }
    guard let best = scores.min(by: { $0.1 < $1.1 }) else { return nil }
    let currentScore = currentChannel.flatMap { channel in scores.first { $0.0 == channel }?.1 }
    let materiallyBetter = currentScore.map { best.1 < $0 * 0.75 } ?? true
    let recommendation = materiallyBetter ? best.0 : currentChannel
    let summary: String
    if bandObservations.isEmpty {
      summary = "No nearby \(band) networks were observed"
    } else if let currentChannel, recommendation == currentChannel {
      summary = "Channel \(currentChannel) is competitive in this scan"
    } else if let recommendation {
      summary = "Channel \(recommendation) had the lowest observed contention"
    } else {
      summary = "Scan data is available; current channel was not identified"
    }
    return WiFiBandRecommendation(
      band: band, currentChannel: currentChannel, recommendedChannel: recommendation,
      nearbyNetworks: bandObservations.count, summary: summary)
  }
}

enum WiFiCongestionScanner {
  struct Scan: Sendable {
    let observations: [WiFiChannelObservation]
    let currentChannel: Int?
    let allowedChannels: Set<Int>
  }

  static func scan() async throws -> Scan {
    #if canImport(CoreWLAN)
    return try await Task.detached {
      guard let interface = CWWiFiClient.shared().interface() else {
        throw ScanError.noInterface
      }
      let networks = try interface.scanForNetworks(withName: nil)
      return Scan(
        observations: networks.compactMap { network in
          guard let channel = network.wlanChannel?.channelNumber else { return nil }
          return WiFiChannelObservation(channel: channel, rssi: network.rssiValue)
        },
        currentChannel: interface.wlanChannel()?.channelNumber,
        allowedChannels: Set(interface.supportedWLANChannels()?.map(\.channelNumber) ?? []))
    }.value
    #else
    throw ScanError.unsupported
    #endif
  }

  enum ScanError: LocalizedError {
    case noInterface, unsupported
    var errorDescription: String? {
      switch self {
      case .noInterface: "No Wi-Fi interface is available"
      case .unsupported: "Wi-Fi scanning is unavailable on this system"
      }
    }
  }
}

@MainActor
extension AirportAppModel {
  func refreshWiFiCongestion() {
    guard !wifiCongestion.isRunning else { return }
    wifiCongestion = WiFiCongestionState(
      condition: .scanning, summary: "Scanning nearby Wi-Fi networks…", isRunning: true)
    wifiCongestionTask?.cancel()
    wifiCongestionTask = Task { [weak self] in
      do {
        let scan = try await WiFiCongestionScanner.scan()
        guard let self, !Task.isCancelled else { return }
        let recommendations = WiFiChannelAnalyzer.analyze(
          observations: scan.observations, currentChannel: scan.currentChannel,
          allowedChannels: scan.allowedChannels)
        wifiCongestion = WiFiCongestionState(
          condition: scan.observations.count >= 12 ? .busy : .clear,
          summary: scan.observations.isEmpty
            ? "No nearby networks were visible"
            : "Observed \(scan.observations.count) nearby networks",
          recommendations: recommendations, lastChecked: Date(), isRunning: false)
        appendLog("Wi-Fi congestion scan completed with \(scan.observations.count) nearby networks.")
      } catch {
        guard let self, !Task.isCancelled else { return }
        wifiCongestion = WiFiCongestionState(
          condition: .unavailable,
          summary: "Scan unavailable. Check Wi-Fi and Location Services access, then try again.",
          lastChecked: Date(), isRunning: false)
        appendLog("Wi-Fi congestion scan unavailable: \(error.localizedDescription)")
      }
    }
  }
}
