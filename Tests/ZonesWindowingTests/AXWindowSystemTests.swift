import Foundation
import Testing
import ZonesCore

@testable import ZonesWindowing

@Suite struct AXWindowSystemTests {
  @Test @WindowActor func conformsAndTimeoutsDoNotCrash() {
    let system: any WindowSystem = AXWindowSystem()
    system.setTimeouts(perApp: Constants.perAppTimeout, processWide: Constants.processTimeout)
    let status = system.trivialRead()
    // CI may run untrusted, so any of these is acceptable; the call must not crash or hang.
    switch status {
    case .ok, .apiDisabled, .timedOut: break
    case .elementGone, .refused: Issue.record("unexpected trivialRead result \(status)")
    }
  }

  /// T64: a timeout ends the hit-test climb at once. A hung app costs one timed-out read, not eight, and no
  /// fallback enumeration follows.
  @Test func climbStopsAtTheFirstTimeout() {
    func run(role: (Int) -> (code: Int32, role: String?), up: (Int) -> (code: Int32, element: Int?)) -> (
      Climb<Int>, Int
    ) {
      var calls = 0
      let climb = Climb.run(
        from: 0, steps: 8, isChrome: { $0 == "AXMenuBar" },
        role: {
          calls += 1
          return role($0)
        },
        up: {
          calls += 1
          return up($0)
        })
      return (climb, calls)
    }
    func name(_ climb: Climb<Int>) -> String {
      switch climb {
      case .window(let element): "window(\(element))"
      case .chrome: "chrome"
      case .lost: "lost"
      case .timedOut: "timedOut"
      }
    }
    let timeout = AXCode.cannotComplete
    let hungRole = run(role: { _ in (timeout, nil) }, up: { (0, $0 + 1) })
    #expect(name(hungRole.0) == "timedOut")
    #expect(hungRole.1 == 1)
    let hungUp = run(role: { _ in (0, "AXGroup") }, up: { _ in (timeout, nil) })
    #expect(name(hungUp.0) == "timedOut")
    #expect(hungUp.1 == 2)

    // Unchanged without a timeout: the window two levels up, menu-bar chrome, and a dead end.
    #expect(name(run(role: { $0 == 2 ? (0, "AXWindow") : (0, "AXGroup") }, up: { (0, $0 + 1) }).0) == "window(2)")
    #expect(name(run(role: { _ in (0, "AXMenuBar") }, up: { (0, $0 + 1) }).0) == "chrome")
    #expect(name(run(role: { _ in (0, "AXGroup") }, up: { _ in (AXCode.noValue, nil) }).0) == "lost")
  }

  /// T64, ADR-0015: every function in `AXWindowSystem.swift` that calls an `AXUIElement…`/`AXObserver…` API is
  /// `@WindowActor`, itself or through its enclosing type. A source scan, because a missing annotation compiles.
  @Test func axHelpersRunOnWindowActor() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let url = root.appendingPathComponent("Sources/ZonesWindowing/Adapters/AXWindowSystem.swift")
    let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
    let axCall = /\bAX(UIElement|Observer)[A-Z]\w*\(/
    let declaration = /^\s*(@\w+\s+)*((public|private|fileprivate|internal|static|nonisolated)\s+)*func\s+(\w+)/
    let topLevelType = /^(@\w+\s+)*((public|private|fileprivate|internal|final)\s+)*(enum|struct|class|extension)\s/
    var offenders: [String] = []
    var scope = ""
    var current: (name: String, isolated: Bool, calls: Bool)?
    func close() {
      if let current, current.calls, !current.isolated { offenders.append(current.name) }
    }
    for (index, line) in lines.enumerated() {
      if line.firstMatch(of: topLevelType) != nil { scope = line }
      if let match = line.firstMatch(of: declaration) {
        close()
        let previous = index > 0 ? lines[index - 1] : ""
        let isolated =
          line.contains("@WindowActor") || previous.trimmingCharacters(in: .whitespaces) == "@WindowActor"
          || scope.contains("@WindowActor")
        current = (String(match.output.4), isolated, false)
      }
      if line.firstMatch(of: axCall) != nil, !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
        current?.calls = true
      }
    }
    close()
    #expect(offenders.isEmpty, "not @WindowActor: \(offenders)")
  }
}
