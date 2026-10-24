import Foundation
import Testing
import ZonesCore
import ZonesTestSupport

@testable import ZonesWindowing

@Suite(.serialized) struct ShortcutDispatchTests {
  /// `.shortcuts` events in the shared ring. Read from the ring (not a sink) because other suites install
  /// their own sinks on `Log.shared` while running in parallel.
  static func shortcutEvents() -> [LogEvent] { Log.shared.ring().events.filter { $0.category == .shortcuts } }

  @Test func droppedAndQueuedDuringSession() {
    let start = Self.shortcutEvents().count
    #expect(ShortcutDispatcher.dispatch(.restore, reducerIdle: false) == .failure(.notIdle))
    #expect(Self.shortcutEvents().count == start + 1)

    #expect(ShortcutDispatcher.dispatch(.restore, reducerIdle: true) == .success(.restore))
    #expect(ShortcutDispatcher.dispatch(.openEditor, reducerIdle: false) == .success(.openEditor))
    #expect(ShortcutDispatcher.dispatch(.openSettings, reducerIdle: false) == .success(.openSettings))
    #expect(Self.shortcutEvents().count == start + 1)

    // Queue half.
    let x = Chord(key: .letter("K"), modifiers: [.control, .option])
    let y = Chord(key: .letter("J"), modifiers: [.control, .option])
    var state = ShortcutStoreState(registered: Set(ShortcutAction.allCases), granted: true)
    var (next, effects) = ShortcutStore.reduce(state, .reducerIdle(false))
    state = next
    #expect(effects.isEmpty)
    #expect(!state.idle)
    (next, effects) = ShortcutStore.reduce(state, .set(.cycleRight, x))
    state = next
    #expect(effects.isEmpty)
    #expect(state.queued.count == 1)
    (next, effects) = ShortcutStore.reduce(state, .set(.cycleLeft, y))
    state = next
    #expect(effects.isEmpty)
    #expect(state.queued.count == 2)
    #expect(state.shortcuts == ShortcutRules.defaults)

    (next, effects) = ShortcutStore.reduce(state, .reducerIdle(true))
    state = next
    #expect(effects == [.register(x, .cycleRight), .register(y, .cycleLeft)])
    #expect(state.queued.isEmpty)
    #expect(state.idle)
  }
}
