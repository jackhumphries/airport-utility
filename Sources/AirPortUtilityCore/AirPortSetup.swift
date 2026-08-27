import SwiftUI

enum AirPortSetupMode: String, CaseIterable, Identifiable {
  case create
  case extend
  case replace

  var id: String { rawValue }

  var title: String {
    switch self {
    case .create: localized("Create a new network")
    case .extend: localized("Add to an existing network")
    case .replace: localized("Replace an existing device")
    }
  }
}

enum AirPortSetupStep: Equatable {
  case examining
  case recommendation
  case choices
  case details
  case applying
  case complete
}

struct AirPortSetupState: Equatable {
  var step: AirPortSetupStep = .examining
  var mode: AirPortSetupMode = .create
  var deviceName = ""
  var networkName = ""
  var password = ""
  var verifyPassword = ""
  var useSinglePassword = true
  var sourceDeviceID = ""
  var airPlayEnabled = true
  var airPlaySpeakerName = ""
  var progressText = localized("Examining the base station…")
  var errorText = ""
  var profile: JSONValue?

  var canContinueDetails: Bool {
    let trimmedDevice = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedNetwork = networkName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedDevice.isEmpty, password.count >= 8, password == verifyPassword else {
      return false
    }
    switch mode {
    case .create: return !trimmedNetwork.isEmpty
    case .extend: return !trimmedNetwork.isEmpty
    case .replace: return !sourceDeviceID.isEmpty
    }
  }
}

@MainActor
extension AirportAppModel {
  public var canRequestRestoreDefaultSettings: Bool {
    !isBusy && !isRestorePending && !isRestoringDefaults && !isShowingSetup
      && !isShowingRestartConfirmation && selectedTopologyDevice() != nil
  }

  var setupDeviceModelName: String {
    let name = selectedTopologyDevice()?.displayModelName.trimmingCharacters(in: .whitespacesAndNewlines)
    if let name, !name.isEmpty { return name }
    return postApplyDeviceNameForStatus
  }

  var setupSourceDevices: [AirportDiscoveredDevice] {
    discoveredDevices.filter { !$0.requiresSetup && $0.id != selectedTopologyDeviceID }
  }

  var setupNetworkSuggestions: [String] {
    var names = wirelessScanNetworkNames
    names += setupSourceDevices.map(\.displayName)
    var seen = Set<String>()
    return names.filter {
      let normalized = $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      return !normalized.isEmpty && seen.insert(normalized).inserted
    }
  }

  var showsSetupAirPlayControls: Bool {
    capabilities.supportsAirPlay
  }

  func beginSetup(for device: AirportDiscoveredDevice? = nil) {
    setupSessionID = UUID()
    let sessionID = setupSessionID
    if let device { selectTopologyDevice(device) }
    let selected = device ?? selectedTopologyDevice()
    let suggestedName = selected?.displayName ?? setupDeviceModelName
    setup = AirPortSetupState(
      step: .examining,
      deviceName: suggestedName,
      networkName: suggestedName,
      airPlaySpeakerName: suggestedName,
      progressText: localized("Examining the base station…"))
    isDevicePopoverPresented = false
    isEditingDevice = false
    isShowingRestartConfirmation = false
    isShowingRestoreConfirmation = false
    isWaitingForSetupRestart = false
    didSetupDeviceDisappear = false
    setupPreRestartServiceID = ""
    setupPreRestartBonjourSeed = ""
    isShowingSetup = true
    Task { @MainActor in
      do {
        if self.mockMode {
          try await Task.sleep(nanoseconds: 650_000_000)
        } else {
          guard self.setupSessionID == sessionID, self.isShowingSetup else { return }
          self.setup.progressText = localized("Gathering information about your network…")
          let profile = try await self.readSetupProfile()
          guard self.setupSessionID == sessionID, self.isShowingSetup else { return }
          self.setup.profile = profile
        }
        guard self.setupSessionID == sessionID, self.isShowingSetup,
          self.setup.step == .examining
        else { return }
        self.setup.step = .recommendation
      } catch {
        guard self.setupSessionID == sessionID, self.isShowingSetup else { return }
        self.setup.errorText = Self.userFacingErrorDescription(error.localizedDescription)
        self.setup.progressText = localized("Could not read the base station setup profile.")
        self.setup.step = .details
      }
    }
  }

