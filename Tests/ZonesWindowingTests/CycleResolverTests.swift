import CoreGraphics
import Foundation
import Testing
import ZonesCore
import ZonesLayout

@testable import ZonesWindowing

@Suite struct CycleResolverTests {
  struct NextCase: Sendable, CustomTestStringConvertible {
    var base: Int?
    var direction: CycleDirection
    var count: Int
    var span: Set<Int>?
    var expected: Int
    var testDescription: String {
      "base=\(base.map(String.init) ?? "nil") \(direction) count=\(count) span=\(span.map { "\($0.sorted())" } ?? "nil") -> \(expected)"
    }
  }

  static let nextCases: [NextCase] = {
    var cases: [NextCase] = []
    // No span, base 1...4 on 4 Zones, both directions, with wrap.
    for base in 1...4 {
      cases.append(NextCase(base: base, direction: .right, count: 4, span: nil, expected: base % 4 + 1))
      cases.append(NextCase(base: base, direction: .left, count: 4, span: nil, expected: (base + 2) % 4 + 1))
    }
    // No base: Right starts at 1, Left at the last Zone.
    cases.append(NextCase(base: nil, direction: .right, count: 4, span: nil, expected: 1))
    cases.append(NextCase(base: nil, direction: .left, count: 4, span: nil, expected: 4))
    // Span {1, 2}: Right continues after the highest, Left wraps before the lowest.
    cases.append(NextCase(base: 1, direction: .right, count: 4, span: [1, 2], expected: 3))
    cases.append(NextCase(base: 1, direction: .left, count: 4, span: [1, 2], expected: 4))
    // Span {4, 5} on 5 Zones.
    cases.append(NextCase(base: 4, direction: .right, count: 5, span: [4, 5], expected: 1))
    cases.append(NextCase(base: 4, direction: .left, count: 5, span: [4, 5], expected: 3))
    // One Zone: always 1.
    cases.append(NextCase(base: 1, direction: .right, count: 1, span: nil, expected: 1))
    cases.append(NextCase(base: 1, direction: .left, count: 1, span: nil, expected: 1))
    return cases
  }()

  @Test("table step A: next", arguments: nextCases)
  func table(_ c: NextCase) {
    #expect(CycleResolver.next(from: c.base, direction: c.direction, count: c.count, span: c.span) == c.expected)
  }

  // MARK: step B: the last-Snap record match

  static let columns4 = ShortcutFixtures.resolved(.columns, count: 4)

  static func record(
    zones: Set<Int>, frame: CGRect, display: DisplayKey = ShortcutFixtures.displayA
  ) -> LastSnapRecord {
    LastSnapRecord(key: ShortcutFixtures.key, display: display, zones: zones, frame: frame)
  }

  struct MatchCase: Sendable, CustomTestStringConvertible {
    var name: String
    var last: LastSnapRecord
    var frame: CGRect
    var matches: Bool
    var testDescription: String { name }
  }

  static let matchCases: [MatchCase] = {
    let z3 = columns4.zones[2].frame
    let rec = record(zones: [3], frame: z3)
    return [
      MatchCase(name: "dx 0", last: rec, frame: z3, matches: true),
      MatchCase(name: "dx 2.0 matches", last: rec, frame: z3.offsetBy(dx: 2.0, dy: 0), matches: true),
      MatchCase(name: "dx 2.5 does not", last: rec, frame: z3.offsetBy(dx: 2.5, dy: 0), matches: false),
      MatchCase(name: "dy 2.5 does not", last: rec, frame: z3.offsetBy(dx: 0, dy: 2.5), matches: false),
      MatchCase(
        name: "width off by 2.5 does not", last: rec,
        frame: CGRect(x: z3.minX, y: z3.minY, width: z3.width + 2.5, height: z3.height), matches: false),
      MatchCase(
        name: "another display", last: record(zones: [3], frame: z3, display: ShortcutFixtures.displayB), frame: z3,
        matches: false),
      MatchCase(name: "zone beyond count", last: record(zones: [5], frame: z3), frame: z3, matches: false),
      MatchCase(name: "zone 0", last: record(zones: [0], frame: z3), frame: z3, matches: false),
    ]
  }()

