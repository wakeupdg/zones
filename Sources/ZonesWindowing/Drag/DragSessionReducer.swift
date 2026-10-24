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
  /// EXTENSION(T22): `topologyChanged`, `spaceChanged` and `wake` are inert in every state for now; the Display
  /// change, Space change and wake handling lands with the cross-Display ticket.
  public static func reduce(_ s: DragState, _ e: DragEvent) -> (DragState, [DragEffect]) {
    switch s {
    case .idle: return idle(s, e)
    case .pressed: return pressed(s, e)
    case .moving: return moving(s, e)
    case .armed: return armed(s, e)
    }
  }

  private static func idle(_ s: DragState, _ e: DragEvent) -> (DragState, [DragEffect]) {
    guard case .mouseDown(let point, let flags, let candidates, let phaseOne, let config) = e else { return (s, []) }
    if case .skip(let reason) = phaseOne { return (.idle, [.skip(reason, candidates.first)]) }
    guard !candidates.isEmpty else { return (.idle, []) }
    // EXTENSION(T21): `.allow(mode)` is accepted and the mode is not stored; SnapPlan mode is `.full` for now.
    // EXTENSION(T21): candidate resolution (ambiguity, cooldown) beyond the first `candidateCap` windows.
    let capped = Array(candidates.prefix(Constants.candidateCap))
    let frames = Dictionary(capped.map { ($0.id, $0.frame) }, uniquingKeysWith: { first, _ in first })
    return (
      .pressed(
        candidates: capped, down: point, downFrames: frames, flags: flags, config: config, samples: 0,
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
      // Walk the candidates in z-order; the first whose frame differs from its mouse-down frame decides.
      // EXTENSION(T21): retry, cooldown, ambiguity and the phase-two skip from facts; candidates beyond the first
      // decisive one. `.timedOut` and `.gone` count as unmoved for now.
      for ref in candidates {
        guard case .frame(let r, _)? = results[ref.id], let was = downFrames[ref.id] else { continue }
        // A size delta over the tolerance is a resize, checked before the origin so a top-left resize that also
        // shifts the origin still ends the session (AC-048).
        if abs(r.width - was.width) > Constants.frameTolerance
          || abs(r.height - was.height) > Constants.frameTolerance
        {
          return (.idle, [.stopSampling])
        }
        if abs(r.origin.x - was.origin.x) > Constants.frameTolerance
          || abs(r.origin.y - was.origin.y) > Constants.frameTolerance
        {
          var fx: [DragEffect] = [.stopSampling]
          if flags.contains(ModifierSet(config.activation)) {
            fx.append(.requestArmContext(window: ref, point: down))
          }
          return (.moving(window: ref, downFrame: was, flags: flags, config: config), fx)
        }
      }
      return (
        .pressed(
          candidates: candidates, down: down, downFrames: downFrames, flags: flags, config: config,
          samples: samples + 1, retried: retried), [.requestSample(ids)]
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
      let scene = OverlayScene(
        layouts: ctx.topology.displays.compactMap { ctx.layouts[$0.key] }, appearance: ctx.appearance,
        options: ctx.options)
      let span = SpanState(zones: [], display: nil, frozen: false, suspended: false)
      return (
        .armed(
          window: window, downFrame: downFrame, flags: flags, config: config, context: ctx, display: nil,
          hit: .none, span: span), [.showOverlay(scene)]
      )
    case .mouseUp, .windowGone:
      return (.idle, [])
    default:
      return (s, [])
    }
  }

  private static func armed(_ s: DragState, _ e: DragEvent) -> (DragState, [DragEffect]) {
    guard case .armed(let window, let downFrame, let flags, let config, let ctx, let display, let hit, let span) = s
    else { return (s, []) }
    switch e {
    case .dragged(let point, _):
      // The highlight follows the cursor Zone, not the window center (AC-034, LI-009).
      let cursor = SpanLogic.cursor(at: point, in: ctx)
      let newSpan = SpanLogic.accumulate(span, at: cursor, flags: flags, config: config)
      let state = DragState.armed(
        window: window, downFrame: downFrame, flags: flags, config: config, context: ctx, display: cursor.display,
        hit: cursor.hit, span: newSpan)
      return (state, highlightChange(from: s, to: state))
    case .flagsChanged(let f):
      // Releasing the Activation Modifier hides the overlay and cancels; the Span is dropped (AC-035).
      guard f.contains(ModifierSet(config.activation)) else {
        return (.moving(window: window, downFrame: downFrame, flags: f, config: config), [.hideOverlay])
      }
      // Pressing the Span Modifier starts or resumes adding, beginning with the Zone already under the cursor.
      let cursor = SpanLogic.Cursor(display: display, hit: hit)
      let newSpan = SpanLogic.accumulate(span, at: cursor, flags: f, config: config)
      let state = DragState.armed(
        window: window, downFrame: downFrame, flags: f, config: config, context: ctx, display: display, hit: hit,
        span: newSpan)
      return (state, highlightChange(from: s, to: state))
    case .mouseUp(let point, let upFlags):
      // The overlay is on screen in armed, so it is always hidden first (AC-053). A snap or restore needs the
      // Activation Modifier in the mouse-up's own flags (LI-007) and a drop recomputed from the mouse-up point,
      // never a stale hit.
      var fx: [DragEffect] = [.hideOverlay]
      if upFlags.contains(ModifierSet(config.activation)) {
        let cursor = SpanLogic.cursor(at: point, in: ctx)
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
    case .windowGone:
      return (.idle, [.hideOverlay])
    default:
      return (s, [])
    }
  }

  /// The `updateHighlight` that moves the overlay from `old` to `new`; nothing when the highlight is unchanged.
  private static func highlightChange(from old: DragState, to new: DragState) -> [DragEffect] {
    guard let was = highlight(of: old), let now = highlight(of: new), was != now else { return [] }
    return [.updateHighlight(now)]
  }

  /// The highlight an armed state shows: a pure function of its Display, Hit and Span (LI-009).
  private static func highlight(of state: DragState) -> Highlight? {
    guard case .armed(_, _, _, _, let ctx, let display, let hit, let span) = state else { return nil }
    return SpanLogic.drop(at: SpanLogic.Cursor(display: display, hit: hit), span: span, in: ctx).highlight
  }
}
