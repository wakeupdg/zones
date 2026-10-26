import CoreGraphics
import Foundation
import Testing
@testable import ZonesCore
import ZonesTestSupport
import os

private let assignmentJSON = """
  {"layout":"builtin:priorityGrid:3","displayName":"Studio Display",
   "lastVisibleFrame":{"x":0,"y":0,"width":2560,"height":1415},"lastScale":2,
   "lastSeen":"2026-10-24T17:02:00Z"}
  """

private let layoutsJSON = """
  {"version":1,"layouts":[{"id":"37D8832A-2D66-02CA-B9F7-8F30A301B230","name":"Desk",
   "surround":{"top":0,"left":0,"bottom":0,"right":0},"insets":{"margin":8,"gap":8},
   "root":{"kind":"split","axis":"horizontal","ratio":0.5,"first":{"kind":"leaf"},
   "second":{"kind":"split","axis":"vertical","ratio":0.5,"first":{"kind":"leaf"},"second":{"kind":"leaf"}}}}]}
  """

@Test func assignmentJSONUsesFlatRect() throws {
  let a = try JSONDecoder().decode(Assignment.self, from: Data(assignmentJSON.utf8))
  #expect(a.layout == LayoutID(rawValue: "builtin:priorityGrid:3"))
  #expect(a.displayName == "Studio Display")
  #expect(a.lastVisibleFrame == CGRect(x: 0, y: 0, width: 2560, height: 1415))
  #expect(a.lastScale == 2)
  #expect(a.lastSeen == Date(timeIntervalSince1970: 1_792_861_320))

  let data = try JSONEncoder().encode(a)
  let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  let frame = try #require(object["lastVisibleFrame"] as? [String: Double])
  #expect(frame == ["x": 0, "y": 0, "width": 2560, "height": 1415])
  #expect(object["lastSeen"] as? String == "2026-10-24T17:02:00Z")

  var unseen = a
  unseen.lastSeen = nil
  let unseenObject = try #require(
    JSONSerialization.jsonObject(with: JSONEncoder().encode(unseen)) as? [String: Any])
  #expect(unseenObject["lastSeen"] == nil)
  #expect(try JSONDecoder().decode(Assignment.self, from: JSONEncoder().encode(unseen)) == unseen)
}

@Test func zonesDocumentRoundTripBothArrays() throws {
  let assignment = try JSONDecoder().decode(Assignment.self, from: Data(assignmentJSON.utf8))
  var doc = try JSONDecoder().decode(ZonesDocument.self, from: Data(layoutsJSON.utf8))
  #expect(doc.version == 1)
  #expect(doc.layouts.count == 1)
  #expect(doc.layouts[0].name == "Desk")
  #expect(doc.assignments.isEmpty)

  let keys = try #require(
    JSONSerialization.jsonObject(with: JSONEncoder().encode(doc)) as? [String: Any])
  #expect(Set(keys.keys) == ["version", "layouts", "assignments"])

  doc.assignments["37D8832A-2D66-02CA-B9F7-8F30A301B230"] = assignment
  let back = try JSONDecoder().decode(ZonesDocument.self, from: JSONEncoder().encode(doc))
  #expect(back == doc)

  let onlyAssignments = #"{"version":1,"assignments":{}}"#
  let decoded = try JSONDecoder().decode(ZonesDocument.self, from: Data(onlyAssignments.utf8))
  #expect(decoded.layouts.isEmpty)
}

@Test func topologyTypesConstruct() {
  let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
  let key = DisplayKey.uuid("37D8832A-2D66-02CA-B9F7-8F30A301B230")
  #expect(key != DisplayKey.unstable("37D8832A-2D66-02CA-B9F7-8F30A301B230"))
  let display = DisplaySnapshot(
    key: key, frame: frame, visibleFrame: frame, scale: 1, isMain: true, mirrorOf: nil,
    name: "Built-in", resolution: CGSize(width: 1920, height: 1080))
  let topology = TopologySnapshot(displays: [display], separateSpaces: true, primaryFrame: frame)
  #expect(topology.displays == [display])
  #expect(PersistentDisplayKey(uuid: "abc").uuid == "abc")

  let ref = WindowRef(
    id: WindowID(rawValue: 7), pid: 42, bundleID: "com.example.app", frame: frame, layer: 0)
  let facts = WindowFacts(
    subrole: .standard, isFullScreen: false, positionSettable: true, sizeSettable: true)
  let wkey = WindowKey(pid: 42, elementHash: 99)
  let entry = OriginalFrameEntry(key: wkey, frame: frame, via: .mouse)
  let snap = LastSnapRecord(key: wkey, display: key, zones: [1, 2], frame: frame)
  #expect(Set([ref, ref]).count == 1)
  #expect(facts.subrole == .standard)
  #expect(entry.via == .mouse && CapturePath.keyboard != entry.via)
  #expect(snap.zones == [1, 2])

  let zone = Zone(number: 1, path: NodePath(steps: []), frame: frame)
  let resolved = ResolvedLayout(
    layoutID: LayoutID(rawValue: "builtin:focus:1"), display: key, visibleFrame: frame,
    layoutRect: frame, scale: 1, zones: [zone])
  #expect(resolved.zones == [zone])
}

