// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

//
//  AppLogCategory.swift
//  AirPortUtility
//
//  Created by Graham Barber on 05/08/2026.
//


import Foundation

enum AppLogCategory: String, Codable, CaseIterable, Sendable {
  case app
  case discovery
  case backend
  case network
  case storage
  case configuration
  case diagnostics

  var displayName: String {
    switch self {
    case .app:
      "App"
    case .discovery:
      "Discovery"
    case .backend:
      "Backend"
    case .network:
      "Network"
    case .storage:
      "Storage"
    case .configuration:
      "Configuration"
    case .diagnostics:
      "Diagnostics"
    }
  }
}
