import AirPortUtilityCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Menu titles live in the app target, so they reach the shared table through
/// AirPortUtilityCore's public entry point.
private func localized(_ key: String, context: String? = nil) -> String {
  AirPortLocalization.text(key, context: context)
}

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
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

  func applicationWillTerminate(_ notification: Notification) {
    stopTopologyDisplayLog()
  }

  // MARK: - Window

  /// Places the window near the top-left of the active screen.
  ///
  /// Not centred: the window grows wider as base stations are discovered, and a
  /// centred window expands in both directions, so on a busy network it ends up
  /// partly off-screen. Anchored top-left it grows right and down into free
  /// space. Uses visibleFrame, so it sits below the menu bar and clear of the
  /// Dock, and falls back to centring if no screen is available.
  private static func positionAtTopLeft(_ window: NSWindow) {
    guard let screen = window.screen ?? NSScreen.main else {
      window.center()
      return
    }
    let margin: CGFloat = 20
    let visible = screen.visibleFrame
    window.setFrameOrigin(
      NSPoint(
        x: visible.minX + margin,
        y: visible.maxY - window.frame.height - margin))
  }

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
    window.title = localized("AirPort Utility")
    window.minSize = window.frameRect(
      forContentRect: NSRect(origin: .zero, size: AirPortMainWindowMetrics.contentSize)
    ).size
    window.contentViewController = NSHostingController(rootView: content)
    window.isReleasedWhenClosed = false
    Self.positionAtTopLeft(window)

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
    mainMenu.addItem(menu(localized("File"), submenu: fileMenu()))
    mainMenu.addItem(menu(localized("Edit", context: "menu"), submenu: editMenu()))
    mainMenu.addItem(menu("Base Station", submenu: baseStationMenu()))
    mainMenu.addItem(menu(localized("Window"), submenu: windowMenu()))
    mainMenu.addItem(menu(localized("Help"), submenu: helpMenu()))
    NSApplication.shared.mainMenu = mainMenu
    NSApplication.shared.windowsMenu = mainMenu.item(withTitle: localized("Window"))?.submenu
    NSApp.servicesMenu =
      mainMenu.item(withTitle: "AirPort Utility")?.submenu?.item(withTitle: localized("Services"))?.submenu
  }

  private func applicationMenu() -> NSMenu {
    let menu = NSMenu(title: "AirPort Utility")
    menu.addItem(
      item(
        localized("About AirPort Utility"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
        target: NSApp))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(
      item(localized("Preferences..."), action: #selector(showPreferences(_:)), key: ",", target: self))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(self.menu(localized("Services"), submenu: NSMenu(title: localized("Services"))))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(
      item(
        localized("Hide AirPort Utility"), action: #selector(NSApplication.hide(_:)), key: "h", target: NSApp))
    menu.addItem(
      item(
        localized("Hide Others"), action: #selector(NSApplication.hideOtherApplications(_:)), key: "h",
        modifiers: [.command, .option], target: NSApp))
    menu.addItem(
      item(localized("Show All"), action: #selector(NSApplication.unhideAllApplications(_:)), target: NSApp))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(
      item(
        localized("Quit AirPort Utility"), action: #selector(NSApplication.terminate(_:)), key: "q",
        target: NSApp))
    return menu
  }

  private func fileMenu() -> NSMenu {
    let menu = NSMenu(title: localized("File"))
    menu.addItem(
      item(localized("Configure Other..."), action: #selector(configureOther(_:)), target: self))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(
      item(
        localized("Import Configuration File..."), action: #selector(importConfigurationFile(_:)),
        target: self))
    menu.addItem(
      item(
        localized("Export Configuration File..."), action: #selector(exportConfigurationFile(_:)),
        target: self))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(item(localized("Close"), action: #selector(NSWindow.performClose(_:)), key: "w"))
    return menu
  }

  private func editMenu() -> NSMenu {
    let menu = NSMenu(title: localized("Edit"))
    menu.addItem(item(localized("Undo"), action: Selector(("undo:")), key: "z"))
    menu.addItem(
      item(localized("Redo"), action: Selector(("redo:")), key: "Z", modifiers: [.command, .shift]))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(item(localized("Cut"), action: #selector(NSText.cut(_:)), key: "x"))
    menu.addItem(item(localized("Copy"), action: #selector(NSText.copy(_:)), key: "c"))
    menu.addItem(item(localized("Paste"), action: #selector(NSText.paste(_:)), key: "v"))
    menu.addItem(item(localized("Delete"), action: #selector(NSText.delete(_:))))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(item(localized("Select All"), action: #selector(NSText.selectAll(_:)), key: "a"))
    return menu
  }

  private func baseStationMenu() -> NSMenu {
    let menu = NSMenu(title: "Base Station")
    menu.addItem(
      item(localized("Refresh"), action: #selector(refreshNetwork(_:)), key: "r", target: self))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(
      item(localized("Show Passwords…"), action: #selector(showPasswords(_:)), target: self))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(
      item(localized("Restart…"), action: #selector(restartBaseStation(_:)), target: self))
    menu.addItem(
      item(
        localized("Restore Default Settings..."), action: #selector(restoreDefaultSettings(_:)),
        target: self))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(disabledItem(localized("Add WPS Printer…")))
    return menu
  }

  private func windowMenu() -> NSMenu {
    let menu = NSMenu(title: localized("Window"))
    menu.addItem(item(localized("Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), key: "m"))
    menu.addItem(item(localized("Zoom"), action: #selector(NSWindow.performZoom(_:))))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(
      item(localized("Bring All to Front"), action: #selector(NSApplication.arrangeInFront(_:)), target: NSApp)
    )
    return menu
  }

  private func helpMenu() -> NSMenu {
    let menu = NSMenu(title: localized("Help"))
    menu.addItem(
      item(localized("AirPort Utility Help"), action: #selector(showHelp(_:)), key: "?", target: self))
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

  @objc func importConfigurationFile(_ sender: Any?) {
    showMainWindow()
    let panel = NSOpenPanel()
    panel.title = localized("Import Configuration File")
    panel.allowedContentTypes = Self.configurationContentTypes
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.begin { [weak self] response in
      guard response == .OK, let url = panel.url else { return }
      Task { @MainActor [weak self] in
        do {
          try self?.model.importConfiguration(from: url)
        } catch {
          self?.presentFileOperationError(error, title: localized("Import Configuration File"))
        }
      }
    }
  }

  @objc func exportConfigurationFile(_ sender: Any?) {
    showMainWindow()
    let panel = NSSavePanel()
    panel.title = localized("Export Configuration File")
    panel.allowedContentTypes = Self.configurationContentTypes
    panel.nameFieldStringValue = model.defaultConfigurationFileName
    panel.begin { [weak self] response in
      guard response == .OK, let url = panel.url else { return }
      Task { @MainActor [weak self] in
        do {
          try self?.model.exportConfiguration(to: url)
        } catch {
          self?.presentFileOperationError(error, title: localized("Export Configuration File"))
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
