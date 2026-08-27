import Foundation

enum DiskInventoryParser {
  private static let maStAllocationUnitBytes: Int64 = 1_048_576

  static func parse(stdout: String) -> [DiskRecord] {
    guard let data = stdout.data(using: .utf8),
      let value = try? JSONDecoder().decode(JSONValue.self, from: data)
    else { return [] }
    return records(in: value, parentBuiltIn: nil)
  }

  /// Values a partition can inherit from the disk it lives on. The device
  /// reports some of them once per physical disk rather than per partition.
  struct InheritedDiskValues {
    var smartStatus: String = ""
    var size: Int64?
    var sizeFree: Int64?
    var vendor: String = ""
    var revision: String = ""
  }

  private static func records(
    in value: JSONValue, parentBuiltIn: Bool?, inherited: InheritedDiskValues = .init()
  ) -> [DiskRecord] {
    switch value {
    case .array(let values):
      let diskDefaultBuiltIn = isSingleUnlabeledDiskArray(values) ? true : parentBuiltIn
      return values.flatMap {
        records(in: $0, parentBuiltIn: diskDefaultBuiltIn, inherited: inherited)
      }
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
        return records(in: decoded, parentBuiltIn: parentBuiltIn, inherited: inherited)
      }
      if let disks = object["disks"] {
        return records(in: disks, parentBuiltIn: nil)
      }
      if case .array(let partitions) = object["partitions"] {
        let diskBuiltIn = diskBuiltIn(object, defaultBuiltIn: parentBuiltIn)
        // SMART, and on some devices the capacity too, are reported once per
        // physical disk rather than per partition. Carry them down so a
        // partition can fall back to its disk's values.
        let diskSMART = string(object["smartStatus"])
        var childInherited = inherited
        if !diskSMART.isEmpty { childInherited.smartStatus = diskSMART }
        if let size = maStByteCount(object["size"]) { childInherited.size = size }
        if let sizeFree = maStByteCount(object["sizeFree"]) { childInherited.sizeFree = sizeFree }
        // Vendor and firmware revision describe the physical drive, so they are
        // only ever present on the disk, never on a partition.
        let vendor = string(object["vendor"])
        if !vendor.isEmpty { childInherited.vendor = vendor }
        let revision = string(object["revision"])
        if !revision.isEmpty { childInherited.revision = revision }
        return partitions.flatMap {
          records(in: $0, parentBuiltIn: diskBuiltIn, inherited: childInherited)
        }
      }
      if let record = record(from: object, parentBuiltIn: parentBuiltIn, inherited: inherited) {
        return [record]
      }
      return []
    default:
      return []
    }
  }

  private static func record(
    from object: [String: JSONValue], parentBuiltIn: Bool?,
    inherited: InheritedDiskValues = .init()
  ) -> DiskRecord? {
    let uuid = string(object["uuid"])
    let name = string(object["name"])
    let deviceName = string(object["deviceName"])
    guard !uuid.isEmpty || !name.isEmpty else { return nil }
    return DiskRecord(
      deviceName: deviceName,
      name: name.isEmpty ? deviceName : name,
      format: string(object["format"]),
      uuid: uuid,
      size: maStByteCount(object["size"]) ?? inherited.size,
      sizeFree: maStByteCount(object["sizeFree"]) ?? inherited.sizeFree,
      builtIn: diskBuiltIn(object, defaultBuiltIn: parentBuiltIn),
      vendor: {
        let own = string(object["vendor"])
        return own.isEmpty ? inherited.vendor : own
      }(),
      revision: {
        let own = string(object["revision"])
        return own.isEmpty ? inherited.revision : own
      }(),
      sizeUsed: maStByteCount(object["sizeUsed"]),
      smartStatus: {
        let own = string(object["smartStatus"])
        return own.isEmpty ? inherited.smartStatus : own
      }()
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
      return Int64(text)
    case .object(let object):
      // The device does not send bare numbers: an integer arrives wrapped as
      // {"type": "integer", "decimal": "623863", "width": 4}. Without this the
      // sizes decode to nil and the Disks pane shows no free space.
      return int64(object["decimal"])
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
