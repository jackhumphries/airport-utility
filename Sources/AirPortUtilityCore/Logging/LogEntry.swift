// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

//
//  LogEntry.swift
//  AirPortUtility
//
//  Created by Graham Barber on 05/08/2026.
//


import Foundation

struct LogEntry: Codable, Equatable, Identifiable, Sendable {
  enum Level: String, Codable, CaseIterable, Sendable {
    case debug
    case info
    case notice
    case warning
    case error
    case fault
  }

  var formattedLine: String {
    let formattedTimestamp = timestamp.formatted(.iso8601)
    return "[\(formattedTimestamp)] [\(level.rawValue.uppercased())] [\(category.displayName)] \(message)"
  }

  let id: UUID
  let timestamp: Date
  let level: Level
  let category: AppLogCategory
  let message: String

  init(
    id: UUID = UUID(),
    timestamp: Date = Date(),
    level: Level,
    category: AppLogCategory,
    message: String
  ) {
    self.id = id
    self.timestamp = timestamp
    self.level = level
    self.category = category
    self.message = message
  }
}
