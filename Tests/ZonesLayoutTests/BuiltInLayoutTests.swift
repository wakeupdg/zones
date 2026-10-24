import Foundation
import Testing
import ZonesCore

@testable import ZonesLayout

struct BuiltInLayoutTests {
  private let insets = Insets(margin: 12, gap: 8)

  @Test func deterministicIdsAndDuplicate() throws {
    let first = Templates.all(insets: insets)
    let second = Templates.all(insets: insets)
    #expect(first.map(\.id) == second.map(\.id))
    #expect(first == second)
    #expect(first.count == 12)
    #expect(Set(first.map(\.id)).count == 12)
    #expect(first.map(\.id.rawValue) == [
      "builtin:columns:2", "builtin:columns:3", "builtin:columns:4", "builtin:columns:5",
      "builtin:rows:2", "builtin:rows:3", "builtin:rows:4", "builtin:rows:5",
      "builtin:grid:4", "builtin:grid:9", "builtin:priorityGrid:3", "builtin:focus:1",
    ])
    let pattern = try Regex("^builtin:(columns|rows|grid|priorityGrid|focus):[0-9]+$")
    for layout in first {
      #expect(layout.id.rawValue.wholeMatch(of: pattern) != nil, "\(layout.id.rawValue)")
      #expect(layout.builtIn != nil)
      #expect(layout.insets == insets)
      #expect(layout.id == Templates.builtInID(layout.builtIn!.template, count: layout.builtIn!.count))
    }
    #expect(Templates.builtInID(.priorityGrid, count: 3).rawValue == "builtin:priorityGrid:3")
    #expect(Templates.builtInID(.columns, count: 5).rawValue == "builtin:columns:5")
    #expect(Templates.builtInID(.focus, count: 1).rawValue == "builtin:focus:1")

    // Never persisted: a built-in encodes without a builtIn key, a duplicate carries no builtin id.
    let builtInText = String(decoding: try JSONEncoder().encode(first[9]), as: UTF8.self)
    #expect(!builtInText.contains("builtIn"))
    let original = Templates.generate(.grid, count: 9, insets: Insets(margin: 0, gap: 0))
    #expect(original.id == Templates.builtInID(.grid, count: 9))
    let newID = LayoutID(rawValue: UUID().uuidString)
    let copy = Templates.duplicate(original, insets: insets, newID: newID)
    #expect(copy.id == newID)
    #expect(copy.id != original.id)
    #expect(copy.name == "Grid copy")
    #expect(copy.builtIn == nil)
    #expect(copy.insets == Insets(margin: 12, gap: 8))
    #expect(copy.root == original.root)
    #expect(copy.surround == original.surround)
    let copyText = String(decoding: try JSONEncoder().encode(copy), as: UTF8.self)
    #expect(!copyText.contains("builtin:"))
    #expect(!copyText.contains("builtIn"))
  }
}
