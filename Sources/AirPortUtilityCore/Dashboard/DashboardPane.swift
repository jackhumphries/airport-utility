// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

//
//  DashboardPane.swift
//  AirPortUtility
//
//  Created by Graham Barber on 20/08/2026.
//

import Charts
import SwiftUI

struct DashboardPane: View {
  @EnvironmentObject private var model: AirportAppModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Dashboard")
            .font(.largeTitle)
            .fontWeight(.semibold)

          Text("Your AirPort network at a glance")
            .foregroundStyle(.secondary)
        }

        LazyVGrid(
          columns: [GridItem(.flexible()), GridItem(.flexible())],
          spacing: 16
        ) {
          DashboardCard(
            title: "Connection",
            value: model.status,
            icon: "network"
          )
          DashboardCard(
            title: "Base Station",
            value: baseStationName,
            icon: "wifi.router"
          )
          DashboardCard(
            title: "Wireless Clients",
            value: "\(model.wirelessClients.count)",
            icon: "laptopcomputer.and.iphone"
          )
          DashboardCard(
            title: "Firmware",
            value: firmwareVersion,
            icon: "checkmark.circle"
          )
          DashboardCard(
            title: "Time Capsule Storage",
            value: diskCapacitySummary,
            icon: "internaldrive"
          )
          DashboardCard(
            title: "Client Health",
            value: clientHealthSummary,
            icon: clientHealthIcon
          )
        }

        DashboardSection(title: "Network", icon: "network") {
          DashboardDetailRow(title: "Wi-Fi Network", value: networkName)
          DashboardDetailRow(title: "Base Station Address", value: lanAddress)
          DashboardDetailRow(title: secondaryAddressTitle, value: secondaryAddress)
          DashboardDetailRow(title: "Router Mode", value: routerMode)
          DashboardDetailRow(title: "DHCP", value: networkSummary.dhcpStatus)
          DashboardDetailRow(title: "DHCP Range", value: networkSummary.dhcpRange)
        }

        DashboardSection(title: "Internet", icon: "globe") {
          DashboardDetailRow(title: "Status", value: networkSummary.internetStatus)
          DashboardDetailRow(title: "Connection", value: networkSummary.connectionMethod)
          DashboardDetailRow(title: "WAN Address", value: networkSummary.wanAddress)
          DashboardDetailRow(title: "Upstream Router", value: networkSummary.upstreamRouter)
          DashboardDetailRow(title: "DNS Servers", value: networkSummary.dnsServers)
        }

        DashboardSection(title: "Wireless", icon: "wifi") {
          DashboardDetailRow(title: "Mode", value: networkSummary.wirelessMode)
          DashboardDetailRow(title: "Network", value: networkName)
          DashboardDetailRow(title: "Security", value: networkSummary.wirelessSecurity)
          DashboardDetailRow(title: "Reported Radio", value: networkSummary.wirelessRadio)
          DashboardDetailRow(title: "Guest Network", value: networkSummary.guestNetwork)
        }

        DashboardSection(title: "Wi-Fi Congestion", icon: wifiCongestionIcon) {
          HStack(spacing: 10) {
            Text(model.wifiCongestion.summary)
              .foregroundStyle(model.wifiCongestion.condition == .busy ? .orange : .primary)
            Spacer()
            Button(model.wifiCongestion.isRunning ? "Scanning…" : "Scan Channels") {
              model.refreshWiFiCongestion()
            }
            .disabled(model.wifiCongestion.isRunning)
          }

          ForEach(model.wifiCongestion.recommendations) { recommendation in
            Divider()
            HStack(alignment: .firstTextBaseline) {
              VStack(alignment: .leading, spacing: 3) {
                Text(recommendation.band).fontWeight(.medium)
                Text(recommendation.summary)
                  .font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              Text("\(recommendation.nearbyNetworks) nearby")
                .font(.caption).foregroundStyle(.secondary)
            }
          }

          if let checked = model.wifiCongestion.lastChecked {
            Text("Checked \(checked.formatted(date: .omitted, time: .standard)). Advisory only; no AirPort settings are changed.")
              .font(.caption).foregroundStyle(.secondary)
          }
        }

        if let guidance = currentHostRecoveryGuidance {
          DashboardSection(title: "Recovery", icon: "exclamationmark.triangle.fill") {
            Label(guidance.reason.headline, systemImage: "exclamationmark.triangle.fill")
              .foregroundStyle(.orange)
            Text("\(guidance.detail) · \(guidance.date.formatted(date: .abbreviated, time: .shortened))")
              .font(.caption).foregroundStyle(.secondary)

            Divider()

            if let candidate = model.mostRecentKnownGoodConfigurationRecord(forHost: guidance.host) {
              HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                  Text(candidate.isAutomaticBackup ? "Automatic backup" : candidate.record.title)
                    .fontWeight(.medium)
                  Text("From \(candidate.record.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Restore Last Known-Good Settings") {
                  if candidate.isAutomaticBackup {
                    model.prepareRollback(fromAutomaticBackup: candidate.record)
                  } else {
                    model.prepareRollback(candidate.record)
                  }
                }
                Button("Dismiss") { model.recoveryGuidance = nil }
              }
              Text("Loads into the editor for review; never applies automatically.")
                .font(.caption).foregroundStyle(.secondary)
            } else {
              HStack {
                Text("No verified-good configuration snapshot is available yet for this base station.")
                  .foregroundStyle(.secondary)
                Spacer()
                Button("Dismiss") { model.recoveryGuidance = nil }
              }
            }

            Divider()
            Text("If the base station remains unreachable, a physical hard reset is the last resort - hold the reset button (or paperclip-hole pin) for the duration in your model's manual until the status light changes. This app cannot perform a hard reset for you; it must be done at the device itself.")
              .font(.caption).foregroundStyle(.secondary)
          }
        }

        DashboardSection(
          title: "Current Warnings",
          icon: networkSummary.warnings.isEmpty
            ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        ) {
          if networkSummary.warnings.isEmpty {
            Label("No AirPort warnings reported", systemImage: "checkmark.circle.fill")
              .foregroundStyle(.green)
          } else {
            ForEach(networkSummary.warnings, id: \.self) { warning in
              Label(warning, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            }
          }
        }

        DashboardSection(title: "Configuration History", icon: "clock.arrow.circlepath") {
          if currentHostConfigurationHistory.isEmpty {
            Text("No configuration changes recorded")
              .foregroundStyle(.secondary)
          } else {
            ForEach(Array(currentHostConfigurationHistory.prefix(5).enumerated()), id: \.element.id) {
              index, record in
              if index > 0 { Divider() }
              HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: configurationStatusIcon(record.status))
                  .foregroundStyle(configurationStatusColor(record.status))
                VStack(alignment: .leading, spacing: 3) {
                  Text(record.title).fontWeight(.medium)
                  Text("\(record.status.userFacingDescription) · \(record.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                compareMenu(for: HistoryEntryReference(record: record, isAutomaticBackup: false))
                  .disabled(
                    AirportConnection.normalizedHost(record.host)
                      != AirportConnection.normalizedHost(model.connection.host))
                Button("Prepare Rollback") { model.prepareRollback(record) }
                  .disabled(
                    AirportConnection.normalizedHost(record.host)
                      != AirportConnection.normalizedHost(model.connection.host))
              }
            }
            Text("Snapshots omit passwords and secrets. Rollback loads settings into the editor for preview; it never applies automatically.")
              .font(.caption).foregroundStyle(.secondary)
          }
        }

        DashboardSection(title: "Automatic Backups", icon: "archivebox") {
          if currentHostAutomaticBackups.isEmpty {
            Text("No automatic backups saved yet")
              .foregroundStyle(.secondary)
          } else {
            ForEach(
              Array(currentHostAutomaticBackups.prefix(5).enumerated()), id: \.element.id
            ) {
              index, record in
              if index > 0 { Divider() }
              HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: "clock")
                  .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                  Text("Automatic backup").fontWeight(.medium)
                  Text(record.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                compareMenu(for: HistoryEntryReference(record: record, isAutomaticBackup: true))
                  .disabled(
                    AirportConnection.normalizedHost(record.host)
                      != AirportConnection.normalizedHost(model.connection.host))
                Button("Restore") { model.prepareRollback(fromAutomaticBackup: record) }
                  .disabled(
                    AirportConnection.normalizedHost(record.host)
                      != AirportConnection.normalizedHost(model.connection.host))
              }
            }
            Text("Saved automatically about once a day while connected, independent of any change you make. Restoring loads settings into the editor for preview; it never applies automatically.")
              .font(.caption).foregroundStyle(.secondary)
          }
        }

        DashboardSection(title: "Connected Clients", icon: "laptopcomputer.and.iphone") {
          if let note = model.wirelessClientDiscoveryNote {
            Label(note, systemImage: "info.circle.fill")
              .foregroundStyle(.secondary)
              .font(.callout)
            Divider()
          }
          if !model.hasLoadedWirelessClients {
            HStack(spacing: 8) {
              ProgressView()
                .controlSize(.small)
              Text("Loading wireless clients…")
                .foregroundStyle(.secondary)
            }
          } else if model.wirelessClients.isEmpty {
            Text("No wireless clients reported")
              .foregroundStyle(.secondary)
          } else {
            DashboardClientHeader()
            Divider()
            ForEach(sortedWirelessClients) { client in
              DashboardClientRow(
                client: client,
                customName: model.customClientName(forMACAddress: client.macAddress),
                onRename: { name in
                  model.setCustomClientName(name, forMACAddress: client.macAddress)
                })
              if client.id != sortedWirelessClients.last?.id {
                Divider()
              }
            }
          }
        }

        DashboardSection(title: "Health History", icon: "chart.xyaxis.line") {
          DashboardHealthHistory(samples: currentHealthHistory) {
            model.clearHealthHistory()
          }
        }

        DashboardSection(title: "Storage", icon: "externaldrive.fill") {
          DashboardStorageDiskHealthRow(state: model.storageHealth)
          Divider()
          DashboardStorageServiceRow(
            state: model.storageHealth,
            onRefresh: model.refreshStorageHealthAndInventoryIfPossible)
          Divider()
          DashboardTimeMachineBackupSection(state: model.timeMachineBackups)
          Divider()
          if model.disks.inventory.isEmpty {
            Text(
              model.disks.didLoadInventory ? "No disks reported" : "Waiting for disk information…"
            )
            .foregroundStyle(.secondary)
          } else {
            ForEach(model.disks.inventory) { disk in
              DashboardDiskRow(disk: disk)
            }
          }
        }
      }
      .padding(24)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear {
      model.isDashboardVisible = true
      model.dashboardPresentationDidChange()
      model.refreshStorageHealthIfPossible()
    }
    .onDisappear {
      model.isDashboardVisible = false
      model.dashboardPresentationDidChange()
    }
  }

  private var baseStationName: String {
    let name = model.baseStation.name.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? model.connection.host : name
  }

  private var firmwareVersion: String {
    let version = model.baseStation.version.trimmingCharacters(in: .whitespacesAndNewlines)
    return version.isEmpty ? "Unknown" : version
  }

  private var networkName: String {
    nonEmpty(model.wireless.networkName)
  }

  private var lanAddress: String {
    nonEmpty(model.network.lanIPAddress)
  }

  private var secondaryAddressTitle: String {
    model.network.routerMode == .bridge ? "Upstream Router" : "WAN Address"
  }

  private var secondaryAddress: String {
    let value =
      model.network.routerMode == .bridge
      ? model.internet.routerAddress
      : model.internet.ipv4Address
    return nonEmpty(value)
  }

  private var routerMode: String {
    model.network.routerMode.label
  }

  private var networkSummary: DashboardNetworkSummary {
    DashboardNetworkSummary(
      internet: model.internet,
      hostInternet: model.hostInternet,
      network: model.network,
      wireless: model.wireless,
      statusText: model.selectedDeviceStatusText(),
      statusDetails: model.selectedDeviceStatusDetails())
  }

  private var diskCapacitySummary: String {
    let disks = model.disks.inventory
    guard !disks.isEmpty else {
      return model.disks.didLoadInventory ? "No disks" : "Loading…"
    }
    let total = disks.compactMap(\.size).reduce(0, +)
    let free = disks.compactMap(\.sizeFree).reduce(0, +)
    guard total > 0 else { return "Available" }
    return "\(byteCount(free)) free of \(byteCount(total))"
  }

  private var weakClientCount: Int {
    model.wirelessClients.filter { client in
      guard let rssi = client.rssi else { return false }
      let normalizedRSSI = rssi > 0 ? rssi - 100 : rssi
      return normalizedRSSI < -82
    }.count
  }

  private var clientHealthSummary: String {
    guard model.hasLoadedWirelessClients else { return "Loading…" }
    guard !model.wirelessClients.isEmpty else { return "No clients reported" }
    return weakClientCount == 0 ? "All clients healthy" : "\(weakClientCount) weak signal"
  }

  private var clientHealthIcon: String {
    guard model.hasLoadedWirelessClients, !model.wirelessClients.isEmpty else {
      return "questionmark.circle"
    }
    return weakClientCount == 0 ? "checkmark.circle" : "exclamationmark.triangle"
  }

  private var wifiCongestionIcon: String {
    switch model.wifiCongestion.condition {
    case .clear: "checkmark.circle.fill"
    case .busy: "exclamationmark.triangle.fill"
    case .scanning: "clock"
    case .unknown, .unavailable: "wifi.exclamationmark"
    }
  }

  private func configurationStatusIcon(_ status: ConfigurationChangeStatus) -> String {
    switch status {
    case .verifiedReachable, .verifiedExpected: "checkmark.circle.fill"
    case .writeFailed, .verificationMismatch, .verificationFailed:
      "exclamationmark.triangle.fill"
    case .prepared, .applied: "clock"
    }
  }

  private func configurationStatusColor(_ status: ConfigurationChangeStatus) -> Color {
    switch status {
    case .verifiedReachable, .verifiedExpected: .green
    case .writeFailed, .verificationMismatch, .verificationFailed: .orange
    case .prepared, .applied: .secondary
    }
  }

  private var sortedWirelessClients: [WirelessClient] {
    model.wirelessClients.sorted {
      $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
    }
  }

  private var currentHealthHistory: [HealthHistorySample] {
    let host = AirportConnection.normalizedHost(model.connection.host)
    let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
    return model.healthHistory.filter { $0.host == host && $0.date >= cutoff }
  }

  private var currentHostConfigurationHistory: [ConfigurationChangeRecord] {
    let host = AirportConnection.normalizedHost(model.connection.host)
    return model.configurationChangeHistory.filter {
      AirportConnection.normalizedHost($0.host) == host
    }
  }

  private var currentHostAutomaticBackups: [ConfigurationChangeRecord] {
    let host = AirportConnection.normalizedHost(model.connection.host)
    return model.automaticConfigurationBackups.filter {
      AirportConnection.normalizedHost($0.host) == host
    }
  }

  private var currentHostRecoveryGuidance: RecoveryGuidance? {
    guard let guidance = model.recoveryGuidance,
      AirportConnection.normalizedHost(guidance.host)
        == AirportConnection.normalizedHost(model.connection.host)
    else { return nil }
    return guidance
  }

  /// The entries currently visible in the two history sections (the same
  /// `.prefix(5)` shown on screen), as a combined list to offer as
  /// comparison targets - not the full, unbounded history in either store.
  private var visibleHistoryEntries: [HistoryEntryReference] {
    let history = currentHostConfigurationHistory.prefix(5)
      .map { HistoryEntryReference(record: $0, isAutomaticBackup: false) }
    let backups = currentHostAutomaticBackups.prefix(5)
      .map { HistoryEntryReference(record: $0, isAutomaticBackup: true) }
    return (history + backups).sorted { $0.record.date > $1.record.date }
  }

  private func historyEntryMenuLabel(_ entry: HistoryEntryReference) -> String {
    let title = entry.isAutomaticBackup ? "Automatic backup" : entry.record.title
    return "\(title) · \(entry.record.date.formatted(date: .abbreviated, time: .shortened))"
  }

  @ViewBuilder
  private func compareMenu(for entry: HistoryEntryReference) -> some View {
    let others = visibleHistoryEntries.filter { $0.id != entry.id }
    Menu("Compare to...") {
      Button("Current") { model.compareToCurrentSettings(entry) }
      if !others.isEmpty {
        Divider()
        ForEach(others) { other in
          Button(historyEntryMenuLabel(other)) { model.compareEntries(entry, other) }
        }
      }
    }
  }

  private func nonEmpty(_ value: String) -> String {
    let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? "Unknown" : value
  }

  private func byteCount(_ value: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
  }
}