  func cancelSetup() {
    setupSessionID = UUID()
    setup.password = ""
    setup.verifyPassword = ""
    setup.errorText = ""
    isWaitingForSetupRestart = false
    didSetupDeviceDisappear = false
    setupPreRestartServiceID = ""
    setupPreRestartBonjourSeed = ""
    clearBaseStationUpdate()
    isShowingSetup = false
  }

  func setupBack() {
    setup.errorText = ""
    switch setup.step {
    case .choices: setup.step = .recommendation
    case .details: setup.step = .choices
    default: break
    }
  }

  func setupNext() {
    setup.errorText = ""
    switch setup.step {
    case .recommendation:
      setup.mode = .create
      setup.step = .details
    case .choices:
      setup.step = .details
    case .details:
      guard setup.canContinueDetails else {
        setup.errorText = localized("Enter names and matching passwords of at least 8 characters.")
        return
      }
      applySetup()
    case .complete:
      cancelSetup()
    default: break
    }
  }

  func showSetupChoices() {
    setup.step = .choices
  }

  public func requestRestoreDefaultSettings() {
    guard canRequestRestoreDefaultSettings else { return }
    guard mockMode || liveCredentialsAvailable else {
      presentSelectedDeviceConnectionPrompt()
      return
    }
    isShowingRestoreConfirmation = true
    isDevicePopoverPresented = false
    clearAuxiliarySheets()
  }

  public func restoreDefaultSettings() {
    guard !isRestoringDefaults, !isRestorePending else { return }
    guard mockMode || liveCredentialsAvailable else {
      presentSelectedDeviceConnectionPrompt()
      return
    }
    let activeConnection = connection
    let deviceIdentifiers =
      selectedTopologyDeviceIdentifiers.isEmpty
      ? connectedTopologyDeviceIdentifiers : selectedTopologyDeviceIdentifiers
    if isBusy {
      isRestorePending = true
      pendingRestoreConnection = activeConnection
      pendingRestoreDeviceIdentifiers = deviceIdentifiers
      status = localized("Waiting to restore default settings")
      return
    }
    startRestoreDefaultSettings(
      connection: activeConnection, deviceIdentifiers: deviceIdentifiers)
  }

  private func startRestoreDefaultSettings(
    connection activeConnection: AirportConnection, deviceIdentifiers: [String]
  ) {
    isRestorePending = false
    pendingRestoreConnection = nil
    pendingRestoreDeviceIdentifiers = []
    isShowingRestoreConfirmation = true
    isRestoringDefaults = true
    isWaitingForRestoreRestart = false
    updatingBaseStationDeviceIdentifiers = deviceIdentifiers
    performRestoreDefaultSettings(connection: activeConnection)
  }

  func startPendingRestoreIfNeeded() {
    guard isRestorePending else { return }
    guard isShowingRestoreConfirmation else {
      isRestorePending = false
      pendingRestoreConnection = nil
      pendingRestoreDeviceIdentifiers = []
      return
    }
    guard !isBusy else { return }
    guard let pendingRestoreConnection else {
      isRestorePending = false
      pendingRestoreDeviceIdentifiers = []
      return
    }
    startRestoreDefaultSettings(
      connection: pendingRestoreConnection,
      deviceIdentifiers: pendingRestoreDeviceIdentifiers)
  }

  private func performRestoreDefaultSettings(connection activeConnection: AirportConnection) {
    let commands = restoreDefaultCommandSequence(connection: activeConnection)
    applySequence(
      title: localized("Restore Default Settings"), commands: commands,
      connection: activeConnection, cleanScope: .none,
      delayBetweenCommandsNanoseconds: 8_000_000_000,
      allowsConnectionHostChange: true
    ) {
      self.isWaitingForRestoreRestart = true
      self.status = localized("Waiting for this base station to restart with default settings.")
      self.completeRestoreIfResetDeviceAvailable()
    } failure: { description in
      self.isRestoringDefaults = false
      self.isRestorePending = false
      self.isWaitingForRestoreRestart = false
      self.pendingRestoreConnection = nil
      self.pendingRestoreDeviceIdentifiers = []
      self.isShowingRestoreConfirmation = false
      self.clearBaseStationUpdate()
      self.status = localizedFormat("Restore failed: %@", description)
    }
  }

