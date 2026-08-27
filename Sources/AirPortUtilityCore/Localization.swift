import Foundation

/// UI string localization for the app.
///
/// Keys are the English source text itself, so English needs no table and any
/// untranslated string falls back to readable English instead of a symbolic key.
///
/// IMPORTANT: never route protocol text through here. ACP setting keys (`syNm`),
/// backend flags (`--router-mode`), JSON keys, and enum raw values that are
/// persisted or sent to the backend are wire format, not display text.
/// Localizing them corrupts the protocol. When an enum raw value doubles as a
/// label, add a separate `displayName` rather than translating the raw value.
public enum AirPortLocalization {
  /// The `.lproj` bundle matching the user's preferred languages.
  ///
  /// Resolved from `Locale.preferredLanguages` rather than the one-argument
  /// `Bundle.preferredLocalizations(from:)`, because that variant matches
  /// against the *main* bundle's localizations. Those are empty for a
  /// command-line build or a test harness, which silently pins every lookup to
  /// English even when the user's language is French.
  static let bundle: Bundle = {
    let available = Bundle.module.localizations
    let preferred = Bundle.preferredLocalizations(
      from: available, forPreferences: preferredLanguages)
    for language in preferred {
      if let url = Bundle.module.url(forResource: language, withExtension: "lproj"),
        let bundle = Bundle(url: url)
      {
        return bundle
      }
    }
    return .module
  }()

  /// The language preference used to pick a table.
  ///
  /// Under XCTest this is pinned to the development language. Many tests assert
  /// on English UI strings, and without pinning, the same test passes on an
  /// English machine and fails on a French one -- so a developer's system
  /// language would decide whether the suite is green.
  private static var preferredLanguages: [String] {
    if NSClassFromString("XCTest") != nil {
      return ["en"]
    }
    return Locale.preferredLanguages
  }

  /// The locale matching the resolved table.
  ///
  /// Foundation-provided text (region names, for example) must agree with the
  /// rest of the UI, and must follow the same XCTest pinning -- otherwise a
  /// test sees English labels beside French country names.
  static let locale: Locale = {
    let available = Bundle.module.localizations
    let preferred = Bundle.preferredLocalizations(
      from: available, forPreferences: preferredLanguages)
    return Locale(identifier: preferred.first ?? "en")
  }()

  /// Looks up `key`, falling back to the key itself when untranslated.
  ///
  /// `context` disambiguates one English word that needs different translations
  /// in different places. "Edit" is the Edit *menu* in the menu bar ("Édition")
  /// but a verb on a button ("Modifier"); with the English source as the key
  /// there is otherwise no way to tell them apart. A contextual entry is stored
  /// as "context.key" and falls back to the plain key when absent.
  public static func text(_ key: String, context: String? = nil) -> String {
    if let context {
      let qualified = "\(context).\(key)"
      let sentinel = "\u{0}"
      let value = bundle.localizedString(forKey: qualified, value: sentinel, table: nil)
      if value != sentinel {
        return value
      }
    }
    return bundle.localizedString(forKey: key, value: key, table: nil)
  }

  /// The resource bundle holding the `.lproj` tables.
  static var resourceBundle: Bundle { .module }

  /// Language codes with a translation table, for diagnostics and tests.
  static var availableLanguages: [String] {
    Bundle.module.localizations.sorted()
  }
}

/// Looks up a format string and fills it in.
///
/// Interpolated text ("Set up this \(model) to ...") cannot be a key, because
/// the key would change with the value. The table stores a format instead
/// ("Set up this %@ to ...") so a translation can move the placeholder to
/// wherever its grammar needs it.
func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
  String(format: AirPortLocalization.text(key), arguments: arguments)
}

/// Shorthand for ``AirPortLocalization/text(_:)`` inside this module.
func localized(_ key: String, context: String? = nil) -> String {
  AirPortLocalization.text(key, context: context)
}
