import Foundation

enum DiskInventoryParser {
  private static let maStAllocationUnitBytes: Int64 = 1_048_576

  static func parse(stdout: String) -> [DiskRecord] {
    guard let data = stdout.data(using: .utf8),
      let value = try? JSONDecoder().decode(JSONValue.self, from: data)
    else { return [] }
    return records(in: value, parentBuiltIn: nil)
  }

  static func diagnosticFieldSummary(stdout: String) -> String {
    guard let data = stdout.data(using: .utf8),
      let root = try? JSONDecoder().decode(JSONValue.self, from: data)
    else { return "disk inventory JSON could not be decoded" }
    let focused = inventoryValue(in: root) ?? root
    var paths: [String] = []
    collectFieldPaths(in: focused, path: "diskInventory", into: &paths)
    return paths.isEmpty ? "disk inventory contains no fields" : paths.sorted().joined(separator: ", ")
  }

  static func diagnosticMetricSummary(stdout: String) -> String {
    guard let data = stdout.data(using: .utf8),
      let root = try? JSONDecoder().decode(JSONValue.self, from: data)
    else { return "disk inventory metrics could not be decoded" }
    let focused = inventoryValue(in: root) ?? root
    var metrics: [String] = []
    collectDiagnosticMetrics(in: focused, path: "diskInventory", into: &metrics)
    return metrics.isEmpty ? "no disk metrics reported" : metrics.sorted().joined(separator: ", ")
  }

  static func smartStatuses(stdout: String) -> [String] {
    guard let data = stdout.data(using: .utf8),
      let root = try? JSONDecoder().decode(JSONValue.self, from: data)
    else { return [] }
    let focused = inventoryValue(in: root) ?? root
    var statuses: [String] = []
    collectSMARTStatuses(in: focused, into: &statuses)
    return statuses.reduce(into: []) { result, status in
      if !result.contains(where: { $0.caseInsensitiveCompare(status) == .orderedSame }) {
        result.append(status)
      }
    }
  }

  static func diagnosticRecordSummary(_ records: [DiskRecord]) -> String {
    guard !records.isEmpty else { return "no parsed volumes" }
    return records.enumerated().map { index, record in
      let name = record.name.trimmingCharacters(in: .whitespacesAndNewlines)
      let format = record.format.trimmingCharacters(in: .whitespacesAndNewlines)
      return "volume[\(index)] device=\(record.deviceName.isEmpty ? "<missing>" : record.deviceName) "
        + "name=\(name.isEmpty ? "<missing>" : name) "
        + "format=\(format.isEmpty ? "<missing>" : format) "
        + "size=\(record.size.map(String.init) ?? "<missing>") "
        + "sizeFree=\(record.sizeFree.map(String.init) ?? "<missing>") "
        + "builtIn=\(record.builtIn)"
    }.joined(separator: "; ")
  }

  private static func inventoryValue(in value: JSONValue) -> JSONValue? {
    guard case .object(let object) = value else { return nil }
    if let settings = object["settings"], case .object(let settingsObject) = settings,
      let inventory = settingsObject["MaSt"]
    {
      return inventory
    }
    if let inventory = object["MaSt"] { return inventory }
    return nil
  }

  private static func collectFieldPaths(
    in value: JSONValue, path: String, into paths: inout [String]
  ) {
    switch value {
    case .object(let object):
      if object.isEmpty { paths.append(path + "={}") }
      for key in object.keys.sorted() {
        collectFieldPaths(in: object[key]!, path: path + "." + key, into: &paths)
      }
    case .array(let values):
      if values.isEmpty { paths.append(path + "=[]") }
      for (index, item) in values.enumerated() {
        collectFieldPaths(in: item, path: path + "[\(index)]", into: &paths)
      }
    case .null: paths.append(path + "=null")
    case .bool: paths.append(path + "=<bool>")
    case .number: paths.append(path + "=<number>")
    case .string: paths.append(path + "=<string>")
    }
  }

  private static func collectDiagnosticMetrics(
    in value: JSONValue, path: String, into metrics: inout [String]
  ) {
    switch value {
    case .object(let object):
      for key in object.keys.sorted() {
        let childPath = path + "." + key
        if key == "decimal" || key == "smartStatus" || key == "blockSize" {
          if let description = scalarDescription(object[key]!) {
            metrics.append(childPath + "=" + description)
          }
        }
        collectDiagnosticMetrics(in: object[key]!, path: childPath, into: &metrics)
      }
    case .array(let values):
      for (index, item) in values.enumerated() {
        collectDiagnosticMetrics(in: item, path: path + "[\(index)]", into: &metrics)
      }
    default:
      break
    }
  }

  private static func collectSMARTStatuses(in value: JSONValue, into statuses: inout [String]) {
    switch value {
    case .object(let object):
      if case .string(let status)? = object["smartStatus"] {
        let status = status.trimmingCharacters(in: .whitespacesAndNewlines)
        if !status.isEmpty { statuses.append(status) }
      }
      for child in object.values {
        collectSMARTStatuses(in: child, into: &statuses)
      }
    case .array(let values):
      for child in values {
        collectSMARTStatuses(in: child, into: &statuses)
      }
    default:
      break
    }
  }

