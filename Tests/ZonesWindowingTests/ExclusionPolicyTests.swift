import CoreGraphics
import Foundation
import Testing
import ZonesCore
import ZonesWindowing

@Suite struct ExclusionPolicyTests {
  struct PhaseOneRow: Sendable {
    var name: String
    var ref: WindowRef
    var ownPid: pid_t
    var exclusions: Set<String>
    var health: AppHealth
    var now: TimeInterval
    var expected: Verdict
  }

  static func ref(pid: pid_t = 100, bundle: String? = "com.example.app") -> WindowRef {
    WindowRef(
      id: WindowID(rawValue: 1), pid: pid, bundleID: bundle,
      frame: CGRect(x: 0, y: 0, width: 100, height: 100), layer: 0)
  }

  static var phaseOneRows: [PhaseOneRow] {
    var marked = AppHealth()
    marked.markUnresponsive(300, now: 10)
    return [
      PhaseOneRow(
        name: "ownProcess", ref: ref(pid: 42), ownPid: 42, exclusions: [], health: AppHealth(),
        now: 10, expected: .skip(.ownProcess)),
      PhaseOneRow(
        name: "systemAgent", ref: ref(bundle: "com.apple.dock"), ownPid: 1, exclusions: [],
        health: AppHealth(), now: 10, expected: .skip(.systemAgent)),
      PhaseOneRow(
        name: "excludedBundle", ref: ref(bundle: "com.example.excluded"), ownPid: 1,
        exclusions: ["com.example.excluded"], health: AppHealth(), now: 10,
        expected: .skip(.excludedBundle)),
      PhaseOneRow(
        name: "unresponsive", ref: ref(pid: 300), ownPid: 1, exclusions: [], health: marked,
        now: 11, expected: .skip(.unresponsive)),
      PhaseOneRow(
        name: "allow", ref: ref(), ownPid: 1, exclusions: ["com.example.other"],
        health: AppHealth(), now: 10, expected: .allow(.full)),
    ]
  }

  struct PhaseTwoRow: Sendable {
    var name: String
    var facts: WindowFacts
    var expected: Verdict
  }

  static func facts(
    _ subrole: Subrole = .standard, fullScreen: Bool = false, position: Bool = true,
    size: Bool = true
  ) -> WindowFacts {
    WindowFacts(
      subrole: subrole, isFullScreen: fullScreen, positionSettable: position, sizeSettable: size)
  }

  static var phaseTwoRows: [PhaseTwoRow] {
    [
      PhaseTwoRow(name: "nonStandardSubrole dialog", facts: facts(.dialog), expected: .skip(.nonStandardSubrole)),
      PhaseTwoRow(name: "nonStandardSubrole floating", facts: facts(.floating), expected: .skip(.nonStandardSubrole)),
      PhaseTwoRow(name: "nonStandardSubrole unknown", facts: facts(.unknown), expected: .skip(.nonStandardSubrole)),
      PhaseTwoRow(name: "sheetOrPopover sheet", facts: facts(.sheet), expected: .skip(.sheetOrPopover)),
      PhaseTwoRow(name: "sheetOrPopover popover", facts: facts(.popover), expected: .skip(.sheetOrPopover)),
      PhaseTwoRow(name: "systemDialog", facts: facts(.systemDialog), expected: .skip(.systemDialog)),
      PhaseTwoRow(
        name: "systemDialog floating", facts: facts(.systemFloatingWindow), expected: .skip(.systemDialog)),
      PhaseTwoRow(name: "fullScreen", facts: facts(fullScreen: true), expected: .skip(.fullScreen)),
      PhaseTwoRow(
        name: "positionNotSettable", facts: facts(position: false), expected: .skip(.positionNotSettable)),
      PhaseTwoRow(name: "positionOnly", facts: facts(size: false), expected: .allow(.positionOnly)),
      PhaseTwoRow(name: "allow", facts: facts(), expected: .allow(.full)),
    ]
  }

  /// AC-143
  @Test func table() {
    var phaseOneSkips: [SkipReason] = []
    for row in Self.phaseOneRows {
      let got = ExclusionPolicy.phaseOne(
        row.ref, ownPid: row.ownPid, exclusions: row.exclusions, health: row.health, now: row.now)
      #expect(got == row.expected, "phase one row \(row.name)")
      if case .skip(let reason) = row.expected { phaseOneSkips.append(reason) }
    }
    #expect(Set(phaseOneSkips).count == phaseOneSkips.count)
    #expect(
      Set(phaseOneSkips) == [.ownProcess, .systemAgent, .excludedBundle, .unresponsive])

    // every system agent id is skipped
    #expect(ExclusionPolicy.systemAgents.count == 6)
    for id in ExclusionPolicy.systemAgents {
      let got = ExclusionPolicy.phaseOne(
        Self.ref(bundle: id), ownPid: 1, exclusions: [], health: AppHealth(), now: 0)
      #expect(got == .skip(.systemAgent), "\(id)")
    }

    var phaseTwoSkips: [SkipReason] = []
    for row in Self.phaseTwoRows {
      let got = ExclusionPolicy.phaseTwo(row.facts)
      #expect(got == row.expected, "phase two row \(row.name)")
      if case .skip(let reason) = row.expected, !phaseTwoSkips.contains(reason) {
        phaseTwoSkips.append(reason)
      }
    }
    // every reason the policy can produce is covered; a future SkipReason fails here
    #expect(
      Set(phaseOneSkips).union(phaseTwoSkips)
        == Set(SkipReason.allCases).subtracting([.ambiguousMatch]))
    #expect(Set(phaseOneSkips).isDisjoint(with: phaseTwoSkips))
  }
}
