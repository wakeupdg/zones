import ApplicationServices
import CoreGraphics
import Foundation
import Testing
import ZonesCore
import ZonesLayout
import ZonesTestSupport
import ZonesWindowing
import os

@testable import Zones

/// Records, at the moment of each overlay hide, how many frame writes the window system had seen.
final class HideOrderSpy: OverlayPresenter, Sendable {
  let inner: FakeOverlayPresenter
  let windows: FakeWindowSystem
  let writesAtHide = OSAllocatedUnfairLock(initialState: [Int]())

  init(inner: FakeOverlayPresenter, windows: FakeWindowSystem) {
    self.inner = inner
    self.windows = windows
  }

  private func writes() -> Int {
    windows.calls.filter {
      switch $0 {
      case .setPosition, .setSize: true
      default: false
      }
    }.count
  }

  @MainActor func show(_ scene: OverlayScene) { inner.show(scene) }
  @MainActor func highlight(_ h: Highlight) { inner.highlight(h) }
  @MainActor func hide() {
    writesAtHide.withLock { $0.append(writes()) }
    inner.hide()
  }
  @MainActor func reassert() { inner.reassert() }
  @MainActor func orderOut() { inner.orderOut() }
  @MainActor func resize(to snapshot: TopologySnapshot) { inner.resize(to: snapshot) }
}

/// Three Displays, one window, the Priority Grid on every Display.
@MainActor
struct DragWorld {
  static let standard = WindowFacts(subrole: .standard, isFullScreen: false, positionSettable: true, sizeSettable: true)

  let h: Harness
  let root: CompositionRoot
  let ref: ZonesCore.WindowRef
  let handle: WindowHandle
  let topology = Fixtures.threeDisplays

  let spy: HideOrderSpy

  init(pid: pid_t = 500, frame: CGRect = CGRect(x: 100, y: 100, width: 600, height: 400)) {
    h = Harness()
    spy = HideOrderSpy(inner: h.overlay, windows: h.windows)
    h.overlayOverride = spy
    ref = ZonesCore.WindowRef(id: WindowID(rawValue: 77), pid: pid, bundleID: "com.example.editor", frame: frame, layer: 0)
    handle = WindowHandle(element: AXUIElementCreateApplication(pid), pid: pid)
    h.displays.enqueue(.snapshot(topology))
    root = h.makeRoot()
    root.topology.forceSnapshot()
  }

  var layouts: [DisplayKey: ResolvedLayout] {
    root.state.resolvedLayouts(for: topology, session: [:])
  }

  /// The center of zone `n` of the Display with `key`.
  func center(of n: Int, on key: DisplayKey) -> CGPoint {
    let frame = layouts[key]!.zones[n - 1].frame
    return CGPoint(x: frame.midX, y: frame.midY)
  }

  func event(_ kind: InputKind, _ point: CGPoint, _ flags: ModifierSet = [.shift]) -> DragDriver.Inbound {
    .input(InputEvent(kind: kind, point: point, flags: flags, windowUnderPointer: ref.id, time: 0))
  }

  /// Scripts the window system so the first tick resolves the handle and sees the window moved by 10 pt.
  func scriptMove(by delta: CGFloat = 10) -> CGRect {
    let moved = ref.frame.offsetBy(dx: delta, dy: delta)
    h.windows.enqueue(.windows([handle]))
    h.windows.enqueue(.frames([handle.key: .value(ref.frame)]))  // resolve
    h.windows.enqueue(.frames([handle.key: .value(moved)]))  // the sample
    h.windows.enqueue(.facts(.value(Self.standard)))
    return moved
  }
}

@MainActor
@Suite struct DragDriverTests {
  @Test func shiftDragSnapsOnFakeStack() async throws {
    let w = DragWorld()
    let root = w.root
    let spy = w.spy

    w.h.enumerator.enqueue(.candidates([w.ref]))
    await root.drag.handle(w.event(.leftDown, CGPoint(x: 200, y: 200)))
    await root.drag.handle(w.event(.leftDragged, CGPoint(x: 210, y: 210)))
    #expect(root.drag.state != .idle)

    let moved = w.scriptMove()
    await root.drag.handle(.tick)
    guard case .armed = root.drag.state else {
      Issue.record("expected armed, got \(root.drag.state)")
      return
    }

    // Drag onto zone 1 of the 2x Display (the left one) and drop there.
    let retina = DisplayKey.uuid("22222222-2222-4222-8222-222222222222")
    let layout = try #require(root.state.resolvedLayouts(for: w.topology, session: [:])[retina])
    let target = layout.zones[0].frame
    let drop = CGPoint(x: target.midX, y: target.midY)
    await root.drag.handle(w.event(.leftDragged, drop))
    w.h.windows.enqueue(.frame(.value(moved)))  // the pre-write read
    w.h.windows.enqueue(.frame(.value(target)))  // the read-back
    await root.drag.handle(w.event(.leftUp, drop))

    #expect(root.drag.state == .idle)
    let calls = w.h.overlay.calls
    #expect(calls.contains { if case .show = $0 { true } else { false } })
    #expect(calls.contains { if case .highlight = $0 { true } else { false } })
    #expect(calls.last == .hide)
    // The overlay was hidden before the first frame write (AC-053).
    #expect(spy.writesAtHide.withLock { $0 } == [0])
    // One Snap: size, position, size to the Zone, on the dragged window only (AC-041).
    let writes = w.h.windows.calls.filter {
      switch $0 {
      case .setPosition, .setSize: true
      default: false
      }
    }
    #expect(
      writes == [
        .setSize(target.size, w.handle), .setPosition(target.origin, w.handle), .setSize(target.size, w.handle),
      ])
    let entry = await root.worker.registry.entry(w.handle.key)
    #expect(entry?.frame == w.ref.frame)
  }
}
