// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

import Foundation

enum NetworkDiagnosticCondition: String, Codable, Sendable {
  case unknown, checking, passed, warning, failed, notApplicable
}

struct NetworkDiagnosticResult: Codable, Equatable, Sendable {
  var condition: NetworkDiagnosticCondition = .unknown
  var summary = "Not checked"
}

struct NetworkDiagnosticsState: Codable, Equatable, Sendable {
  var gateway = NetworkDiagnosticResult()
  var dns = NetworkDiagnosticResult()
  var internet = NetworkDiagnosticResult()
  var doubleNAT = NetworkDiagnosticResult()
  var lastChecked: Date?
  var isRunning = false
}

enum DoubleNATAssessment {
  static func assess(routerMode: RouterMode, wanAddress: String) -> NetworkDiagnosticResult {
    guard routerMode != .bridge else {
      return NetworkDiagnosticResult(
        condition: .notApplicable, summary: "AirPort is in Bridge Mode")
    }
    let address = wanAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !address.isEmpty, address != "0.0.0.0" else {
      return NetworkDiagnosticResult(
        condition: .unknown, summary: "WAN address was not reported")
    }
    if isPrivateIPv4(address) {
      return NetworkDiagnosticResult(
        condition: .warning,
        summary: "AirPort WAN address is private; upstream NAT is likely")
    }
    return NetworkDiagnosticResult(
      condition: .passed, summary: "AirPort WAN address is not in a private range")
  }

  static func isPrivateIPv4(_ address: String) -> Bool {
    let parts = address.split(separator: ".").compactMap { Int($0) }
    guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
    return parts[0] == 10
      || (parts[0] == 172 && (16...31).contains(parts[1]))
      || (parts[0] == 192 && parts[1] == 168)
      || (parts[0] == 100 && (64...127).contains(parts[1]))
  }
}

enum NetworkDiagnosticProbe {
  static func run(_ executable: String, _ arguments: [String]) async -> Bool {
    await Task.detached {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: executable)
      process.arguments = arguments
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
      do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
      } catch {
        return false
      }
    }.value
  }

  static func resolves(_ hostname: String) async -> Bool {
    await Task.detached {
      let process = Process()
      let output = Pipe()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/dscacheutil")
      process.arguments = ["-q", "host", "-a", "name", hostname]
      process.standardOutput = output
      process.standardError = FileHandle.nullDevice
      do {
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return process.terminationStatus == 0
          && text.range(of: #"(?m)^ip_address:\s*\S+"#, options: .regularExpression) != nil
      } catch {
        return false
      }
    }.value
  }
}

@MainActor
extension AirportAppModel {
  func refreshNetworkDiagnostics() {
    guard !networkDiagnostics.isRunning else { return }
    let gateway = hostInternet.routerAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    let routerMode = network.routerMode
    let wanAddress = internet.ipv4Address
    networkDiagnostics = NetworkDiagnosticsState(
      gateway: NetworkDiagnosticResult(condition: .checking, summary: "Checking gateway…"),
      dns: NetworkDiagnosticResult(condition: .checking, summary: "Resolving a public hostname…"),
      internet: NetworkDiagnosticResult(condition: .checking, summary: "Checking public route…"),
      doubleNAT: DoubleNATAssessment.assess(routerMode: routerMode, wanAddress: wanAddress),
      isRunning: true)
    networkDiagnosticsTask?.cancel()
    networkDiagnosticsTask = Task { [weak self] in
      async let gatewayOK = gateway.isEmpty
        ? false : NetworkDiagnosticProbe.run("/sbin/ping", ["-c", "1", "-W", "1000", gateway])
      async let dnsOK = NetworkDiagnosticProbe.resolves("captive.apple.com")
      async let internetOK = NetworkDiagnosticProbe.run(
        "/usr/bin/nc", ["-z", "-w", "4", "1.1.1.1", "443"])
      let results = await (gatewayOK, dnsOK, internetOK)
      guard let self, !Task.isCancelled else { return }
      networkDiagnostics = NetworkDiagnosticsState(
        gateway: gateway.isEmpty
          ? NetworkDiagnosticResult(condition: .unknown, summary: "Default gateway was not reported")
          : NetworkDiagnosticResult(
            condition: results.0 ? .passed : .failed,
            summary: results.0 ? "Default gateway responded" : "Default gateway did not respond"),
        dns: NetworkDiagnosticResult(
          condition: results.1 ? .passed : .failed,
          summary: results.1 ? "Public hostname resolved" : "Public hostname did not resolve"),
        internet: NetworkDiagnosticResult(
          condition: results.2 ? .passed : .failed,
          summary: results.2 ? "Public TCP route is reachable" : "Public TCP route is unreachable"),
        doubleNAT: DoubleNATAssessment.assess(routerMode: routerMode, wanAddress: wanAddress),
        lastChecked: Date(), isRunning: false)
      appendLog("Network diagnostics completed: gateway=\(results.0), DNS=\(results.1), Internet=\(results.2).")
    }
  }
}
