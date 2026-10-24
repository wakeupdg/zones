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

  static func message(_ seed: UInt64, _ note: String) -> Comment {
    Comment(rawValue: Generator.failureMessage(seed: seed, layout: layout, note: note))
  }

  /// The generated stream for `seed`, with the driver's answers interleaved: each `requestArmContext` gets the
  /// context at once, each `requestSample` a moved sample, and each `armContext` is followed by a replay of the
  /// last `dragged` (the app's driver does that after answering a request).
  static func drive(
    seed: UInt64, context: ArmContext = F.context, config: ModifierConfig = F.config,
    events: [DragEvent]? = nil
  ) -> [Step] {
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
      if case .armContext = event, let p = lastDragPoint { replies.append(.dragged(point: p, flags: [])) }
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
}