  func restoreDefaultCommandSequence(connection activeConnection: AirportConnection)
    -> [(String, [String])]
  {
    let emptyBytes = #"{"type":"bytes","hex":""}"#
    let productID =
      selectedTopologyDevice()?.productID.trimmingCharacters(in: .whitespacesAndNewlines)
      ?? baseStation.productID.trimmingCharacters(in: .whitespacesAndNewlines)
    if productID == "3" {
      func marker(
        _ setting: String, connection: AirportConnection
      ) -> [String] {
        AirportCommand.rawWriteJSON(
          setting: setting, valueJSON: emptyBytes, connection: connection, dryRun: false
        ).usingAirPortBackendSubcommand("legacy-write")
          + ["--streaming", "--acp17", "--request-flags", "0"]
      }
      var factoryConnection = activeConnection
      factoryConnection.password = "public"
      return [
        (localized("Identify Base Station"), marker("lebl", connection: activeConnection)),
        (localized("Restore Factory Defaults"), marker("acRF", connection: activeConnection)),
        (localized("Restart Base Station"), marker("acRB", connection: activeConnection)),
        (localized("Finish Factory Restore"), marker("lebs", connection: factoryConnection)),
        (localized("Restart with Default Settings"), marker("acRB", connection: factoryConnection)),
      ]
    }
    let reset = AirportCommand.rawWriteJSON(
      setting: "acRF", valueJSON: emptyBytes, connection: activeConnection, dryRun: false
    ).usingAirPortBackendSubcommand("legacy-write") + ["--streaming", "--request-flags", "0"]
    var factoryConnection = activeConnection
    factoryConnection.password = "public"
    let reboot = AirportCommand.rawWriteJSON(
      setting: "acRB", valueJSON: emptyBytes, connection: factoryConnection, dryRun: false
    ).usingAirPortBackendSubcommand("legacy-write") + ["--streaming", "--request-flags", "0"]
    return [(localized("Restore Factory Defaults"), reset), (localized("Restart Base Station"), reboot)]
  }

  func applySetup() {
    guard setup.canContinueDetails else { return }
    guard !isBusy else {
      setup.errorText = localized("Wait for the current base station operation to finish, then try again.")
      return
    }
    guard setup.profile != nil else {
      setup.errorText = localized("The base station setup profile has not loaded. Go Back and try again.")
      return
    }
    let activeConnection = connection
    let commands = setupCommandSequence(connection: activeConnection)
    let password = setup.password
    updatingBaseStationDeviceIdentifiers =
      selectedTopologyDeviceIdentifiers.isEmpty
      ? connectedTopologyDeviceIdentifiers : selectedTopologyDeviceIdentifiers
    setupPreRestartServiceID = selectedTopologyDeviceID ?? ""
    setupPreRestartBonjourSeed = selectedTopologyDevice()?.txtFields["bjsd"] ?? ""
    isWaitingForSetupRestart = false
    didSetupDeviceDisappear = false
    setup.step = .applying
    setup.progressText = localizedFormat("Setting up this %@…", setupDeviceModelName)
    applySequence(
      title: localized("Setup"), commands: commands, connection: activeConnection, cleanScope: .none,
      appliedAdminPassword: password, allowsConnectionHostChange: true
    ) {
      self.setupWriteDidSucceed(password: password)
    } failure: { description in
      self.isWaitingForSetupRestart = false
      self.didSetupDeviceDisappear = false
      self.setupPreRestartServiceID = ""
      self.setupPreRestartBonjourSeed = ""
      self.clearBaseStationUpdate()
      self.setup.errorText = description
      self.setup.progressText = localized("Setup failed")
      self.setup.step = .details
    }
  }

  func setupWriteDidSucceed(password: String) {
    connection.password = password
    setup.progressText = localized("Waiting for this base station to apply its settings and restart…")
    setup.password = ""
    setup.verifyPassword = ""
    isWaitingForSetupRestart = true
    isRestoringDefaults = false
    completeSetupIfRestartedDeviceAvailable()
  }

  func setupRestartDidComplete(with device: AirportDiscoveredDevice) {
    guard isShowingSetup, setup.step == .applying, isWaitingForSetupRestart else { return }
    isWaitingForSetupRestart = false
    didSetupDeviceDisappear = false
    setupPreRestartServiceID = ""
    setupPreRestartBonjourSeed = ""
    clearBaseStationUpdate()
    selectTopologyDevice(device)
    applyDeviceStatus(problemCodes: device.problemCodes)
    isDevicePopoverPresented = false
    deselectTopologyDevice(device)
    setup.step = .complete
    isShowingSetup = false
  }

