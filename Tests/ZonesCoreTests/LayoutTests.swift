import Foundation
import Testing
import ZonesCore

private func jsonObject<T: Encodable>(_ value: T) throws -> Any {
  let encoder = JSONEncoder()
  let data = try encoder.encode(value)
  return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
}

private func parse(_ json: String) throws -> Any {
  try JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed])
}

private let sampleTreeJSON = """
  {"kind":"split","axis":"horizontal","ratio":0.5,
   "first":{"kind":"leaf"},
   "second":{"kind":"split","axis":"vertical","ratio":0.5,"first":{"kind":"leaf"},"second":{"kind":"leaf"}}}
  """

private let sampleTree = SplitNode.split(
  axis: .horizontal, ratio: 0.5, first: .leaf,
  second: .split(axis: .vertical, ratio: 0.5, first: .leaf, second: .leaf))

@Test func splitNodeJSONShape() throws {
  let leaf = try jsonObject(SplitNode.leaf) as? [String: Any]
  #expect(leaf?.count == 1)
  #expect(leaf?["kind"] as? String == "leaf")

  let encoded = try jsonObject(sampleTree) as? NSDictionary
  let expected = try parse(sampleTreeJSON) as? NSDictionary
  #expect(encoded == expected)

  let decoded = try JSONDecoder().decode(SplitNode.self, from: Data(sampleTreeJSON.utf8))
  #expect(decoded == sampleTree)
}

@Test func layoutIDEncodesAsBareString() throws {
  let id = LayoutID(rawValue: "builtin:priorityGrid:3")
  let data = try JSONEncoder().encode(id)
  #expect(String(decoding: data, as: UTF8.self) == "\"builtin:priorityGrid:3\"")
  let back = try JSONDecoder().decode(LayoutID.self, from: data)
  #expect(back == id)
}

@Test func layoutRoundTripOmitsBuiltIn() throws {
  let layout = Layout(
    id: LayoutID(rawValue: "builtin:columns:2"), name: "Columns 2",
    root: .split(axis: .horizontal, ratio: 0.5, first: .leaf, second: .leaf),
    surround: Surround(top: 0, left: 0, bottom: 0, right: 0),
    insets: Insets(margin: 8, gap: 8),
    builtIn: BuiltInRef(template: .columns, count: 2))
  let object = try #require(jsonObject(layout) as? [String: Any])
  #expect(object["builtIn"] == nil)
  #expect(Set(object.keys) == ["id", "name", "root", "surround", "insets"])
  #expect((object["id"] as? String) == "builtin:columns:2")
  let surround = try #require(object["surround"] as? [String: Double])
  #expect(Set(surround.keys) == ["top", "left", "bottom", "right"])
  let insets = try #require(object["insets"] as? [String: Double])
  #expect(insets == ["margin": 8, "gap": 8])

  let data = try JSONEncoder().encode(layout)
  let back = try JSONDecoder().decode(Layout.self, from: data)
  var expected = layout
  expected.builtIn = nil
  #expect(back == expected)
}

@Test func templateCountsMatchContract() {
  #expect(Template.columns.counts == [2, 3, 4, 5])
  #expect(Template.rows.counts == [2, 3, 4, 5])
  #expect(Template.grid.counts == [4, 9])
  #expect(Template.priorityGrid.counts == [3])
  #expect(Template.focus.counts == [1])
  #expect(Template.allCases.map(\.rawValue) == ["Columns", "Rows", "Grid", "Priority Grid", "Focus"])
}
