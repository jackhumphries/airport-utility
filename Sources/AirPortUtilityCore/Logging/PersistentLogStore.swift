// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

//
//  PersistentLogStore.swift
//  AirPortUtility
//
//  Created by Graham Barber on 05/08/2026.
//


import Foundation

actor PersistentLogStore {
  static let shared = PersistentLogStore()

  private let fileManager: FileManager
  private let encoder: JSONEncoder
  private let logFileURL: URL
  private let maximumFileSize: UInt64

  init(
    fileManager: FileManager = .default,
    logFileURL: URL? = nil,
    maximumFileSize: UInt64 = 5 * 1_024 * 1_024
  ) {
    self.fileManager = fileManager
    self.maximumFileSize = maximumFileSize

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    self.encoder = encoder

    if let logFileURL {
      self.logFileURL = logFileURL
    } else {
      let applicationSupport = fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first!

      self.logFileURL = applicationSupport
        .appendingPathComponent(
          "AirPort Utility Powerhouse",
          isDirectory: true
        )
        .appendingPathComponent("Logs", isDirectory: true)
        .appendingPathComponent("airport-utility.log")
    }
  }

  func append(_ entry: LogEntry) throws {
    try ensureLogDirectoryExists()
    try rotateIfNeeded()

    let data = try encoder.encode(entry)
    var line = data
    line.append(0x0A)

    if fileManager.fileExists(atPath: logFileURL.path) {
      let handle = try FileHandle(forWritingTo: logFileURL)
      defer {
        try? handle.close()
      }

      try handle.seekToEnd()
      try handle.write(contentsOf: line)
    } else {
      try line.write(
        to: logFileURL,
        options: .atomic
      )
    }
  }

  func readEntries() throws -> [LogEntry] {
    guard fileManager.fileExists(atPath: logFileURL.path) else {
      return []
    }

    let data = try Data(contentsOf: logFileURL)

    guard
      let text = String(data: data, encoding: .utf8),
      !text.isEmpty
    else {
      return []
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    return text
      .split(separator: "\n")
      .compactMap { line in
        guard let data = line.data(using: .utf8) else {
          return nil
        }

        return try? decoder.decode(LogEntry.self, from: data)
      }
  }

  func clear() throws {
    guard fileManager.fileExists(atPath: logFileURL.path) else {
      return
    }

    try fileManager.removeItem(at: logFileURL)
  }

  func currentLogFileURL() -> URL {
    logFileURL
  }

  private func ensureLogDirectoryExists() throws {
    let directory = logFileURL.deletingLastPathComponent()

    try fileManager.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
  }

  private func rotateIfNeeded() throws {
    guard fileManager.fileExists(atPath: logFileURL.path) else {
      return
    }

    let attributes = try fileManager.attributesOfItem(
      atPath: logFileURL.path
    )

    guard
      let fileSize = attributes[.size] as? NSNumber,
      fileSize.uint64Value >= maximumFileSize
    else {
      return
    }

    let rotatedURL = logFileURL
      .deletingPathExtension()
      .appendingPathExtension("previous.log")

    if fileManager.fileExists(atPath: rotatedURL.path) {
      try fileManager.removeItem(at: rotatedURL)
    }

    try fileManager.moveItem(
      at: logFileURL,
      to: rotatedURL
    )
  }
}