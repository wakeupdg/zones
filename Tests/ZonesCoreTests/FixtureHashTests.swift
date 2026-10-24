import CryptoKit
import Foundation
import Testing
import ZonesCore

/// Goldens never change after their hash is recorded. A format change adds a new `v<N+1>` golden and bumps
/// `Constants.documentVersion`; it never edits an old golden.
@Suite struct FixtureHashTests {
  static let hashes: [String: String] = [
    "layouts.v1.json": "1b3667bfc61dbd789c6ec81f4ab73f7d1a9f816d774b9ce2c7f348e44a996f65",
    "assignments.v1.json": "9db18430fdf4511bdaefc6a83b2fa95f6665df0564bde0b6f6b3a5cfff220e7f",
  ]

  private static func goldenFiles() throws -> [String] {
    let directory = TestFixtures.url("")
    return try FileManager.default.contentsOfDirectory(atPath: directory.path)
      .filter { $0.range(of: #"^[a-z]+\.v\d+\.json$"#, options: .regularExpression) != nil }
      .sorted()
  }

  @Test func goldensUnchanged() throws {
    let files = try Self.goldenFiles()
    #expect(Set(files) == Set(Self.hashes.keys), "every golden needs a recorded hash, and vice versa")
    for (name, expected) in Self.hashes {
      let digest = SHA256.hash(data: try TestFixtures.data(name))
      let actual = digest.map { String(format: "%02x", $0) }.joined()
      #expect(actual == expected, "\(name) changed; add a new version instead of editing a golden")
    }
  }

  @Test func highestFixtureMatchesDocumentVersion() throws {
    var highest: [String: Int] = [:]
    for file in try Self.goldenFiles() {
      let parts = file.split(separator: ".")
      let version = try #require(Int(parts[1].dropFirst()))
      highest[String(parts[0]), default: 0] = max(highest[String(parts[0]), default: 0], version)
    }
    #expect(Set(highest.keys) == ["layouts", "assignments"])
    for (kind, version) in highest {
      #expect(version == Constants.documentVersion, "\(kind): newest golden must match Constants.documentVersion")
    }
  }
}
