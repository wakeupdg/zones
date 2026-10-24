import CoreGraphics
import Testing
import ZonesCore
import ZonesLayout
import ZonesTestSupport
import ZonesWindowing

/// AC-166 and AC-082: properties of `DragSessionReducer` over seeded random event streams (ADR-0016).
@Suite struct ReducerInvariantTests {
  typealias F = DragFixtures

  static let seeds: Range<UInt64> = 0..<300
  static let eventCount = 200
  static let layout = Fixtures.nineZone

  /// One reducer step with everything the properties need to see.
  struct Step {
    var before: DragState
    var event: DragEvent
    var after: DragState
    var effects: [DragEffect]
    /// Whether the Overlay was on screen before the step (`showOverlay` sets it, `hideOverlay` clears it).
    var overlayShownBefore: Bool
    /// A `frameSample` has been delivered since the last `mouseDown`, counting this step's own event.
    var sampleDelivered: Bool
    /// The last `dragged` point since the last `mouseDown`, as of before this step.
    var lastDragPoint: CGPoint?
    /// The last `Highlight` the Overlay was told about since it was last shown, as of after this step.
    var lastHighlight: Highlight?
    var overlayShownAfter: Bool
  }

  static let movedResult = SampleResult.frame(F.downFrame.offsetBy(dx: 30, dy: 10), F.standardFacts)

  /// The 9-Zone context; odd seeds already have an Original Frame, so drops outside the visible frame restore.
  static func context(for seed: UInt64) -> ArmContext {
    var ctx = F.context
    ctx.hasOriginalFrame = seed % 2 == 1
    return ctx
  }

  static func message(_ seed: UInt64, _ note: String) -> Comment {
    Comment(rawValue: Generator.failureMessage(seed: seed, layout: layout, note: note))
  }

  /// The generated stream for `seed`, with the driver's answers interleaved: each `requestArmContext` gets the
  /// context at once, each `requestSample` a moved sample, and each `armContext` is followed by a replay of the
  /// last `dragged` (the app's driver does that after answering a request).
  static func drive(
    seed: UInt64, context ctx: ArmContext? = nil, config: ModifierConfig = F.config,
    events: [DragEvent]? = nil
  ) -> [Step] {
    let context = ctx ?? Self.context(for: seed)
    var generator = Generator(seed: seed)
    let stream = events ?? generator.dragEvents(count: eventCount, context: context, config: config)
    var queue = stream[...]
    var state = DragState.idle
    var steps: [Step] = []
    var overlayShown = false
    var sampleDelivered = false
    var lastDragPoint: CGPoint?
    var lastHighlight: Highlight?
    while let event = queue.popFirst() {
      switch event {
      case .mouseDown: sampleDelivered = false; lastDragPoint = nil
      case .frameSample: sampleDelivered = true
      default: break
      }
      let pointBefore = lastDragPoint
      if case .dragged(let point, _) = event { lastDragPoint = point }
      let (next, effects) = DragSessionReducer.reduce(state, event)
      let shownBefore = overlayShown
      for effect in effects {
        switch effect {
        case .showOverlay: overlayShown = true; lastHighlight = nil
        case .hideOverlay: overlayShown = false
        case .updateHighlight(let h): lastHighlight = h
        default: break
        }
      }
      steps.append(
        Step(
          before: state, event: event, after: next, effects: effects, overlayShownBefore: shownBefore,
          sampleDelivered: sampleDelivered, lastDragPoint: pointBefore, lastHighlight: lastHighlight,
          overlayShownAfter: overlayShown))
      state = next
      var replies: [DragEvent] = []
      for effect in effects {
        switch effect {
        case .requestArmContext: replies.append(.armContext(context))
        case .requestSample(let ids):
          replies.append(.frameSample(Dictionary(uniqueKeysWithValues: ids.map { ($0, movedResult) })))
        default: break
        }
      }
      // The reducer keeps no cursor point outside armed (its documented known gap), so after a new snapshot the
      // driver re-sends its last `dragged`: after an armContext answer and after a topologyChanged.
      switch event {
      case .armContext, .topologyChanged:
        if let p = lastDragPoint { replies.append(.dragged(point: p, flags: [])) }
      default: break
      }
      queue = replies[...] + queue
    }
    return steps
  }

