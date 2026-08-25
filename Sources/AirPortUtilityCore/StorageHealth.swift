// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

import Foundation
@preconcurrency import Network

enum StorageServiceAvailability: String, Codable, Sendable {
  case unknown
  case checking
  case reachable
  case unreachable
  case disabled
  case notAvailable
}

enum StorageDiskCondition: String, Codable, Sendable {
  case unknown
  case healthy
  case warning
  case unavailable
  case notAvailable
}

struct StorageHealthState: Equatable, Sendable {
  var diskCondition: StorageDiskCondition = .unknown
  var diskDetail = "Disk information has not loaded"
  var totalBytes: Int64?
  var freeBytes: Int64?
  var smartStatus = ""
  var smbAvailability: StorageServiceAvailability = .unknown
  var smbDetail = "Not checked"
  var lastChecked: Date?

}

struct StorageHealthEvent: Identifiable, Equatable, Sendable {
  let id: UUID
  let date: Date
  let host: String
  let diskCondition: StorageDiskCondition
  let totalBytes: Int64?
  let freeBytes: Int64?
  let smbAvailability: StorageServiceAvailability
  let summary: String
}

enum StorageHealthAssessment {
  private static let warningFreeFraction = 0.10
  private static let warningFreeBytes: Int64 = 20 * 1_024 * 1_024 * 1_024

  nonisolated static func diskState(
    supportsDisks: Bool,
    didLoadInventory: Bool,
    records: [DiskRecord],
    smartStatuses: [String] = []
  ) -> StorageHealthState {
    guard supportsDisks else {
      return StorageHealthState(
        diskCondition: .notAvailable,
        diskDetail: "This AirPort does not report shared-disk support")
    }
    guard didLoadInventory else {
      return StorageHealthState(
        diskCondition: .unavailable,
        diskDetail: "Disk inventory is unavailable; disk condition is unknown")
    }
    guard !records.isEmpty else {
      return StorageHealthState(
        diskCondition: .warning,
        diskDetail: "No disk volumes were reported")
    }

    let capacities = records.compactMap { record -> (Int64, Int64)? in
      guard let size = record.size, let free = record.sizeFree, size > 0 else { return nil }
      return (size, free)
    }
    guard capacities.count == records.count else {
      return StorageHealthState(
        diskCondition: .unavailable,
        diskDetail: "Disk volumes were reported, but capacity information is incomplete")
    }
    guard capacities.allSatisfy({ $0.1 >= 0 && $0.1 <= $0.0 }) else {
      return StorageHealthState(
        diskCondition: .warning,
        diskDetail: "The AirPort reported inconsistent disk capacity data")
    }

    guard let total = safeSum(capacities.map(\.0)), let free = safeSum(capacities.map(\.1)) else {
      return StorageHealthState(
        diskCondition: .unavailable,
        diskDetail: "Disk capacity totals are too large to assess safely")
    }
    let isLow = capacities.contains { size, available in
      let threshold = min(warningFreeBytes, Int64(Double(size) * warningFreeFraction))
      return available < threshold
    }
    let normalizedSMARTStatuses = smartStatuses
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    let smartStatus = normalizedSMARTStatuses.joined(separator: ", ")
    let smartIsVerified = !normalizedSMARTStatuses.isEmpty
      && normalizedSMARTStatuses.allSatisfy { $0.caseInsensitiveCompare("verified") == .orderedSame }
    let smartNeedsAttention = !normalizedSMARTStatuses.isEmpty && !smartIsVerified
    return StorageHealthState(
      diskCondition: isLow || smartNeedsAttention ? .warning : .healthy,
      diskDetail: smartNeedsAttention
        ? "The AirPort reported SMART status: \(smartStatus)"
        : isLow
        ? "Disk space is low"
        : smartIsVerified
        ? "Capacity values look normal; SMART status is verified"
        : "Capacity values look normal; hardware health is not reported",
      totalBytes: total,
      freeBytes: free,
      smartStatus: smartStatus)
  }

  private nonisolated static func safeSum(_ values: [Int64]) -> Int64? {
    var total: Int64 = 0
    for value in values {
      let result = total.addingReportingOverflow(value)
      guard !result.overflow else { return nil }
      total = result.partialValue
    }
    return total
  }
}

enum StoragePortProbe {
  nonisolated static func canConnect(
    host: String,
    port: UInt16,
    timeout: TimeInterval
  ) async -> Bool {
    let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !host.isEmpty, let port = NWEndpoint.Port(rawValue: port) else { return false }

    return await withCheckedContinuation { continuation in
      let queue = DispatchQueue(label: "com.pepperstm.airport-utility.storage-port-probe")
      let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
      let completion = StoragePortProbeCompletion(continuation: continuation)

      connection.stateUpdateHandler = { state in
        switch state {
        case .ready:
          completion.finish(true, connection: connection)
        case .failed, .cancelled:
          completion.finish(false, connection: connection)
        default:
          break
        }
      }

      queue.asyncAfter(deadline: .now() + max(timeout, 0.1)) {
        completion.finish(false, connection: connection)
      }
      connection.start(queue: queue)
    }
  }
}

private final class StoragePortProbeCompletion: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Bool, Never>?

  init(continuation: CheckedContinuation<Bool, Never>) {
    self.continuation = continuation
  }

  func finish(_ result: Bool, connection: NWConnection) {
    lock.lock()
    guard let continuation else {
      lock.unlock()
      return
    }
    self.continuation = nil
    lock.unlock()

    connection.stateUpdateHandler = nil
    connection.cancel()
    continuation.resume(returning: result)
  }
}