  @Test("table step B: matchedRecord tolerance", arguments: matchCases)
  func tableRecordMatch(_ c: MatchCase) {
    let got = CycleResolver.matchedRecord(c.last, frame: c.frame, layout: Self.columns4)
    #expect((got != nil) == c.matches)
    #expect(CycleResolver.matchedRecord(nil, frame: c.frame, layout: Self.columns4) == nil)
  }

  @Test("table step B: Calculator clamped at Zone 3 cycles Right to 4") func tableCalculatorClamped() {
    let z3 = Self.columns4.zones[2].frame
    // The app clamped the write: a smaller frame at Zone 3's origin, not Zone 3's rectangle.
    let clamped = CGRect(x: z3.minX, y: z3.minY, width: 300, height: 400)
    #expect(clamped != z3)
    let last = Self.record(zones: [3], frame: clamped)
    let base = CycleResolver.base(last, frame: clamped, layout: Self.columns4)
    #expect(base == 3)
    #expect(CycleResolver.next(from: base, direction: .right, count: 4, span: nil) == 4)
  }

  @Test("table step B: a Span record continues after its highest or before its lowest") func tableSpanRecord() {
    let z1 = Self.columns4.zones[0].frame, z2 = Self.columns4.zones[1].frame
    let union = z1.union(z2)
    let last = Self.record(zones: [1, 2], frame: union)
    let matched = CycleResolver.matchedRecord(last, frame: union, layout: Self.columns4)
    #expect(matched == last)
    let base = CycleResolver.base(last, frame: union, layout: Self.columns4)
    #expect(base == 1)
    let span = matched?.zones
    #expect(CycleResolver.next(from: base, direction: .right, count: 4, span: span) == 3)
    #expect(CycleResolver.next(from: base, direction: .left, count: 4, span: span) == 4)
  }

  // MARK: step C: max intersection

  @Test("table step C: hand move falls back to the Zone of maximum intersection") func tableMaxIntersection() {
    let layout = Self.columns4
    let z = layout.zones.map(\.frame)
    // A stale record (the window moved by hand): base is the Zone with the most overlap.
    let stale = Self.record(zones: [1], frame: z[0])
    #expect(CycleResolver.base(stale, frame: z[2], layout: layout) == 3)
    #expect(CycleResolver.base(nil, frame: z[3], layout: layout) == 4)
    // Mostly in Zone 2, a little in Zone 3.
    let mostlyTwo = CGRect(x: z[1].minX + 100, y: z[1].minY + 50, width: z[1].width, height: 300)
    #expect(CycleResolver.base(nil, frame: mostlyTwo, layout: layout) == 2)
  }

  @Test("table step C: a tie goes to the lower number") func tableTie() {
    let layout = Self.columns4
    let z1 = layout.zones[0].frame, z2 = layout.zones[1].frame
    // Centered on the Zone 1 / Zone 2 boundary: equal area in each.
    let straddle = CGRect(x: z1.maxX - 100, y: z1.minY + 100, width: 200, height: 300)
    #expect(z1.maxX == z2.minX)
    #expect(CycleResolver.base(nil, frame: straddle, layout: layout) == 1)
  }

  @Test("table step C: no intersection gives nil, Right starts at 1 and Left at the last Zone") func tableNoIntersection() {
    let layout = Self.columns4
    let outside = CGRect(x: 5000, y: 5000, width: 200, height: 200)
    let base = CycleResolver.base(nil, frame: outside, layout: layout)
    #expect(base == nil)
    #expect(CycleResolver.next(from: base, direction: .right, count: 4, span: nil) == 1)
    #expect(CycleResolver.next(from: base, direction: .left, count: 4, span: nil) == 4)
  }
}
