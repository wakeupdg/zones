import ApplicationServices
import CoreGraphics
import Foundation
import Testing
import ZonesCore
import ZonesTestSupport
import ZonesWindowing

/// AC-163: each seam fake has a response queue, a typed call log and fake-Clock latency.
@Suite struct FakeContractTests {
  /// A handle over a real application element. `pid` picks which one, so two handles can differ.
  static func handle(pid: pid_t = getpid()) -> WindowHandle {
    WindowHandle(element: AXUIElementCreateApplication(pid), pid: pid)
  }

  @Test @WindowActor func windowSystem() {
    let clock = FakeClock()
    let ws = FakeWindowSystem(clock: clock)
    let h = Self.handle()
    let rect = CGRect(x: 10, y: 20, width: 300, height: 200)

    // Queue: FIFO, then the documented default; the call log records every call in order.
    ws.enqueue(.frame(.value(rect)))
    ws.enqueue(.frame(.timedOut))
    #expect(ws.frame(h) == .value(rect))
    #expect(ws.frame(h) == .timedOut)
    #expect(ws.frame(h) == .elementGone)
    #expect(ws.calls == [.frame(h), .frame(h), .frame(h)])

    // Other methods draw from their own kind of response.
    ws.enqueue(.position(.refused(7)))
    ws.enqueue(.size(.timedOut))
    #expect(ws.setPosition(CGPoint(x: 1, y: 2), h) == .refused(7))
    #expect(ws.setSize(CGSize(width: 3, height: 4), h) == .timedOut)
    #expect(ws.setPosition(CGPoint(x: 1, y: 2), h) == .ok)
    #expect(ws.calls.last == .setPosition(CGPoint(x: 1, y: 2), h))

    // ADR-0015 amendment: two consecutive timeouts against the same app can be scripted.
    ws.reset()
    ws.enqueue(.position(.timedOut))
    ws.enqueue(.position(.timedOut))
    #expect(ws.setPosition(.zero, h) == .timedOut)
    #expect(ws.setPosition(.zero, h) == .timedOut)

    // reset() empties the queue and the log.
    ws.enqueue(.frame(.value(rect)))
    ws.reset()
    #expect(ws.calls.isEmpty)
    #expect(ws.frame(h) == .elementGone)

    // Latency 2: nothing completes at 1 s, the call completes at 2 s.
    ws.reset()
    ws.latency = 2
    _ = ws.frame(h)
    #expect(ws.calls == [.frame(h)])
    #expect(ws.completed.isEmpty)
    #expect(ws.inFlight == 1)
    clock.advance(by: 1)
    #expect(ws.completed.isEmpty)
    clock.advance(by: 1)
    #expect(ws.completed == [.frame(h)])
    #expect(ws.inFlight == 0)
  }

  private static func ref(_ id: UInt32, x: Double = 0) -> ZonesCore.WindowRef {
    ZonesCore.WindowRef(
      id: WindowID(rawValue: id), pid: 100, bundleID: "com.example.app",
      frame: CGRect(x: x, y: 0, width: 100, height: 100), layer: 0)
  }

  @Test func windowEnumerator() {
    let clock = FakeClock()
    let en = FakeWindowEnumerator(clock: clock)
    let a = Self.ref(1), b = Self.ref(2, x: 50)

    // Queue: lists come back FIFO per method, then the neutral default.
    en.enqueue(.onScreen([a, b]))
    en.enqueue(.onScreen([b]))
    #expect(en.onScreenWindows() == [a, b])
    #expect(en.onScreenWindows() == [b])
    #expect(en.onScreenWindows().isEmpty)

    en.enqueue(.windows([a]))
    #expect(en.windows(ids: [a.id]) == [a])

    // candidates(under:hint:) is logged with its hint.
    en.enqueue(.candidates([b, a]))
    let point = CGPoint(x: 60, y: 10)
    #expect(en.candidates(under: point, hint: b.id) == [b, a])
    #expect(en.candidates(under: point, hint: nil).isEmpty)
    #expect(
      en.calls == [
        .onScreenWindows, .onScreenWindows, .onScreenWindows, .windows(ids: [a.id]),
        .candidates(under: point, hint: b.id), .candidates(under: point, hint: nil),
      ])

