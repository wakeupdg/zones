import Foundation

/// The single decoder for disk and export documents (ADR-0017). Sniffs `version`, runs the step chain
/// `n -> n+1` up to the current version, then decodes. Golden fixtures per version guard it (AC-152).
public enum Migrator {
  /// One migration step: rewrites a version-`n` JSON object into version `n + 1` (the version key is set by the chain).
  typealias Step = @Sendable (inout [String: Any]) throws -> Void

  /// Version-to-version steps keyed by the version they migrate from. Empty while the format is at version 1.
  static let steps: [Int: Step] = [:]

  public static func migrate(_ raw: Data) -> Result<(ZonesDocument, from: Int), DocumentError> {
    migrate(raw, current: Constants.documentVersion, steps: steps)
  }

  static func migrate(
    _ raw: Data, current: Int, steps: [Int: Step]
  ) -> Result<(ZonesDocument, from: Int), DocumentError> {
    guard var object = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] else {
      return .failure(.corrupt("document is not a JSON object"))
    }
    guard let found = sniffVersion(object), found >= 1 else {
      return .failure(.corrupt("document has no valid version"))
    }
    guard found <= current else { return .failure(.newerVersion(found: found, supported: current)) }
    do {
      var version = found
      while version < current {
        guard let step = steps[version] else {
          return .failure(.corrupt("no migration from version \(version)"))
        }
        try step(&object)
        version += 1
        object["version"] = version
      }
      let data = version == found ? raw : try JSONSerialization.data(withJSONObject: object)
      let document = try JSONDecoder().decode(ZonesDocument.self, from: data)
      return .success((document, from: found))
    } catch let error as DocumentError {
      return .failure(error)
    } catch {
      return .failure(.corrupt(String(describing: error)))
    }
  }

  /// Reads just the `version` key, without decoding the rest.
  static func sniffVersion(_ object: [String: Any]) -> Int? {
    guard let number = object["version"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
      return nil
    }
    let value = number.doubleValue
    guard value == value.rounded(), abs(value) < 1_000_000 else { return nil }
    return Int(value)
  }
}
