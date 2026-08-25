import Foundation

enum SetupProfileTemplates {
  enum TemplateError: LocalizedError {
    case missing(String)

    var errorDescription: String? {
      switch self {
      case .missing(let productID):
        "No setup profile template is available for product \(productID)."
      }
    }
  }

  static func tracedProductID(for productID: String, modelName: String = "") -> String {
    switch productID.trimmingCharacters(in: .whitespacesAndNewlines) {
    case "102", "107", "115": return "115"
    case "106", "109", "113", "116", "119": return "106"
    case "3", "104", "105", "108", "114", "117", "120": return "120"
    default:
      let modelName = modelName.lowercased()
      if modelName.contains("express") { return "115" }
      if modelName.contains("time capsule") { return "106" }
      return "120"
    }
  }

  static func load(productID: String, modelName: String = "") throws -> JSONValue {
    let tracedProductID = tracedProductID(for: productID, modelName: modelName)
    guard let url = resourceURL(
      name: "SetupProfile-\(tracedProductID)", extension: "json")
    else { throw TemplateError.missing(productID) }
    return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
  }

  static func loadLegacyExtreme() throws -> JSONValue {
    guard let url = resourceURL(name: "LegacySetupProfile-3", extension: "json")
    else { throw TemplateError.missing("3") }
    return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
  }

  private static func resourceURL(name: String, extension fileExtension: String) -> URL? {
    Bundle.main.url(forResource: name, withExtension: fileExtension)
      ?? Bundle.module.url(forResource: name, withExtension: fileExtension)
  }
}
