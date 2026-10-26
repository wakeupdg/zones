import ApplicationServices
import CoreGraphics
import Foundation
import Testing
import ZonesCore
import ZonesLayout
import ZonesTestSupport
import ZonesWindowing

@testable import Zones

@MainActor
@Suite struct ShortcutDriverTests {
  private static func droppedCount() -> Int {
    Log.shared.ring().events.filter { $0.message.hasPrefix("shortcut dropped") }.count
  }

  @Test func pressWhileDraggingDropped() async {
    let w = DragWorld()
    let root = w.root
    let before = Self.droppedCount()

    // A Drag Session is live: the mouse is down on a window.
    w.h.enumerator.enqueue(.candidates([w.ref]))
    await root.drag.handle(w.event(.leftDown, CGPoint(x: 200, y: 200)))
    #expect(!root.drag.isIdle)
    await root.shortcuts.press(.sendToZone(1))
    #expect(w.h.windows.calls.isEmpty)
    #expect(Self.droppedCount() == before + 1)

    // The Settings shortcut is not a window command and passes even mid-drag.
    await root.shortcuts.press(.openSettings)
    #expect(w.h.uiLog.withLock { $0 } == ["settings"])
    #expect(w.h.windows.calls.isEmpty)
  }

  @Test func idlePressResolvesAndSnaps() async throws {
    let w = DragWorld()
    let root = w.root
    let primary = Fixtures.threeDisplays.displays[0]
    let layout = try #require(root.state.resolvedLayouts(for: w.topology, session: [:])[primary.key])
    let target = layout.zones[0].frame
    let current = CGRect(x: 100, y: 100, width: 600, height: 400)

    w.h.windows.enqueue(.focused(w.handle))
    w.h.windows.enqueue(.frame(.value(current)))  // the focused-window read
    w.h.windows.enqueue(.facts(.value(DragWorld.standard)))
    w.h.windows.enqueue(.frame(.value(current)))  // SnapService's pre-write read
    w.h.windows.enqueue(.frame(.value(target)))  // the read-back
    await root.shortcuts.press(.sendToZone(1))

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
    // The keyboard path captures the pre-write frame as the Original Frame (ADR-0009).
    #expect(await root.worker.registry.entry(w.handle.key)?.frame == current)
    #expect(await root.worker.registry.entry(w.handle.key)?.via == .keyboard)
  }

  @Test func noFocusedWindowIsANoOp() async {
    let w = DragWorld()
    await w.root.shortcuts.press(.sendToZone(2))
    let writes = w.h.windows.calls.filter {
      switch $0 {
      case .setPosition, .setSize: true
      default: false
      }
    }
    #expect(writes.isEmpty)
  }

  @Test func launchRegistersOnlyAppActionsUntilGranted() {
    let h = Harness()
    let root = h.makeRoot()
    root.shortcuts.receive(.launch)
    let registered = h.hotkeys.calls.compactMap { call -> ShortcutAction? in
      if case .register(_, let action) = call { action } else { nil }
    }
    #expect(Set(registered) == [.openEditor, .openSettings])

    root.shortcuts.receive(.permission(granted: true))
    let all = h.hotkeys.calls.compactMap { call -> ShortcutAction? in
      if case .register(_, let action) = call { action } else { nil }
    }
    #expect(Set(all) == Set(ShortcutAction.allCases))

    root.shortcuts.receive(.permission(granted: false))
    #expect(h.hotkeys.calls.contains(.unregister(.restore)))
    #expect(!h.hotkeys.calls.contains(.unregister(.openSettings)))
  }

  @Test func changedChordIsPersisted() {
    let h = Harness()
    let root = h.makeRoot()
    root.shortcuts.receive(.launch)
    let chord = Chord(key: .letter("K"), modifiers: [.command, .option])
    root.shortcuts.receive(.set(.openEditor, chord))
    #expect(root.state.preferences.shortcuts.first { $0.action == .openEditor }?.chord == chord)
    #expect(h.preferences.load() != nil)
  }
}
