import CoreGraphics
import Testing
import ZonesCore
import ZonesTestSupport
import ZonesWindowing

/// T63: every way a sampled press ends without an Overlay leaves one log line, so a drag that shows no Overlay can
/// be diagnosed from the unified log. A plain click (no `dragged`) stays silent.
@Suite struct DragExitLogTests {
  typealias F = DragFixtures

  private static func sampling(flags: ModifierSet = .shift, candidates: [WindowRef] = [F.window]) -> DragState {
    let (down, _) = DragSessionReducer.reduce(.idle, F.mouseDown(flags: flags, candidates: candidates))
    return DragSessionReducer.reduce(down, F.dragged()).0
  }

  @Test func mouseUpBeforeAnyMoveIsLogged() {
    let (state, fx) = DragSessionReducer.reduce(Self.sampling(), .mouseUp(point: F.downPoint, flags: .shift))
    #expect(state == .idle)
    #expect(fx == [.stopSampling, .log("drag: mouse-up before the window moved (1 candidate)")])
  }

  @Test func windowGoneWhileSamplingIsLogged() {
    let (state, fx) = DragSessionReducer.reduce(Self.sampling(), .windowGone)
    #expect(state == .idle)
    #expect(fx == [.stopSampling, .log("drag: window gone before it moved")])
  }

  @Test func noAccessibilityMatchIsLogged() {
    let refs = [F.ref(1), F.ref(2)]
    let tick = DragEvent.frameSample([refs[0].id: .gone, refs[1].id: .gone])
    let (state, fx) = DragSessionReducer.reduce(Self.sampling(candidates: refs), tick)
    #expect(state == .idle)
    #expect(fx == [.stopSampling, .log("drag: no Accessibility window matches the 2 candidates")])
  }

  @Test func resizeIsLogged() {
    let f = F.downFrame
    let grown = CGRect(x: f.minX, y: f.minY, width: f.width + 40, height: f.height)
    let (state, fx) = DragSessionReducer.reduce(Self.sampling(), F.sample(grown))
    #expect(state == .idle)
    #expect(fx == [.stopSampling, .log("drag: window resized, not moved")])
  }

  @Test func clickWithoutDragStaysSilent() {
    let (down, _) = DragSessionReducer.reduce(.idle, F.mouseDown())
    let (state, fx) = DragSessionReducer.reduce(down, .mouseUp(point: F.downPoint, flags: []))
    #expect(state == .idle)
    #expect(fx.isEmpty)
  }

  @Test func candidateOverflowNamesTheCount() {
    let refs = (1...(Constants.candidateCap + 1)).map { F.ref(UInt32($0)) }
    let (state, fx) = DragSessionReducer.reduce(.idle, F.mouseDown(candidates: refs))
    #expect(state == .idle)
    #expect(
      fx == [
        .log("mouseDown: \(refs.count) candidate windows under the cursor (cap \(Constants.candidateCap))"),
        .skip(.ambiguousMatch, nil),
      ])
  }

  // The unified log line carries the app identity riding on the event, never window text (LI-003).
  @Test func unifiedLogLineNamesTheApp() {
    let skip = LogEvent(
      time: 0, category: .input, level: .info, message: "skip ambiguousMatch", bundleID: "com.google.GeminiMacOS",
      pid: 42)
    #expect(UnifiedLogSink.line(for: skip) == "skip ambiguousMatch bundle=com.google.GeminiMacOS pid=42")
    let plain = LogEvent(time: 0, category: .input, level: .info, message: "drag: window gone before it moved")
    #expect(UnifiedLogSink.line(for: plain) == "drag: window gone before it moved")
  }
}
