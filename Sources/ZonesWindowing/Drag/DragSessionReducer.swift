import CoreGraphics
import Foundation
import ZonesCore
import ZonesLayout

/// The pure Drag Session state machine (ADR-0006, ADR-0007): idle, pressed, moving, armed.
public enum DragSessionReducer {
  /// One step: no I/O, no time source, no actor. One switch per state.
  ///
  /// Known gap: no state holds a live cursor point outside armed. The driver re-sends its last `dragged` right
  /// after answering `requestArmContext`, which sets the first highlight; mouse-up always recomputes its hit from
  /// its own point, so a drop never uses a stale hit.
  ///
  /// A `wake` ends the session from every state (AC-024): idle, `hideOverlay`, and `stopSampling` when a pressed
  /// session was polling frames. No snap, no restore: the wake-time frame is not a drop.
  ///
  /// `topologyChanged` and `spaceChanged` act in armed only (pressed and moving hold no snapshot) and are inert
  /// in every other state.
  /// EXTENSION(T22): cross-Display handling beyond the re-arm lands with the cross-Display ticket.
  public static func reduce(_ s: DragState, _ e: DragEvent) -> (DragState, [DragEffect]) {
    if case .wake = e { return (.idle, wakeEffects(s)) }
    switch s {
    case .idle: return idle(s, e)
    case .pressed: return pressed(s, e)
    case .moving: return moving(s, e)
    case .armed: return armed(s, e)
    }
  }

  private static func wakeEffects(_ s: DragState) -> [DragEffect] {
    if case .pressed(_, _, _, _, _, let samples, _) = s, samples > 0 { return [.stopSampling, .hideOverlay] }
    return [.hideOverlay]
  }

  private static func idle(_ s: DragState, _ e: DragEvent) -> (DragState, [DragEffect]) {
    guard case .mouseDown(let point, let flags, let candidates, let phaseOne, let config) = e else { return (s, []) }
    if case .skip(let reason) = phaseOne { return (.idle, [.skip(reason, candidates.first)]) }
    guard !candidates.isEmpty else { return (.idle, [.log("mouseDown: no candidate window under the cursor")]) }
    // More candidates than the cap cannot be told apart in one batched read: skip before any sampling.
    guard candidates.count <= Constants.candidateCap else { return (.idle, [.skip(.ambiguousMatch, nil)]) }
    // EXTENSION(T21): `.allow(mode)` is accepted and the mode is not stored; SnapPlan mode is `.full` for now
    // (phase one only ever allows `.full`; see the ledger note on `positionOnly`).
    let frames = Dictionary(candidates.map { ($0.id, $0.frame) }, uniquingKeysWith: { first, _ in first })
    return (
      .pressed(
        candidates: candidates, down: point, downFrames: frames, flags: flags, config: config, samples: 0,
        retried: false), []
    )
  }

  private static func pressed(_ s: DragState, _ e: DragEvent) -> (DragState, [DragEffect]) {
    guard case .pressed(let candidates, let down, let downFrames, let flags, let config, let samples, let retried) = s
    else { return (s, []) }
    let ids = candidates.map(\.id)
    switch e {
    case .dragged:
      // `samples` counts requestSample effects issued: the first dragged event starts the polling.
      guard samples == 0 else { return (s, []) }
      return (
        .pressed(
          candidates: candidates, down: down, downFrames: downFrames, flags: flags, config: config, samples: 1,
          retried: retried), [.requestSample(ids)]
      )
    case .flagsChanged(let f):
      return (
        .pressed(
          candidates: candidates, down: down, downFrames: downFrames, flags: f, config: config, samples: samples,
          retried: retried), []
      )
    case .mouseUp, .windowGone:
      return (.idle, samples > 0 ? [.stopSampling] : [])
    case .frameSample(let results):
      let tick = CandidateTick.classify(candidates: candidates, downFrames: downFrames, results: results)
      // A size change over the tolerance is a resize, checked before any mover so a top-left resize that also
      // shifts the origin still ends the session (AC-048).
      if tick.resized { return (.idle, [.stopSampling]) }
      // One mover wins at once, even when another candidate timed out in the same tick.
      if tick.movers.count == 1, let winner = tick.movers.first {
        // Phase two: the facts riding on the first moved sample decide whether the window may be moved at all.
        // Missing facts mean no safe phase two (ledger decision). `allow(.positionOnly)` moves on; the mode has
        // no carrier in `moving`/`armed`, so SnapPlan mode stays `.full` (ledger note).
        guard let facts = winner.facts else { return (.idle, [.stopSampling, .skip(.unresponsive, winner.ref)]) }
        if case .skip(let reason) = ExclusionPolicy.phaseTwo(facts) {
          return (.idle, [.stopSampling, .skip(reason, winner.ref)])
        }
        var fx: [DragEffect] = [.stopSampling]
        if flags.contains(ModifierSet(config.activation)) {
          fx.append(.requestArmContext(window: winner.ref, point: down))
        }
        return (.moving(window: winner.ref, downFrame: winner.downFrame, flags: flags, config: config), fx)
      }
      // `samples` counts the requests issued, so it equals the number of this returned sample.
      if tick.movers.count > 1, samples >= Constants.settleSamples {
        return (.idle, [.stopSampling, .skip(.ambiguousMatch, nil)])
      }
      let survivors = tick.survivors
      guard !survivors.isEmpty else { return (.idle, [.stopSampling]) }
      // No mover and a timed-out read: one immediate retry per press, then give up on the app.
      var nowRetried = retried
      if tick.movers.isEmpty, let slow = tick.timedOut.first {
        if retried { return (.idle, [.stopSampling, .skip(.unresponsive, slow)]) }
        nowRetried = true
      }
      let alive = Set(survivors.map(\.id))
      let kept = downFrames.filter { alive.contains($0.key) }
      return (
        .pressed(
          candidates: survivors, down: down, downFrames: kept, flags: flags, config: config,
          samples: samples + 1, retried: nowRetried), [.requestSample(survivors.map(\.id))]
      )
    default:
      return (s, [])
    }
  }

