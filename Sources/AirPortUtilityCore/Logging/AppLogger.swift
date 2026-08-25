// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

//
//  AppLogger.swift
//  AirPortUtility
//
//  Created by Graham Barber on 05/08/2026.
//


import Foundation
import OSLog

struct AppLogger: Sendable {
  static let shared = AppLogger()

  private static let subsystem = "com.pepperstm.airport-utility"

  private let store: PersistentLogStore

  init(
    store: PersistentLogStore = .shared
  ) {
    self.store = store
  }

  func debug(
    _ message: String,
    category: AppLogCategory = .app
  ) {
    log(
      level: .debug,
      message: message,
      category: category
    )
  }

  func info(
    _ message: String,
    category: AppLogCategory = .app
  ) {
    log(
      level: .info,
      message: message,
      category: category
    )
  }

  func notice(
    _ message: String,
    category: AppLogCategory = .app
  ) {
    log(
      level: .notice,
      message: message,
      category: category
    )
  }

  func warning(
    _ message: String,
    category: AppLogCategory = .app
  ) {
    log(
      level: .warning,
      message: message,
      category: category
    )
  }

  func error(
    _ message: String,
    category: AppLogCategory = .app
  ) {
    log(
      level: .error,
      message: message,
      category: category
    )
  }

  func fault(
    _ message: String,
    category: AppLogCategory = .app
  ) {
    log(
      level: .fault,
      message: message,
      category: category
    )
  }

  private func log(
    level: LogEntry.Level,
    message: String,
    category: AppLogCategory
  ) {
    let redactedMessage = LogRedactor.redact(message)

    let logger = Logger(
      subsystem: Self.subsystem,
      category: category.rawValue
    )

    switch level {
    case .debug:
      logger.debug("\(redactedMessage, privacy: .public)")

    case .info:
      logger.info("\(redactedMessage, privacy: .public)")

    case .notice:
      logger.notice("\(redactedMessage, privacy: .public)")

    case .warning:
      logger.warning("\(redactedMessage, privacy: .public)")

    case .error:
      logger.error("\(redactedMessage, privacy: .public)")

    case .fault:
      logger.fault("\(redactedMessage, privacy: .public)")
    }

    let entry = LogEntry(
      level: level,
      category: category,
      message: redactedMessage
    )

    Task {
      do {
        try await store.append(entry)
      } catch {
        logger.error(
          "Unable to persist log entry: \(error.localizedDescription, privacy: .public)"
        )
      }
    }
  }
}