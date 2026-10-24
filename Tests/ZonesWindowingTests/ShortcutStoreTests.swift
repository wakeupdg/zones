import Foundation
import Testing
import ZonesCore
import ZonesTestSupport

@testable import ZonesWindowing

@Suite struct ShortcutStoreTests {
  static let ctrlOpt: ModifierSet = [.control, .option]

  @Test func defaultsMatchADR() {
    let d = ShortcutRules.defaults
    let expected: [Shortcut] =
      [
        Shortcut(action: .sendToZone(1), chord: Chord(key: .digit(1), modifiers: [.control, .option])),
        Shortcut(action: .sendToZone(2), chord: Chord(key: .digit(2), modifiers: [.control, .option])),
        Shortcut(action: .sendToZone(3), chord: Chord(key: .digit(3), modifiers: [.control, .option])),
        Shortcut(action: .sendToZone(4), chord: Chord(key: .digit(4), modifiers: [.control, .option])),
        Shortcut(action: .sendToZone(5), chord: Chord(key: .digit(5), modifiers: [.control, .option])),
        Shortcut(action: .sendToZone(6), chord: Chord(key: .digit(6), modifiers: [.control, .option])),
        Shortcut(action: .sendToZone(7), chord: Chord(key: .digit(7), modifiers: [.control, .option])),
        Shortcut(action: .sendToZone(8), chord: Chord(key: .digit(8), modifiers: [.control, .option])),
        Shortcut(action: .sendToZone(9), chord: Chord(key: .digit(9), modifiers: [.control, .option])),
        Shortcut(action: .cycleRight, chord: Chord(key: .arrowRight, modifiers: [.control, .option])),
        Shortcut(action: .cycleLeft, chord: Chord(key: .arrowLeft, modifiers: [.control, .option])),
        Shortcut(action: .restore, chord: Chord(key: .letter("R"), modifiers: [.control, .option])),
        Shortcut(action: .openEditor, chord: Chord(key: .letter("E"), modifiers: [.control, .option])),
        Shortcut(action: .openSettings, chord: Chord(key: .comma, modifiers: [.control, .option])),
      ]
    #expect(d.count == 14)
    #expect(d == expected)
    #expect(d.map { $0.action } == ShortcutAction.allCases)
    #expect(d.allSatisfy { $0.chord != nil })
  }

  @Test func requiresCommandOrControl() {
    #expect(!ShortcutRules.validate(Chord(key: .digit(1), modifiers: [.option])))
    #expect(!ShortcutRules.validate(Chord(key: .digit(1), modifiers: [.shift, .option])))
    #expect(!ShortcutRules.validate(Chord(key: .digit(1), modifiers: [.shift])))
    #expect(!ShortcutRules.validate(Chord(key: .digit(1), modifiers: [])))
    #expect(ShortcutRules.validate(Chord(key: .digit(1), modifiers: [.control, .option])))
    #expect(ShortcutRules.validate(Chord(key: .digit(1), modifiers: [.command])))
    #expect(ShortcutRules.validate(Chord(key: .digit(1), modifiers: [.control])))
    #expect(ShortcutRules.validate(Chord(key: .digit(1), modifiers: [.command, .option])))
  }

