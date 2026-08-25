// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

import Foundation

struct Site: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  var name: String
  var host: String
  var stableIdentifiers: [String]
  var lastConnectedDate: Date?
}

final class SiteStore: @unchecked Sendable {
  private let directory: URL
  private let fileManager: FileManager
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  init(directory: URL? = nil, fileManager: FileManager = .default) {
    self.fileManager = fileManager
    self.directory = directory ?? Self.defaultDirectory()
    encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
  }

  func loadSites() -> [Site] {
    guard let data = try? Data(contentsOf: indexURL),
      let sites = try? decoder.decode([Site].self, from: data)
    else { return [] }
    return sites
  }

  func save(_ sites: [Site]) throws {
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    try encoder.encode(sites).write(to: indexURL, options: [.atomic])
  }

  private var indexURL: URL { directory.appendingPathComponent("sites.json") }

  nonisolated static func defaultDirectory() -> URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("AirPort Utility Powerhouse/Sites", isDirectory: true)
  }
}

@MainActor
extension AirportAppModel {
  func saveCurrentConnectionAsSite(name: String) {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return }
    let host = AirportConnection.normalizedHost(connection.host)
    guard !host.isEmpty else { return }
    let stableIdentifiers =
      discoveredDevices.first(where: { isKnownConnectedTopologyDevice($0, connectionHost: host) })?
      .normalizedStableIdentifiers ?? []
    let site = Site(
      id: UUID(), name: name, host: host, stableIdentifiers: stableIdentifiers,
      lastConnectedDate: Date())
    sites.append(site)
    persistSites()
    appendLog("Saved \(host) as site \"\(name)\".")
  }

  func connectToSite(_ site: Site) {
    guard !isBusy else { return }
    guard let index = sites.firstIndex(where: { $0.id == site.id }) else { return }
    if !site.stableIdentifiers.isEmpty,
      let matched = discoveredDevices.first(where: {
        $0.sharesStableIdentity(with: site.stableIdentifiers)
      })
    {
      selectTopologyDevice(matched)
      refresh()
      sites[index].host = AirportConnection.normalizedHost(matched.connectionHost)
    } else {
      connection.host = AirportConnection.normalizedHost(site.host)
      loadSavedPasswordForConnectionHost(device: nil, fallbackHosts: [connection.host])
      refresh()
    }
    sites[index].lastConnectedDate = Date()
    persistSites()
  }

  func renameSite(_ site: Site, to newName: String) {
    let newName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !newName.isEmpty, let index = sites.firstIndex(where: { $0.id == site.id }) else {
      return
    }
    sites[index].name = newName
    persistSites()
  }

  func removeSite(_ site: Site) {
    sites.removeAll { $0.id == site.id }
    persistSites()
  }

  func updateSiteHostsFromDiscoveredDevices(_ devices: [AirportDiscoveredDevice]) {
    var didChange = false
    for index in sites.indices {
      guard !sites[index].stableIdentifiers.isEmpty,
        let matched = devices.first(where: {
          $0.sharesStableIdentity(with: sites[index].stableIdentifiers)
        })
      else { continue }
      let freshHost = AirportConnection.normalizedHost(matched.connectionHost)
      guard !freshHost.isEmpty, freshHost != sites[index].host else { continue }
      sites[index].host = freshHost
      didChange = true
    }
    guard didChange else { return }
    persistSites()
  }

  private func persistSites() {
    do {
      try siteStore.save(sites)
    } catch {
      appendLog("Could not save sites: \(error.localizedDescription)")
    }
  }
}
