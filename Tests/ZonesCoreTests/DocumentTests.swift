import CoreGraphics
import Foundation
import Testing
import ZonesCore

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