  @Test func recorderStateTable() {
    let bound = ShortcutRules.defaults
    func chord(_ key: Key, _ m: ModifierSet) -> Chord { Chord(key: key, modifiers: m) }
    let table: [(Chord, ShortcutAction, RecorderState)] = [
      // Duplicate of another action's chord.
      (chord(.digit(2), Self.ctrlOpt), .sendToZone(1), .conflict(duplicate: .sendToZone(2))),
      (chord(.letter("E"), Self.ctrlOpt), .restore, .conflict(duplicate: .openEditor)),
      // Own chord is never a conflict.
      (chord(.digit(1), Self.ctrlOpt), .sendToZone(1), .accepted),
      // Rejected beats conflict.
      (chord(.digit(1), [.option]), .restore, .rejected),
      (chord(.digit(1), [.shift, .option]), .restore, .rejected),
      (chord(.letter("K"), []), .restore, .rejected),
      // Warnings.
      (chord(.letter("K"), [.command]), .restore, .warning(.commandOnly)),
      (chord(.letter("K"), [.command, .shift]), .restore, .warning(.commandShiftOnly)),
      (chord(.arrowRight, [.control]), .restore, .warning(.controlOnlyWithArrowOrDigit)),
      (chord(.arrowUp, [.control]), .restore, .warning(.controlOnlyWithArrowOrDigit)),
      (chord(.digit(3), [.control]), .restore, .warning(.controlOnlyWithArrowOrDigit)),
      // Accepted.
      (chord(.letter("K"), [.control]), .restore, .accepted),
      (chord(.comma, [.control]), .restore, .accepted),
      (chord(.digit(5), Self.ctrlOpt), .restore, .conflict(duplicate: .sendToZone(5))),
    ]
    for (c, action, expected) in table {
      #expect(ShortcutRules.recorderState(c, for: action, bound: bound) == expected)
    }
    // Control+Option+5 with nothing bound elsewhere is accepted (no warning).
    #expect(ShortcutRules.recorderState(chord(.digit(5), Self.ctrlOpt), for: .sendToZone(5), bound: bound) == .accepted)
    #expect(ShortcutRules.recorderState(chord(.digit(5), Self.ctrlOpt), for: .restore, bound: []) == .accepted)
    // First conflict in array order.
    let dup = [
      Shortcut(action: .cycleLeft, chord: chord(.letter("K"), [.control])),
      Shortcut(action: .cycleRight, chord: chord(.letter("K"), [.control])),
    ]
    #expect(
      ShortcutRules.recorderState(chord(.letter("K"), [.control]), for: .restore, bound: dup)
        == .conflict(duplicate: .cycleLeft))
  }

  @Test @MainActor func windowHotkeysOnlyWhileGranted() {
    let windowActions = ShortcutAction.allCases.filter { $0.isWindowAction }
    #expect(windowActions.count == 12)

    let h = StoreHarness()
    h.send(.launch)
    #expect(h.registrar.bound(.openEditor) != nil)
    #expect(h.registrar.bound(.openSettings) != nil)
    for a in windowActions { #expect(h.registrar.bound(a) == nil) }

    h.send(.permission(granted: true))
    for a in ShortcutAction.allCases { #expect(h.registrar.bound(a) != nil) }

    let before = h.mutations.count
    h.send(.permission(granted: false))
    let off = h.mutations.dropFirst(before)
    #expect(off.count == 12)
    #expect(Set(off) == Set(windowActions.map { FakeHotkeyRegistrar.Call.unregister($0) }))
    for a in windowActions { #expect(h.registrar.bound(a) == nil) }
    #expect(h.registrar.bound(.openEditor) != nil)
    #expect(h.registrar.bound(.openSettings) != nil)
    #expect(h.state.shortcuts == ShortcutRules.defaults)  // chords stay stored

    let steady = h.mutations.count
    h.send(.permission(granted: false))
    #expect(h.mutations.count == steady)
    h.send(.permission(granted: true))
    let afterOn = h.mutations.count
    #expect(afterOn - steady == 12)
    h.send(.permission(granted: true))
    #expect(h.mutations.count == afterOn)
  }

  @Test @MainActor func failureKeepsPreviousChord() {
    let h = StoreHarness()
    h.send(.launch)
    h.send(.permission(granted: true))
    let old = Chord(key: .letter("E"), modifiers: [.control, .option])
    let x = Chord(key: .letter("K"), modifiers: [.control, .option])
    #expect(h.registrar.bound(.openEditor) == old)
    let committed = h.state.shortcuts

    // Pure reducer: only a register effect; shortcuts untouched until the result arrives.
    let (pendingState, effects) = ShortcutStore.reduce(h.state, .set(.openEditor, x))
    #expect(effects == [.register(x, .openEditor)])
    #expect(pendingState.shortcuts == committed)

    let (failedState, failEffects) = ShortcutStore.reduce(pendingState, .registration(.openEditor, .inUse))
    #expect(failEffects == [.failed(.openEditor, .inUse)])
    #expect(failedState.shortcuts == committed)
    #expect(failedState.registered == h.state.registered)

    // End to end against the fake: the previous chord stays live.
    h.registrar.enqueue(.registration(.inUse))
    let all = h.send(.set(.openEditor, x))
    #expect(all == [.register(x, .openEditor), .failed(.openEditor, .inUse)])
    #expect(!all.contains { if case .persist = $0 { true } else { false } })
    #expect(h.state.shortcuts == committed)
    #expect(h.state.pending.isEmpty)
    #expect(h.registrar.bound(.openEditor) == old)

    // A later success commits and persists.
    let ok = h.send(.set(.openEditor, x))
    #expect(ok.contains(.persist(h.state.shortcuts)))
    #expect(h.state.chord(of: .openEditor) == x)
    #expect(h.registrar.bound(.openEditor) == x)
  }
}

/// Test-local driver: runs the reducer, executes effects on the fake registrar, and feeds each result back
/// as `.registration`.
@MainActor final class StoreHarness {
  var state: ShortcutStoreState
  let registrar = FakeHotkeyRegistrar(clock: FakeClock())
  /// Register and unregister calls only (reads of `bound` are not mutations).
  var mutations: [FakeHotkeyRegistrar.Call] {
    registrar.calls.filter { if case .bound = $0 { false } else { true } }
  }
  private(set) var allEffects: [ShortcutStoreEffect] = []

  init(_ state: ShortcutStoreState = ShortcutStoreState()) { self.state = state }

  /// Reduces `event`, applies the effects, and returns every effect emitted (including follow-ups).
  @discardableResult func send(_ event: ShortcutStoreEvent) -> [ShortcutStoreEffect] {
    let (next, effects) = ShortcutStore.reduce(state, event)
    state = next
    allEffects += effects
    return effects + apply(effects)
  }

  func apply(_ effects: [ShortcutStoreEffect]) -> [ShortcutStoreEffect] {
    var followUps: [ShortcutStoreEffect] = []
    for effect in effects {
      switch effect {
      case .register(let chord, let action):
        let result = registrar.register(chord, for: action)
        followUps += send(.registration(action, result))
      case .unregister(let action):
        registrar.unregister(action)
      case .failed, .persist:
        break
      }
    }
    return followUps
  }
}
