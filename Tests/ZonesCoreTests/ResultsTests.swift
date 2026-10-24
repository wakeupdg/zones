import CoreGraphics
import Foundation
import Testing
import ZonesCore

@Test func skipReasonHasTenCases() {
  #expect(SkipReason.allCases.count == 10)
  #expect(
    SkipReason.allCases.map(\.rawValue) == [
      "ownProcess", "systemAgent", "excludedBundle", "unresponsive", "ambiguousMatch",
      "nonStandardSubrole", "sheetOrPopover", "systemDialog", "fullScreen", "positionNotSettable",
    ])
}

@Test func logEventHasNoTitleField() throws {
  let event = LogEvent(
    time: 1, category: .snap, level: .info, message: "skip", bundleID: "com.example", pid: 7,
    skip: .excludedBundle)
  let labels = Mirror(reflecting: event).children.compactMap(\.label)
  #expect(!labels.isEmpty)
  #expect(!labels.contains { $0.lowercased().contains("title") })
  #expect(Set(labels) == ["time", "category", "level", "message", "bundleID", "pid", "skip"])
  let back = try JSONDecoder().decode(LogEvent.self, from: JSONEncoder().encode(event))
  #expect(back == event)
}

@Test func timerIDRawValuesAreStable() {
  let expected = [
    "trustPoll", "healthTick", "suspectResolve", "relaunchGate", "deadTapRetry", "nilUUIDRetry",
    "topologyDebounce", "frameSample", "unresponsiveCooldown",
  ]
  for name in expected {
    #expect(TimerID(rawValue: name)?.rawValue == name)
  }
  #expect(TimerHandle(id: .frameSample, token: 1) != TimerHandle(id: .frameSample, token: 2))
}

@Test func verdictAndFrameWriteResultAreHashable() {
  let verdicts: Set<Verdict> = [.allow(.full), .allow(.positionOnly), .skip(.fullScreen), .allow(.full)]
  #expect(verdicts.count == 3)
  let rect = CGRect(x: 0, y: 0, width: 10, height: 10)
  let results: Set<FrameWriteResult> = [
    .applied(rect), .clamped(rect), .refused(-25205), .timedOut, .elementGone, .noOp(.sameFrame),
    .applied(rect),
  ]
  #expect(results.count == 6)
  let reads: Set<AXRead<Int>> = [.value(1), .value(1), .timedOut, .refused(3)]
  #expect(reads.count == 3)
  #expect(AXStatus.ok != AXStatus.refused(1))
}

@Test func documentKindRawValuesAreFileNames() {
  #expect(DocumentKind.layouts.rawValue == "layouts.json")
  #expect(DocumentKind.assignments.rawValue == "assignments.json")
  #expect(DocumentKind.recovery.rawValue == "enhanced-ui-recovery.json")
}

@Test func eventRingStartsEmptyAtDefaultCapacity() {
  let ring = EventRing()
  #expect(ring.capacity == Constants.ringCapacity)
  #expect(ring.events.isEmpty)
  #expect(ring.skipCounts.isEmpty)
}
