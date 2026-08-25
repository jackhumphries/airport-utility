// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

//
//  DefaultDiagnosticsService.swift
//  AirPortUtility
//
//  Created by Graham Barber on 06/08/2026.
//


import AppKit
import Foundation

@MainActor
final class DefaultDiagnosticsService: DiagnosticsService {

    func loadLogs() async throws -> [LogEntry] {
        try await PersistentLogStore.shared.readEntries()
    }

    func clearLogs() async throws {
        try await PersistentLogStore.shared.clear()
    }

    func revealLogs() {
        Task {
            let url = await PersistentLogStore.shared.currentLogFileURL()

            if FileManager.default.fileExists(atPath: url.path) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } else {
                NSWorkspace.shared.open(url.deletingLastPathComponent())
            }
        }
    }

    func saveSupportBundle(_ contents: String) async throws -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export Diagnostics Bundle"
        panel.nameFieldStringValue = "AirPort-Utility-Diagnostics.airportdiagnostics.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
