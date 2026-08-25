import Darwin
import XCTest

@testable import AirPortUtilityCore

final class AirPortCommandTests: XCTestCase {
  func testOrderedRawACPWriteUsesSingleRedactedValuesArgument() {
    let connection = AirportConnection(host: "192.0.2.1", password: "secret")
    let values = #"{"syNm":"capsule","syPW":"password"}"#

    let args = AirportCommand.rawWriteValuesJSON(values, connection: connection, dryRun: false)

    XCTAssertEqual(args.first, "write")
    let valuesIndex = args.firstIndex(of: "--values-json")
    XCTAssertNotNil(valuesIndex)
    XCTAssertEqual(AirportCommand.redact(args)[valuesIndex! + 1], "<password>")
  }
  private var connection: AirportConnection {
    AirportConnection(host: "192.168.4.45", password: "secret", repoPath: "/repo")
  }

  private var runsSlowProcessTests: Bool {
    ProcessInfo.processInfo.environment["AIRPORT_UTILITY_SLOW_TESTS"] == "1"
  }

  private func requireSlowProcessTests() throws {
    guard runsSlowProcessTests else {
      throw XCTSkip("Set AIRPORT_UTILITY_SLOW_TESTS=1 to run subprocess integration tests.")
    }
  }

  func testRedactsPasswordArguments() {
    let nameArgs = [
      "192.168.4.45", "--password", "secret",
      "--wireless-password", "wifi-secret",
      "--setting", "syNm",
      "--value", "time capsule",
    ]

    XCTAssertEqual(
      AirportCommand.redact(nameArgs),
      [
        "192.168.4.45", "--password", "<password>",
        "--wireless-password", "<password>",
        "--setting", "syNm",
        "--value", "time capsule",
      ])

    let passwordArgs = [
      "192.168.4.45", "--password", "secret",
      "--setting", "syPW",
      "--value", "new-secret",
    ]

    XCTAssertEqual(
      AirportCommand.redact(passwordArgs),
      [
        "192.168.4.45", "--password", "<password>",
        "--setting", "syPW",
        "--value", "<password>",
      ])
  }

  func testWirelessClientCommandsSelectProtocolAndRedactCredentials() {
    let modern = AirportCommand.wirelessClients(
      connection: connection,
      usesLegacyACP: false,
      snmpCommunity: "")
    XCTAssertEqual(
      modern,
      [
        "wireless-clients", "192.168.4.45", "--json",
        "--password", "secret",
      ])
    XCTAssertEqual(AirportCommand.redact(modern).last, "<password>")

    let legacy = AirportCommand.wirelessClients(
      connection: connection,
      usesLegacyACP: true,
      snmpCommunity: "private-community")
    XCTAssertEqual(
      legacy,
      [
        "wireless-clients", "192.168.4.45", "--json",
        "--legacy", "--snmp-community", "private-community",
      ])
    XCTAssertEqual(AirportCommand.redact(legacy).last, "<password>")

    let identityDiscovery = AirportCommand.wirelessClients(
      connection: connection,
      usesLegacyACP: false,
      snmpCommunity: "",
      discoverIdentities: true)
    XCTAssertEqual(
      identityDiscovery,
      [
        "wireless-clients", "192.168.4.45", "--json",
        "--discover-identities", "--password", "secret",
      ])
  }

  func testRedactsInlinePasswordArguments() {
    let args = [
      "192.168.4.45",
      "--password=secret",
      "--wireless-password=wifi-secret",
      "--setting",
      "syPW",
      "--value=new-secret",
      "--value-json=\"json-secret\"",
      "--domain-name=example.test",
    ]

    XCTAssertEqual(
      AirportCommand.redact(args),
      [
        "192.168.4.45",
        "--password=<password>",
        "--wireless-password=<password>",
        "--setting",
        "syPW",
        "--value=<password>",
        "--value-json=<password>",
        "--domain-name=example.test",
      ])
  }

  func testRedactsAirPlaySpeakerPasswordArguments() {
    let args = [
      "192.168.4.45",
      "--password",
      "secret",
      "--airplay-speaker-name",
      "Studio Express",
      "--airplay-speaker-password",
      "audio-secret",
    ]

    XCTAssertEqual(
      AirportCommand.redact(args),
      [
        "192.168.4.45",
        "--password",
        "<password>",
        "--airplay-speaker-name",
        "Studio Express",
        "--airplay-speaker-password",
        "<password>",
      ])
  }

  func testRedactsRawPasswordValueWhenSettingIsInline() {
    let args = [
      "192.168.4.45",
      "--password=secret",
      "--setting=syPW",
      "--value=new-secret",
      "--value-json=\"json-secret\"",
    ]

    XCTAssertEqual(
      AirportCommand.redact(args),
      [
        "192.168.4.45",
        "--password=<password>",
        "--setting=syPW",
        "--value=<password>",
        "--value-json=<password>",
      ])
  }

  func testRedactsRawPasswordValueWhenSettingHasWhitespaceOrDifferentCase() {
    let separatedArgs = [
      "192.168.4.45",
      "--password",
      "secret",
      "--setting",
      " sypw ",
      "--value",
      "new-secret",
    ]

    XCTAssertEqual(
      AirportCommand.redact(separatedArgs),
      [
        "192.168.4.45",
        "--password",
        "<password>",
        "--setting",
        " sypw ",
        "--value",
        "<password>",
      ])

    let inlineArgs = [
      "192.168.4.45",
      "--password=secret",
      "--setting= SYPW ",
      "--value-json=\"json-secret\"",
    ]

    XCTAssertEqual(
      AirportCommand.redact(inlineArgs),
      [
        "192.168.4.45",
        "--password=<password>",
        "--setting= SYPW ",
        "--value-json=<password>",
      ])
  }

  func testRedactsPPPDialInPassword() {
    let args = [
      "write", "192.168.4.45",
      "--ppp-dial-in-account", "pppaccount",
      "--ppp-dial-in-password", "ppppassword",
    ]

    XCTAssertEqual(
      AirportCommand.redact(args),
      [
        "write", "192.168.4.45",
        "--ppp-dial-in-account", "pppaccount",
        "--ppp-dial-in-password", "<password>",
      ])
  }

  func testBuildsReadSettingCommand() {
    XCTAssertEqual(
      AirportCommand.readSetting("syNm", connection: connection),
      [
        "read", "192.168.4.45", "--password", "secret", "--setting", "syNm",
      ])
  }

  func testLegacyReadScriptIsAvailableForOlderBaseStations() {
    XCTAssertEqual(AirportCommand.legacyReadScript, "./backend/airport_backend.py")
  }

  func testSRPChallengeFailureUsesLegacyACPCompatibilityPath() {
    let result = CommandResult(
      arguments: ["airport-express.local", "--password", "password", "--setting", "syNm"],
      redactedArguments: [
        "airport-express.local", "--password", "<password>", "--setting", "syNm",
      ],
      stdout: "",
      stderr: "error: SRP challenge failed with ACP status -16\n",
      exitCode: 1)

    XCTAssertTrue(AirportAppModel.shouldRetryWithLegacyACP(AirportCommandError.failed(result)))
  }

  func testBuildsReadSettingsCommand() {
    XCTAssertEqual(
      AirportCommand.readSettings(["syNm", "sySN", "syVs"], connection: connection, json: true),
      [
        "read", "192.168.4.45", "--password", "secret",
        "--setting", "syNm",
        "--setting", "sySN",
        "--setting", "syVs",
        "--json",
      ])
  }

  func testBuildsFirmwareInstallCommand() {
    XCTAssertEqual(
      AirportCommand.installFirmware(
        connection: connection,
        firmwarePath: "/tmp/7.8.1.basebinary",
        dryRun: true),
      [
        "write",
        "192.168.4.45",
        "--password",
        "secret",
        "--upload-firmware",
        "/tmp/7.8.1.basebinary",
        "--dry-run",
      ])

    XCTAssertEqual(
      AirportCommand.installFirmware(
        connection: connection,
        firmwarePath: "/tmp/7.8.1.basebinary",
        dryRun: false),
      [
        "write",
        "192.168.4.45",
        "--password",
        "secret",
        "--upload-firmware",
        "/tmp/7.8.1.basebinary",
        "--i-know-this-updates-firmware",
      ])
  }

  func testBuildCommandsTrimHostWhitespace() {
    let connection = AirportConnection(
      host: " time-capsule.local \n", password: "password", repoPath: "/repo")

    XCTAssertEqual(
      AirportCommand.readSetting("syNm", connection: connection).dropFirst().first,
      "time-capsule.local")
  }

  func testResolverFailureShowsFriendlyMessage() {
    let result = CommandResult(
      arguments: ["time-capsule.local", "--password", "password"],
      redactedArguments: ["time-capsule.local", "--password", "<password>"],
      stdout: "",
      stderr: "error: [Errno 8] nodename nor servname provided, or not known\n",
      exitCode: 1
    )

    XCTAssertEqual(
      AirportCommandError.failed(result).localizedDescription,
      "Could not find time-capsule.local. Check that the Time Capsule is on this network, or enter its IP address instead of the .local name."
    )
  }

  func testPendingDiskInventoryFailureShowsFriendlyMessage() {
    let result = CommandResult(
      arguments: ["time-capsule.local", "--password", "password", "--setting", "MaSt"],
      redactedArguments: ["time-capsule.local", "--password", "<password>", "--setting", "MaSt"],
      stdout: "",
      stderr: "Command failed: Refresh to load disk inventory from MaSt.\n",
      exitCode: 1
    )

    XCTAssertEqual(
      AirportCommandError.failed(result).localizedDescription,
      "Disk information is not available yet."
    )
  }

  func testPendingDiskInventoryFailureWithoutRawSettingNameShowsFriendlyMessage() {
    let result = CommandResult(
      arguments: ["time-capsule.local", "--password", "password", "--setting", "MaSt"],
      redactedArguments: ["time-capsule.local", "--password", "<password>", "--setting", "MaSt"],
      stdout: "",
      stderr: "Command failed: Refresh to load disk inventory.\n",
      exitCode: 1)

    XCTAssertEqual(
      AirportCommandError.failed(result).localizedDescription,
      "Disk information is not available yet."
    )
  }

