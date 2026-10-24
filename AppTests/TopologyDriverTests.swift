import CoreGraphics
import Foundation
import Testing
import ZonesCore
import ZonesLayout
import ZonesTestSupport
import ZonesWindowing

@testable import Zones

@MainActor
@Suite struct TopologyDriverTests {
  @Test func rawChangeDebouncesThenResizesPanels() async {
    let h = Harness()
    let root = h.makeRoot()
    h.displays.enqueue(.snapshot(Fixtures.threeDisplays))

    root.topology.receive(.reconfiguration)
    #expect(h.clock.pending == [.topologyDebounce])
    #expect(h.displays.calls.isEmpty)  // not read until the debounce fires

    // A burst re-arms one timer rather than stacking.
    root.topology.receive(.screenParameters)
    #expect(h.clock.pending == [.topologyDebounce])

    h.clock.fire(.topologyDebounce)
    await waitUntil { !h.overlay.calls.isEmpty }
    #expect(h.displays.calls == [.snapshot])
    #expect(h.overlay.calls == [.resize(Fixtures.threeDisplays)])
    #expect(root.topology.snapshot == Fixtures.threeDisplays)
    #expect(h.clock.pending.isEmpty)
    // No window moved: the window system was never touched (ADR-0014).
    #expect(h.windows.calls.isEmpty)
  }

  @Test func unchangedSnapshotResizesNothing() {
    let h = Harness()
    let root = h.makeRoot()
    h.displays.enqueue(.snapshot(Fixtures.threeDisplays))
    root.topology.forceSnapshot()
    root.topology.receive(.reconfiguration)
    root.topology.timerFired(.topologyDebounce)
    #expect(h.overlay.calls == [.resize(Fixtures.threeDisplays)])  // only the first commit
  }

  @Test func committedChangeReachesTheDragSession() async {
    let w = DragWorld()
    // Arm a session, then unplug the portrait Display: the overlay is re-shown from the new snapshot.
    w.h.enumerator.enqueue(.candidates([w.ref]))
    await w.root.drag.handle(w.event(.leftDown, CGPoint(x: 200, y: 200)))
    await w.root.drag.handle(w.event(.leftDragged, CGPoint(x: 205, y: 205)))
    _ = w.scriptMove()
    await w.root.drag.handle(.tick)
    guard case .armed = w.root.drag.state else {
      Issue.record("expected armed")
      return
    }
    var smaller = w.topology
    smaller.displays.removeLast()
    w.h.displays.enqueue(.snapshot(smaller))
    w.root.topology.receive(.reconfiguration)
    w.root.topology.timerFired(.topologyDebounce)
    // The change was posted to the drag inbox; the loop is not running in this test, so deliver it by hand.
    await w.root.drag.handle(.topology(smaller))
    guard case .armed(_, _, _, _, let context, _, _, _) = w.root.drag.state else {
      Issue.record("expected still armed")
      return
    }
    #expect(context.topology == smaller)
    let shows = w.h.overlay.calls.filter { if case .show = $0 { true } else { false } }
    #expect(shows.count == 2)
  }

  @Test func pickPersistsAssignmentForKnownDisplay() {
    let h = Harness()
    let root = h.makeRoot()
    h.displays.enqueue(.snapshot(Fixtures.threeDisplays))
    root.topology.forceSnapshot()
    let key = Fixtures.threeDisplays.displays[1].key
    let layout = Templates.builtInID(.columns, count: 3)
    root.topology.pick(layout, for: key)
    guard case .uuid(let uuid) = key else { return }
    #expect(root.state.assignments[uuid]?.layout == layout)
    // The assignment is on disk.
    #expect(h.files.files.keys.contains { $0.lastPathComponent == "assignments.json" })
  }
}