  private static func scalarDescription(_ value: JSONValue) -> String? {
    switch value {
    case .string(let value): return value
    case .number(let value):
      return value.rounded() == value ? String(format: "%.0f", value) : String(value)
    case .bool(let value): return String(value)
    default: return nil
    }
  }

  private static func records(in value: JSONValue, parentBuiltIn: Bool?) -> [DiskRecord] {
    switch value {
    case .array(let values):
      let diskDefaultBuiltIn = isSingleUnlabeledDiskArray(values) ? true : parentBuiltIn
      return values.flatMap { records(in: $0, parentBuiltIn: diskDefaultBuiltIn) }
    case .object(let object):
      if let settings = object["settings"],
        case .object(let settingsObject) = settings,
        let mast = settingsObject["MaSt"]
      {
        return records(in: mast, parentBuiltIn: nil)
      }
      if let mast = object["MaSt"] {
        return records(in: mast, parentBuiltIn: nil)
      }
      if let decoded = object["decoded"] {
        return records(in: decoded, parentBuiltIn: parentBuiltIn)
      }
      if let disks = object["disks"] {
        return records(in: disks, parentBuiltIn: nil)
      }
      if case .array(let partitions) = object["partitions"] {
        let diskBuiltIn = diskBuiltIn(object, defaultBuiltIn: parentBuiltIn)
        return partitions.flatMap { records(in: $0, parentBuiltIn: diskBuiltIn) }
      }
      if let record = record(from: object, parentBuiltIn: parentBuiltIn) {
        return [record]
      }
      return []
    default:
      return []
    }
  }

  private static func record(from object: [String: JSONValue], parentBuiltIn: Bool?) -> DiskRecord?
  {
    let uuid = string(object["uuid"])
    let name = string(object["name"])
    let deviceName = string(object["deviceName"])
    guard !uuid.isEmpty || !name.isEmpty else { return nil }
    return DiskRecord(
      deviceName: deviceName,
      name: name.isEmpty ? deviceName : name,
      format: string(object["format"]),
      uuid: uuid,
      size: maStByteCount(object["size"]),
      sizeFree: maStByteCount(object["sizeFree"]),
      builtIn: diskBuiltIn(object, defaultBuiltIn: parentBuiltIn)
    )
  }

  private static func isSingleUnlabeledDiskArray(_ values: [JSONValue]) -> Bool {
    guard values.count == 1,
      case .object(let object) = values[0],
      object["partitions"] != nil,
      explicitBuiltIn(object) == nil
    else {
      return false
    }
    return !isKnownExternalDisk(object)
  }

  private static func diskBuiltIn(_ object: [String: JSONValue], defaultBuiltIn: Bool?) -> Bool {
    if let builtIn = explicitBuiltIn(object) {
      return builtIn
    }
    if isKnownExternalDisk(object) {
      return false
    }
    if string(object["deviceName"]).lowercased().hasPrefix("wd") {
      return true
    }
    return defaultBuiltIn ?? false
  }

  private static func explicitBuiltIn(_ object: [String: JSONValue]) -> Bool? {
    bool(object["builtIn"]) ?? bool(object["builtin"])
  }

  private static func isKnownExternalDisk(_ object: [String: JSONValue]) -> Bool {
    string(object["deviceName"]).lowercased().hasPrefix("usb")
  }

  private static func string(_ value: JSONValue?) -> String {
    guard let value else { return "" }
    switch value {
    case .string(let text):
      return text
    case .number(let number):
      if number.rounded() == number, let intValue = safeInt64(number) {
        return String(intValue)
      }
      return String(number)
    case .object(let object):
      if case .string(let text) = object["text"] { return text }
      if case .string(let hex) = object["hex"] { return hex }
      return ""
    default:
      return ""
    }
  }

  private static func int64(_ value: JSONValue?) -> Int64? {
    guard let value else { return nil }
    switch value {
    case .number(let number):
      return safeInt64(number)
    case .string(let text):
      return Int64(text.trimmingCharacters(in: .whitespacesAndNewlines))
    case .object(let object):
      if case .string(let decimal)? = object["decimal"] {
        return Int64(decimal.trimmingCharacters(in: .whitespacesAndNewlines))
      }
      if let rawValue = object["value"] {
        return int64(rawValue)
      }
      return nil
    default:
      return nil
    }
  }

  private static func maStByteCount(_ value: JSONValue?) -> Int64? {
    guard let units = int64(value), units >= 0 else { return nil }
    let (bytes, overflow) = units.multipliedReportingOverflow(by: maStAllocationUnitBytes)
    return overflow ? nil : bytes
  }

  private static func bool(_ value: JSONValue?) -> Bool? {
    guard let value else { return nil }
    if case .bool(let bool) = value { return bool }
    return nil
  }

  private static func safeInt64(_ number: Double) -> Int64? {
    guard number.isFinite, number.rounded() == number,
      number >= -9_223_372_036_854_775_808.0,
      number < 9_223_372_036_854_775_808.0
    else {
      return nil
    }
    return Int64(number)
  }
}