private struct DashboardHealthHistory: View {
  let samples: [HealthHistorySample]
  let onClear: () -> Void

  var body: some View {
    if samples.count < 2 {
      VStack(alignment: .leading, spacing: 4) {
        Text("Collecting history")
          .fontWeight(.medium)
        Text("Trend charts appear after two health samples. The app keeps one combined sample per 15-minute window.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    } else {
      VStack(alignment: .leading, spacing: 18) {
        if samples.contains(where: { $0.freeBytes != nil }) {
          VStack(alignment: .leading, spacing: 6) {
            Text("Time Capsule free space")
              .fontWeight(.medium)
            Chart(samples.compactMap { sample -> HealthChartPoint? in
              guard let bytes = sample.freeBytes else { return nil }
              return HealthChartPoint(date: sample.date, value: Double(bytes) / 1_000_000_000)
            }) { point in
              AreaMark(x: .value("Date", point.date), y: .value("GB free", point.value))
                .foregroundStyle(.blue.opacity(0.12))
              LineMark(x: .value("Date", point.date), y: .value("GB free", point.value))
                .foregroundStyle(.blue)
                .interpolationMethod(.monotone)
            }
            .chartYAxisLabel("GB free")
            .frame(height: 150)
          }
        }

        if backupAllocationPoints.count >= 2 {
          VStack(alignment: .leading, spacing: 6) {
            Text("Time Machine backup allocation")
              .fontWeight(.medium)
            Chart(backupAllocationPoints) { point in
              AreaMark(x: .value("Date", point.date), y: .value("GB allocated", point.value))
                .foregroundStyle(.purple.opacity(0.12))
              LineMark(x: .value("Date", point.date), y: .value("GB allocated", point.value))
                .foregroundStyle(.purple)
                .interpolationMethod(.monotone)
            }
            .chartYAxisLabel("GB allocated")
            .frame(height: 150)
            Text(backupGrowthSummary)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        VStack(alignment: .leading, spacing: 6) {
          Text("Connected and weak-signal clients")
            .fontWeight(.medium)
          Chart {
            ForEach(samples) { sample in
              LineMark(
                x: .value("Date", sample.date),
                y: .value("Clients", sample.wirelessClientCount),
                series: .value("Series", "Connected"))
                .foregroundStyle(by: .value("Series", "Connected"))
              LineMark(
                x: .value("Date", sample.date),
                y: .value("Clients", sample.weakSignalClientCount),
                series: .value("Series", "Weak signal"))
                .foregroundStyle(by: .value("Series", "Weak signal"))
            }
          }
          .chartForegroundStyleScale(["Connected": Color.blue, "Weak signal": Color.orange])
          .chartYScale(domain: 0...(maxClientCount + 1))
          .frame(height: 150)
        }

        HStack {
          Text("Last 30 days · \(samples.count) samples")
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer()
          Button("Clear History", action: onClear)
        }
      }
    }
  }

  private var maxClientCount: Int {
    max(samples.map(\.wirelessClientCount).max() ?? 0, 1)
  }

  private var backupAllocationPoints: [HealthChartPoint] {
    samples.compactMap { sample in
      guard let bytes = sample.backupAllocatedBytes else { return nil }
      return HealthChartPoint(date: sample.date, value: Double(bytes) / 1_000_000_000)
    }
  }

  private var backupGrowthSummary: String {
    guard let growth = TimeMachineBackupHistoryAnalysis.latestGrowth(in: samples) else {
      return "Collecting sparsebundle growth history"
    }
    let magnitude = ByteCountFormatter.string(
      fromByteCount: abs(growth.deltaBytes), countStyle: .file)
    let elapsed = DateComponentsFormatter()
    elapsed.allowedUnits = growth.interval >= 86_400 ? [.day, .hour] : [.hour, .minute]
    elapsed.unitsStyle = .abbreviated
    let interval = elapsed.string(from: growth.interval) ?? "the latest interval"
    switch growth.condition {
    case .growing:
      return "Allocated backup data grew by \(magnitude) over \(interval)."
    case .unchanged:
      return "Allocated backup data was unchanged over \(interval)."
    case .decreased:
      return "Allocated backup data decreased by \(magnitude) over \(interval), which can follow thinning or deletion."
    }
  }
}

private struct HealthChartPoint: Identifiable {
  let id = UUID()
  let date: Date
  let value: Double
}

private struct DashboardStorageDiskHealthRow: View {
  let state: StorageHealthState

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: icon)
        .foregroundStyle(color)
        .frame(width: 18)
      VStack(alignment: .leading, spacing: 2) {
        Text("Disk Condition")
          .fontWeight(.medium)
        Text(state.diskDetail)
          .font(.caption)
          .foregroundStyle(.secondary)
        if let total = state.totalBytes, let free = state.freeBytes {
          Text("\(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)) free of \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))")
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        if !state.smartStatus.isEmpty {
          Text("SMART: \(state.smartStatus)")
            .font(.caption2)
            .foregroundStyle(state.diskCondition == .warning ? Color.orange : Color.secondary)
        }
      }
      Spacer()
      Text(statusText)
        .foregroundStyle(color)
    }
  }

  private var statusText: String {
    switch state.diskCondition {
    case .unknown: "Unknown"
    case .healthy: "Capacity OK"
    case .warning: "Attention"
    case .unavailable: "Unavailable"
    case .notAvailable: "Not supported"
    }
  }

  private var icon: String {
    switch state.diskCondition {
    case .healthy: "checkmark.circle.fill"
    case .warning: "exclamationmark.triangle.fill"
    case .unknown, .unavailable, .notAvailable: "questionmark.circle"
    }
  }

  private var color: Color {
    switch state.diskCondition {
    case .healthy: .green
    case .warning: .orange
    default: .secondary
    }
  }
}

private struct DashboardStorageServiceRow: View {
  let state: StorageHealthState
  let onRefresh: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: icon)
        .foregroundStyle(color)
        .frame(width: 18)
      VStack(alignment: .leading, spacing: 2) {
        Text("SMB File Sharing")
          .fontWeight(.medium)
        Text(state.smbDetail)
          .font(.caption)
          .foregroundStyle(.secondary)
        if let lastChecked = state.lastChecked {
          Text("Checked \(lastChecked.formatted(date: .omitted, time: .standard))")
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
      }
      Spacer()
      if state.smbAvailability == .checking {
        ProgressView()
          .controlSize(.small)
      } else {
        Text(statusText)
          .foregroundStyle(color)
      }
      Button(action: onRefresh) {
        Image(systemName: "arrow.clockwise")
      }
      .buttonStyle(.plain)
      .disabled(state.smbAvailability == .checking)
      .help("Refresh disk information and SMB reachability")
    }
  }

