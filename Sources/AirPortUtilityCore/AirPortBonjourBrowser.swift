import Darwin
import Foundation

final class AirPortBonjourBrowser: NSObject {
  private let serviceTypes = ["_airport._tcp."]

  /// File-sharing services a base station publishes when sharing is enabled,
  /// mapped to the label shown in the device popover.
  ///
  /// Presence is all Bonjour reports. It does not advertise an SMB dialect --
  /// that is negotiated per connection -- so this can say SMB but never SMB2.
  private static let fileSharingServiceTypes = [
    "_afpovertcp._tcp.": "AFP",
    "_smb._tcp.": "SMB",
  ]
  private static let stableIdentifierTXTKeys = ["wama", "rama", "sysn"]
  private static let knownModelNameFragments = ["express", "time capsule", "extreme"]
  private let onChange: @MainActor ([AirportDiscoveredDevice]) -> Void
  private var browsers: [NetServiceBrowser] = []
  private var services: [String: NetService] = [:]
  private var txtRecords: [String: Data] = [:]
  /// Lowercased service name -> protocol labels it publishes. A Time Capsule
  /// publishes its file-sharing services under the device name, so the name is
  /// what ties them back to the AirPort service.
  private var fileSharingProtocols: [String: Set<String>] = [:]

  init(onChange: @escaping @MainActor ([AirportDiscoveredDevice]) -> Void) {
    self.onChange = onChange
    super.init()
  }

  func start() {
    stop()
    for serviceType in serviceTypes + Array(Self.fileSharingServiceTypes.keys) {
      let browser = NetServiceBrowser()
      browser.delegate = self
      browser.searchForServices(ofType: serviceType, inDomain: "local.")
      browsers.append(browser)
    }
  }

  func stop() {
    for browser in browsers {
      browser.stop()
      browser.delegate = nil
    }
    browsers.removeAll()
    for service in services.values {
      service.stopMonitoring()
      service.stop()
      service.delegate = nil
    }
    services.removeAll()
    txtRecords.removeAll()
    fileSharingProtocols.removeAll()
    publish()
  }

  private func key(for service: NetService) -> String {
    "\(service.domain)|\(service.type)|\(service.name)"
  }

  private func publish() {
    let devices = services.values
      .map(device)
      .sorted {
        $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
      }
    let onChange = onChange
    Task { @MainActor in
      onChange(devices)
    }
  }

  private func device(from service: NetService) -> AirportDiscoveredDevice {
    let txtRecord =
      (txtRecords[key(for: service)] ?? service.txtRecordData())
      .map(NetService.dictionary(fromTXTRecord:)) ?? [:]
    let txtFields = Self.airportTXTFields(from: txtRecord)
    return AirportDiscoveredDevice(
      id: key(for: service),
      name: service.name,
      hostName: service.hostName ?? "",
      addresses: service.addresses?.compactMap(Self.numericHostAddress) ?? [],
      identifiers: Self.stableIdentifiers(fromTXTRecord: txtRecord),
      txtFields: txtFields,
      modelName: Self.modelName(fromTXTFields: txtFields),
      productID: txtFields["syap"] ?? "",
      publishedProtocols: publishedProtocols(forServiceNamed: service.name)
    )
  }

  /// Protocol labels published under `name`, ordered so the row reads the same
  /// way every time rather than in set order.
  private func publishedProtocols(forServiceNamed name: String) -> [String] {
    let found = fileSharingProtocols[name.lowercased()] ?? []
    return Self.fileSharingServiceTypes.values.sorted().filter(found.contains)
  }

  static func stableIdentifiers(fromTXTRecord txtRecord: [String: Data]) -> [String] {
    let fields = airportTXTFields(from: txtRecord)
    return stableIdentifierTXTKeys.compactMap { key in
      guard let value = fields[key], !value.isEmpty else { return nil }
      return "\(key):\(value.lowercased())"
    }
  }

  static func airportTXTFields(from txtRecord: [String: Data]) -> [String: String] {
    var fields: [String: String] = [:]
    for (key, data) in txtRecord {
      let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
      let value =
        String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let rawRecord = value.isEmpty ? key : "\(key)=\(value)"
      for field in rawRecord.split(separator: ",") {
        let field = field.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = field.firstIndex(of: "=") else { continue }
        let fieldKey = field[..<separator]
          .trimmingCharacters(in: .whitespacesAndNewlines)
          .lowercased()
        let fieldValue = field[field.index(after: separator)...]
          .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fieldKey.isEmpty, !fieldValue.isEmpty else { continue }
        fields[fieldKey] = fieldValue
      }
    }
    return fields
  }