  func setupCommandSequence(connection activeConnection: AirportConnection) -> [(String, [String])] {
    if usesLegacyACP, let valuesJSON = try? setupLegacyAtomicValuesJSON() {
      return [
        (
          localized("Setup"),
          AirportCommand.rawWriteValuesJSON(
            valuesJSON, connection: activeConnection, dryRun: false
          ).usingAirPortBackendSubcommand("legacy-write") + [
            "--streaming"
          ] + (usesLegacyACP17 ? ["--acp17"] : [])
        )
      ]
    }
    if !usesLegacyACP, let valuesJSON = try? setupAtomicValuesJSON() {
      return [
        (
          localized("Setup"),
          AirportCommand.rawWriteValuesJSON(
            valuesJSON, connection: activeConnection, dryRun: false) + ["--no-verify"]
        )
      ]
    }
    let deviceName = setup.deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
    var networkName = setup.networkName.trimmingCharacters(in: .whitespacesAndNewlines)
    if setup.mode == .replace,
      let source = setupSourceDevices.first(where: { $0.id == setup.sourceDeviceID })
    {
      networkName = source.displayName
    }
    let password = setup.password
    var flags = [
      BackendFlag("--connect-using", "dhcp"),
      BackendFlag("--wireless-name", networkName),
      BackendFlag("--wireless-security", "wpa-wpa2-personal"),
      BackendFlag("--wireless-password", password),
      BackendFlag("--allow-network-extension", nil),
      BackendFlag("--allow-setup-over-wan", nil),
    ]
    switch setup.mode {
    case .create:
      flags += [
        BackendFlag("--wireless-mode", "create"),
        BackendFlag("--router-mode", setupCreateRouterMode),
        BackendFlag("--dhcp-range-start", "10.0.1.2"),
        BackendFlag("--dhcp-range-end", "10.0.1.200"),
        BackendFlag("--dhcp-lease", "86400"),
      ]
    case .extend:
      flags += [BackendFlag("--wireless-mode", "extend"), BackendFlag("--router-mode", "bridge")]
    case .replace:
      flags += [BackendFlag("--wireless-mode", "create"), BackendFlag("--router-mode", "bridge")]
    }
    if capabilities.supportsAirPlay {
      flags += [
        BackendFlag(setup.airPlayEnabled ? "--airplay-enabled" : "--no-airplay-enabled", nil),
        BackendFlag("--airplay-speaker-name", setup.airPlaySpeakerName),
      ]
    }
    let settings = AirportCommand.friendlyWrite(
      connection: activeConnection, flags: flags, dryRun: false)
    let name = AirportCommand.rawWrite(
      setting: "syNm", value: deviceName, connection: activeConnection, dryRun: false)
    let adminPassword = AirportCommand.rawWrite(
      setting: "syPW", value: password, connection: activeConnection, dryRun: false)
    var commands = appliedFinalCommand([
      (localized("Network Setup"), settings), (localized("Base Station Name"), name),
      (localized("Base Station Password"), adminPassword),
    ])
    if !commands[commands.count - 1].1.contains("--setup-complete") {
      commands[commands.count - 1].1.append("--setup-complete")
    }
    return commands
  }

  private var setupCreateRouterMode: String {
    let productID = selectedTopologyDevice()?.productID.trimmingCharacters(in: .whitespacesAndNewlines)
    return switch productID.flatMap({ $0.isEmpty ? nil : $0 })
      ?? baseStation.productID.trimmingCharacters(in: .whitespacesAndNewlines)
    {
    case "106", "109", "113", "116", "119": "bridge"
    default: "dhcp-and-nat"
    }
  }

