import Foundation
import Testing
import ZonesCore

@Suite struct MigrationTests {
  struct Golden: Sendable, CustomTestStringConvertible {
    var file: String
    var expected: ZonesDocument
    var testDescription: String { file }
  }

  /// One row per kind and version. A new document version adds rows for `*.v<N>.json`.
  static let goldens: [Golden] = {
    var rows: [Golden] = []
    for version in 1...Constants.documentVersion {
      let expectedLayouts = TestFixtures.layoutsDocument
      let expectedAssignments = TestFixtures.assignmentsDocument
      rows.append(Golden(file: "layouts.v\(version).json", expected: expectedLayouts))
      rows.append(Golden(file: "assignments.v\(version).json", expected: expectedAssignments))
    }
    return rows
  }()

  @Test(arguments: goldens)
  func goldenFixturesMigrate(golden: Golden) throws {
    let raw = try TestFixtures.data(golden.file)
    let (document, from) = try Migrator.migrate(raw).get()
    #expect(document == golden.expected)
    #expect(document.version == Constants.documentVersion)
    #expect(from >= 1 && from <= Constants.documentVersion)
  }
}