  static func modelName(fromTXTFields fields: [String: String]) -> String {
    let description = fields["syds"]?
      .replacingOccurrences(of: "\\ ", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !description.isEmpty {
      let modelName = description.replacingOccurrences(
        of: #"\s+V\d+(?:\.\d+)*$"#,
        with: "",
        options: .regularExpression)
      let lowercasedModelName = modelName.lowercased()
      if knownModelNameFragments.contains(where: lowercasedModelName.contains) {
        return modelName
      }
    }
    switch fields["syap"]?.trimmingCharacters(in: .whitespacesAndNewlines) {
    case "102", "107", "115":
      return "AirPort Express"
    case "106", "109", "113", "116", "119":
      return "AirPort Time Capsule"
    case "3", "104", "105", "108", "114", "117", "120":
      return "AirPort Extreme"
    default:
      return ""
    }
  }

  private static func numericHostAddress(from data: Data) -> String? {
    data.withUnsafeBytes { rawBuffer -> String? in
      guard rawBuffer.count >= MemoryLayout<sockaddr>.size,
        let sockaddrPointer = rawBuffer.baseAddress?.assumingMemoryBound(to: sockaddr.self)
      else {
        return nil
      }
      let addressLength = Int(sockaddrPointer.pointee.sa_len)
      guard addressLength >= MemoryLayout<sockaddr>.size,
        addressLength <= rawBuffer.count
      else {
        return nil
      }
      var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      let result = getnameinfo(
        sockaddrPointer,
        socklen_t(addressLength),
        &hostBuffer,
        socklen_t(hostBuffer.count),
        nil,
        0,
        NI_NUMERICHOST
      )
      guard result == 0 else { return nil }
      let terminatorIndex = hostBuffer.firstIndex(of: 0) ?? hostBuffer.count
      return String(
        decoding: hostBuffer[..<terminatorIndex].map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
  }
}

extension AirPortBonjourBrowser: NetServiceBrowserDelegate {
  func netServiceBrowser(
    _ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool
  ) {
    // A file-sharing service is evidence about a device, not a device. Record
    // which protocols its name publishes and stop; letting it through would
    // list every share as its own base station.
    if let label = Self.fileSharingServiceTypes[service.type] {
      fileSharingProtocols[service.name.lowercased(), default: []].insert(label)
      if !moreComing {
        publish()
      }
      return
    }

    let serviceKey = key(for: service)
    if let previousService = services[serviceKey], previousService !== service {
      previousService.stopMonitoring()
      previousService.stop()
      previousService.delegate = nil
      txtRecords.removeValue(forKey: serviceKey)
    }
    services[serviceKey] = service
    service.delegate = self
    service.startMonitoring()
    service.resolve(withTimeout: 5)
    if !moreComing {
      publish()
    }
  }

  func netServiceBrowser(
    _ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool
  ) {
    if let label = Self.fileSharingServiceTypes[service.type] {
      let name = service.name.lowercased()
      fileSharingProtocols[name]?.remove(label)
      if fileSharingProtocols[name]?.isEmpty == true {
        fileSharingProtocols.removeValue(forKey: name)
      }
      if !moreComing {
        publish()
      }
      return
    }

    let serviceKey = key(for: service)
    guard let storedService = services[serviceKey], storedService === service else { return }
    services.removeValue(forKey: serviceKey)
    storedService.stopMonitoring()
    storedService.stop()
    storedService.delegate = nil
    txtRecords.removeValue(forKey: serviceKey)
    if !moreComing {
      publish()
    }
  }

  func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
    publish()
  }
}

extension AirPortBonjourBrowser: NetServiceDelegate {
  func netServiceDidResolveAddress(_ sender: NetService) {
    let serviceKey = key(for: sender)
    guard services[serviceKey] === sender else { return }
    publish()
  }

  func netService(_ sender: NetService, didUpdateTXTRecord data: Data) {
    let serviceKey = key(for: sender)
    guard services[serviceKey] === sender else { return }
    txtRecords[serviceKey] = data
    publish()
  }

  func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
    let serviceKey = key(for: sender)
    guard services[serviceKey] === sender else { return }
    publish()
  }
}
