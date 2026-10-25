import Foundation
import Testing
import ZonesCore
import ZonesTestSupport
import ZonesWindowing
import os

@testable import Zones

@MainActor
@Suite struct PermissionDriverTests {
  /// One effect on a fresh, quiet harness. The closure hooks report through `hooks`.
  private func run(_ effect: PermissionEffect, prepare: (Harness, CompositionRoot) -> Void = { _, _ in }) async
    -> (Harness, CompositionRoot, [String])
  {
    let h = Harness()
    let root = h.makeRoot()
    let hooks = OSAllocatedUnfairLock(initialState: [String]())
    root.permission.onWindowHotkeys = { on in hooks.withLock { $0.append(on ? "register" : "unregister") } }
    root.permission.onForceTopologySnapshot = { hooks.withLock { $0.append("topology") } }
    prepare(h, root)
    root.permission.interpret(effect)
    await root.permission.quiesce()
    return (h, root, hooks.withLock { $0 })
  }

  @Test func effectsDispatchedOneToOne() async {
    // Timers go to the clock.
    var (h, _, _) = await run(.schedule(.healthTick, 5))
    #expect(h.clock.pending == [.healthTick])
    (h, _, _) = await run(.cancel(.trustPoll)) { _, root in root.permission.interpret(.schedule(.trustPoll, 1)) }
    #expect(h.clock.pending.isEmpty)

    // Adapter calls: exactly one each.
    (h, _, _) = await run(.probe)
    #expect(h.probe.calls == [.isTrusted])
    (h, _, _) = await run(.heartbeat)
    #expect(h.windows.calls == [.trivialRead])
    (h, _, _) = await run(.startTap)
    #expect(h.input.calls == [.start])
    (h, _, _) = await run(.revalidateTap)
    #expect(h.input.calls == [.reenable])
    (h, _, _) = await run(.recreateTap)
    #expect(h.input.calls == [.recreate])
    (h, _, _) = await run(.disableTap)
    #expect(h.input.calls == [.stop])
    (h, _, _) = await run(.invalidateTap)
    #expect(h.input.calls == [.stop])
    (h, _, _) = await run(.orderPanelsOut)
    #expect(h.overlay.calls == [.orderOut])

    // Surfaces.
    (h, _, _) = await run(.dismissOnboarding)
    #expect(h.surfaces.calls == [.dismissOnboarding])
    (h, _, _) = await run(.showOnboarding)
    #expect(h.surfaces.calls == [.showOnboarding])
    (h, _, _) = await run(.badge(true))
    #expect(h.surfaces.calls == [.badge(true)])
    (h, _, _) = await run(.grantMenuItem(false))
    #expect(h.surfaces.calls == [.grant(false)])
    (h, _, _) = await run(.offerRelaunch(true))
    #expect(h.surfaces.calls == [.relaunch(true)])

    // Hooks into the other drivers.
    var hooks: [String]
    (_, _, hooks) = await run(.registerWindowHotkeys)
    #expect(hooks == ["register"])
    (_, _, hooks) = await run(.unregisterWindowHotkeys)
    #expect(hooks == ["unregister"])
    (_, _, hooks) = await run(.forceTopologySnapshot)
    #expect(hooks == ["topology"])

    // Enhanced UI recovery file: one remove each.
    (h, _, _) = await run(.drainEnhancedUI)
    #expect(h.files.calls.filter { if case .remove = $0 { true } else { false } }.count == 1)
    (h, _, _) = await run(.removeRecoveryRecord)
    #expect(h.files.calls.filter { if case .remove = $0 { true } else { false } }.count == 1)
  }

  @Test func probeResultReachesTheMachine() async {
    let h = Harness()
    h.probe.enqueue(.trusted(true))
    let root = h.makeRoot()
    root.permission.interpret(.probe)
    #expect(root.permission.state == .granted)
    #expect(h.input.calls == [.start])
  }

  /// T56: every trust-poll probe reaches `onTrustPoll` once, after the machine has seen the result, so the
  /// onboarding window's help line rides the existing 1 s poll (AC-156: no timer of its own).
  @Test func probeReportsTrustPollAfterTheMachine() async {
    let h = Harness()
    h.probe.enqueue(.trusted(false))
    let root = h.makeRoot()
    var seen: [PermissionState] = []
    root.permission.onTrustPoll = { [weak root] in seen.append(root?.permission.state ?? .granted) }
    root.permission.interpret(.probe)
    #expect(seen == [.notGranted])
    h.probe.enqueue(.trusted(true))
    root.permission.interpret(.probe)
    #expect(seen == [.notGranted, .granted])
  }

  @Test func disabledTapIsReenabledThenDeclaredLost() async {
    let h = Harness()
    h.probe.enqueue(.trusted(true))
    let root = h.makeRoot()
    root.permission.receive(.probe(h.probe.isTrusted()))
    #expect(root.permission.state == .granted)
    h.input.reset()

    for _ in 0..<Constants.reenableLimit { root.permission.signal(.disabledByTimeout) }
    #expect(h.input.calls == Array(repeating: .reenable, count: Constants.reenableLimit))
    #expect(root.permission.tap == .alive)

    // The next disable inside the window: the tap is lost; the machine hears `tapNil` and recreates it.
    root.permission.signal(.disabledByUserInput)
    #expect(root.permission.tap == .alive)  // the recreate succeeded, so the tap is alive again
    #expect(h.input.calls.last == .recreate)
    if case .suspect = root.permission.state {} else { Issue.record("expected suspect, got \(root.permission.state)") }
  }

  @Test func deadTapRetryTimerRecreates() async {
    let h = Harness()
    let root = h.makeRoot()
    h.input.enqueue(.recreate(.unavailable))
    // Force the dead state through the reducer's own path.
    for _ in 0...Constants.reenableLimit { root.permission.signal(.disabledByTimeout) }
    #expect(root.permission.tap == .dead)
    #expect(h.clock.pending.contains(.deadTapRetry))
    let before = h.input.calls.filter { $0 == .recreate }.count
    root.permission.timerFired(.deadTapRetry)
    #expect(h.input.calls.filter { $0 == .recreate }.count == before + 1)
  }

  @Test func heartbeatAfterRecreateIsTaggedTrivialRead() async {
    let h = Harness()
    h.probe.enqueue(.trusted(true))
    let root = h.makeRoot()
    root.permission.receive(.probe(true))
    // apiDisabled -> suspect + recreateTap; the fake recreate succeeds -> tapRecreated(true) -> one heartbeat.
    root.permission.receive(.apiDisabled)
    await root.permission.quiesce()
    // The trivial read answered ok after the recreate: granted again.
    #expect(root.permission.state == .granted)
    #expect(h.windows.calls.contains(.trivialRead))
  }
}
