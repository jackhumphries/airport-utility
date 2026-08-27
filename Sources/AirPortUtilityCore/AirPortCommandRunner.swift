import Darwin
import Foundation

enum AirportCommandOutputStream: Sendable {
  case stdout
  case stderr
}

struct AirportCommandOutputChunk: Sendable {
  var stream: AirportCommandOutputStream
  var text: String
}

enum AirportCommandError: LocalizedError, Sendable {
  case missingScript(String)
  case launchFailed(path: String, reason: String)
  case failed(CommandResult)
  case timedOut(String)

  var errorDescription: String? {
    switch self {
    case .missingScript(let path):
      "Missing backend script at \(path)"
    case .launchFailed(let path, let reason):
      "Could not launch backend script at \(path): \(reason)"
    case .failed(let result):
      Self.failureDescription(for: result)
    case .timedOut(let command):
      "\(command) timed out"
    }
  }

  private static func failureDescription(for result: CommandResult) -> String {
    let output = result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !output.isEmpty else {
      return "Command failed with exit \(result.exitCode)"
    }
    if DiskInventoryMessage.containsPendingPlaceholder(output) {
      return localized("Disk information is not available yet.")
    }
    let lowercased = output.lowercased()
    if lowercased.contains("nodename nor servname")
      || lowercased.contains("name or service not known")
      || lowercased.contains("temporary failure in name resolution")
      || lowercased.contains("failed to resolve")
    {
      let host = result.arguments.first?.trimmingCharacters(in: .whitespacesAndNewlines)
      if let host, !host.isEmpty {
        return
          "Could not find \(host). Check that the Time Capsule is on this network, or enter its IP address instead of the .local name."
      }
      return
        localized("Could not find the Time Capsule. Check that it is on this network, or enter its IP address instead of the .local name.")
    }
    return output
  }

}

final class AirportCommandRunner: @unchecked Sendable {
  func run(
    script: String, arguments: [String], connection: AirportConnection, timeout: TimeInterval = 45,
    outputHandler: (@Sendable (AirportCommandOutputChunk) -> Void)? = nil
  ) async throws -> CommandResult {
    let task = Task.detached(priority: .userInitiated) {
      let scriptURL = URL(
        fileURLWithPath: script, relativeTo: URL(fileURLWithPath: connection.repoPath)
      ).standardizedFileURL
      guard FileManager.default.fileExists(atPath: scriptURL.path) else {
        throw AirportCommandError.missingScript(scriptURL.path)
      }

      let process = Process()
      process.executableURL = scriptURL
      process.arguments = arguments
      process.currentDirectoryURL = URL(fileURLWithPath: connection.repoPath)

      let stdout = PipeOutputBuffer { text in
        outputHandler?(AirportCommandOutputChunk(stream: .stdout, text: text))
      }
      let stderr = PipeOutputBuffer { text in
        outputHandler?(AirportCommandOutputChunk(stream: .stderr, text: text))
      }
      process.standardOutput = stdout.pipe
      process.standardError = stderr.pipe

      do {
        try process.run()
      } catch {
        stdout.stopReading()
        stderr.stopReading()
        throw AirportCommandError.launchFailed(
          path: scriptURL.path, reason: error.localizedDescription)
      }
      defer {
        stdout.stopReading()
        stderr.stopReading()
      }

      let didTimeOut: Bool
      do {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
          try await Task.sleep(nanoseconds: 100_000_000)
        }
        didTimeOut = process.isRunning
      } catch {
        Self.terminate(process)
        throw error
      }

      if didTimeOut {
        Self.terminate(process)
      }

      let stdoutText = stdout.stringValue()
      let stderrText = stderr.stringValue()
      let redacted = AirportCommand.redact(arguments)
      let result = CommandResult(
        arguments: arguments, redactedArguments: redacted, stdout: stdoutText, stderr: stderrText,
        exitCode: process.terminationStatus)

      if didTimeOut {
        throw AirportCommandError.timedOut(AirportCommand.display(script, redacted))
      }
      guard result.succeeded else {
        throw AirportCommandError.failed(result)
      }
      return result
    }
    return try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      task.cancel()
    }
  }

  private static func terminate(_ process: Process) {
    guard process.isRunning else { return }
    process.terminate()
    waitForExit(process, until: Date().addingTimeInterval(1))
    if process.isRunning {
      kill(process.processIdentifier, SIGKILL)
    }
    waitForExit(process, until: Date().addingTimeInterval(1))
  }

  private static func waitForExit(_ process: Process, until deadline: Date) {
    while process.isRunning && Date() < deadline {
      Thread.sleep(forTimeInterval: 0.05)
    }
  }
}

private final class PipeOutputBuffer: @unchecked Sendable {
  let pipe = Pipe()
  private let lock = NSLock()
  private var data = Data()
  private let outputHandler: (@Sendable (String) -> Void)?

  init(outputHandler: (@Sendable (String) -> Void)? = nil) {
    self.outputHandler = outputHandler
    pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let availableData = handle.availableData
      guard !availableData.isEmpty else { return }
      self?.append(availableData)
    }
  }

  func stringValue() -> String {
    stopReading()
    drainAvailableData()
    lock.lock()
    let output = String(data: data, encoding: .utf8) ?? ""
    lock.unlock()
    return output
  }

  func stopReading() {
    pipe.fileHandleForReading.readabilityHandler = nil
  }

  private func append(_ newData: Data) {
    lock.lock()
    data.append(newData)
    lock.unlock()
    if let outputHandler,
      let text = String(data: newData, encoding: .utf8),
      !text.isEmpty
    {
      outputHandler(text)
    }
  }

  private func drainAvailableData() {
    let descriptor = pipe.fileHandleForReading.fileDescriptor
    let originalFlags = fcntl(descriptor, F_GETFL)
    if originalFlags >= 0 {
      _ = fcntl(descriptor, F_SETFL, originalFlags | O_NONBLOCK)
    }
    defer {
      if originalFlags >= 0 {
        _ = fcntl(descriptor, F_SETFL, originalFlags)
      }
    }

    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
      let bytesRead = buffer.withUnsafeMutableBytes {
        Darwin.read(descriptor, $0.baseAddress, $0.count)
      }
      if bytesRead > 0 {
        append(Data(buffer.prefix(bytesRead)))
      } else if bytesRead == 0 {
        break
      } else if errno == EINTR {
        continue
      } else {
        break
      }
    }
  }
}