  static func kind(_ e: DragEvent) -> String {
    switch e {
    case .mouseDown: "mouseDown"
    case .dragged: "dragged"
    case .mouseUp: "mouseUp"
    case .flagsChanged: "flagsChanged"
    case .frameSample: "frameSample"
    case .armContext: "armContext"
    case .windowGone: "windowGone"
    case .topologyChanged: "topologyChanged"
    case .spaceChanged: "spaceChanged"
    case .wake: "wake"
    }
  }

  static let allKinds: Set<String> = [
    "mouseDown", "dragged", "mouseUp", "flagsChanged", "frameSample", "armContext", "windowGone",
    "topologyChanged", "spaceChanged", "wake",
  ]

  // Slice 1
  @Test func dragEventsAreSeededAndTotal() {
    var seen: Set<String> = []
    var sampleKinds: Set<String> = []
    for seed in 0..<200 as Range<UInt64> {
      var a = Generator(seed: seed)
      var b = Generator(seed: seed)
      let first = a.dragEvents(count: 50, context: F.context, config: F.config)
      let second = b.dragEvents(count: 50, context: F.context, config: F.config)
      #expect(first == second, Self.message(seed, "same seed gives equal streams"))
      #expect(first.count == 50, Self.message(seed, "count is exact"))
      if let head = first.first {
        #expect(Self.kind(head) == "mouseDown", Self.message(seed, "mouseDown first"))
      }
      for e in first {
        seen.insert(Self.kind(e))
        if case .frameSample(let results) = e {
          for r in results.values {
            switch r {
            case .frame(let f, _): sampleKinds.insert(f == F.downFrame ? "unmoved" : "moved")
            case .timedOut: sampleKinds.insert("timedOut")
            case .gone: sampleKinds.insert("gone")
            }
          }
        }
      }
    }
    #expect(seen == Self.allKinds, "kinds seen: \(seen.sorted())")
    #expect(sampleKinds == ["moved", "unmoved", "timedOut", "gone"], "sample kinds: \(sampleKinds.sorted())")
    var other = Generator(seed: 1)
    var one = Generator(seed: 2)
    #expect(
      other.dragEvents(count: 50, context: F.context, config: F.config)
        != one.dragEvents(count: 50, context: F.context, config: F.config))
  }

  // Slice 2 (AC-166): the Overlay is shown only on entry to armed. A topologyChanged re-arm from a new snapshot
  // (T21 slice 10, ADR-0014) shows the replacement Overlay while already armed; that is the one allowed re-show.
  @Test func overlayShownOnlyOnEntryToArmed() {
    var shows = 0
    var reArms = 0
    for seed in Self.seeds {
      for step in Self.drive(seed: seed) {
        for case .showOverlay in step.effects {
          shows += 1
          #expect(F.isArmed(step.after), Self.message(seed, "showOverlay must end armed: \(step.event)"))
          if F.isArmed(step.before) {
            reArms += 1
            guard case .topologyChanged = step.event else {
              Issue.record(Self.message(seed, "showOverlay from armed on \(step.event)"))
              continue
            }
          }
        }
      }
    }
    #expect(shows > 300, "property was exercised: \(shows) showOverlay effects")
    #expect(reArms > 0, "topology re-arm path was exercised")
  }

  // Slice 3 (AC-166): every path out of armed hides a shown Overlay, and idle never leaves one up.
  @Test func everyPathToIdleHidesShownOverlay() {
    var exits: [String: Int] = [:]
    var topologyAndSpaceSteps = 0
    for seed in Self.seeds {
      for step in Self.drive(seed: seed) {
        if step.overlayShownBefore && !F.isArmed(step.after) {
          #expect(
            step.effects.contains(.hideOverlay),
            Self.message(seed, "left armed without hideOverlay on \(step.event)"))
          exits[Self.kind(step.event), default: 0] += 1
        }
        if step.after == .idle {
          #expect(!step.overlayShownAfter, Self.message(seed, "idle with the Overlay up after \(step.event)"))
        }
        switch step.event {
        case .topologyChanged, .spaceChanged: if F.isArmed(step.before) { topologyAndSpaceSteps += 1 }
        default: break
        }
      }
    }
    for kind in ["windowGone", "wake", "mouseUp", "flagsChanged"] {
      #expect((exits[kind] ?? 0) > 0, "no exit through \(kind) was exercised: \(exits)")
    }
    #expect(topologyAndSpaceSteps > 0, "topologyChanged/spaceChanged were exercised while armed")
  }

  // Slice 4 (AC-166): a snap needs the Activation Modifier in the mouse-up's own flags.
  @Test func snapOnlyWithActivationAtMouseUp() {
    var snaps = 0
    var unmodified = 0
    for seed in Self.seeds {
      for step in Self.drive(seed: seed) {
        let activation = ModifierSet(F.config.activation)
        let snapped = step.effects.contains(where: F.isSnap)
        if snapped {
          snaps += 1
          guard case .mouseUp(_, let flags) = step.event else {
            Issue.record(Self.message(seed, "snap on \(step.event)"))
            continue
          }
          #expect(flags.contains(activation), Self.message(seed, "snap on a mouseUp without the Activation Modifier"))
        }
        if F.isArmed(step.before), case .mouseUp(_, let flags) = step.event, !flags.contains(activation) {
          unmodified += 1
          #expect(!snapped, Self.message(seed, "snap from armed on a mouseUp without the Activation Modifier"))
          #expect(step.effects.contains(.hideOverlay), Self.message(seed, "armed mouseUp must hide the Overlay"))
        }
      }
    }
    #expect(snaps > 50, "snaps exercised: \(snaps)")
    #expect(unmodified > 0, "armed mouseUp without activation exercised: \(unmodified)")
  }

  // Slice 5 (AC-166): restore only ever follows a mouseUp from armed, never anything from moving.
  @Test func restoreNeverFromMoving() {
    var restores = 0
    for seed in Self.seeds {
      for step in Self.drive(seed: seed) where step.effects.contains(where: F.isRestore) {
        restores += 1
        #expect(!F.isMoving(step.before), Self.message(seed, "restore from moving on \(step.event)"))
        #expect(F.isArmed(step.before), Self.message(seed, "restore from \(step.before) on \(step.event)"))
        guard case .mouseUp = step.event else {
          Issue.record(Self.message(seed, "restore on \(step.event)"))
          continue
        }
        #expect(step.after == .idle, Self.message(seed, "restore must end idle"))
      }
      for step in Self.drive(seed: seed) where F.isMoving(step.before) {
        #expect(!step.effects.contains(where: F.isRestore), Self.message(seed, "moving emitted restore"))
      }
    }
    #expect(restores > 0, "restore exercised: \(restores)")
  }

  /// Both modifiers down, a drag through several Zones, then the generated stream: the Span is non-empty early.
  static func directedPrefix(seed: UInt64, then random: [DragEvent]) -> [DragEvent] {
    var g = Generator(seed: seed &+ 7_000)
    let both = ModifierSet(F.config.activation).union(ModifierSet(F.config.span))
    var events: [DragEvent] = [F.mouseDown(flags: both), .dragged(point: F.center(1), flags: both)]
    for _ in 0..<g.int(2...5) { events.append(.dragged(point: F.center(g.int(1...9)), flags: both)) }
    return events + random
  }

  // Slice 6 (AC-166): releasing then pressing the Span Modifier again keeps the Span's Zone set.
  @Test func spanReleaseThenRepressPreservesSet() {
    let activation = ModifierSet(F.config.activation)
    let spanKey = ModifierSet(F.config.span)
    var seedsHit: Set<UInt64> = []
    var forks = 0
    for seed in Self.seeds {
      var g = Generator(seed: seed)
      let random = g.dragEvents(count: Self.eventCount, context: Self.context(for: seed), config: F.config)
      for steps in [
        Self.drive(seed: seed),
        Self.drive(seed: seed, events: Self.directedPrefix(seed: seed, then: random)),
      ] {
        for step in steps {
          guard case .armed(_, _, let flags, _, _, let display, let hit, let span) = step.after,
            !span.zones.isEmpty, !span.suspended, flags.contains(activation), flags.contains(spanKey)
          else { continue }
          forks += 1
          seedsHit.insert(seed)
          let released = DragSessionReducer.reduce(step.after, .flagsChanged(flags.subtracting(spanKey)))
          let repressed = DragSessionReducer.reduce(released.0, .flagsChanged(flags))
          guard case .armed(_, _, _, _, _, _, _, let after) = repressed.0 else {
            Issue.record(Self.message(seed, "release/re-press left armed: \(repressed.0)"))
            continue
          }
          #expect(
            after.zones == span.zones,
            Self.message(seed, "span \(span.zones) became \(after.zones) via release/re-press at \(display as Any) \(hit)"))
        }
      }
    }
    #expect(seedsHit.count >= 50, "non-empty Span forks hit on \(seedsHit.count) seeds (\(forks) forks)")
  }

  // Slice 7 (AC-166): in pressed, before the first sample returns, no AX-bound effect (snap, restore,
  // requestArmContext) is emitted. Not AX-bound: requestSample, stopSampling, skip, log and the Overlay effects
  // (a wake in pressed still hides the Overlay).
  @Test func noAXEffectFromPressedBeforeFirstSample() {
    var checked = 0
    var withEffects = 0
    for seed in Self.seeds {
      for step in Self.drive(seed: seed) where F.isPressed(step.before) && !step.sampleDelivered {
        checked += 1
        if !step.effects.isEmpty { withEffects += 1 }
        for effect in step.effects {
          switch effect {
          case .snap, .restore, .requestArmContext:
            Issue.record(Self.message(seed, "AX-bound \(effect) from pressed before the first sample, on \(step.event)"))
          default: break  // overlay effects (a wake's hideOverlay) and requestSample, stopSampling, skip, log
          }
        }
      }
    }
    #expect(checked > 300, "pressed steps before a sample: \(checked)")
    #expect(withEffects > 0, "some of those steps emitted effects: \(withEffects)")
  }

  // Slice 8 (AC-082): in every armed state the highlighted set is the set a mouseUp would snap to, and dimAll
  // appears only for hit == none with an Original Frame.
  @Test func highlightEqualsDropSet() {
    var compared = 0
    var snapForks = 0
    var restoreForks = 0
    var dimmed = 0
    for seed in Self.seeds {
      for step in Self.drive(seed: seed) {
        guard case .armed(_, _, let flags, _, let ctx, _, let hit, _) = step.after else { continue }
        // Every updateHighlight that dims obeys the rule against the state it produced.
        for case .updateHighlight(let h) in step.effects where h.dimAll {
          dimmed += 1
          #expect(hit == .none && ctx.hasOriginalFrame, Self.message(seed, "dimAll with hit \(hit), original frame \(ctx.hasOriginalFrame)"))
        }
        if let h = step.lastHighlight, h.dimAll {
          #expect(hit == .none && ctx.hasOriginalFrame, Self.message(seed, "stale dimAll with hit \(hit)"))
        }
        // The arming and re-arming steps hold no live cursor yet: the driver replays the last dragged right after
        // them (the reducer's documented known gap), so the state is compared from that replay on.
        switch step.event {
        case .armContext where !F.isArmed(step.before), .topologyChanged: continue
        default: break
        }
        let point: CGPoint?
        if case .dragged(let p, _) = step.event { point = p } else { point = step.lastDragPoint }
        guard let point else { continue }
        compared += 1
        let primary = step.lastHighlight?.primary ?? []
        let fork = DragSessionReducer.reduce(step.after, .mouseUp(point: point, flags: flags))
        if let plan = fork.1.compactMap({ e -> SnapPlan? in if case .snap(let p) = e { p } else { nil } }).first {
          snapForks += 1
          #expect(plan.zones == primary, Self.message(seed, "highlight \(primary) but a drop snaps \(plan.zones)"))
        } else {
          if fork.1.contains(where: F.isRestore) {
            restoreForks += 1
            #expect(hit == .none && ctx.hasOriginalFrame, Self.message(seed, "restore with hit \(hit)"))
          }
          #expect(primary.isEmpty, Self.message(seed, "highlight \(primary) but a drop snaps nothing"))
        }
      }
    }
    #expect(compared > 1000, "armed steps compared: \(compared)")
    #expect(snapForks > 300, "snap forks: \(snapForks)")
    #expect(restoreForks > 0, "restore forks: \(restoreForks)")
    #expect(dimmed > 0, "dimAll highlights: \(dimmed)")
  }
}