  func setupLegacyAtomicValuesJSON(timestamp: Int? = nil) throws -> String {
    guard case .object(let response) = setup.profile,
      case .object(var settings)? = response["settings"]
    else { throw AirPortSetupPayloadError.missingProfile }
    let name = setup.deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
    let networkName = setup.networkName.trimmingCharacters(in: .whitespacesAndNewlines)
    let password = setup.password
    let empty: JSONValue = .object(["type": .string("bytes"), "hex": .string("")])
    let psk: JSONValue = .object([
      "type": .string("wpa-psk"), "password": .string(password), "ssid": .string(networkName),
    ])
    var changes: [String: JSONValue] = [
      "ctim": .number(Double(timestamp ?? Int(Date().timeIntervalSince1970 - 978_307_200))),
      "dhBg": .string("10.0.1.2"), "dhDB": .string("10.0.1.2"),
      "dhDE": .string("10.0.1.200"), "dhEn": .string("10.0.1.200"),
      "dhDL": .number(14_400), "dhLe": .number(14_400),
      "dhDS": .string("255.255.255.0"), "dhSN": .string("255.255.255.0"),
      "dhRo": .string("10.0.1.1"), "laIP": .string("10.0.1.1"),
      "laSM": .string("255.255.255.0"), "nDMZ": .string("0.0.0.0"),
      "naFl": .number(0), "raCr": .string(password), "raDS": .bool(true),
      "raNA": .bool(true), "raNm": .string(networkName), "raSt": .number(0),
      "raTr": .number(0), "raWB": .bool(false), "raWE": psk, "raWM": .number(5),
      "syNm": .string(name), "syPW": .string(password), "waCV": .number(0x300),
      "waNM": .bool(true), "acFN": empty, "acRB": empty,
    ]
    if capabilities.supportsAirPlay {
      changes["aWan"] = .bool(false)
      changes["auNN"] = .string(name)
      changes["auRR"] = .bool(true)
    }
    if capabilities.supportsModem {
      changes["lcVs"] = .string("561.3")
    }
    for (key, value) in changes { settings[key] = value }
    let encoder = JSONEncoder()
    return String(decoding: try encoder.encode(JSONValue.object(settings)), as: UTF8.self)
  }

  func setupAtomicValuesJSON(timestamp: Int? = nil) throws -> String {
    guard var profile = setup.profile?.restoreProfileOnly else {
      throw AirPortSetupPayloadError.missingProfile
    }
    let name = setup.deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
    let networkName = setup.networkName.trimmingCharacters(in: .whitespacesAndNewlines)
    let password = setup.password
    let psk: JSONValue = .object([
      "type": .string("wpa-psk"), "password": .string(password), "ssid": .string(networkName),
    ])
    let passwordBytes: JSONValue = .object([
      "type": .string("bytes"),
      "hex": .string(password.utf8.map { String(format: "%02x", $0) }.joined()),
    ])

    profile = profile.setting(path: ["restoreProfile", "syNm"], to: .string(name))
    profile = profile.setting(path: ["restoreProfile", "syPW"], to: .string(password))
    profile = profile.settingInteger(path: ["restoreProfile", "waCV"], to: 0x8300)
    profile = profile.settingInteger(
      path: ["restoreProfile", "raTr"],
      to: setupCreateRouterMode == "bridge" ? 4_294_967_295 : 0)
    profile = profile.setting(path: ["restoreProfile", "raWB"], to: .bool(true))
    profile = profile.setting(path: ["restoreProfile", "raNA"], to: .bool(false))
    profile = profile.setting(path: ["restoreProfile", "raDS"], to: .bool(false))
    profile = profile.setting(path: ["restoreProfile", "waNM"], to: .bool(false))
    profile = profile.setting(path: ["restoreProfile", "6sfw"], to: .bool(true))
    profile = profile.settingIfPresent(path: ["restoreProfile", "IDNm"], to: .string(""))
    profile = profile.setting(path: ["restoreProfile", "nDMZ"], to: .string("0.0.0.0"))
    profile = profile.setting(path: ["restoreProfile", "wbHN"], to: .string(""))
    profile = profile.setting(path: ["restoreProfile", "wbHU"], to: .string(""))
    profile = profile.setting(
      path: ["restoreProfile", "wbHP"],
      to: .string(""))
    profile = profile.setting(
      path: ["restoreProfile", "DRes"],
      to: .object(["dhcpReservations": .array([])]))
    profile = profile.setting(
      path: ["restoreProfile", "fire"],
      to: .object(["firewallEnabled": .bool(false), "entries": .array([])]))
    profile = profile.setting(
      path: ["restoreProfile", "syIg"],
      to: .object(["problems": .array([])]))
    if case .array(let accessEntries)? = profile.value(
      path: ["restoreProfile", "tACL", "entries"]), let first = accessEntries.first
    {
      let fullAccess = first
        .setting(path: ["description"], to: .string("FullAccess"))
        .setting(
          path: ["wirelessAccessTimes"],
          to: .array([.string("days=mtwtfss;t=0-0")]))
      profile = profile.setting(
        path: ["restoreProfile", "tACL", "entries"], to: .array([fullAccess]))
    }
    profile = profile.setting(path: ["restoreProfile", "laIP"], to: .string("10.0.1.1"))
    profile = profile.setting(path: ["restoreProfile", "dhBg"], to: .string("10.0.1.2"))
    profile = profile.setting(path: ["restoreProfile", "dhEn"], to: .string("10.0.1.200"))
    profile = profile.settingInteger(path: ["restoreProfile", "dhLe"], to: 86_400)
    let completionTimestamp = timestamp ?? Int(Date().timeIntervalSince1970 - 978_307_200)
    profile = profile.settingInteger(
      path: ["restoreProfile", "time"], to: completionTimestamp + 978_307_200)
    profile = profile.mapArray(path: ["restoreProfile", "WiFi", "radios"]) { radio in
      var configured = radio
        .setting(path: ["raNm"], to: .string(networkName))
        .settingInteger(path: ["raSt"], to: 0)
        .settingInteger(path: ["raWM"], to: 5)
        .setting(path: ["raCr"], to: passwordBytes)
        .setting(path: ["raWE"], to: psk)
        .setting(path: ["dWDS"], to: .bool(true))
        .setting(path: ["raCl"], to: .bool(false))
      if SetupProfileTemplates.tracedProductID(for: setupProductID) == "115" {
        configured = configured.setting(path: ["pSTA"], to: .bool(false))
      }
      return configured
    }

    guard let wifi = profile.value(path: ["restoreProfile", "WiFi"]),
      let timezone = profile.value(path: ["restoreProfile", "timz"])
    else {
      throw AirPortSetupPayloadError.incompleteProfile
    }
    let clientVersion = "639.26-MacAU"
    var ordered: [(String, JSONValue)] = [
      ("AUVs", .string(clientVersion)),
      ("Prof", profile),
      ("WiFi", wifi),
      ("ctim", .number(Double(completionTimestamp))),
      ("lcVr", .number(33_554_432)),
      ("lcVs", .string(clientVersion)),
      ("raDS", .bool(false)),
      ("raNA", .bool(false)),
      ("raWB", .bool(true)),
    ]
    if setupProductID == "120" {
      ordered.append(("sttE", .bool(true)))
    }
    ordered += [
      ("syNm", .string(name)),
      ("syPW", .string(password)),
      ("timz", timezone),
    ]
    let encoder = JSONEncoder()
    let members = try ordered.map { key, value -> String in
      let encodedKey = try String(decoding: encoder.encode(key), as: UTF8.self)
      let encodedValue = try String(decoding: encoder.encode(value), as: UTF8.self)
      return "\(encodedKey):\(encodedValue)"
    }
    return "{" + members.joined(separator: ",") + "}"
  }

