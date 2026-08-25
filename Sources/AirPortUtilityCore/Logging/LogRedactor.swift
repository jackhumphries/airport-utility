// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

//
//  LogRedactor.swift
//  AirPortUtility
//
//  Created by Graham Barber on 05/08/2026.
//


import Foundation

enum LogRedactor {
  private static let sensitiveKeys = [
    "password",
    "passwd",
    "passphrase",
    "secret",
    "token",
    "authorization",
    "adminPassword",
    "wirelessPassword",
    "pppoePassword"
  ]

  static func redact(_ value: String) -> String {
    var redacted = value

    for key in sensitiveKeys {
      redacted = redactAssignments(
        in: redacted,
        key: key
      )
    }

    redacted = redactAuthorizationHeaders(in: redacted)
    redacted = redactURLCredentials(in: redacted)

    return redacted
  }

  private static func redactAssignments(
    in value: String,
    key: String
  ) -> String {
    let escapedKey = NSRegularExpression.escapedPattern(for: key)

    let patterns = [
      #"(?i)(\b\#(escapedKey)\b\s*[:=]\s*)("[^"]*"|'[^']*'|[^\s,;}]+)"#,
      #"(?i)("\#(escapedKey)"\s*:\s*)("[^"]*"|null)"#
    ]

    var result = value

    for pattern in patterns {
      guard let regex = try? NSRegularExpression(pattern: pattern) else {
        continue
      }

      let range = NSRange(result.startIndex..., in: result)
      result = regex.stringByReplacingMatches(
        in: result,
        range: range,
        withTemplate: "$1<redacted>"
      )
    }

    return result
  }

  private static func redactAuthorizationHeaders(
    in value: String
  ) -> String {
    guard let regex = try? NSRegularExpression(
      pattern: #"(?i)(authorization\s*:\s*)([^\r\n]+)"#
    ) else {
      return value
    }

    let range = NSRange(value.startIndex..., in: value)

    return regex.stringByReplacingMatches(
      in: value,
      range: range,
      withTemplate: "$1<redacted>"
    )
  }

  private static func redactURLCredentials(
    in value: String
  ) -> String {
    guard let regex = try? NSRegularExpression(
      pattern: #"([a-zA-Z][a-zA-Z0-9+.-]*://[^:\s/@]+:)([^@\s/]+)(@)"#
    ) else {
      return value
    }

    let range = NSRange(value.startIndex..., in: value)

    return regex.stringByReplacingMatches(
      in: value,
      range: range,
      withTemplate: "$1<redacted>$3"
    )
  }
}