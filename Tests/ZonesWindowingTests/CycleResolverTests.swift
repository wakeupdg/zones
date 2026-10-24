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
}
