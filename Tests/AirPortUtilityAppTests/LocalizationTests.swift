import Foundation
import XCTest

@testable import AirPortUtilityCore

/// Guards the localization tables as strings are migrated pane by pane.
final class LocalizationTests: XCTestCase {
  private static let expectedLanguages = ["de", "en", "es", "fr", "it"]

  private func table(_ language: String) throws -> [String: String] {
    let bundle = AirPortLocalization.resourceBundle
    let url = try XCTUnwrap(
      bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: "\(language).lproj"),
      "missing \(language).lproj/Localizable.strings")
    return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
  }

  func testAllExpectedLanguagesShip() {
    XCTAssertEqual(AirPortLocalization.availableLanguages, Self.expectedLanguages)
  }

  /// Every English key must exist in every other table, or that string silently
  /// falls back to English for those users.
  func testTranslationsCoverEveryEnglishKey() throws {
    let english = try table("en")
    XCTAssertFalse(english.isEmpty)

    for language in Self.expectedLanguages where language != "en" {
      let translated = try table(language)
      let missing = Set(english.keys).subtracting(translated.keys).sorted()
      XCTAssertTrue(
        missing.isEmpty,
        "\(language) is missing \(missing.count) key(s): \(missing.prefix(10))")
    }
  }

  /// A translated value that still equals the English source is usually an
  /// untranslated placeholder. The exceptions are per language, not global: a
  /// term that is genuinely identical in German may still be a real word in
  /// French, and a global allowlist would stop catching a lazy French entry.
  ///
  /// Every entry below is a brand name or a loanword the target language
  /// actually uses. Add to it only after checking the term in that language.
  private static let identicalByDesign: [String: Set<String>] = [
    "fr": [
      "15 minutes", "30 minutes", "AirPlay", "AirPort Express", "AirPort Extreme", "Description", "Destination", "Double NAT", "Internet", "Local", "Services", "Time Capsule", "Tunnel", "Type", "Zoom", "minute",
    ],
    "de": [
      "Accounts:", "AirPlay", "AirPort Express", "AirPort Extreme", "Firmware", "Host", "Host:", "Hostname:", "Internet", "Name", "Name:", "Region", "Region:", "Repo", "Repository", "Repository:", "Router", "Time Capsule", "Tunnel", "Version:",
    ],
    "es": [
      "AirPlay", "AirPort Express", "AirPort Extreme", "Firmware", "Host", "Host:", "Internet", "Local", "Repo", "Router", "Time Capsule", "Zoom",
    ],
    "it": [
      "AirPlay", "AirPort Express", "AirPort Extreme", "Default", "Firmware", "Host", "Host:", "Internet", "Password", "Password:", "Repo", "Repository", "Repository:", "Router", "Time Capsule", "Tunnel", "Wireless", "Zoom",
    ],
  ]

  func testTranslationsDifferFromEnglish() throws {
    let english = try table("en")

    for language in Self.expectedLanguages where language != "en" {
      let allowed = Self.identicalByDesign[language] ?? []
      let translated = try table(language)
      for (key, value) in translated
      where !allowed.contains(key) && value == english[key] {
        XCTFail("\(language): \"\(key)\" is identical to English")
      }
    }
  }

  /// Guards the allowlist itself: an entry that is no longer identical has been
  /// translated since, and should be removed so the check stays meaningful.
  func testIdenticalAllowlistHasNoStaleEntries() throws {
    let english = try table("en")

    for (language, allowed) in Self.identicalByDesign {
      let translated = try table(language)
      for key in allowed.sorted() where translated[key] != english[key] {
        XCTFail("\(language): \"\(key)\" is translated now; drop it from the allowlist")
      }
    }
  }

  /// Protocol text must never be localized: ACP keys, backend flags and
  /// persisted raw values are wire format, not display strings.
  func testTablesContainNoProtocolTokens() throws {
    for language in Self.expectedLanguages {
      for key in try table(language).keys {
        XCTAssertFalse(key.hasPrefix("--"), "\(language): backend flag \"\(key)\" localized")
        // ACP keys are four characters shaped lowercase-lowercase-UPPER-alnum
        // (syNm, raCr, peSC, wdFl). Plain four-letter words like "Help" or
        // "Edit" are ordinary UI text and must not trip this.
        XCTAssertNil(
          key.range(of: "^[a-z]{2}[A-Z0-9][A-Za-z0-9]$", options: .regularExpression),
          "\(language): possible ACP key \"\(key)\" localized")
      }
    }
  }

  /// Pane raw values stay English because they are persisted, used for snapshot
  /// file names, and used to build accessibility identifiers.
  func testPaneRawValuesRemainEnglish() {
    XCTAssertEqual(Pane.baseStation.rawValue, "Base Station")
    XCTAssertEqual(Pane.disks.rawValue, "Disks")
    XCTAssertEqual(Pane.advanced.rawValue, "Advanced")
  }

  /// Region names come from Foundation rather than the .strings tables.
  /// An entry that maps to no ISO region silently falls back to English in all
  /// four languages, so the whole list must map.
  func testEveryRegionMapsToAnISORegion() {
    let unmapped = WirelessRegionOption.allCases.filter { $0.isoRegionCode == nil }
    XCTAssertTrue(unmapped.isEmpty, "unmapped regions: \(unmapped.map(\.name))")
  }

  func testRegionNamesTranslate() {
    let france = WirelessRegionOption.allCases.first { $0.name == "Germany" }
    let code = try? XCTUnwrap(france?.isoRegionCode)
    XCTAssertEqual(code, "DE")
    XCTAssertEqual(Locale(identifier: "fr").localizedString(forRegionCode: "DE"), "Allemagne")
    XCTAssertEqual(Locale(identifier: "es").localizedString(forRegionCode: "DE"), "Alemania")
  }

  /// The topology decides a device's status colour by comparing display text.
  /// The "no problems" default and the message the status builder produces for
  /// an empty problem list must therefore be the same string, in every
  /// language -- otherwise every device renders as if it had a problem.
  @MainActor
  func testDefaultStatusMatchesTheNoProblemStatusMessage() {
    XCTAssertEqual(BaseStationState().statusText, DeviceStatusMessage.text(problemCodes: []))
  }

  func testLookupFallsBackToTheKeyWhenUntranslated() {
    let key = "A string that is deliberately absent from every table"
    XCTAssertEqual(AirPortLocalization.text(key), key)
  }
}