  private var setupProductID: String {
    let selected = selectedTopologyDevice()?.productID.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return selected.isEmpty
      ? baseStation.productID.trimmingCharacters(in: .whitespacesAndNewlines) : selected
  }
}

private enum AirPortSetupPayloadError: LocalizedError {
  case missingProfile
  case incompleteProfile

  var errorDescription: String? {
    switch self {
    case .missingProfile: localized("The base station setup profile has not loaded yet.")
    case .incompleteProfile: localized("The base station setup profile is missing Wi-Fi or timezone settings.")
    }
  }
}

private extension JSONValue {
  var restoreProfileOnly: JSONValue? {
    guard case .object(let object) = self,
      let restoreProfile = object["restoreProfile"]
    else { return nil }
    return .object(["restoreProfile": restoreProfile])
  }

  func value(path: [String]) -> JSONValue? {
    guard let first = path.first else { return self }
    guard case .object(let object) = self, let child = object[first] else { return nil }
    return child.value(path: Array(path.dropFirst()))
  }

  func setting(path: [String], to value: JSONValue) -> JSONValue {
    guard let first = path.first else { return value }
    guard case .object(var object) = self else { return self }
    if path.count == 1 {
      object[first] = value
    } else if let child = object[first] {
      object[first] = child.setting(path: Array(path.dropFirst()), to: value)
    }
    return .object(object)
  }

  func settingInteger(path: [String], to value: Int) -> JSONValue {
    if case .object(var typed)? = self.value(path: path),
      case .string("integer")? = typed["type"]
    {
      typed["decimal"] = .string(String(value))
      return setting(path: path, to: .object(typed))
    }
    return setting(path: path, to: .number(Double(value)))
  }