@Suite struct DocumentTests {
  private func topLevel(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  @Test func codecFieldNames() throws {
    // layouts.json
    let layoutsBytes = try TestFixtures.data("layouts.v1.json")
    let layouts = try JSONDecoder().decode(ZonesDocument.self, from: layoutsBytes)
    #expect(layouts == TestFixtures.layoutsDocument)
    let layoutsOut = try layouts.encoded(for: .layouts)
    let layoutsObject = try topLevel(layoutsOut)
    #expect(Set(layoutsObject.keys) == ["version", "layouts"])
    let list = try #require(layoutsObject["layouts"] as? [[String: Any]])
    let root = try #require(list[0]["root"] as? [String: Any])
    #expect(root["kind"] as? String == "split")
    #expect(Set(root.keys) == ["kind", "axis", "ratio", "first", "second"])
    let leaf = try #require(root["first"] as? [String: Any])
    #expect(leaf as NSDictionary == ["kind": "leaf"] as NSDictionary)
    #expect(Set(list[0].keys) == ["id", "name", "surround", "insets", "root"])

    // assignments.json
    let assignmentBytes = try TestFixtures.data("assignments.v1.json")
    let assignments = try JSONDecoder().decode(ZonesDocument.self, from: assignmentBytes)
    #expect(assignments == TestFixtures.assignmentsDocument)
    let assignmentsOut = try assignments.encoded(for: .assignments)
    let assignmentsObject = try topLevel(assignmentsOut)
    #expect(Set(assignmentsObject.keys) == ["version", "assignments"])
    let map = try #require(assignmentsObject["assignments"] as? [String: [String: Any]])
    let frame = try #require(map[TestFixtures.studioKey]?["lastVisibleFrame"] as? [String: Double])
    #expect(frame["x"] == 0)
    #expect(Set(frame.keys) == ["x", "y", "width", "height"])
    #expect(map[TestFixtures.studioKey]?["lastSeen"] as? String == "2026-10-24T17:02:00Z")

    // bytes are stable on a second encode
    let again = try JSONDecoder().decode(ZonesDocument.self, from: layoutsOut)
    #expect(try again.encoded(for: .layouts) == layoutsOut)
    let againAssignments = try JSONDecoder().decode(ZonesDocument.self, from: assignmentsOut)
    #expect(try againAssignments.encoded(for: .assignments) == assignmentsOut)
  }

  @Test func rejectsNonUUIDKey() throws {
    for bad in ["unstable:3", "nil:7", "abc", ""] {
      let json = Data("[\"\(bad)\"]".utf8)
      #expect(throws: DocumentError.nonUUIDKey(bad)) {
        _ = try JSONDecoder().decode([PersistentDisplayKey].self, from: json)
      }
    }
    let upper = "37D8832A-2D66-02CA-B9F7-8F30A301B230"
    let ok = try JSONDecoder().decode([PersistentDisplayKey].self, from: Data("[\"\(upper)\"]".utf8))
    #expect(ok == [PersistentDisplayKey(uuid: upper)])
    let lower = upper.lowercased()
    let okLower = try JSONDecoder().decode([PersistentDisplayKey].self, from: Data("[\"\(lower)\"]".utf8))
    #expect(okLower == [PersistentDisplayKey(uuid: lower)])
    let back = try JSONDecoder().decode(
      [PersistentDisplayKey].self, from: JSONEncoder().encode(ok))
    #expect(back == ok)

    // The same rule guards the keys of a decoded assignments document.
    let doc = #"{"version":1,"assignments":{"unstable:3":{"layout":"builtin:focus:1","displayName":"X","lastVisibleFrame":{"x":0,"y":0,"width":1,"height":1},"lastScale":1}}}"#
    #expect(throws: DocumentError.nonUUIDKey("unstable:3")) {
      _ = try JSONDecoder().decode(ZonesDocument.self, from: Data(doc.utf8))
    }
  }

  @Test func exportRoundTrip() throws {
    var both = TestFixtures.layoutsDocument
    both.assignments = TestFixtures.assignmentsDocument.assignments
    let single = ZonesDocument(version: Constants.documentVersion, layouts: [TestFixtures.centered])
    for original in [both, single] {
      let exported = try original.encoded(for: nil)
      let object = try #require(JSONSerialization.jsonObject(with: exported) as? [String: Any])
      #expect(object["version"] as? Int == Constants.documentVersion)
      #expect(object["layouts"] != nil && object["assignments"] != nil)
      let (decoded, from) = try Migrator.migrate(exported).get()
      #expect(decoded == original)
      #expect(from == Constants.documentVersion)
    }
  }

  private let directory = URL(fileURLWithPath: "/virtual/Zones")

  @Test func atomicWriteSurvivesFailure() throws {
    let fs = LocalFakeFileSystem()
    let store = DocumentStore(fs: fs, directory: directory, clock: FakeClock())
    let first = TestFixtures.layoutsDocument
    try store.save(first, as: .layouts)
    #expect(store.load(.layouts) == .loaded(first))

    fs.failAfterBytes = 10
    var second = first
    second.layouts.removeLast()
    do {
      try store.save(second, as: .layouts)
      Issue.record("save should have thrown")
    } catch {
      if case .io = error {} else { Issue.record("expected .io, got \(error)") }
    }
    #expect(store.load(.layouts) == .loaded(first))
    #expect(fs.paths == [directory.appending(path: "layouts.json")])
  }

  @Test func foundationFileSystemRoundTrip() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "zones-t10-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let fs = FoundationFileSystem()
    let url = root.appending(path: "nested/layouts.json")
    #expect(!fs.exists(url))
    try fs.writeAtomic(Data("one".utf8), to: url)
    #expect(fs.exists(url))
    try fs.writeAtomic(Data("two".utf8), to: url)
    #expect(try fs.read(url) == Data("two".utf8))
    let moved = root.appending(path: "nested/layouts.bak")
    try fs.move(url, to: moved)
    #expect(!fs.exists(url) && fs.exists(moved))
    try fs.remove(moved)
    #expect(!fs.exists(moved))
    #expect(throws: (any Error).self) { _ = try fs.read(moved) }
  }

  @Test func corruptFileQuarantined() throws {
    let fs = LocalFakeFileSystem()
    let sink = LocalArrayLogSink()
    let store = DocumentStore(
      fs: fs, directory: directory, clock: FakeClock(), wallClock: { 1_792_861_320 }, sink: sink)
    let target = directory.appending(path: "layouts.json")
    let garbage = Data([0x00, 0xFF, 0x7B, 0x22, 0x01])
    try fs.writeAtomic(garbage, to: target)

    let result = store.load(.layouts)
    #expect(result == .defaults(quarantined: "layouts.20261024-170200.corrupt"))
    #expect(!fs.exists(target))
    #expect(fs.contents(directory.appending(path: "layouts.20261024-170200.corrupt")) == garbage)
    #expect(sink.events.count == 1)
    #expect(sink.events.first?.level == .notice)
    #expect(sink.events.first?.category == .core)

    // A second load finds no file: the empty default, and no further event.
    #expect(store.load(.layouts) == .loaded(ZonesDocument()))
    #expect(sink.events.count == 1)
  }

  @Test func newerVersionRefusedAndUntouched() throws {
    let newer = Data(#"{"version":2,"layouts":[],"future":{"x":1}}"#.utf8)
    switch Migrator.migrate(newer) {
    case .success: Issue.record("a newer document must be refused")
    case .failure(let error):
      #expect(error == .newerVersion(found: 2, supported: 1))
      #expect(error.message.contains("2") && error.message.contains("1"))
    }

    let fs = LocalFakeFileSystem()
    let sink = LocalArrayLogSink()
    let store = DocumentStore(fs: fs, directory: directory, clock: FakeClock(), sink: sink)
    let target = directory.appending(path: "layouts.json")
    try fs.writeAtomic(newer, to: target)
    let writesBefore = fs.writeLog.count

    #expect(store.load(.layouts) == .newerLeftUntouched(version: 2))
    #expect(fs.contents(target) == newer)
    #expect(fs.moveLog.isEmpty)
    #expect(fs.paths == [target])
    #expect(sink.events.count == 1)
    #expect(sink.events.first?.category == .core)

    do {
      try store.save(TestFixtures.layoutsDocument, as: .layouts)
      Issue.record("save over a newer document must throw")
    } catch {
      #expect(error == .newerVersion(found: 2, supported: 1))
    }
    #expect(fs.writeLog.count == writesBefore)
    #expect(fs.contents(target) == newer)
  }
}

/// Collects events for assertions.
final class LocalArrayLogSink: LogSink, Sendable {
  private let storage = OSAllocatedUnfairLock(initialState: [LogEvent]())
  var events: [LogEvent] { storage.withLock { $0 } }
  func write(_ event: LogEvent) { storage.withLock { $0.append(event) } }
}