  func testFriendlyDiskInventoryFailureDoesNotLeakAsCommandOutput() {
    let result = CommandResult(
      arguments: ["time-capsule.local", "--password", "password", "--setting", "MaSt"],
      redactedArguments: ["time-capsule.local", "--password", "<password>", "--setting", "MaSt"],
      stdout: "",
      stderr: "Error: Disk information is not available yet.\n",
      exitCode: 1
    )

    XCTAssertEqual(
      AirportCommandError.failed(result).localizedDescription,
      "Disk information is not available yet."
    )
  }

  func testLaunchFailureShowsBackendPathAndReason() {
    XCTAssertEqual(
      AirportCommandError.launchFailed(
        path: "/repo/backend/airport_backend.py",
        reason: "Permission denied"
      ).localizedDescription,
      "Could not launch backend script at /repo/backend/airport_backend.py: Permission denied"
    )
  }

  func testCommandTimeoutKillsProcessThatIgnoresTerminate() async throws {
    try requireSlowProcessTests()
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("airport-timeout-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let scriptURL = temporaryDirectory.appendingPathComponent("ignore_term.py")
    try """
    #!/usr/bin/env python3
    import signal
    import time

    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    while True:
        time.sleep(0.1)
    """.write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

    let runner = AirportCommandRunner()
    let connection = AirportConnection(
      host: "time-capsule.local",
      password: "secret",
      repoPath: temporaryDirectory.path
    )
    let start = Date()

    do {
      _ = try await runner.run(
        script: "./ignore_term.py",
        arguments: ["time-capsule.local", "--password", "secret"],
        connection: connection,
        timeout: 0.1)
      XCTFail("Expected timeout")
    } catch {
      XCTAssertTrue(error.localizedDescription.contains("timed out"))
    }

    XCTAssertLessThan(Date().timeIntervalSince(start), 3)
  }

  func testCommandCancellationKillsProcessThatIgnoresTerminate() async throws {
    try requireSlowProcessTests()
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("airport-cancel-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let scriptURL = temporaryDirectory.appendingPathComponent("ignore_term.py")
    let pidURL = temporaryDirectory.appendingPathComponent("child.pid")
    try """
    #!/usr/bin/env python3
    import os
    import signal
    import time

    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    with open("child.pid", "w", encoding="utf-8") as file:
        file.write(str(os.getpid()))
        file.flush()
    while True:
        time.sleep(0.1)
    """.write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

    let runner = AirportCommandRunner()
    let connection = AirportConnection(
      host: "time-capsule.local",
      password: "secret",
      repoPath: temporaryDirectory.path
    )
    let task = Task {
      try await runner.run(
        script: "./ignore_term.py",
        arguments: ["time-capsule.local", "--password", "secret"],
        connection: connection,
        timeout: 30)
    }

    for _ in 0..<50 where !FileManager.default.fileExists(atPath: pidURL.path) {
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: pidURL.path))
    let pidText = try String(contentsOf: pidURL, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let pid = try XCTUnwrap(Int32(pidText))

    task.cancel()
    do {
      _ = try await task.value
      XCTFail("Expected cancellation")
    } catch is CancellationError {
    } catch {
      XCTFail("Expected cancellation, got \(error)")
    }

    for _ in 0..<50 {
      if kill(pid, 0) != 0 {
        return
      }
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTFail("Cancelled backend process was still running")
  }

  func testCommandRunnerDoesNotDeadlockOnLargeOutput() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("airport-large-output-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let scriptURL = temporaryDirectory.appendingPathComponent("large_output.py")
    try """
    #!/usr/bin/env python3
    import os

    os.write(1, b"x" * 1048576)
    os.write(2, b"y" * 1048576)
    """.write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

    let runner = AirportCommandRunner()
    let connection = AirportConnection(
      host: "time-capsule.local",
      password: "secret",
      repoPath: temporaryDirectory.path
    )

    let result = try await runner.run(
      script: "./large_output.py",
      arguments: ["time-capsule.local", "--password", "secret"],
      connection: connection,
      timeout: 2)

    XCTAssertEqual(result.stdout.count, 1_048_576)
    XCTAssertEqual(result.stderr.count, 1_048_576)
  }

  func testCommandRunnerDoesNotBlockWhenChildKeepsOutputPipeOpen() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("airport-open-pipe-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let scriptURL = temporaryDirectory.appendingPathComponent("open_pipe.py")
    let pidURL = temporaryDirectory.appendingPathComponent("child.pid")
    defer {
      if let pidText = try? String(contentsOf: pidURL, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines),
        let pid = Int32(pidText)
      {
        kill(pid, SIGKILL)
      }
    }
    try """
    #!/usr/bin/env python3
    import os
    import signal
    import sys
    import time

    pid = os.fork()
    if pid == 0:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        while True:
            time.sleep(0.1)

    with open("child.pid", "w", encoding="utf-8") as file:
        file.write(str(pid))
        file.flush()
    print("parent done")
    sys.exit(0)
    """.write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

    let runner = AirportCommandRunner()
    let connection = AirportConnection(
      host: "time-capsule.local",
      password: "secret",
      repoPath: temporaryDirectory.path
    )
    let start = Date()

    let result = try await runner.run(
      script: "./open_pipe.py",
      arguments: ["time-capsule.local", "--password", "secret"],
      connection: connection,
      timeout: 2)

    let pidText = try String(contentsOf: pidURL, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let pid = try XCTUnwrap(Int32(pidText))

    XCTAssertEqual(kill(pid, 0), 0)
    XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "parent done")
    XCTAssertLessThan(Date().timeIntervalSince(start), 3)
  }

  func testCommandRunnerStreamsOutputChunks() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("airport-stream-output-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let scriptURL = temporaryDirectory.appendingPathComponent("stream_output.py")
    try """
    #!/usr/bin/env python3
    import sys
    import time

    print("firmware-upload progress: one", flush=True)
    time.sleep(0.1)
    print("firmware-upload progress: two", flush=True)
    print("warning line", file=sys.stderr, flush=True)
    """.write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

    let runner = AirportCommandRunner()
    let connection = AirportConnection(
      host: "time-capsule.local",
      password: "secret",
      repoPath: temporaryDirectory.path
    )
    let recorder = CommandOutputChunkRecorder()

    let result = try await runner.run(
      script: "./stream_output.py",
      arguments: ["time-capsule.local", "--password", "secret"],
      connection: connection,
      timeout: 2
    ) { chunk in
      recorder.append(chunk)
    }

    XCTAssertTrue(result.stdout.contains("firmware-upload progress: one"))
    XCTAssertTrue(result.stdout.contains("firmware-upload progress: two"))
    XCTAssertTrue(result.stderr.contains("warning line"))
    let streamedStdout = recorder.text(for: .stdout)
    let streamedStderr = recorder.text(for: .stderr)
    XCTAssertTrue(streamedStdout.contains("firmware-upload progress: one"))
    XCTAssertTrue(streamedStdout.contains("firmware-upload progress: two"))
    XCTAssertTrue(streamedStderr.contains("warning line"))
  }

  func testBuildsDryRunWriteCommand() {
    let args = AirportCommand.friendlyWrite(
      connection: connection,
      flags: [("--connect-using", "dhcp"), ("--wireless-name", "Network Name")],
      dryRun: true
    )

    XCTAssertEqual(
      args,
      [
        "write", "192.168.4.45", "--password", "secret", "--dry-run",
        "--connect-using", "dhcp", "--wireless-name", "Network Name",
      ])
  }

  func testBuildsDryRunWriteCommandFromTypedFlags() {
    let args = AirportCommand.friendlyWrite(
      connection: connection,
      flags: [
        BackendFlag("--connect-using", "dhcp"),
        BackendFlag("--no-hidden-network"),
        BackendFlag("--wireless-name", "Network Name"),
      ],
      dryRun: true
    )

    XCTAssertEqual(
      args,
      [
        "write", "192.168.4.45", "--password", "secret", "--dry-run",
        "--connect-using", "dhcp", "--no-hidden-network", "--wireless-name", "Network Name",
      ])
  }

  func testBuildsEraseAndArchiveCommands() {
    XCTAssertEqual(
      AirportCommand.eraseDisk(
        connection: connection, method: .quick, confirmed: true, dryRun: false),
      [
        "write", "192.168.4.45", "--password", "secret", "--erase-disk",
        "--erase-method", "quick", "--i-know-this-erases-the-disk",
      ])

    XCTAssertEqual(
      AirportCommand.archiveDisk(
        connection: connection, archiveName: "Archive", confirmed: true, dryRun: true),
      [
        "write", "192.168.4.45", "--password", "secret", "--archive-disk",
        "--dry-run", "--archive-name", "Archive", "--i-know-this-starts-the-archive",
      ])
  }

  func testEraseCommandTrimsOptionalVolumeName() {
    XCTAssertEqual(
      AirportCommand.eraseDisk(
        connection: connection,
        method: .zero,
        volumeName: " Live Test Disk ",
        partitionUUID: " 1343746ea33b5473a8adf43b75e5d004 ",
        message: " All users will be disconnected from this disk. ",
        confirmed: true,
        dryRun: true),
      [
        "write", "192.168.4.45", "--password", "secret", "--erase-disk", "--dry-run",
        "--erase-method", "zero", "--volume-name", "Live Test Disk",
        "--partition-uuid", "1343746ea33b5473a8adf43b75e5d004",
        "--erase-message", "All users will be disconnected from this disk.",
        "--i-know-this-erases-the-disk",
      ])
  }

  func testArchiveCommandTrimsOptionalArchiveName() {
    XCTAssertEqual(
      AirportCommand.archiveDisk(
        connection: connection, archiveName: " Archive Name ", confirmed: false, dryRun: false),
      [
        "write", "192.168.4.45", "--password", "secret", "--archive-disk",
        "--archive-name", "Archive Name",
      ])
  }

  func testArchiveCommandOmitsBlankArchiveName() {
    XCTAssertEqual(
      AirportCommand.archiveDisk(
        connection: connection, archiveName: " \n ", confirmed: false, dryRun: false),
      [
        "write", "192.168.4.45", "--password", "secret", "--archive-disk",
      ])
  }

  func testBackendRejectsBlankWirelessNameBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--wireless-name", " \n ",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("Wireless Network Name cannot be empty"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsBlankRawBaseStationNameBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--setting", "syNm",
        "--value", " \n ",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("Base Station Name cannot be empty"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsBlankRawAdminPasswordBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--setting", "syPW",
        "--value", " \n ",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("Admin Password cannot be empty"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsStructuredRawAdminPasswordBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--setting", "syPW",
        "--value-json", "123",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("Admin Password must be a text value"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsStructuredRawBaseStationNameBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--setting", "syNm",
        "--value-json", #"{"name":"time capsule"}"#,
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("Base Station Name must be a text value"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendDryRunJsonEmitsModernProtocolIntentBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run-json", "--setting", "syNm",
        "--value", "time capsule 3",
      ])

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertFalse(result.stderr.contains("could not connect"))

    let document = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any])
    XCTAssertEqual(document["format"] as? String, "airport-normalized-protocol-intent-v1")
    XCTAssertEqual(document["backend"] as? String, "modern")
    XCTAssertEqual(document["changedKeys"] as? [String], ["syNm"])

    let operations = try XCTUnwrap(document["operations"] as? [[String: Any]])
    XCTAssertEqual(operations.count, 2)
    XCTAssertEqual(operations[0]["function"] as? String, "acpd.parseDirtyPlist")
    XCTAssertEqual(operations[0]["writeAffecting"] as? Bool, false)
    XCTAssertEqual(operations[1]["function"] as? String, "acpd.setDirtyPlist")
    XCTAssertEqual(operations[1]["writeAffecting"] as? Bool, true)

    let properties = try XCTUnwrap(operations[1]["properties"] as? [[String: Any]])
    XCTAssertEqual(properties.first?["name"] as? String, "syNm")
    let encoded = try XCTUnwrap(properties.first?["encoded"] as? [String: Any])
    XCTAssertEqual(encoded["text"] as? String, "time capsule 3")
  }

  func testBackendDryRunJsonRedactsPasswordValues() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run-json", "--setting", "syPW",
        "--value", "new-secret",
      ])

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertFalse(result.stdout.contains("new-secret"))