  func settingIfPresent(path: [String], to value: JSONValue) -> JSONValue {
    guard self.value(path: path) != nil else { return self }
    return setting(path: path, to: value)
  }

  func mapArray(path: [String], transform: (JSONValue) -> JSONValue) -> JSONValue {
    guard let first = path.first, case .object(var object) = self else { return self }
    if path.count == 1, case .array(let values) = object[first] {
      object[first] = .array(values.map(transform))
    } else if let child = object[first] {
      object[first] = child.mapArray(path: Array(path.dropFirst()), transform: transform)
    }
    return .object(object)
  }
}

struct AirPortSetupSheet: View {
  @EnvironmentObject private var model: AirportAppModel

  var body: some View {
    VStack(spacing: 0) {
      content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      Divider()
      controls
        .padding(.horizontal, 20)
        .frame(height: 52)
    }
    .frame(width: 650, height: 430)
    .interactiveDismissDisabled(model.setup.step == .applying)
  }

  @ViewBuilder private var content: some View {
    switch model.setup.step {
    case .examining, .applying:
      progress
    case .recommendation:
      recommendation
    case .choices:
      choices
    case .details:
      details
    case .complete:
      completion
    }
  }

  private var progress: some View {
    VStack(spacing: 18) {
      deviceImage
      ProgressView().controlSize(.small)
      Text(model.setup.progressText).font(.system(size: 15, weight: .semibold))
    }
    .accessibilityIdentifier("setup.progress")
  }

  private var recommendation: some View {
    VStack(spacing: 20) {
      deviceImage
      Text(localizedFormat("Set up this %@ to create a new Wi-Fi network.", model.setupDeviceModelName))
        .font(.system(size: 16, weight: .semibold))
      Text(localizedFormat("This %@ will create a network.", model.setupDeviceModelName))
        .font(.system(size: 13)).foregroundStyle(.secondary)
    }
    .padding(40)
  }

