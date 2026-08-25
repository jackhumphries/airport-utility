import AirPortUtilityCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
  private let model = AirportAppModel()
  private var windowController: NSWindowController?
  private var topologyDisplayLogTimer: Timer?
  private var topologyDisplayLogHandle: FileHandle?
  private static let baseConfigurationContentType =
    UTType(filenameExtension: "baseconfig") ?? .propertyList
  private static let configurationContentTypes: [UTType] = [
    baseConfigurationContentType, .json, .propertyList,
  ]
  private static let helpURL = URL(string: "https://support.apple.com/guide/aputility/welcome/mac")

  // MARK: - App Lifecycle

  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
    withExtendedLifetime(delegate) {}
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    if HealthNotificationCenter.isAvailableForCurrentProcess {
      UNUserNotificationCenter.current().delegate = self
    }
    installMainMenu()
    if ProcessInfo.processInfo.environment["AIRPORT_UTILITY_SNAPSHOT"] == "1" {
      renderSnapshotsAndQuit()
      return
    }
    DispatchQueue.main.async { [weak self] in
      self?.showMainWindow()
      if Self.shouldStartTopologyDisplayLog {
        self?.startTopologyDisplayLog()
      }
    }
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .sound]
  }

  func applicationWillTerminate(_ notification: Notification) {
    stopTopologyDisplayLog()
  }

  // MARK: - Window

  private func showMainWindow() {
    if let window = windowController?.window {
      window.makeKeyAndOrderFront(nil)
      NSApplication.shared.activate(ignoringOtherApps: true)
      return
    }

    let content = ContentView()
      .environmentObject(model)

    let window = NSWindow(
      contentRect: NSRect(
        x: 140,
        y: 120,
        width: AirPortMainWindowMetrics.contentSize.width,
        height: AirPortMainWindowMetrics.contentSize.height),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "AirPort Utility"
    window.minSize = window.frameRect(
      forContentRect: NSRect(origin: .zero, size: AirPortMainWindowMetrics.contentSize)
    ).size
    window.contentViewController = NSHostingController(rootView: content)
    window.isReleasedWhenClosed = false
    window.center()

    let controller = NSWindowController(window: window)
    windowController = controller
    controller.showWindow(nil)
    window.orderFrontRegardless()
    NSApplication.shared.activate(ignoringOtherApps: true)
  }

  // MARK: - Snapshot Mode

  private func renderSnapshotsAndQuit() {
    do {
      let outputPath =
        ProcessInfo.processInfo.environment["AIRPORT_UTILITY_SNAPSHOT_DIR"]
        ?? FileManager.default.currentDirectoryPath + "/.build/ui-snapshots"
      let urls = try AirPortSnapshotRenderer.renderAll(
        model: model,
        outputDirectory: URL(fileURLWithPath: outputPath)
      )
      for url in urls {
        print(url.path)
      }
      NSApplication.shared.terminate(nil)
    } catch {
      fputs("Snapshot failed: \(error.localizedDescription)\n", stderr)
      NSApplication.shared.terminate(nil)
    }
  }

  // MARK: - Topology Display Log

  private func startTopologyDisplayLog() {
    guard topologyDisplayLogTimer == nil else { return }
    let url = Self.topologyDisplayLogURL
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      _ = FileManager.default.createFile(atPath: url.path, contents: Data())
      let handle = try FileHandle(forWritingTo: url)
      topologyDisplayLogHandle = handle
      appendTopologyDisplayLogLine(
        #"{"event":"started topology display log","path":"\#(url.path)"}"#)
      let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) {
        [weak self] _ in
        Task { @MainActor [weak self] in
          self?.appendTopologyDisplayLogTick()
        }
      }
      timer.tolerance = 0.02
      topologyDisplayLogTimer = timer
    } catch {
      stopTopologyDisplayLog()
      fputs("Could not open topology display log at \(url.path): \(error)\n", stderr)
    }
  }

  private func stopTopologyDisplayLog() {
    topologyDisplayLogTimer?.invalidate()
    topologyDisplayLogTimer = nil
    try? topologyDisplayLogHandle?.close()
    topologyDisplayLogHandle = nil
  }

  private static var shouldStartTopologyDisplayLog: Bool {
    let environment = ProcessInfo.processInfo.environment
    return environment["AIRPORT_UTILITY_TOPOLOGY_LOG"] == "1"
      || environment["AIRPORT_UTILITY_TOPOLOGY_LOG_PATH"] != nil
  }

  private static var topologyDisplayLogURL: URL {
    if let path = ProcessInfo.processInfo.environment["AIRPORT_UTILITY_TOPOLOGY_LOG_PATH"],
      !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return URL(fileURLWithPath: path)
    }
    return FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Desktop")
      .appendingPathComponent("log")
  }

  private func appendTopologyDisplayLogTick() {
    appendTopologyDisplayLogLine(model.topologyDisplayLogSnapshot())
  }

  private func appendTopologyDisplayLogLine(_ line: String) {
    guard let handle = topologyDisplayLogHandle,
      let data = (line + "\n").data(using: .utf8)
    else {
      return
    }
    handle.write(data)
    handle.synchronizeFile()
  }

  // MARK: - Menus

  private func installMainMenu() {
    let mainMenu = NSMenu()
    mainMenu.addItem(menu("AirPort Utility", submenu: applicationMenu()))
    mainMenu.addItem(menu("File", submenu: fileMenu()))
    mainMenu.addItem(menu("Edit", submenu: editMenu()))
    mainMenu.addItem(menu("Base Station", submenu: baseStationMenu()))
    mainMenu.addItem(menu("Window", submenu: windowMenu()))
    mainMenu.addItem(menu("Help", submenu: helpMenu()))
    NSApplication.shared.mainMenu = mainMenu
    NSApplication.shared.windowsMenu = mainMenu.item(withTitle: "Window")?.submenu
    NSApp.servicesMenu =
      mainMenu.item(withTitle: "AirPort Utility")?.submenu?.item(withTitle: "Services")?.submenu
  }

  private func applicationMenu() -> NSMenu {
    let menu = NSMenu(title: "AirPort Utility")
    menu.addItem(
      item(
        "About AirPort Utility", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
        target: NSApp))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(
      item("Preferences...", action: #selector(showPreferences(_:)), key: ",", target: self))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(self.menu("Services", submenu: NSMenu(title: "Services")))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(
      item(
        "Hide AirPort Utility", action: #selector(NSApplication.hide(_:)), key: "h", target: NSApp))
    menu.addItem(
      item(
        "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), key: "h",
        modifiers: [.command, .option], target: NSApp))
    menu.addItem(
      item("Show All", action: #selector(NSApplication.unhideAllApplications(_:)), target: NSApp))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(
      item(
        "Quit AirPort Utility", action: #selector(NSApplication.terminate(_:)), key: "q",
        target: NSApp))
    return menu
  }

  private func fileMenu() -> NSMenu {
    let menu = NSMenu(title: "File")
    menu.addItem(
      item("Configure Other...", action: #selector(configureOther(_:)), target: self))
    menu.addItem(
      item("Sites...", action: #selector(sites(_:)), target: self))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(
      item(
        "Import Configuration File...", action: #selector(importConfigurationFile(_:)),
        target: self))
    menu.addItem(
      item(
        "Export Configuration File...", action: #selector(exportConfigurationFile(_:)),
        target: self))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(item("Close", action: #selector(NSWindow.performClose(_:)), key: "w"))
    return menu
  }

  private func editMenu() -> NSMenu {
    let menu = NSMenu(title: "Edit")
    menu.addItem(item("Undo", action: Selector(("undo:")), key: "z"))
    menu.addItem(
      item("Redo", action: Selector(("redo:")), key: "Z", modifiers: [.command, .shift]))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(item("Cut", action: #selector(NSText.cut(_:)), key: "x"))
    menu.addItem(item("Copy", action: #selector(NSText.copy(_:)), key: "c"))
    menu.addItem(item("Paste", action: #selector(NSText.paste(_:)), key: "v"))
    menu.addItem(item("Delete", action: #selector(NSText.delete(_:))))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(item("Select All", action: #selector(NSText.selectAll(_:)), key: "a"))
    return menu
  }

  private func baseStationMenu() -> NSMenu {
    let menu = NSMenu(title: "Base Station")
    menu.addItem(
      item("Refresh", action: #selector(refreshNetwork(_:)), key: "r", target: self))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(
      item("Show Passwords…", action: #selector(showPasswords(_:)), target: self))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(
      item("Restart…", action: #selector(restartBaseStation(_:)), target: self))
    menu.addItem(
      item(
        "Restore Default Settings...", action: #selector(restoreDefaultSettings(_:)),
        target: self))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(disabledItem("Add WPS Printer…"))
    return menu
  }

  private func windowMenu() -> NSMenu {
    let menu = NSMenu(title: "Window")
    menu.addItem(item("Minimize", action: #selector(NSWindow.performMiniaturize(_:)), key: "m"))
    menu.addItem(item("Zoom", action: #selector(NSWindow.performZoom(_:))))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(
      item("Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), target: NSApp)
    )
    return menu
  }

  private func helpMenu() -> NSMenu {
    let menu = NSMenu(title: "Help")
    menu.addItem(
      item("AirPort Utility Help", action: #selector(showHelp(_:)), key: "?", target: self))
    return menu
  }

  private func menu(_ title: String, submenu: NSMenu) -> NSMenuItem {
    let menuItem = NSMenuItem()
    menuItem.title = title
    menuItem.submenu = submenu
    return menuItem
  }

  private func item(
    _ title: String,
    action: Selector,
    key: String = "",
    modifiers: NSEvent.ModifierFlags = [.command],
    target: AnyObject? = nil
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
    item.target = target
    return item
  }

  private func disabledItem(_ title: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.isEnabled = false
    return item
  }

  // MARK: - Menu Actions

  @objc private func showMainWindowFromMenu(_ sender: Any?) {
    showMainWindow()
  }

  @objc private func beginEditingFromMenu(_ sender: Any?) {
    model.beginEditing()
  }

  @objc private func configureOther(_ sender: Any?) {
    showMainWindow()
    model.showConfigureOther()
  }

  @objc private func sites(_ sender: Any?) {
    showMainWindow()
    model.showSites()
  }

  @objc func importConfigurationFile(_ sender: Any?) {
    showMainWindow()
    let panel = NSOpenPanel()
    panel.title = "Import Configuration File"
    panel.allowedContentTypes = Self.configurationContentTypes
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.begin { [weak self] response in
      guard response == .OK, let url = panel.url else { return }
      Task { @MainActor [weak self] in
        do {
          try self?.model.importConfiguration(from: url)
        } catch {
          self?.presentFileOperationError(error, title: "Import Configuration File")
        }
      }
    }
  }

  @objc func exportConfigurationFile(_ sender: Any?) {
    showMainWindow()
    let panel = NSSavePanel()
    panel.title = "Export Configuration File"
    panel.allowedContentTypes = Self.configurationContentTypes
    panel.nameFieldStringValue = model.defaultConfigurationFileName
    panel.begin { [weak self] response in
      guard response == .OK, let url = panel.url else { return }
      Task { @MainActor [weak self] in
        do {
          try self?.model.exportConfiguration(to: url)
        } catch {
          self?.presentFileOperationError(error, title: "Export Configuration File")
        }
      }
    }
  }

  @objc private func showPasswords(_ sender: Any?) {
    showMainWindow()
    model.showPasswords()
  }

  @objc private func refreshNetwork(_ sender: Any?) {
    showMainWindow()
    model.refreshNetwork()
  }

  @objc private func restartBaseStation(_ sender: Any?) {
    showMainWindow()
    model.requestRestartBaseStation()
  }

  @objc private func restoreDefaultSettings(_ sender: Any?) {
    showMainWindow()
    model.requestRestoreDefaultSettings()
  }

  @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    if menuItem.action == #selector(refreshNetwork(_:)) {
      return model.canRefreshNetwork && windowController?.window?.attachedSheet == nil
    }
    if menuItem.action == #selector(showPasswords(_:)) {
      return model.canShowPasswords
    }
    if menuItem.action == #selector(restartBaseStation(_:)) {
      return model.canRequestRestartBaseStation
    }
    if menuItem.action == #selector(restoreDefaultSettings(_:)) {
      return model.canRequestRestoreDefaultSettings
    }
    return true
  }

  private func presentFileOperationError(_ error: Error, title: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = error.localizedDescription
    alert.alertStyle = .warning
    if let window = windowController?.window {
      alert.beginSheetModal(for: window)
    } else {
      alert.runModal()
    }
  }

  @objc private func showPreferences(_ sender: Any?) {
    showMainWindow()
    model.showPreferences()
  }

  @objc private func showHelp(_ sender: Any?) {
    guard let helpURL = Self.helpURL else { return }
    NSWorkspace.shared.open(helpURL)
  }
}