    let document = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any])
    let operations = try XCTUnwrap(document["operations"] as? [[String: Any]])
    let properties = try XCTUnwrap(operations[1]["properties"] as? [[String: Any]])
    let value = try XCTUnwrap(properties.first?["value"] as? [String: Any])
    let encoded = try XCTUnwrap(properties.first?["encoded"] as? [String: Any])
    XCTAssertEqual(value["redacted"] as? Bool, true)
    XCTAssertEqual(encoded["redacted"] as? Bool, true)
  }

  func testBackendRejectsJsonPasswordChangeCombinedWithNetworkSettingsBeforeNetworkAccess()
    throws
  {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--setting", "syPW",
        "--value-json", #""new-secret""#, "--domain-name", "example.test",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(
      result.stderr.contains("do not combine a password change with network setting changes"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsEraseDiskCombinedWithIncompleteSettingsBeforeValidatingSettings()
    throws
  {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--erase-disk",
        "--connect-using", "static",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("do not combine --erase-disk with setting changes"))
    XCTAssertFalse(result.stderr.contains("IPv4 Address cannot be empty"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsArchiveDiskCombinedWithIncompleteSettingsBeforeValidatingSettings()
    throws
  {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--archive-disk",
        "--connect-using", "static",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("do not combine --archive-disk with setting changes"))
    XCTAssertFalse(result.stderr.contains("IPv4 Address cannot be empty"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendAcceptsFirmwareUploadWithoutSettings() throws {
    let firmware = FileManager.default.temporaryDirectory
      .appendingPathComponent("test-\(UUID().uuidString).basebinary")
    try Data(repeating: 0x46, count: 12).write(to: firmware)
    defer { try? FileManager.default.removeItem(at: firmware) }

    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--upload-firmware", firmware.path,
      ])

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(result.stdout.contains("dry-run accepted"))
    XCTAssertFalse(result.stderr.contains("do not combine --upload-firmware with setting changes"))
  }

  func testBackendRejectsFirmwareUploadCombinedWithSettings() throws {
    let firmware = FileManager.default.temporaryDirectory
      .appendingPathComponent("test-\(UUID().uuidString).basebinary")
    try Data(repeating: 0x46, count: 12).write(to: firmware)
    defer { try? FileManager.default.removeItem(at: firmware) }

    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--upload-firmware", firmware.path,
        "--domain-name", "example.test",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("do not combine --upload-firmware with setting changes"))
  }

  func testBackendJsonAdminPasswordUsesVerifyWithoutReadback() throws {
    let script = """
      import sys
      import backend.airport_backend as writer

      def fake_write_dirty_settings(
        host,
        password,
        dirty_plist,
        readback_setting=None,
        verify_setting=None,
        verify_password=None,
        dry_run=False,
      ):
        print(f"readback={readback_setting}")
        print(f"verify={verify_setting}")
        print(f"verify_password={verify_password}")
        print(f"dry_run={dry_run}")
        print(f"value={dirty_plist['syPW']}")
        return {"outputs": {"result": "ok"}}, None

      writer.write_dirty_settings = fake_write_dirty_settings
      sys.argv = [
        "airport_backend.py",
        "192.0.2.1",
        "--password",
        "old-secret",
        "--setting",
        "syPW",
        "--value-json",
        "\\"new-secret\\"",
      ]
      raise SystemExit(writer.main())
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(result.stdout.contains("readback=None"))
    XCTAssertTrue(result.stdout.contains("verify=syNm"))
    XCTAssertTrue(result.stdout.contains("verify_password=new-secret"))
    XCTAssertTrue(result.stdout.contains("dry_run=False"))
    XCTAssertTrue(result.stdout.contains("value=new-secret"))
  }

  func testBackendParseDirtyPlistAllowsMinimalUpdates() throws {
    let script = """
      import backend.airport_backend as writer

      calls = []

      class FakeSock:
        def __enter__(self):
          return self

        def __exit__(self, exc_type, exc, traceback):
          return False

      class FakeTransport:
        pass

      def fake_open_encrypted_transport(host, password):
        return FakeSock(), FakeTransport()

      def fake_rpc_call(transport, function, inputs, flags):
        calls.append((function, inputs, flags))
        return {"outputs": {"result": "ok"}}

      writer.open_encrypted_transport = fake_open_encrypted_transport
      writer.rpc_call = fake_rpc_call
      writer.write_dirty_settings("time-capsule.local", "secret", {"raNm": "Network"}, dry_run=True)

      for function, inputs, flags in calls:
        keys = ",".join(sorted(inputs.get("drTY", {})))
        print(f"{function}:allowMinimal={inputs.get('allowMinimal')} flags={flags} keys={keys}")
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(
      result.stdout.contains("acpd.parseDirtyPlist:allowMinimal=True flags=4 keys=raNm"))
  }

  func testBackendFriendlyWirelessUsesRadioKeysAndDerivedWPAKey() throws {
    let script = """
      import json
      import sys
      import backend.airport_backend as writer

      def json_default(value):
        if isinstance(value, bytes):
          try:
            return {"bytes": value.decode("utf-8")}
          except UnicodeDecodeError:
            return {"hex": value.hex()}
        raise TypeError(f"unsupported type: {type(value)!r}")

      def fake_write_dirty_settings(
        host,
        password,
        dirty_plist,
        readback_setting=None,
        verify_setting=None,
        verify_password=None,
        dry_run=False,
      ):
        print(json.dumps(dirty_plist, default=json_default, sort_keys=True))
        return {"outputs": {"result": "ok"}}, None

      writer.write_dirty_settings = fake_write_dirty_settings
      sys.argv = [
        "airport_backend.py",
        "192.0.2.1",
        "--password",
        "secret",
        "--dry-run",
        "--wireless-mode",
        "create",
        "--wireless-name",
        "test",
        "--wireless-security",
        "wpa2-personal",
        "--wireless-password",
        "airport#543210",
        "--radio-channel",
        "11",
      ]
      raise SystemExit(writer.main())
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(result.stdout.contains("\"raSt\": 0"))
    XCTAssertTrue(result.stdout.contains("\"raNm\": \"test\""))
    XCTAssertTrue(result.stdout.contains("\"raWM\": 7"))
    XCTAssertTrue(result.stdout.contains("\"raCr\": {\"bytes\": \"airport#543210\"}"))
    XCTAssertTrue(
      result.stdout.contains(
        "\"raWE\": {\"hex\": \"bb4cba8053f12fd99681a268ce25a966366e2ca56ad2a52b905da6ca363e5a79\"}")
    )
    XCTAssertTrue(result.stdout.contains("\"raCh\": 11"))
    XCTAssertFalse(result.stdout.contains("bsNM"))
    XCTAssertFalse(result.stdout.contains("bsSM"))
    XCTAssertFalse(result.stdout.contains("bsSK"))
    XCTAssertFalse(result.stdout.contains("bsRC"))
  }

  func testBackendWDSPeerListUsesFixedEightByteSlots() throws {
    let script = """
      import backend.airport_backend as writer
      print(writer.wds_node_list_value([
        "00:21:E9:B9:2E:C3",
        "00:1B:63:21:F5:8F",
      ]).hex())
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertEqual(
      result.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
      "0021e9b92ec30000001b6321f58f0000")
  }

  func testBackendWDSModeWritesClassicWDSRole() throws {
    let script = """
      import json
      import sys
      import backend.airport_backend as writer

      def fake_write_dirty_settings(
        host,
        password,
        dirty_plist,
        readback_setting=None,
        verify_setting=None,
        verify_password=None,
        dry_run=False,
      ):
        print(json.dumps(dirty_plist, sort_keys=True))
        return {"outputs": {"result": "ok"}}, None

      writer.write_dirty_settings = fake_write_dirty_settings
      sys.argv = [
        "airport_backend.py",
        "192.0.2.1",
        "--password",
        "secret",
        "--dry-run",
        "--wireless-mode",
        "wds",
        "--wds-mode",
        "remote",
      ]
      raise SystemExit(writer.main())
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(result.stdout.contains("\"raSt\": 10"))
    XCTAssertTrue(result.stdout.contains("\"bsWM\": 3"))
  }

  func testLegacyBackendAirPlayFlagsUseExpressSettingEncodings() throws {
    let script = """
      import argparse
      import backend.airport_backend as writer

      parser = writer.build_parser()
      args = parser.parse_args([
        "192.0.2.1",
        "--password", "secret",
        "--airplay-enabled",
        "--airplay-speaker-name", "Studio Express",
        "--airplay-over-wan",
      ])
      dirty = writer.build_dirty(args)
      for key in sorted(dirty):
        print(f"{key}={writer.encode_setting_value(key, dirty[key]).hex()}")
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(result.stdout.contains("aWan=01"))
    XCTAssertTrue(result.stdout.contains("auNN=53747564696f2045787072657373"))
    XCTAssertTrue(result.stdout.contains("auRR=0001"))
  }

  func testBackendAllowSetupOverWANFlagWritesRemoteConfigurationBlocks() throws {
    let script = """
      import json
      import sys
      import backend.airport_backend as writer

      def fake_write_dirty_settings(
        host,
        password,
        dirty_plist,
        readback_setting=None,
        verify_setting=None,
        verify_password=None,
        dry_run=False,
      ):
        print(json.dumps({"dry_run": dry_run, "dirty": dirty_plist}, sort_keys=True))
        return {"outputs": {"result": "ok"}}, None

      writer.write_dirty_settings = fake_write_dirty_settings
      for flag in ("--allow-setup-over-wan", "--no-allow-setup-over-wan"):
        sys.argv = [
          "airport_backend.py",
          "192.0.2.1",
          "--password",
          "secret",
          "--dry-run",
          flag,
        ]
        writer.main()
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(result.stdout.contains(#""raWB": true"#))
    XCTAssertTrue(result.stdout.contains(#""raWB": false"#))
    XCTAssertTrue(result.stdout.contains(#""raDS": true"#))
    XCTAssertTrue(result.stdout.contains(#""raDS": false"#))
    XCTAssertTrue(result.stdout.contains(#""raNA": true"#))
    XCTAssertTrue(result.stdout.contains(#""raNA": false"#))
    XCTAssertTrue(result.stdout.contains(#""waNM": false"#))
    XCTAssertTrue(result.stdout.contains(#""waNM": true"#))
  }

  func testBackendFriendlyWirelessWritesPatchProfileBackedRadioSettings() throws {
    let script = """
      import json
      import sys
      import backend.airport_backend as writer

      profile = {
        "restoreProfile": {
          "raWB": True,
          "syRe": 0,
          "WiFi": {
            "radios": [
              {"raNm": "extreme", "raSt": 0, "raCl": False, "dWDS": True},
              {"raNm": "extreme", "raSt": 0, "raCl": False, "dWDS": True},
            ]
          },
        },
        "profiles": [
          {
            "raWB": True,
            "syRe": 0,
            "WiFi": {
              "radios": [
                {"raNm": "extreme", "raSt": 0, "raCl": False, "dWDS": True},
                {"raNm": "extreme", "raSt": 0, "raCl": False, "dWDS": True},
              ]
            },
          }
        ],
      }

      writer.read_cfb0_setting = lambda host, password, setting: profile

      def fake_write_dirty_settings(
        host,
        password,
        dirty_plist,
        readback_setting=None,
        verify_setting=None,
        verify_password=None,
        dry_run=False,
      ):
        print(json.dumps(dirty_plist, sort_keys=True))
        return {"outputs": {"result": "ok"}}, None

      writer.write_dirty_settings = fake_write_dirty_settings
      sys.argv = [
        "airport_backend.py",
        "192.0.2.1",
        "--password",
        "secret",
        "--wireless-mode",
        "off",
        "--wireless-name",
        "extreme-test",
        "--hidden-network",
        "--no-allow-network-extension",
        "--no-allow-setup-over-wan",
        "--region-code",
        "1",
      ]
      writer.main()
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(result.stdout.contains(#""Prof""#))
    XCTAssertTrue(result.stdout.contains(#""raSt": 3"#))
    XCTAssertTrue(result.stdout.contains(#""raNm": "extreme-test""#))
    XCTAssertTrue(result.stdout.contains(#""raCl": true"#))
    XCTAssertTrue(result.stdout.contains(#""dWDS": false"#))
    XCTAssertTrue(result.stdout.contains(#""raWB": false"#))
    XCTAssertTrue(result.stdout.contains(#""syRe": 1"#))
  }

  func testBackendNetworkOptionsPatchProfileBackedExtremeSettings() throws {
    let script = """
      import json
      import sys
      import backend.airport_backend as writer

      profile = {
        "restoreProfile": {
          "dhBg": "10.0.1.2",
          "dhEn": "10.0.1.200",
          "dhLe": 86400,
          "nDMZ": "0.0.0.0",
          "naFl": 1,
        },
        "profiles": [
          {
            "dhBg": "10.0.1.2",
            "dhEn": "10.0.1.200",
            "dhLe": 86400,
            "nDMZ": "0.0.0.0",
            "naFl": 1,
          }
        ],
      }

      writer.read_cfb0_setting = lambda host, password, setting: profile

      def fake_write_dirty_settings(
        host,
        password,
        dirty_plist,
        readback_setting=None,
        verify_setting=None,
        verify_password=None,
        dry_run=False,
      ):
        print(json.dumps(dirty_plist, sort_keys=True))
        return {"outputs": {"result": "ok"}}, None

      writer.write_dirty_settings = fake_write_dirty_settings
      sys.argv = [
        "airport_backend.py",
        "192.0.2.1",
        "--password",
        "secret",
        "--no-nat-pmp",
        "--default-host",
        "10.0.1.253",
      ]
      writer.main()
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(result.stdout.contains(#""Prof""#))
    XCTAssertTrue(result.stdout.contains(#""naFl": 0"#))
    XCTAssertTrue(result.stdout.contains(#""nDMZ": "10.0.1.253""#))
  }

  func testBackendBaseStationNamePatchesProfileBackedExtremeName() throws {
    let script = """
      import json
      import sys
      import backend.airport_backend as writer

      profile = {
        "restoreProfile": {"syNm": "extreme"},
        "profiles": [{"syNm": "extreme"}],
      }

      writer.read_cfb0_setting = lambda host, password, setting: profile

      def fake_write_dirty_settings(
        host,
        password,
        dirty_plist,
        readback_setting=None,
        verify_setting=None,
        verify_password=None,
        dry_run=False,
      ):
        print(json.dumps(dirty_plist, sort_keys=True))
        return {"outputs": {"result": "ok"}}, None

      writer.write_dirty_settings = fake_write_dirty_settings
      sys.argv = [
        "airport_backend.py",
        "192.0.2.1",
        "--password",
        "secret",
        "--setting",
        "syNm",
        "--value-json",
        '"extreme-test"',
      ]
      writer.main()
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(result.stdout.contains(#""Prof""#))
    XCTAssertTrue(result.stdout.contains(#""syNm": "extreme-test""#))
  }

  func testBackendRouterModeWritesLegacyProfileRouterModeWhenBaseStationUsesRaTr() throws {
    let script = """
      import json
      import sys
      import backend.airport_backend as writer

      profile = {
        "restoreProfile": {"raTr": 0},
        "profiles": [{"raTr": 0}],
      }

      writer.read_cfb0_setting = lambda host, password, setting: profile

      def fake_write_dirty_settings(
        host,
        password,
        dirty_plist,
        readback_setting=None,
        verify_setting=None,
        verify_password=None,
        dry_run=False,
      ):
        print(json.dumps(dirty_plist, sort_keys=True))
        return {"outputs": {"result": "ok"}}, None

      writer.write_dirty_settings = fake_write_dirty_settings
      sys.argv = [
        "airport_backend.py",
        "192.0.2.1",
        "--password",
        "secret",
        "--dry-run",
        "--router-mode",
        "bridge",
      ]
      writer.main()
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(result.stdout.contains(#""Prof""#))
    XCTAssertTrue(result.stdout.contains(#""raTr": 4294967295"#))
    XCTAssertFalse(result.stdout.contains(#""bsRM""#))
  }

  func testLegacyBackendRestartUsesStreamingApplyMarkers() throws {
    let script = """
      import sys
      import backend.airport_backend as writer

      def fake_streaming(host, password, dirty, timeout, request_flags=4):
        print(f"streaming host={host} keys={','.join(dirty.keys())}")
        return [{"setting": key, "flags": 0, "status": 0} for key in dirty]

      def fail_fixed(*args, **kwargs):
        raise AssertionError("fixed-body write should not be used for restart apply")

      writer.send_property_write_streaming = fake_streaming
      writer.send_property_write = fail_fixed
      sys.argv = [
        "airport_backend.py",
        "192.0.2.1",
        "--password", "secret",
        "--airplay-speaker-name", "Studio Express",
        "--restart",
        "--json",
      ]
      raise SystemExit(writer.main())
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(result.stdout.contains("streaming host=192.0.2.1 keys=auNN,acFN,acRB"))
    XCTAssertTrue(result.stdout.contains("\"apply\": true"))
    XCTAssertTrue(result.stdout.contains("\"restart\": true"))
    XCTAssertTrue(result.stdout.contains("\"acFN\""))
    XCTAssertTrue(result.stdout.contains("\"acRB\""))
  }

  func testLegacyBackendPropertyParserUsesMergedHelperNames() throws {
    let script = """
      import backend.airport_backend as backend

      body = backend.compose_property_element("syNm", b"Express")
      parsed = backend.parse_property_results(body)
      print(parsed[0][0])
      print(parsed[0][2].decode("utf-8"))
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertEqual(
      result.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
      "syNm\nExpress")
  }

  func testLegacyBackendSetupCompleteWritesCoreFoundationTimestamp() throws {
    let script = """
      import sys
      import backend.airport_backend as writer

      def fake_streaming(host, password, dirty, timeout, request_flags=4):
        for key in sorted(dirty):
          print(f"{key}={writer.encode_setting_value(key, dirty[key]).hex()}")
        return [{"setting": key, "flags": 0, "status": 0} for key in dirty]

      writer.send_property_write_streaming = fake_streaming
      sys.argv = [
        "airport_backend.py",
        "192.0.2.1",
        "--password", "secret",
        "--setup-complete",
        "--setup-complete-timestamp", "804489950",
        "--restart",
      ]
      raise SystemExit(writer.main())
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(result.stdout.contains("ctim=2ff38ade"))
    XCTAssertTrue(result.stdout.contains("acFN="))
    XCTAssertTrue(result.stdout.contains("acRB="))
  }

  func testBackendSetupCompleteWritesCoreFoundationTimestamp() throws {
    let script = """
      import backend.airport_backend as writer

      parser = writer.argparse.ArgumentParser()
      writer.add_network_arguments(parser)
      parser.add_argument("--setup-complete", action="store_true")
      parser.add_argument("--setup-complete-timestamp", type=int)
      args = parser.parse_args([
        "--setup-complete",
        "--setup-complete-timestamp", "804490593",
      ])
      dirty = writer.build_network_dirty_plist(args)
      for key in sorted(dirty):
        print(f"{key}={dirty[key]}")
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(result.stdout.contains("ctim=804490593"))
  }

  func testBackendOpenWirelessClearsStoredPasswordMaterial() throws {
    let script = """
      import json
      import sys
      import backend.airport_backend as writer

      def json_default(value):
        if isinstance(value, bytes):
          return {"bytes": value.decode("utf-8"), "hex": value.hex()}
        raise TypeError(f"unsupported type: {type(value)!r}")

      def fake_write_dirty_settings(
        host,
        password,
        dirty_plist,
        readback_setting=None,
        verify_setting=None,
        verify_password=None,
        dry_run=False,
      ):
        print(json.dumps(dirty_plist, default=json_default, sort_keys=True))
        return {"outputs": {"result": "ok"}}, None

      writer.write_dirty_settings = fake_write_dirty_settings
      sys.argv = [
        "airport_backend.py",
        "192.0.2.1",
        "--password",
        "secret",
        "--dry-run",
        "--wireless-security",
        "none",
      ]
      raise SystemExit(writer.main())
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(result.stdout.contains("\"raWM\": 1"))
    XCTAssertTrue(result.stdout.contains("\"raCr\": {\"bytes\": \"\", \"hex\": \"\"}"))
    XCTAssertTrue(result.stdout.contains("\"raWE\": {\"bytes\": \"\", \"hex\": \"\"}"))
  }

  func testBackendRejectsSecuredWirelessWithoutWirelessPasswordBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--wireless-security",
        "wpa2-personal",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("Wireless Password cannot be empty"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsBlankWirelessPasswordBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--wireless-password", " ",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("Wireless Password cannot be empty"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsInvalidRegionCodeBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--region-code", "300",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("region code must be between 0 and 255"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsInvalidRadioChannelBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--radio-channel", "channel 11",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("radio channel must be 'automatic' or a channel number"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsBlankPPPoEAccountBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--pppoe-account", " ",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("PPPoE Account Name cannot be empty"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsPPPoEModeWithoutAccountBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--connect-using", "pppoe",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("PPPoE Account Name cannot be empty"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsDynamicGlobalHostnameWithoutHostnameBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--dynamic-global-hostname",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("Global Hostname cannot be empty"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsBlankGlobalHostnameBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--global-hostname", " ",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("Global Hostname cannot be empty"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendAcceptsMinimalStaticModeDirtyUpdateBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run-json", "--connect-using", "static",
      ])

    XCTAssertEqual(result.exitCode, 0)
    XCTAssertTrue(result.stdout.contains(#""waCV""#))
    XCTAssertFalse(result.stderr.contains("IPv4 Address cannot be empty"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsBlankStaticFieldsBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--connect-using", "static",
        "--ipv4-address", " ", "--subnet-mask", " ", "--router-address", " ",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("IPv4 Address cannot be empty"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsLeadingZeroIPv4AddressBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--connect-using", "static",
        "--ipv4-address", "192.168.004.45", "--subnet-mask", "255.255.252.0",
        "--router-address", "192.168.4.1",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("IPv4 Address must be an IPv4 address"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsZeroSubnetMaskBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--connect-using", "static",
        "--ipv4-address", "192.168.4.45", "--subnet-mask", "0.0.0.0",
        "--router-address", "192.168.4.1",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(
      result.stderr.contains("Subnet Mask must be between 255.0.0.0 and 255.255.255.254"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsAllOnesSubnetMaskBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--connect-using", "static",
        "--ipv4-address", "192.168.4.45", "--subnet-mask", "255.255.255.255",
        "--router-address", "192.168.4.1",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(
      result.stderr.contains("Subnet Mask must be between 255.0.0.0 and 255.255.255.254"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsLeadingZeroDNSServerBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--dns-server", "001.1.1.1",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("DNS Server must be an IPv4 address"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsDNSClearConflictBeforeStaticRequiredFields() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--connect-using", "static",
        "--dns-server", "1.1.1.1", "--clear-dns",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("use either --dns-server or --clear-dns, not both"))
    XCTAssertFalse(result.stderr.contains("IPv4 Address cannot be empty"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsIPv6DNSClearConflictBeforeStaticRequiredFields() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--connect-using", "static",
        "--ipv6-dns-server", "2001:4860:4860::8888", "--clear-ipv6-dns",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(
      result.stderr.contains("use either --ipv6-dns-server or --clear-ipv6-dns, not both"))
    XCTAssertFalse(result.stderr.contains("IPv4 Address cannot be empty"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsDHCPRouterModeWithoutRangeStartBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--router-mode", "dhcp-and-nat",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("DHCP Range Beginning cannot be empty"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsDHCPRouterModeWithoutRangeEndBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--router-mode", "dhcp-and-nat",
        "--dhcp-range-start", "10.0.1.2",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("DHCP Range Ending cannot be empty"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsDHCPRouterModeWithoutLeaseBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--router-mode", "dhcp-and-nat",
        "--dhcp-range-start", "10.0.1.2", "--dhcp-range-end", "10.0.1.200",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("DHCP Lease cannot be empty"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsDHCPRangeSubnetMismatchBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--router-mode", "dhcp-and-nat",
        "--dhcp-range-start", "10.0.1.2", "--dhcp-range-end", "10.0.2.200",
        "--dhcp-lease", "1", "--dhcp-lease-unit", "hours",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(
      result.stderr.contains(
        "DHCP Range Beginning and Ending must use the same supported private subnet"
      ))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsDHCPRangeEndBeforeStartBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--router-mode", "dhcp-and-nat",
        "--dhcp-range-start", "10.0.1.200", "--dhcp-range-end", "10.0.1.2",
        "--dhcp-lease", "1", "--dhcp-lease-unit", "hours",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(
      result.stderr.contains(
        "DHCP Range Beginning and Ending must use the same supported private subnet"
      ))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsPartialDHCPRangePairMismatchBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run",
        "--dhcp-range-start", "10.0.1.2", "--dhcp-range-end", "10.0.2.200",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(
      result.stderr.contains(
        "DHCP Range Beginning and Ending must use the same supported private subnet"
      ))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsPartialDHCPRangeStartBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run",
        "--dhcp-range-start", "10.0.1.2",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("DHCP Range Ending cannot be empty"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsPartialDHCPRangeEndBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run",
        "--dhcp-range-end", "10.0.1.200",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("DHCP Range Beginning cannot be empty"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsInvalidDHCPRangeBeginningBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run",
        "--dhcp-range-start", "10.0.0.999", "--dhcp-range-end", "10.0.0.200",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("DHCP Range Beginning must be an IPv4 address"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsInvalidDHCPRangeEndingBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run",
        "--dhcp-range-start", "10.0.0.2", "--dhcp-range-end", "10.0.0.999",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("DHCP Range Ending must be an IPv4 address"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsInvalidDefaultHostBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--default-host", "host.local",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("Default Host must be an IPv4 address"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsDefaultHostClearConflictBeforeDHCPRequiredFields() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--router-mode", "dhcp-and-nat",
        "--default-host", "10.0.0.10", "--clear-default-host",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(
      result.stderr.contains("use either --default-host or --clear-default-host, not both"))
    XCTAssertFalse(result.stderr.contains("DHCP Range Beginning cannot be empty"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsInvalidIPv6AddressBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--ipv6-address", "192.168.4.45",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("IPv6 Address must be an IPv6 address"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsInvalidIPv6DNSServerBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--ipv6-dns-server", "192.168.4.1",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("IPv6 DNS Server must be an IPv6 address"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsDiskPasswordModeWithoutDiskPasswordBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--disk-security", "disk-password",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("Disk Password cannot be empty"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsBlankDiskPasswordBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--disk-password", " ",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("Disk Password cannot be empty"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsInvalidWINSServerBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--wins-server", "wins.local",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("WINS Server must be an IPv4 address"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendRejectsLeadingZeroWINSServerBeforeNetworkAccess() throws {
    let result = try runWriteScript(
      arguments: [
        "192.0.2.1", "--password", "secret", "--dry-run", "--wins-server", "192.168.004.1",
      ])

    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertTrue(result.stderr.contains("WINS Server must be an IPv4 address"))
    XCTAssertFalse(result.stderr.contains("could not connect"))
  }

  func testBackendArchivePartitionSelectionUsesBuiltInFlag() throws {
    let script = """
      import backend.airport_backend as writer
      mast = [
        {
          "deviceName": "wd0",
          "builtIn": True,
          "partitions": [{"deviceName": "dk2", "name": "Data", "uuid": bytes.fromhex("11111111111111111111111111111111")}],
        },
        {
          "deviceName": "usb0",
          "builtIn": False,
          "partitions": [{"deviceName": "dk3", "name": "Archive", "uuid": bytes.fromhex("22222222222222222222222222222222")}],
        },
      ]
      source = writer.matching_partitions(mast, None, None, True)
      destination = writer.matching_partitions(mast, None, None, False)
      print(source[0][1]["name"])
      print(destination[0][1]["name"])
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertEqual(result.stdout.split(separator: "\n").map(String.init), ["Data", "Archive"])
  }

  func testBackendEraseSelectionFallsBackToBuiltInDiskWhenNoPartitions() throws {
    let script = """
      import backend.airport_backend as writer
      writer.read_cfb0_setting = lambda host, password, setting: [
        {
          "deviceName": "wd0",
          "builtIn": True,
          "info": "Disk 1",
          "uuid": bytes.fromhex("11111111111111111111111111111111"),
          "partitions": [],
        },
        {
          "deviceName": "sd0",
          "builtIn": False,
          "uuid": bytes.fromhex("22222222222222222222222222222222"),
          "partitions": [],
        },
      ]
      options, selected = writer.build_erase_disk_options(
        "host", "secret", "quick", None, None, None)
      print(options["volumeName"])
      print(options["uuid"].hex())
      print(selected)
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    let lines = result.stdout.split(separator: "\n").map(String.init)
    XCTAssertEqual(lines[0], "Data")
    XCTAssertEqual(lines[1], "11111111111111111111111111111111")
    XCTAssertTrue(lines[2].contains("wd0"))
  }

  func testBackendEraseSelectionUsesProvidedVolumeNameWhenNoPartitions() throws {
    let script = """
      import backend.airport_backend as writer
      writer.read_cfb0_setting = lambda host, password, setting: [
        {
          "deviceName": "wd0",
          "builtIn": True,
          "uuid": bytes.fromhex("11111111111111111111111111111111"),
          "partitions": [],
        },
      ]
      options, _ = writer.build_erase_disk_options(
        "host", "secret", "quick", "Backups", None, None)
      print(options["volumeName"])
      print(options["uuid"].hex())
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertEqual(
      result.stdout.split(separator: "\n").map(String.init),
      [
        "Backups", "11111111111111111111111111111111",
      ])
  }

  func testBackendDiskSelectionErrorsDoNotExposeMaStName() throws {
    let script = """
      import backend.airport_backend as writer
      mast = [{
        "deviceName": "wd0",
        "builtIn": True,
        "partitions": [{
          "deviceName": "dk2",
          "name": "Data",
          "uuid": bytes.fromhex("11111111111111111111111111111111"),
        }],
      }]
      checks = [
        lambda: writer.iter_mast_partitions({"not": "a disk list"}),
        lambda: writer.select_mast_partition([], None, None),
        lambda: writer.select_mast_partition(mast, bytes.fromhex("22222222222222222222222222222222"), None),
        lambda: writer.select_mast_partition(mast, None, "Missing"),
        lambda: writer.select_archive_partition(mast, "destination", None, None, False),
        lambda: writer.partition_uuid({"name": "Data"}),
        lambda: writer.partition_volume_name({"uuid": bytes.fromhex("11111111111111111111111111111111")}),
      ]
      for check in checks:
        try:
          check()
        except ValueError as error:
          print(error)
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertFalse(result.stdout.contains("MaSt"))
    XCTAssertTrue(result.stdout.contains("disk inventory did not decode to a disk list"))
    XCTAssertTrue(result.stdout.contains("disk inventory did not contain any disk partitions"))
    XCTAssertTrue(result.stdout.contains("was not found in disk inventory"))
    XCTAssertTrue(
      result.stdout.contains("no external archive destination partition found in disk inventory"))
    XCTAssertTrue(
      result.stdout.contains("selected disk inventory partition does not have a 16-byte uuid"))
    XCTAssertTrue(
      result.stdout.contains("selected disk inventory partition does not have a volume name"))
  }

  func testBackendArchiveCapacityCheckDerivesUsedBytes() throws {
    let script = """
      import backend.airport_backend as writer
      writer.read_cfb0_setting = lambda host, password, setting: [
        {
          "deviceName": "wd0",
          "builtIn": True,
          "partitions": [{
            "deviceName": "dk2",
            "name": "Data",
            "uuid": bytes.fromhex("11111111111111111111111111111111"),
            "size": 1000,
            "sizeFree": 100,
          }],
        },
        {
          "deviceName": "usb0",
          "builtIn": False,
          "partitions": [{
            "deviceName": "dk3",
            "name": "Archive",
            "uuid": bytes.fromhex("22222222222222222222222222222222"),
            "sizeFree": 800,
          }],
        },
      ]
      try:
        writer.build_archive_disk_options("host", "secret", None, None, None, None, None, None)
      except ValueError as error:
        print(error)
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(result.stdout.contains("archive destination has insufficient free space"))
    XCTAssertTrue(result.stdout.contains("needs 900"))
    XCTAssertTrue(result.stdout.contains("has 800"))
  }

  func testBackendAirPlayFlagsMapToDirtyPlistKeys() throws {
    let script = """
      import argparse
      import json
      import backend.airport_backend as writer

      parser = argparse.ArgumentParser()
      writer.add_network_arguments(parser)
      args = parser.parse_args([
        "--airplay-enabled",
        "--airplay-speaker-name", "Studio Express",
        "--airplay-speaker-password", "audio-secret",
        "--airplay-over-wan",
      ])
      print(json.dumps(writer.build_network_dirty_plist(args), sort_keys=True))
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(result.stdout.contains(#""auRR": true"#))
    XCTAssertTrue(result.stdout.contains(#""auNN": "Studio Express""#))
    XCTAssertTrue(result.stdout.contains(#""auNP": "audio-secret""#))
    XCTAssertTrue(result.stdout.contains(#""aWan": true"#))
  }

  func testBackendFirmwareUploadDryRunAcceptsManifestURL() throws {
    let script = """
      import backend.airport_backend as writer
      writer.upload_firmware(
        "host",
        "secret",
        "https://apsu.apple.com/data/115/78100.3/7.8.1.basebinary",
        dry_run=True,
      )
      print(writer.firmware_source_summary("https://apsu.apple.com/data/115/78100.3/7.8.1.basebinary"))
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(result.stdout.contains("firmware URL https://apsu.apple.com"))
  }

  func testBackendACPStreamHeaderUsesStreamingBodySize() throws {
    let script = """
      import struct
      import backend.airport_backend as reader
      header = reader.make_header(b"", flags=0, command=0x15, body_size=reader.ACP_STREAM_SIZE)
      print(struct.unpack(">I", header[16:20])[0])
      print(struct.unpack(">I", header[28:32])[0])
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertEqual(
      result.stdout.split(separator: "\n").map(String.init),
      ["4294967295", "21"])
  }

  func testBackendFirmwarePropertyStreamWritesRecords() throws {
    let script = """
      import types
      import backend.airport_backend as reader
      import backend.airport_backend as writer

      class FakeTransport:
        def __init__(self):
          self.stream_headers = []
          self.sent = []
          self.reads = [
            reader.ACP_PROPERTY_HEADER.pack(b"\\x00\\x00\\x00\\x00", 0, 4),
            b"\\x00\\x00\\x00\\x00",
          ]

        def send_stream_header(self, flags, command):
          self.stream_headers.append((flags, command))

        def recv(self):
          return types.SimpleNamespace(status=0), b""

        def send_encrypted_stream(self, data):
          self.sent.append(data)

        def recv_decrypted(self, count):
          data = self.reads.pop(0)
          assert len(data) == count
          return data

      transport = FakeTransport()
      writer.send_property_stream(transport, "fuup", b"abc")
      name, flags, size = reader.ACP_PROPERTY_HEADER.unpack(transport.sent[0])
      term_name, term_flags, term_size = reader.ACP_PROPERTY_HEADER.unpack(transport.sent[2][:12])
      print(transport.stream_headers)
      print(name.decode("ascii"), flags, size)
      print(transport.sent[1])
      print(term_name.hex(), term_flags, term_size, transport.sent[2][12:].hex())
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(result.stdout.contains("[(4, 21)]"))
    XCTAssertTrue(result.stdout.contains("fuup 0 3"))
    XCTAssertTrue(result.stdout.contains("b'abc'"))
    XCTAssertTrue(result.stdout.contains("00000000 0 4 00000000"))
  }

  func testBackendFirmwarePropertyStreamConsumesStatusUntilTerminator() throws {
    let script = """
      import types
      import backend.airport_backend as reader
      import backend.airport_backend as writer

      class FakeTransport:
        def __init__(self):
          self.reads = [
            reader.ACP_PROPERTY_HEADER.pack(b"fuup", 0, 4),
            b"\\x00\\x00\\x00\\x00",
            reader.ACP_PROPERTY_HEADER.pack(b"\\x00\\x00\\x00\\x00", 0, 4),
            b"\\x00\\x00\\x00\\x00",
          ]

        def send_stream_header(self, flags, command):
          pass

        def recv(self):
          return types.SimpleNamespace(status=0), b""

        def send_encrypted_stream(self, data):
          pass

        def recv_decrypted(self, count):
          data = self.reads.pop(0)
          assert len(data) == count
          return data

      transport = FakeTransport()
      writer.send_property_stream(transport, "fuup", b"abc")
      print(len(transport.reads))
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "0")
  }

  func testBackendFirmwarePropertyStreamReportsUploadProgress() throws {
    let script = """
      import types
      import backend.airport_backend as reader
      import backend.airport_backend as writer

      class FakeTransport:
        def __init__(self):
          self.reads = [
            reader.ACP_PROPERTY_HEADER.pack(b"\\x00\\x00\\x00\\x00", 0, 4),
            b"\\x00\\x00\\x00\\x00",
          ]

        def send_stream_header(self, flags, command):
          pass

        def recv(self):
          return types.SimpleNamespace(status=0), b""

        def send_encrypted_stream(self, data, progress_callback=None):
          if progress_callback is not None:
            progress_callback(len(data) // 2, len(data))
            progress_callback(len(data), len(data))

        def recv_decrypted(self, count):
          data = self.reads.pop(0)
          assert len(data) == count
          return data

      events = []
      writer.send_property_stream(
        FakeTransport(),
        "fuup",
        b"abcdef",
        progress_callback=lambda current, total: events.append((current, total)))
      print(events)
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(result.stdout.contains("[(3, 6), (6, 6)]"))
  }

  func testBackendFirmwareProgressEmitterPrintsJSONLine() throws {
    let script = """
      import backend.airport_backend as writer

      writer.emit_firmware_upload_progress("upload", 10, 20)
      writer.emit_firmware_upload_progress("program", 96, 96, "96/96")
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(
      result.stdout.contains(
        "firmware-upload progress: {\"complete\": false, \"current\": 10"))
    XCTAssertTrue(result.stdout.contains("\"phase\": \"upload\""))
    XCTAssertTrue(result.stdout.contains("\"phase\": \"program\""))
    XCTAssertTrue(result.stdout.contains("\"raw\": \"96/96\""))
  }

  func testBackendFirmwarePropertyUploadCapabilityUsesFeatureList() throws {
    let script = """
      import backend.airport_backend as writer

      values = iter([
        b"SAcCafupip6N",
        b"SAcCip6N",
      ])

      def fake_read_property(transport, setting):
        assert setting == "feat"
        return next(values)

      writer.firmware_session.read_property = fake_read_property
      print(writer.supports_firmware_property_upload(object()))
      print(writer.supports_firmware_property_upload(object()))
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertEqual(
      result.stdout.split(whereSeparator: \.isNewline).map(String.init),
      ["True", "False"])
  }

  func testBackendFirmwareUploadSendsRebootAfterCompletedProgress() throws {
    let script = """
      import backend.airport_backend as writer

      calls = []
      writer.prepare_firmware_upload_session = lambda transport: {"prepared": True}
      def fake_send_property_stream(transport, setting, value, request_flags=writer.FIRMWARE_REQUEST_FLAGS):
        calls.append((setting, len(value), request_flags))
      writer.send_property_stream = fake_send_property_stream
      writer.wait_for_firmware_progress = lambda transport: {
        "available": True,
        "complete": True,
        "current": 96,
        "total": 96,
        "raw": "96/96",
      }
      result = writer.upload_firmware_with_properties(object(), b"APPLE-FIRMWARE image")
      print(calls)
      print(result)
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(
      result.stdout.contains(
        "[('fuup', 20, 4), ('fust', 0, 4), ('acRB', 0, 0)]"))
    XCTAssertTrue(result.stdout.contains("'rebootCommand': {'sent': True, 'property': 'acRB'}"))
  }

  func testBackendFirmwarePropertyStreamSendsLargePayloadAsOneRecord() throws {
    let script = """
      import types
      import backend.airport_backend as reader
      import backend.airport_backend as writer

      class FakeTransport:
        def __init__(self):
          self.sent = []
          self.reads = [
            reader.ACP_PROPERTY_HEADER.pack(b"\\x00\\x00\\x00\\x00", 0, 4),
            b"\\x00\\x00\\x00\\x00",
          ]

        def send_stream_header(self, flags, command):
          pass

        def recv(self):
          return types.SimpleNamespace(status=0), b""

        def send_encrypted_stream(self, data):
          self.sent.append(data)

        def recv_decrypted(self, count):
          data = self.reads.pop(0)
          assert len(data) == count
          return data

      transport = FakeTransport()
      writer.send_property_stream(transport, "fuup", b"F" * (writer.ACP_MAX_BODY_SIZE + 1))
      records = []
      for item in transport.sent:
        if len(item) == reader.ACP_PROPERTY_HEADER.size:
          name, flags, size = reader.ACP_PROPERTY_HEADER.unpack(item)
          records.append((name.decode("ascii", errors="ignore"), size))
      print(records)
      print([len(item) for item in transport.sent])
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(result.stdout.contains("('fuup', 1572865)"))
    XCTAssertTrue(result.stdout.contains("[12, 1572865, 16]"))
  }

  func testBackendFirmwareLegacyUploadUsesCommandThree() throws {
    let script = """
      import backend.airport_backend as writer

      class FakeTransport:
        def __init__(self):
          self.sent = []

        def send(self, body, flags, command):
          self.sent.append((body, flags, command))

      transport = FakeTransport()
      result = writer.upload_firmware_legacy(transport, b"PKfirmware")
      print(result)
      print(transport.sent)
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(result.stdout.contains("'method': 'legacy-command'"))
    XCTAssertTrue(result.stdout.contains("b'PKfirmware', 0, 3"))
  }

  func testBackendFirmwareImageParserValidatesAppleEnvelope() throws {
    let script = """
      import backend.airport_backend as writer

      header = bytearray(0x20)
      header[:len(writer.FIRMWARE_MAGIC)] = writer.FIRMWARE_MAGIC
      header[len(writer.FIRMWARE_MAGIC)] = 0
      header[0x10:0x14] = (106).to_bytes(4, "big")
      header[0x14:0x18] = (0x07818000).to_bytes(4, "big")
      body = bytes(header) + b"payload"
      firmware = body + writer.acp_adler32(body).to_bytes(4, "big")
      info = writer.parse_firmware_image_info(firmware)
      print(info["productID"])
      print(info["sourceVersionRaw"])
      print(info["size"])
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertEqual(
      result.stdout.split(whereSeparator: \.isNewline).map(String.init),
      ["106", "125927424", "43"])
  }

  func testBackendFirmwareImageParserRejectsBadChecksum() throws {
    let script = """
      import backend.airport_backend as writer

      header = bytearray(0x20)
      header[:len(writer.FIRMWARE_MAGIC)] = writer.FIRMWARE_MAGIC
      header[len(writer.FIRMWARE_MAGIC)] = 0
      header[0x10:0x14] = (106).to_bytes(4, "big")
      body = bytes(header) + b"payload"
      firmware = body + b"\\x00\\x00\\x00\\x00"
      try:
        writer.parse_firmware_image_info(firmware)
      except ValueError as error:
        print(error)
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(result.stdout.contains("firmware checksum mismatch"))
  }

  func testBackendFirmwareProgressPollsUntilComplete() throws {
    let script = """
      import backend.airport_backend as writer

      values = iter([b"10/100", b"100/100"])
      calls = []
      def fake_read_property(transport, setting, flags=0):
        calls.append((setting, flags))
        return next(values)
      writer.read_property = fake_read_property
      result = writer.wait_for_firmware_progress(object(), timeout_seconds=2, poll_seconds=0)
      print(result)
      print(calls)
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(result.stdout.contains("'current': 100"))
    XCTAssertTrue(result.stdout.contains("'total': 100"))
    XCTAssertTrue(result.stdout.contains("'complete': True"))
    XCTAssertTrue(result.stdout.contains("('fugp', 4)"))
  }

  func testBackendFirmwareDerivesScopedLinkLocalUploadCandidate() throws {
    let script = """
      import backend.airport_backend as writer

      writer.route_interface_for_host = lambda host: "en0"
      print(writer.firmware_link_local_address_from_mac("00:1f:f3:c9:62:99"))
      print(writer.firmware_upload_host_candidates(
        "192.168.4.45",
        {"wanMACAddress": "00:1f:f3:c9:62:99"},
      ))
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(result.stdout.contains("fe80::21f:f3ff:fec9:6299"))
    XCTAssertTrue(
      result.stdout.contains("['fe80::21f:f3ff:fec9:6299%en0', '192.168.4.45']"))
  }

  func testBackendFirmwareCandidateRouteLookupHasACPPort() throws {
    let script = """
      import socket
      import backend.airport_backend as writer

      calls = []
      def fake_getaddrinfo(host, port, family, kind):
        calls.append((host, port, family, kind))
        return [
          (socket.AF_INET6, socket.SOCK_STREAM, 0, "", ("fe80::1", port, 0, 7))
        ]

      socket.getaddrinfo = fake_getaddrinfo
      socket.if_indextoname = lambda scope_id: f"en{scope_id}"
      print(writer.ACP_PORT)
      print(writer.resolved_ipv6_link_local_hosts("time-capsule.local"))
      print(calls)
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(result.stdout.contains("5009"))
    XCTAssertTrue(result.stdout.contains("['fe80::1%en7']"))
    XCTAssertTrue(result.stdout.contains("('time-capsule.local', 5009"))
  }

  func testBackendFirmwarePreparationUsesUtilityProbeSequence() throws {
    let script = """
      import backend.airport_backend as writer

      calls = []
      def fake_read_property(transport, setting, flags=0):
        calls.append(("read", setting, flags))
        return b"CFB0\\xd0\\x00END!"

      def fake_rpc_call(transport, function, inputs, flags):
        calls.append(("rpc", function, inputs, flags))
        return {"outputs": {"data": {"name": "bridge0"}}}

      writer.read_property = fake_read_property
      writer.rpc_call = fake_rpc_call
      result = writer.prepare_firmware_upload_session(object())
      print(calls)
      print(result)
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(
      result.stdout.contains(
        "[('read', 'raSL', 4), ('rpc', 'acpd.system.interfaces', {}, 4), ('read', 'sySt', 4)]"
      ))
    XCTAssertTrue(result.stdout.contains("'acpd.system.interfaces': {'available': True"))
  }

  func testBackendFirmwarePreflightRejectsProductMismatch() throws {
    let script = """
      import backend.airport_backend as writer

      class FakeSocket:
        def __enter__(self):
          return self

        def __exit__(self, exc_type, exc, traceback):
          return False

      writer.open_encrypted_transport = lambda host, password: (FakeSocket(), object())
      writer.firmware_session.read_properties = lambda transport, settings: ({"syAP": (115).to_bytes(4, "big")}, {})
      try:
        writer.preflight_firmware_upload("host", "secret", {"productID": 106})
      except ValueError as error:
        print(error)
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(result.stdout.contains("image 106, device 115"))
  }

  func testBackendFirmwareUploadUsesLinkLocalCandidateForPropertyStream() throws {
    let script = """
      import os
      import tempfile
      import backend.airport_backend as writer

      class FakeSocket:
        def __enter__(self):
          return self

        def __exit__(self, exc_type, exc, traceback):
          return False

        def settimeout(self, timeout):
          print(f"timeout {timeout}")

      class FakeTransport:
        pass

      def fake_open(host, password):
        print(f"open {host} {password}")
        return FakeSocket(), FakeTransport()

      def fake_property_upload(transport, data):
        print(f"property-upload {data[:14]!r} {len(data)}")
        return {"method": "property-stream", "size": len(data)}

      def make_firmware(payload):
        header = bytearray(0x20)
        header[:len(writer.FIRMWARE_MAGIC)] = writer.FIRMWARE_MAGIC
        header[len(writer.FIRMWARE_MAGIC)] = 0
        header[0x10:0x14] = (106).to_bytes(4, "big")
        body = bytes(header) + payload
        return body + writer.acp_adler32(body).to_bytes(4, "big")

      handle = tempfile.NamedTemporaryFile(delete=False)
      try:
        handle.write(make_firmware(b"PKfirmware-linklocal"))
        handle.close()
        writer.open_encrypted_transport = fake_open
        writer.preflight_firmware_upload = lambda host, password, info: {
          "deviceProductID": info["productID"],
          "supportsPropertyUpload": True,
        }
        writer.firmware_upload_host_candidates = lambda host, preflight: [
          "fe80::21f:f3ff:fec9:6299%en0",
          host,
        ]
        writer.upload_firmware_with_properties = fake_property_upload
        print(writer.upload_firmware("192.168.4.45", "secret", handle.name, dry_run=False))
      finally:
        os.unlink(handle.name)
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(result.stdout.contains("open fe80::21f:f3ff:fec9:6299%en0 secret"))
    XCTAssertFalse(result.stdout.contains("open 192.168.4.45 secret"))
    XCTAssertTrue(result.stdout.contains("'uploadHost': 'fe80::21f:f3ff:fec9:6299%en0'"))
  }

  func testBackendFirmwareUploadFallsBackWhenLinkLocalOpenFails() throws {
    let script = """
      import os
      import tempfile
      import backend.airport_backend as writer

      class FakeSocket:
        def __enter__(self):
          return self

        def __exit__(self, exc_type, exc, traceback):
          return False

        def settimeout(self, timeout):
          print(f"timeout {timeout}")

      class FakeTransport:
        pass

      def fake_open(host, password):
        print(f"open {host} {password}")
        if host.startswith("fe80::"):
          raise OSError("no route")
        return FakeSocket(), FakeTransport()

      def fake_property_upload(transport, data):
        print(f"property-upload {len(data)}")
        return {"method": "property-stream", "size": len(data)}

      def make_firmware(payload):
        header = bytearray(0x20)
        header[:len(writer.FIRMWARE_MAGIC)] = writer.FIRMWARE_MAGIC
        header[len(writer.FIRMWARE_MAGIC)] = 0
        header[0x10:0x14] = (106).to_bytes(4, "big")
        body = bytes(header) + payload
        return body + writer.acp_adler32(body).to_bytes(4, "big")

      handle = tempfile.NamedTemporaryFile(delete=False)
      try:
        handle.write(make_firmware(b"PKfirmware-fallback"))
        handle.close()
        writer.open_encrypted_transport = fake_open
        writer.preflight_firmware_upload = lambda host, password, info: {
          "deviceProductID": info["productID"],
          "supportsPropertyUpload": True,
        }
        writer.firmware_upload_host_candidates = lambda host, preflight: [
          "fe80::21f:f3ff:fec9:6299%en0",
          host,
        ]
        writer.upload_firmware_with_properties = fake_property_upload
        print(writer.upload_firmware("192.168.4.45", "secret", handle.name, dry_run=False))
      finally:
        os.unlink(handle.name)
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(result.stdout.contains("open fe80::21f:f3ff:fec9:6299%en0 secret"))
    XCTAssertTrue(result.stdout.contains("open 192.168.4.45 secret"))
    XCTAssertTrue(result.stdout.contains("'uploadHost': '192.168.4.45'"))
  }

  func testBackendFirmwareUploadChoosesPropertyStreamWhenAdvertised() throws {
    let script = """
      import os
      import tempfile
      import backend.airport_backend as writer

      class FakeSocket:
        def __enter__(self):
          return self

        def __exit__(self, exc_type, exc, traceback):
          return False

        def settimeout(self, timeout):
          print(f"timeout {timeout}")

      class FakeTransport:
        pass

      def fake_open(host, password):
        print(f"open {host} {password}")
        return FakeSocket(), FakeTransport()

      def fake_property_upload(transport, data):
        print(f"property-upload {data[:14]!r} {len(data)}")
        return {"method": "property-stream", "size": len(data)}

      def make_firmware(payload):
        header = bytearray(0x20)
        header[:len(writer.FIRMWARE_MAGIC)] = writer.FIRMWARE_MAGIC
        header[len(writer.FIRMWARE_MAGIC)] = 0
        header[0x10:0x14] = (106).to_bytes(4, "big")
        body = bytes(header) + payload
        return body + writer.acp_adler32(body).to_bytes(4, "big")

      handle = tempfile.NamedTemporaryFile(delete=False)
      try:
        handle.write(make_firmware(b"PKfirmware-781"))
        handle.close()
        writer.open_encrypted_transport = fake_open
        writer.preflight_firmware_upload = lambda host, password, info: {
          "deviceProductID": info["productID"],
          "supportsPropertyUpload": True,
        }
        writer.upload_firmware_with_properties = fake_property_upload
        print(writer.upload_firmware("host", "secret", handle.name, dry_run=False))
      finally:
        os.unlink(handle.name)
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(result.stdout.contains("open host secret"))
    XCTAssertTrue(result.stdout.contains("timeout 60"))
    XCTAssertTrue(result.stdout.contains("property-upload b'APPLE-FIRMWARE'"))
    XCTAssertTrue(result.stdout.contains("'method': 'property-stream'"))
    XCTAssertFalse(result.stdout.contains("'method': 'legacy-command'"))
  }

  func testBackendFirmwareUploadFallsBackToLegacyCommandWhenPropertyPathUnavailable() throws {
    let script = """
      import os
      import tempfile
      import backend.airport_backend as writer

      class FakeSocket:
        def __enter__(self):
          return self

        def __exit__(self, exc_type, exc, traceback):
          return False

        def settimeout(self, timeout):
          print(f"timeout {timeout}")

      class FakeTransport:
        pass

      def fake_open(host, password):
        print(f"open {host} {password}")
        return FakeSocket(), FakeTransport()

      def fake_legacy_upload(transport, data):
        print(f"legacy-upload {data[:14]!r} {len(data)}")
        return {"method": "legacy-command", "size": len(data)}

      def make_firmware(payload):
        header = bytearray(0x20)
        header[:len(writer.FIRMWARE_MAGIC)] = writer.FIRMWARE_MAGIC
        header[len(writer.FIRMWARE_MAGIC)] = 0
        header[0x10:0x14] = (106).to_bytes(4, "big")
        body = bytes(header) + payload
        return body + writer.acp_adler32(body).to_bytes(4, "big")

      handle = tempfile.NamedTemporaryFile(delete=False)
      try:
        handle.write(make_firmware(b"PKfirmware-769"))
        handle.close()
        writer.open_encrypted_transport = fake_open
        writer.preflight_firmware_upload = lambda host, password, info: {
          "deviceProductID": info["productID"],
          "supportsPropertyUpload": False,
        }
        writer.upload_firmware_legacy = fake_legacy_upload
        print(writer.upload_firmware("host", "secret", handle.name, dry_run=False))
      finally:
        os.unlink(handle.name)
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(result.stdout.contains("open host secret"))
    XCTAssertTrue(result.stdout.contains("timeout 60"))
    XCTAssertTrue(result.stdout.contains("legacy-upload b'APPLE-FIRMWARE'"))
    XCTAssertTrue(result.stdout.contains("'method': 'legacy-command'"))
    XCTAssertFalse(result.stdout.contains("'method': 'property-stream'"))
  }

  func testBackendFirmwareUploadAllowsLargePropertyStreamFirmware() throws {
    let script = """
      import os
      import tempfile
      import backend.airport_backend as writer

      class FakeSocket:
        def __enter__(self):
          return self

        def __exit__(self, exc_type, exc, traceback):
          return False

        def settimeout(self, timeout):
          print(f"timeout {timeout}")

      class FakeTransport:
        pass

      def fake_open(host, password):
        return FakeSocket(), FakeTransport()

      def fake_property_upload(transport, data):
        print(f"property-size {len(data)}")
        return {"method": "property-stream", "size": len(data)}

      def make_firmware(payload):
        header = bytearray(0x20)
        header[:len(writer.FIRMWARE_MAGIC)] = writer.FIRMWARE_MAGIC
        header[len(writer.FIRMWARE_MAGIC)] = 0
        header[0x10:0x14] = (106).to_bytes(4, "big")
        body = bytes(header) + payload
        return body + writer.acp_adler32(body).to_bytes(4, "big")

      handle = tempfile.NamedTemporaryFile(delete=False)
      try:
        handle.write(make_firmware(b"F" * (writer.ACP_MAX_BODY_SIZE + 1)))
        handle.close()
        writer.open_encrypted_transport = fake_open
        writer.preflight_firmware_upload = lambda host, password, info: {
          "deviceProductID": info["productID"],
          "supportsPropertyUpload": True,
        }
        writer.upload_firmware_with_properties = fake_property_upload
        print(writer.upload_firmware("host", "secret", handle.name, dry_run=False))
      finally:
        os.unlink(handle.name)
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(result.stdout.contains("timeout 60"))
    XCTAssertTrue(result.stdout.contains("property-size 1572901"))
    XCTAssertTrue(result.stdout.contains("'method': 'property-stream'"))
  }

  func testBackendFirmwareUploadAllowsLargeLegacyFirmwareCommand() throws {
    let script = """
      import os
      import tempfile
      import backend.airport_backend as writer

      class FakeSocket:
        def __enter__(self):
          return self

        def __exit__(self, exc_type, exc, traceback):
          return False

        def settimeout(self, timeout):
          pass

      class FakeTransport:
        pass

      def fake_open(host, password):
        return FakeSocket(), FakeTransport()

      def fake_legacy_upload(transport, data):
        print(f"legacy-size {len(data)}")
        return {"method": "legacy-command", "size": len(data)}

      def make_firmware(payload):
        header = bytearray(0x20)
        header[:len(writer.FIRMWARE_MAGIC)] = writer.FIRMWARE_MAGIC
        header[len(writer.FIRMWARE_MAGIC)] = 0
        header[0x10:0x14] = (106).to_bytes(4, "big")
        body = bytes(header) + payload
        return body + writer.acp_adler32(body).to_bytes(4, "big")

      handle = tempfile.NamedTemporaryFile(delete=False)
      try:
        handle.write(make_firmware(b"F" * (writer.ACP_MAX_BODY_SIZE + 1)))
        handle.close()
        writer.open_encrypted_transport = fake_open
        writer.preflight_firmware_upload = lambda host, password, info: {
          "deviceProductID": info["productID"],
          "supportsPropertyUpload": False,
        }
        writer.upload_firmware_legacy = fake_legacy_upload
        print(writer.upload_firmware("host", "secret", handle.name, dry_run=False))
      finally:
        os.unlink(handle.name)
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(result.stdout.contains("legacy-size 1572901"))
    XCTAssertTrue(result.stdout.contains("'method': 'legacy-command'"))
  }

  func testBackendFirmwareUploadRejectsURLWithoutDryRunBeforeNetwork() throws {
    let script = """
      import backend.airport_backend as writer
      try:
        writer.upload_firmware(
          "host",
          "secret",
          "https://apsu.apple.com/data/115/78100.3/7.8.1.basebinary",
          dry_run=False,
        )
      except ValueError as error:
        print(error)
      """
    let result = try runPython(script: script)

    XCTAssertEqual(result.exitCode, 0, result.stderr)
    XCTAssertTrue(result.stdout.contains("download firmware URL before uploading it"))
  }

  private func runWriteScript(arguments: [String]) throws -> (
    stdout: String, stderr: String, exitCode: Int32
  ) {
    try runPython(arguments: ["backend/airport_backend.py", "write"] + arguments)
  }

  private func runPython(script: String) throws -> (
    stdout: String, stderr: String, exitCode: Int32
  ) {
    try runPython(arguments: ["-c", script])
  }

  private func runPython(arguments: [String]) throws -> (
    stdout: String, stderr: String, exitCode: Int32
  ) {
    try requireSlowProcessTests()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = arguments
    process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    try process.run()
    process.waitUntilExit()

    return (
      String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
      String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
      process.terminationStatus
    )
  }
}

private final class CommandOutputChunkRecorder: @unchecked Sendable {
  private let queue = DispatchQueue(label: "CommandOutputChunkRecorder")
  private var chunks: [AirportCommandOutputChunk] = []

  func append(_ chunk: AirportCommandOutputChunk) {
    queue.sync {
      chunks.append(chunk)
    }
  }

  func text(for stream: AirportCommandOutputStream) -> String {
    queue.sync {
      chunks.filter { $0.stream == stream }.map(\.text).joined()
    }
  }
}