  private var choices: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(localizedFormat("What do you want to do with this %@?", model.setupDeviceModelName))
        .font(.system(size: 16, weight: .semibold))
      Picker("", selection: $model.setup.mode) {
        ForEach(AirPortSetupMode.allCases) { mode in Text(mode.title).tag(mode) }
      }
      .pickerStyle(.radioGroup)
      .accessibilityIdentifier("setup.mode")
      Text(choiceDescription).font(.system(size: 13)).foregroundStyle(.secondary)
    }
    .frame(width: 430, alignment: .leading)
  }

  private var details: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(model.setup.mode.title).font(.system(size: 16, weight: .semibold))
      if model.setup.mode == .replace {
        Picker(localized("Base Station to Replace:"), selection: $model.setup.sourceDeviceID) {
          Text(localized("Choose a base station")).tag("")
          ForEach(model.setupSourceDevices) { Text($0.displayName).tag($0.id) }
        }
        .frame(width: 440)
      } else if model.setup.mode == .extend, !model.setupNetworkSuggestions.isEmpty {
        Picker(localized("Network Name:"), selection: $model.setup.networkName) {
          ForEach(model.setupNetworkSuggestions, id: \.self) { Text($0).tag($0) }
        }
        .frame(width: 440)
      } else {
        setupField(localized("Network Name:"), text: $model.setup.networkName, secure: false)
      }
      setupField(localized("Base Station Name:"), text: $model.setup.deviceName, secure: false)
      setupField(localized("Password:"), text: $model.setup.password, secure: true)
      setupField(localized("Verify Password:"), text: $model.setup.verifyPassword, secure: true)
      Toggle(localized("Use a single password"), isOn: $model.setup.useSinglePassword)
        .toggleStyle(.checkbox).font(.system(size: 13)).padding(.leading, 170)
      if model.showsSetupAirPlayControls {
        Toggle(localized("Enable AirPlay"), isOn: $model.setup.airPlayEnabled)
          .toggleStyle(.checkbox).font(.system(size: 13)).padding(.leading, 170)
        setupField(localized("AirPlay Speaker Name:"), text: $model.setup.airPlaySpeakerName, secure: false)
      }
      Text(model.setup.errorText.isEmpty ? localized("Password must be at least 8 characters.") : model.setup.errorText)
        .font(.system(size: 11))
        .foregroundStyle(model.setup.errorText.isEmpty ? Color.secondary : Color.red)
        .padding(.leading, 178)
    }
    .frame(width: 520, alignment: .leading)
  }

  private var completion: some View {
    VStack(spacing: 18) {
      deviceImage
      Text(localized("Setup Complete")).font(.system(size: 18, weight: .semibold))
      Text(localizedFormat("“%@” is now available.", model.setup.deviceName)).font(.system(size: 13))
    }
  }

  private var controls: some View {
    HStack {
      if model.setup.step == .recommendation {
        Button(localized("Other Options")) { model.showSetupChoices() }
          .accessibilityIdentifier("setup.other.options")
      } else if model.setup.step == .choices || model.setup.step == .details {
        Button(localized("Back")) { model.setupBack() }.accessibilityIdentifier("setup.back")
      }
      Spacer()
      if model.setup.step != .applying && model.setup.step != .complete {
        Button(localized("Cancel")) { model.cancelSetup() }.accessibilityIdentifier("setup.cancel")
      }
      if model.setup.step != .examining && model.setup.step != .applying {
        Button(model.setup.step == .complete ? localized("Done") : localized("Next")) { model.setupNext() }
          .keyboardShortcut(.defaultAction)
          .disabled(model.setup.step == .details && !model.setup.canContinueDetails)
          .accessibilityIdentifier(model.setup.step == .complete ? "setup.done" : "setup.next")
      }
    }
  }

  private var deviceImage: some View {
    airPortResourceImage(
      named: model.selectedTopologyDevice()?.topologyImageName
        ?? "GenericBase-3D-cropped~mac.tiff",
      fallbackSystemName: "wifi.router")
      .resizable().scaledToFit().frame(width: 105, height: 105)
  }

  private var choiceDescription: String {
    switch model.setup.mode {
    case .create: localized("Create a separate Wi-Fi network using this base station.")
    case .extend: localized("Join or extend a Wi-Fi network that is already available.")
    case .replace: localized("Copy compatible settings from another AirPort base station.")
    }
  }

  @ViewBuilder private func setupField(_ label: String, text: Binding<String>, secure: Bool) -> some View {
    HStack(spacing: 8) {
      Text(label).font(.system(size: 13)).frame(width: 165, alignment: .trailing)
      if secure { SecureField("", text: text).textFieldStyle(.roundedBorder) }
      else { TextField("", text: text).textFieldStyle(.roundedBorder) }
    }
    .frame(width: 455)
  }
}

struct RestartBaseStationSheet: View {
  @EnvironmentObject private var model: AirportAppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(localized("Restart Base Station?")).font(.system(size: 15, weight: .semibold))
      Text(
        localized("The device and its network services will be temporarily unavailable. Are you sure you want to continue?")
      )
      .font(.system(size: 13))
      .fixedSize(horizontal: false, vertical: true)
      HStack {
        Spacer()
        Button(localized("Cancel")) { model.isShowingRestartConfirmation = false }
          .accessibilityIdentifier("restart.cancel")
        Button(localized("Continue")) { model.restartBaseStation() }
          .keyboardShortcut(.defaultAction)
          .accessibilityIdentifier("restart.continue")
      }
    }
    .padding(20)
    .frame(width: 430)
  }
}

struct RestoreDefaultSettingsSheet: View {
  @EnvironmentObject private var model: AirportAppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if model.isRestoringDefaults || model.isRestorePending {
        Text(localized("Restoring Base Station…")).font(.system(size: 15, weight: .semibold))
        HStack(spacing: 12) {
          ProgressView().controlSize(.small)
          Text(localized("Waiting for this base station to restore its default settings and restart…"))
            .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("restore.progress")
      } else {
        Text(localized("Restore Default Settings?")).font(.system(size: 15, weight: .semibold))
        Text(localized("Restoring this Base Station to factory defaults erases its settings."))
          .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        HStack {
          Spacer()
          Button(localized("Cancel")) { model.isShowingRestoreConfirmation = false }
            .accessibilityIdentifier("restore.cancel")
          Button(localized("Continue")) { model.restoreDefaultSettings() }
            .keyboardShortcut(.defaultAction).accessibilityIdentifier("restore.continue")
        }
      }
    }
    .padding(20).frame(width: 430)
    .interactiveDismissDisabled(model.isRestoringDefaults || model.isRestorePending)
  }
}
