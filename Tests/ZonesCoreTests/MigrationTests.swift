import Foundation
import Testing
import ZonesTestSupport
@testable import ZonesCore

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

  @Test func migrationWritesBackupFirst() throws {
    let directory = URL(fileURLWithPath: "/virtual/Zones")
    let target = directory.appending(path: "layouts.json")
    let original = try TestFixtures.data("layouts.v1.json")
    let fs = LocalFakeFileSystem(files: [target: original])
    let steps: [Int: Migrator.Step] = [1: { _ in }]
    let store = DocumentStore(
      fs: fs, directory: directory, clock: FakeClock(), currentVersion: 2, steps: steps,
      wallClock: { 1_792_861_320 })

    let result = store.load(.layouts)
    var expected = TestFixtures.layoutsDocument
    expected.version = 2
    #expect(result == .migrated(expected, from: 1, backup: "layouts.20261024-170200.bak"))

    let backup = directory.appending(path: "layouts.20261024-170200.bak")
    #expect(fs.contents(backup) == original)
    let (onDisk, _) = try Migrator.migrate(
      try #require(fs.contents(target)), current: 2, steps: steps
    ).get()
    #expect(onDisk == expected)
    #expect(try #require(fs.contents(target)) != original)
    #expect(fs.writeLog == [backup, target])
    #expect(store.backupName(.layouts, now: 0) == "layouts.19700101-000000.bak")
  }
}