    // Latency 2 completes at the second advance(by: 1), not the first.
    en.reset()
    #expect(en.calls.isEmpty)
    en.latency = 2
    _ = en.onScreenWindows()
    clock.advance(by: 1)
    #expect(en.completed.isEmpty)
    #expect(en.inFlight == 1)
    clock.advance(by: 1)
    #expect(en.completed == [.onScreenWindows])
    #expect(en.inFlight == 0)

    // reset() drops queued responses too.
    en.reset()
    en.enqueue(.onScreen([a]))
    en.reset()
    #expect(en.onScreenWindows().isEmpty)
  }

  @Test func inputSource() async {
    let clock = FakeClock()
    let src = FakeInputSource(clock: clock)
    #expect(src.config == .production)

    // Queue: scripted results in order, then the defaults (.started, true, .started).
    src.enqueue(.start(.unavailable))
    src.enqueue(.start(.started))
    src.enqueue(.reenable(false))
    src.enqueue(.recreate(.unavailable))
    #expect(src.start() == .unavailable)
    #expect(src.start() == .started)
    #expect(src.reenable() == false)
    #expect(src.reenable() == true)
    #expect(src.recreate() == .unavailable)
    #expect(src.recreate() == .started)
    src.stop()
    #expect(src.calls == [.start, .start, .reenable, .reenable, .recreate, .recreate, .stop])

    // Streams: emitted events and signals arrive in order.
    let event = InputEvent(
      kind: .leftDown, point: CGPoint(x: 5, y: 6), flags: .shift, windowUnderPointer: WindowID(rawValue: 9),
      time: 1.5)
    src.emit(event)
    src.emit(.disabledByTimeout)
    src.emit(.recreated(true))
    var events = src.events.makeAsyncIterator()
    var signals = src.signals.makeAsyncIterator()
    #expect(await events.next() == event)
    #expect(await signals.next() == .disabledByTimeout)
    #expect(await signals.next() == .recreated(true))

    // Latency 2 completes at the second advance(by: 1).
    src.reset()
    src.latency = 2
    _ = src.start()
    clock.advance(by: 1)
    #expect(src.completed.isEmpty)
    clock.advance(by: 1)
    #expect(src.completed == [.start])

    // reset() clears queue and log, and finishes the old streams.
    src.enqueue(.start(.unavailable))
    var old = src.events.makeAsyncIterator()
    src.reset()
    #expect(src.calls.isEmpty)
    #expect(await old.next() == nil)
    #expect(src.start() == .started)
  }

  @Test func displayProvider() async {
    let clock = FakeClock()
    let dp = FakeDisplayProvider(clock: clock)
    let single = TopologySnapshot(
      displays: [Fixtures.threeDisplays.displays[0]], separateSpaces: true,
      primaryFrame: Fixtures.threeDisplays.primaryFrame)

    // Queue: snapshots in order; after the queue drains the last one repeats (a stable topology).
    dp.enqueue(.snapshot(Fixtures.threeDisplays))
    dp.enqueue(.snapshot(single))
    #expect(dp.snapshot() == Fixtures.threeDisplays)
    #expect(dp.snapshot() == single)
    #expect(dp.snapshot() == single)
    #expect(dp.calls == [.snapshot, .snapshot, .snapshot])

    // Change notifications reach the stream in order.
    dp.emit(.wake)
    dp.emit(.activeSpace)
    var changes = dp.changes.makeAsyncIterator()
    #expect(await changes.next() == .wake)
    #expect(await changes.next() == .activeSpace)

    // Latency 2 completes at the second advance(by: 1).
    dp.reset()
    dp.latency = 2
    _ = dp.snapshot()
    clock.advance(by: 1)
    #expect(dp.completed.isEmpty)
    clock.advance(by: 1)
    #expect(dp.completed == [.snapshot])

    // reset() forgets the queue, the repeated snapshot and the log.
    dp.reset()
    dp.enqueue(.snapshot(single))
    dp.reset()
    #expect(dp.calls.isEmpty)
    #expect(dp.snapshot().displays.isEmpty)
  }

  @Test @MainActor func overlayPresenter() {
    let clock = FakeClock()
    let overlay = FakeOverlayPresenter(clock: clock)
    let scene = OverlayScene(
      layouts: [],
      appearance: Appearance(
        fill: RGBA(r: 0, g: 0.5, b: 1, a: 1), opacity: 0.4, defaultInsets: Insets(margin: 0, gap: 0)),
      options: AccessibilityOptions(reduceTransparency: false, reduceMotion: false))
    let light = Highlight(display: nil, primary: [1, 2], secondary: [3], dimAll: false)

    #expect(!overlay.isShown)
    overlay.show(scene)
    #expect(overlay.isShown)
    overlay.highlight(light)
    #expect(overlay.isShown)
    overlay.hide()
    #expect(!overlay.isShown)
    overlay.show(scene)
    overlay.reassert()
    overlay.orderOut()
    #expect(!overlay.isShown)
    overlay.resize(to: Fixtures.threeDisplays)
    #expect(
      overlay.calls == [
        .show(scene), .highlight(light), .hide, .show(scene), .reassert, .orderOut,
        .resize(Fixtures.threeDisplays),
      ])

    // Latency 2 completes at the second advance(by: 1).
    overlay.reset()
    #expect(overlay.calls.isEmpty)
    #expect(!overlay.isShown)
    overlay.latency = 2
    overlay.hide()
    clock.advance(by: 1)
    #expect(overlay.completed.isEmpty)
    clock.advance(by: 1)
    #expect(overlay.completed == [.hide])
  }

  @Test @MainActor func hotkeyRegistrar() async {
    let clock = FakeClock()
    let keys = FakeHotkeyRegistrar(clock: clock)
    let chord = Chord(key: .arrowLeft, modifiers: [.control, .option])

    // Queue: .inUse first (nothing bound), then the default .registered binds the chord.
    keys.enqueue(.registration(.inUse))
    #expect(keys.register(chord, for: .cycleLeft) == .inUse)
    #expect(keys.bound(.cycleLeft) == nil)
    #expect(keys.register(chord, for: .cycleLeft) == .registered)
    #expect(keys.bound(.cycleLeft) == chord)
    keys.unregister(.cycleLeft)
    #expect(keys.bound(.cycleLeft) == nil)
    #expect(
      keys.calls == [
        .register(chord, .cycleLeft), .bound(.cycleLeft), .register(chord, .cycleLeft),
        .bound(.cycleLeft), .unregister(.cycleLeft), .bound(.cycleLeft),
      ])

    // press(_:) reaches the presses stream.
    keys.press(.restore)
    keys.press(.sendToZone(3))
    var presses = keys.presses.makeAsyncIterator()
    #expect(await presses.next() == .restore)
    #expect(await presses.next() == .sendToZone(3))

    // Latency 2 completes at the second advance(by: 1).
    keys.reset()
    keys.latency = 2
    keys.unregister(.restore)
    clock.advance(by: 1)
    #expect(keys.completed.isEmpty)
    clock.advance(by: 1)
    #expect(keys.completed == [.unregister(.restore)])

    // reset() clears bindings, queue, log.
    keys.reset()
    _ = keys.register(chord, for: .restore)
    keys.reset()
    #expect(keys.calls.isEmpty)
    #expect(keys.bound(.restore) == nil)
  }

  @Test @MainActor func loginItemService() throws {
    let clock = FakeClock()
    let login = FakeLoginItemService(clock: clock)

    // Without a script the status follows register and unregister.
    #expect(login.status() == .notRegistered)
    try login.register()
    #expect(login.status() == .enabled)
    try login.unregister()
    #expect(login.status() == .notRegistered)

    // Queue: a scripted status wins once; register() can be scripted to throw.
    login.enqueue(.status(.requiresApproval))
    #expect(login.status() == .requiresApproval)
    #expect(login.status() == .notRegistered)
    login.enqueue(.register(.launchDeniedByUser))
    #expect(throws: LoginItemError.launchDeniedByUser) { try login.register() }
    #expect(login.status() == .notRegistered)
    login.enqueue(.unregister(.other("boom")))
    #expect(throws: LoginItemError.other("boom")) { try login.unregister() }
    login.openLoginItemsSettings()
    #expect(login.calls.last == .openLoginItemsSettings)
    #expect(login.calls.contains(.register))
    #expect(login.calls.contains(.unregister))

    // Latency 2 completes at the second advance(by: 1).
    login.reset()
    #expect(login.calls.isEmpty)
    login.latency = 2
    login.openLoginItemsSettings()
    clock.advance(by: 1)
    #expect(login.completed.isEmpty)
    clock.advance(by: 1)
    #expect(login.completed == [.openLoginItemsSettings])

    // reset() clears the queue and the tracked status.
    login.reset()
    login.enqueue(.status(.notFound))
    try login.register()
    login.reset()
    #expect(login.status() == .notRegistered)
  }
}