  private static func moving(_ s: DragState, _ e: DragEvent) -> (DragState, [DragEffect]) {
    guard case .moving(let window, let downFrame, let flags, let config) = s else { return (s, []) }
    switch e {
    case .flagsChanged(let f):
      // The Activation Modifier pressed after the move arms the session too (AC-037).
      let activation = ModifierSet(config.activation)
      let newly = f.contains(activation) && !flags.contains(activation)
      return (
        .moving(window: window, downFrame: downFrame, flags: f, config: config),
        newly ? [.requestArmContext(window: window, point: downFrame.origin)] : []
      )
    case .armContext(let ctx):
      guard flags.contains(ModifierSet(config.activation)) else { return (s, []) }
      let scene = overlayScene(for: ctx)
      let span = SpanState(zones: [], display: nil, frozen: false, suspended: false)
      return (
        .armed(
          window: window, downFrame: downFrame, flags: flags, config: config, context: ctx, display: nil,
          hit: .none, span: span, point: nil), [.showOverlay(scene)]
      )
    case .mouseUp, .windowGone:
      return (.idle, [])
    default:
      return (s, [])
    }
  }

  private static func armed(_ s: DragState, _ e: DragEvent) -> (DragState, [DragEffect]) {
    guard case .armed(let window, let downFrame, let flags, let config, let ctx, let display, let hit, let span, let lastPoint) = s
    else { return (s, []) }
    switch e {
    case .dragged(let point, _):
      // The highlight follows the cursor Zone, not the window center (AC-034, LI-009).
      let cursor = SpanLogic.cursor(at: point, in: ctx)
      let newSpan = SpanLogic.accumulate(span, at: cursor, flags: flags, config: config)
      let state = DragState.armed(
        window: window, downFrame: downFrame, flags: flags, config: config, context: ctx, display: cursor.display,
        hit: cursor.hit, span: newSpan, point: point)
      return (state, SpanLogic.highlightChange(from: s, to: state))
    case .flagsChanged(let f):
      // Releasing the Activation Modifier hides the overlay and cancels; the Span is dropped (AC-035).
      guard f.contains(ModifierSet(config.activation)) else {
        return (.moving(window: window, downFrame: downFrame, flags: f, config: config), [.hideOverlay])
      }
      // Releasing the Span Modifier freezes the set; pressing it again resumes adding.
      let cursor = SpanLogic.Cursor(display: display, hit: hit)
      let newSpan = SpanLogic.flagsChanged(span, from: flags, to: f, at: cursor, config: config)
      let state = DragState.armed(
        window: window, downFrame: downFrame, flags: f, config: config, context: ctx, display: display, hit: hit,
        span: newSpan, point: lastPoint)
      return (state, SpanLogic.highlightChange(from: s, to: state))
    case .mouseUp(let point, let upFlags):
      // The overlay is on screen in armed, so it is always hidden first (AC-053). A snap or restore needs the
      // Activation Modifier in the mouse-up's own flags (LI-007) and a drop recomputed from the mouse-up point,
      // never a stale hit.
      var fx: [DragEffect] = [.hideOverlay]
      if upFlags.contains(ModifierSet(config.activation)) {
        let cursor = SpanLogic.cursor(at: point, in: ctx)
        guard let cursorDisplay = cursor.display, ctx.layouts[cursorDisplay] != nil else {
          // The cursor is over a Display the arm snapshot does not know: nothing to snap or restore (AC-045).
          fx.append(.log("drop outside the arm snapshot: no Display or Layout under \(point)"))
          return (.idle, fx)
        }
        let dropSpan = SpanLogic.accumulate(span, at: cursor, flags: upFlags, config: config)
        let drop = SpanLogic.drop(at: cursor, span: dropSpan, in: ctx)
        if drop.restore {
          fx.append(.restore(window, downFrame: downFrame))
        } else if let dropDisplay = drop.display, let layout = ctx.layouts[dropDisplay], !drop.zones.isEmpty {
          // EXTENSION(T21): SnapPlan mode comes from the phase-one verdict; `.full` for now.
          fx.append(
            .snap(
              SnapPlan(
                window: window, display: dropDisplay, zones: drop.zones, target: Span.rect(drop.zones, in: layout),
                mode: .full, via: .mouse, originalFrame: ctx.hasOriginalFrame ? nil : downFrame)))
        }
      }
      return (.idle, fx)
    case .topologyChanged(let newCtx):
      // Re-arm from the new snapshot (ADR-0014: no re-layout): a fresh overlay and a re-hit. The re-hit uses the
      // same call as the mouseUp path, at the last cursor point, so the highlight equals the drop set even when
      // the cursor's previous Display is gone (LI-009). Before the first `dragged` there is no point, and the
      // stand-in is the center of the Zone the cursor was last over, in the OLD layout.
      let cursor =
        if let lastPoint {
          SpanLogic.cursor(at: lastPoint, in: newCtx)
        } else {
          rehit(lastHitPoint(display: display, hit: hit, in: ctx), previous: display, in: newCtx)
        }
      // Accumulate the Span at the new cursor exactly as `dragged` does, so the stored Span (and `suspended`)
      // matches what mouseUp will drop (LI-009).
      let newSpan = SpanLogic.accumulate(span, at: cursor, flags: flags, config: config)
      let state = DragState.armed(
        window: window, downFrame: downFrame, flags: flags, config: config, context: newCtx, display: cursor.display,
        hit: cursor.hit, span: newSpan, point: lastPoint)
      var fx: [DragEffect] = [.showOverlay(overlayScene(for: newCtx))]
      if let highlight = SpanLogic.highlight(of: state) { fx.append(.updateHighlight(highlight)) }
      return (state, fx)
    case .spaceChanged:
      // A Space switch can drop the overlay panels; re-assert them and refresh the highlight (AC-062).
      var fx: [DragEffect] = [.reassertPanels]
      if let highlight = SpanLogic.highlight(of: s) { fx.append(.updateHighlight(highlight)) }
      return (s, fx)
    case .windowGone:
      return (.idle, [.hideOverlay])
    default:
      return (s, [])
    }
  }

  private static func overlayScene(for ctx: ArmContext) -> OverlayScene {
    OverlayScene(
      layouts: ctx.topology.displays.compactMap { ctx.layouts[$0.key] }, appearance: ctx.appearance,
      options: ctx.options)
  }

  /// A pure stand-in for the cursor: the center of the hit Zone in `ctx`'s layout for `display`; nil when the
  /// cursor was over no Zone.
  private static func lastHitPoint(display: DisplayKey?, hit: Hit, in ctx: ArmContext) -> CGPoint? {
    guard let display, let layout = ctx.layouts[display] else { return nil }
    guard let number = SpanLogic.zones(of: hit).first else { return nil }
    guard let zone = layout.zones.first(where: { $0.number == number }) else { return nil }
    return CGPoint(x: zone.frame.midX, y: zone.frame.midY)
  }

  /// The re-hit after a snapshot change: nothing when the previous Display is gone or there is no point.
  private static func rehit(_ point: CGPoint?, previous: DisplayKey?, in ctx: ArmContext) -> SpanLogic.Cursor {
    guard let point, let previous, ctx.topology.display(previous) != nil else {
      return SpanLogic.Cursor(display: nil, hit: .none)
    }
    return SpanLogic.cursor(at: point, in: ctx)
  }
}