  private var statusText: String {
    switch state.smbAvailability {
    case .unknown:
      "Not checked"
    case .checking:
      "Checking"
    case .reachable:
      "Reachable"
    case .unreachable:
      "Unavailable"
    case .disabled:
      "Disabled"
    case .notAvailable:
      "Not supported"
    }
  }

  private var icon: String {
    switch state.smbAvailability {
    case .unknown, .disabled, .notAvailable:
      "questionmark.circle"
    case .checking:
      "ellipsis.circle"
    case .reachable:
      "checkmark.circle.fill"
    case .unreachable:
      "exclamationmark.triangle.fill"
    }
  }

  private var color: Color {
    switch state.smbAvailability {
    case .reachable:
      .green
    case .unreachable:
      .orange
    default:
      .secondary
    }
  }
}

private struct DashboardTimeMachineBackupSection: View {
  let state: TimeMachineBackupState

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        Image(systemName: "clock.arrow.circlepath")
          .foregroundStyle(overallColor)
          .frame(width: 18)
        VStack(alignment: .leading, spacing: 2) {
          Text("Time Machine Backups")
            .fontWeight(.medium)
          Text(state.detail)
            .font(.caption)
            .foregroundStyle(.secondary)
          if let lastChecked = state.lastChecked {
            Text("Checked \(lastChecked.formatted(date: .omitted, time: .standard))")
              .font(.caption2)
              .foregroundStyle(.tertiary)
          }
        }
        Spacer()
        if state.isScanning {
          ProgressView()
            .controlSize(.small)
        }
      }

      ForEach(state.backups) { backup in
        HStack(spacing: 10) {
          Image(systemName: backupIcon(backup.condition))
            .foregroundStyle(backupColor(backup.condition))
            .frame(width: 18)
          VStack(alignment: .leading, spacing: 2) {
            Text(backup.computerName)
            Text(activityText(backup))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          if let size = backup.allocatedBytes {
            Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
              .foregroundStyle(.secondary)
          }
          Text(conditionText(backup.condition))
            .foregroundStyle(backupColor(backup.condition))
        }
      }
    }
  }

  private var overallColor: Color {
    if state.backups.contains(where: { $0.condition == .stale }) { return .red }
    if state.backups.contains(where: { $0.condition == .warning }) { return .orange }
    if !state.backups.isEmpty { return .green }
    return .secondary
  }

  private func activityText(_ backup: TimeMachineBackupRecord) -> String {
    guard let date = backup.latestActivity else { return "Latest backup activity unknown" }
    return "Latest activity \(date.formatted(date: .abbreviated, time: .shortened))"
  }

  private func conditionText(_ condition: TimeMachineBackupCondition) -> String {
    switch condition {
    case .current: "Current"
    case .warning: "Overdue"
    case .stale: "Stale"
    case .unknown: "Unknown"
    }
  }

  private func backupIcon(_ condition: TimeMachineBackupCondition) -> String {
    switch condition {
    case .current: "checkmark.circle.fill"
    case .warning, .stale: "exclamationmark.triangle.fill"
    case .unknown: "questionmark.circle"
    }
  }

  private func backupColor(_ condition: TimeMachineBackupCondition) -> Color {
    switch condition {
    case .current: .green
    case .warning: .orange
    case .stale: .red
    case .unknown: .secondary
    }
  }
}

