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

  @Test @MainActor func clearedStaysUnbound() {
    let h = StoreHarness()
    h.send(.launch)
    h.send(.permission(granted: true))
    #expect(h.registrar.bound(.restore) != nil)
    let before = h.mutations.count

    let effects = h.send(.set(.restore, nil))
    #expect(effects == [.unregister(.restore), .persist(h.state.shortcuts)])
    let delta = h.mutations.dropFirst(before)
    #expect(Array(delta) == [.unregister(.restore)])
    #expect(h.registrar.bound(.restore) == nil)
    let stored = h.state.shortcuts.first { $0.action == .restore }
    #expect(stored != nil)
    #expect(stored?.chord == nil)  // cleared, not reverted to the default
    #expect(!h.state.registered.contains(.restore))

    // Clearing again emits nothing to unregister.
    let again = h.send(.set(.restore, nil))
    #expect(!again.contains(.unregister(.restore)))

    // Launch and permission off/on never register restore.
    let afterClear = h.mutations.count
    h.send(.launch)
    h.send(.permission(granted: false))
    h.send(.permission(granted: true))
    let later = h.mutations.dropFirst(afterClear)
    #expect(!later.contains { if case .register(_, .restore) = $0 { true } else { false } })
    #expect(h.registrar.bound(.restore) == nil)
  }

  @Test @MainActor func diffReregistersOnlyChanged() {
    let h = StoreHarness()
    h.send(.launch)
    h.send(.permission(granted: true))
    let before = h.mutations.count
    let newChord = Chord(key: .letter("L"), modifiers: [.control, .option])

    h.send(.set(.cycleLeft, newChord))
    let delta = Array(h.mutations.dropFirst(before))
    #expect(delta == [.register(newChord, .cycleLeft)])
    #expect(h.registrar.bound(.cycleLeft) == newChord)
    for a in ShortcutAction.allCases where a != .cycleLeft {
      #expect(h.registrar.bound(a) == ShortcutRules.defaults.first { $0.action == a }?.chord)
    }

    // The identical chord again produces zero calls.
    let steady = h.mutations.count
    let effects = h.send(.set(.cycleLeft, newChord))
    #expect(effects.isEmpty)
    #expect(h.mutations.count == steady)

    // A window action set while ungranted commits and persists with no registration.
    let u = StoreHarness()
    u.send(.launch)
    let ueffects = u.send(.set(.cycleRight, newChord))
    #expect(ueffects == [.persist(u.state.shortcuts)])
    #expect(u.state.chord(of: .cycleRight) == newChord)
    #expect(u.registrar.bound(.cycleRight) == nil)
    // Granting later registers the new chord.
    u.send(.permission(granted: true))
    #expect(u.registrar.bound(.cycleRight) == newChord)
  }

  @Test func carbonKeyCodeTable() {
    for shortcut in ShortcutRules.defaults {
      let key = shortcut.chord!.key
      #expect(CarbonKeyMap.keyCode(for: key) != nil)
    }
    var codes: [UInt32] = []
    let digitCodes: [Int: UInt32] = [
      1: 18, 2: 19, 3: 20, 4: 21, 5: 23, 6: 22, 7: 26, 8: 28, 9: 25, 0: 29,
    ]
    for d in 0...9 {
      let code = CarbonKeyMap.keyCode(for: .digit(d))
      #expect(code == digitCodes[d])
      codes.append(code ?? 9999)
    }
    let letterCodes: [String: UInt32] = [
      "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7, "C": 8, "V": 9, "B": 11, "Q": 12,
      "W": 13, "E": 14, "R": 15, "Y": 16, "T": 17, "O": 31, "U": 32, "I": 34, "P": 35, "L": 37, "J": 38,
      "K": 40, "N": 45, "M": 46,
    ]
    #expect(letterCodes.count == 26)
    for (letter, expected) in letterCodes {
      #expect(CarbonKeyMap.keyCode(for: .letter(letter)) == expected)
      #expect(CarbonKeyMap.keyCode(for: .letter(letter.lowercased())) == expected)
      codes.append(expected)
    }
    #expect(CarbonKeyMap.keyCode(for: .arrowLeft) == 123)
    #expect(CarbonKeyMap.keyCode(for: .arrowRight) == 124)
    #expect(CarbonKeyMap.keyCode(for: .arrowDown) == 125)
    #expect(CarbonKeyMap.keyCode(for: .arrowUp) == 126)
    #expect(CarbonKeyMap.keyCode(for: .comma) == 43)
    codes += [123, 124, 125, 126, 43]
    #expect(Set(codes).count == codes.count)  // all distinct
    #expect(codes.count == 41)

    #expect(CarbonKeyMap.keyCode(for: .digit(10)) == nil)
    #expect(CarbonKeyMap.keyCode(for: .digit(-1)) == nil)
    #expect(CarbonKeyMap.keyCode(for: .letter("AB")) == nil)
    #expect(CarbonKeyMap.keyCode(for: .letter("")) == nil)
    #expect(CarbonKeyMap.keyCode(for: .letter("ß")) == nil)  // uppercases to "SS": must not trap

    #expect(CarbonKeyMap.modifiers([.control, .option]) == 4096 + 2048)
    #expect(CarbonKeyMap.modifiers([.command]) == 256)
    #expect(CarbonKeyMap.modifiers([.shift]) == 512)
    #expect(CarbonKeyMap.modifiers([.command, .shift, .option, .control]) == 256 + 512 + 2048 + 4096)
    #expect(CarbonKeyMap.modifiers([]) == 0)
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