private struct DashboardClientHeader: View {
  var body: some View {
    HStack(spacing: 12) {
      Text("Advertised Hostname")
        .frame(maxWidth: .infinity, alignment: .leading)
      Text("IP Address")
        .frame(width: 125, alignment: .leading)
      Text("Signal")
        .frame(width: 105, alignment: .leading)
      Text("Rate")
        .frame(width: 80, alignment: .trailing)
      Text("PHY")
        .frame(width: 115, alignment: .trailing)
    }
    .font(.caption)
    .foregroundStyle(.secondary)
  }
}

private struct DashboardClientRow: View {
  let client: WirelessClient
  var customName: String?
  var onRename: (String?) -> Void = { _ in }

  @State private var isRenaming = false
  @State private var renameDraft = ""

  var body: some View {
    HStack(spacing: 12) {
      HStack(spacing: 10) {
        Image(systemName: signalIcon)
          .foregroundStyle(signalColor)
          .frame(width: 20)
        Image(systemName: client.guessedDeviceType.systemImage)
          .foregroundStyle(.secondary)
          .frame(width: 16)
        VStack(alignment: .leading, spacing: 2) {
          Text(customName ?? client.advertisedHostname ?? "Not advertised")
            .fontWeight(.medium)
            .foregroundStyle(
              customName == nil && client.advertisedHostname == nil ? .secondary : .primary
            )
            .lineLimit(1)
          Text(subtitle)
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Text(nonEmpty(client.ipAddress))
        .frame(width: 125, alignment: .leading)
        .textSelection(.enabled)
      Text(signalText)
        .foregroundStyle(signalColor)
        .frame(width: 105, alignment: .leading)
      Text(rateText)
        .frame(width: 80, alignment: .trailing)
      Text(nonEmpty(client.phyMode))
        .lineLimit(1)
        .frame(width: 115, alignment: .trailing)
    }
    .font(.callout)
    .padding(.vertical, 3)
    .contentShape(Rectangle())
    .contextMenu {
      Button("Rename…") {
        renameDraft = customName ?? ""
        isRenaming = true
      }
      if customName != nil {
        Button("Clear Custom Name") { onRename(nil) }
      }
    }
    .alert("Rename Client", isPresented: $isRenaming) {
      TextField("Name", text: $renameDraft)
      Button("Cancel", role: .cancel) {}
      Button("Save") { onRename(renameDraft) }
    } message: {
      Text(
        "Shown only in this app, on this Mac. Never sent to the AirPort or the device itself.")
    }
  }

  private var subtitle: String {
    let vendor = client.vendorName
    if client.isPrivateAddress {
      return "\(normalizedMACAddress) · Private address"
    }
    if let vendor {
      return "\(normalizedMACAddress) · \(vendor)"
    }
    return normalizedMACAddress
  }

  private var normalizedRSSI: Int? {
    guard let rssi = client.rssi else { return nil }
    return rssi > 0 ? rssi - 100 : rssi
  }

  private var signalText: String {
    guard let normalizedRSSI else { return "Unknown" }
    return "\(normalizedRSSI) dBm"
  }

  private var signalIcon: String {
    guard let normalizedRSSI else { return "wifi.slash" }
    if normalizedRSSI < -82 { return "wifi.exclamationmark" }
    return "wifi"
  }

  private var signalColor: Color {
    guard let normalizedRSSI else { return .secondary }
    if normalizedRSSI < -82 { return .orange }
    return .green
  }

  private var rateText: String {
    guard let rate = client.dataRateMbps, rate.isFinite, rate >= 0 else { return "—" }
    return rate.rounded() == rate ? "\(Int(rate)) Mb/s" : "\(String(format: "%g", rate)) Mb/s"
  }

  private var normalizedMACAddress: String {
    let value = client.macAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? "Unknown" : value.uppercased()
  }

  private func nonEmpty(_ value: String?) -> String {
    let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return value.isEmpty ? "—" : value
  }
}

private struct DashboardCard: View {
  let title: String
  let value: String
  let icon: String

  var body: some View {
    HStack(spacing: 16) {
      Image(systemName: icon)
        .font(.title2)
        .frame(width: 32)

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.caption)
          .foregroundStyle(.secondary)

        Text(value)
          .font(.headline)
          .lineLimit(2)
      }

      Spacer()
    }
    .padding()
    .frame(maxWidth: .infinity, minHeight: 90)
    .background(.regularMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 14))
  }
}

private struct DashboardSection<Content: View>: View {
  let title: String
  let icon: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(title, systemImage: icon)
        .font(.headline)
      content
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.regularMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 14))
  }
}

private struct DashboardDetailRow: View {
  let title: String
  let value: String

  var body: some View {
    HStack {
      Text(title)
        .foregroundStyle(.secondary)
      Spacer()
      Text(value)
        .lineLimit(1)
        .textSelection(.enabled)
    }
  }
}

private struct DashboardDiskRow: View {
  let disk: DiskRecord

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(disk.name.isEmpty ? disk.deviceName : disk.name)
          .fontWeight(.medium)
        Spacer()
        Text(capacityText)
          .foregroundStyle(.secondary)
      }

      if let fractionUsed {
        ProgressView(value: fractionUsed)
      }
    }
  }

  private var capacityText: String {
    guard let total = disk.size, let free = disk.sizeFree else {
      return "Not reported by this AirPort"
    }
    return "\(byteCount(free)) free of \(byteCount(total))"
  }

  private var fractionUsed: Double? {
    guard let total = disk.size, let free = disk.sizeFree, total > 0 else { return nil }
    return min(max(Double(total - free) / Double(total), 0), 1)
  }

  private func byteCount(_ value: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
  }
}
