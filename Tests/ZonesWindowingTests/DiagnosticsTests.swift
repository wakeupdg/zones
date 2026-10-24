import Foundation
import Testing
import ZonesCore
import ZonesTestSupport
import ZonesWindowing

@Suite struct DiagnosticsTests {
  static func event(_ i: Int, category: LogCategory = .core) -> LogEvent {
    LogEvent(time: Double(i), category: category, level: .info, message: "e\(i)")
  }

  @Test func ringBoundedAndSinks() {
    var ring = EventRing()
    for i in 0..<500 { ring.append(Self.event(i)) }
    #expect(ring.events.count == 200)
    #expect(ring.events.map(\.time) == (300..<500).map(Double.init))

    var small = EventRing(capacity: 3)
    for i in 0..<10 { small.append(Self.event(i)) }
    #expect(small.events.map(\.message) == ["e7", "e8", "e9"])

    let expected: [LogCategory] = [
      .core, .layout, .windowing, .input, .permission, .topology, .snap, .restore, .shortcuts, .overlay,
      .diagnostics, .app,
    ]
    #expect(LogCategory.allCases == expected)

    let log = Log()
    let sink = ArrayLogSink()
    log.install(sink: sink)
    for i in 0..<5 { log.event(Self.event(i)) }
    #expect(sink.events.count == 5)
    #expect(log.ring().events == sink.events)

    let unified = UnifiedLogSink()
    for category in LogCategory.allCases {
      for level in [LogLevel.debug, .info, .notice, .error] {
        unified.write(LogEvent(time: 0, category: category, level: level, message: "probe"))
      }
    }
  }

  static func ref(_ bundle: String?, pid: Int32) -> WindowRef {
    WindowRef(id: WindowID(rawValue: 1), pid: pid, bundleID: bundle, frame: .zero, layer: 0)
  }

  @Test func skipReasonsCounted() {
    let log = Log()
    let sink = ArrayLogSink()
    log.install(sink: sink)
    for reason in SkipReason.allCases {
      let before = sink.events.count
      log.skip(reason, Self.ref("com.example.a", pid: 42), category: .snap)
      #expect(sink.events.count == before + 1)
      let e = sink.events.last
      #expect(e?.skip == reason)
      #expect(e?.bundleID == "com.example.a")
      #expect(e?.pid == 42)
      #expect(e?.category == .snap)
      #expect(e?.message == "skip " + reason.rawValue)
      #expect(log.ring().skipCounts["com.example.a"]?[reason] == 1)
    }
    log.skip(.fullScreen, Self.ref("com.example.a", pid: 42), category: .snap)
    #expect(log.ring().skipCounts["com.example.a"]?[.fullScreen] == 2)
    log.skip(.fullScreen, Self.ref("com.example.b", pid: 7), category: .snap)
    #expect(log.ring().skipCounts["com.example.b"]?[.fullScreen] == 1)
    #expect(log.ring().skipCounts["com.example.a"]?[.fullScreen] == 2)
    log.skip(.ownProcess, nil, category: .snap)
    #expect(log.ring().skipCounts["unknown"]?[.ownProcess] == 1)
    #expect(sink.events.last?.pid == nil)
    #expect(sink.events.last?.bundleID == nil)

    let shared = ArrayLogSink()
    Log.shared.install(sink: shared)
    Log.skip(.systemAgent, Self.ref("com.example.c", pid: 9), category: .windowing)
    #expect(shared.events.count == 1)
    #expect(shared.events.first?.skip == .systemAgent)
    #expect(Log.shared.ring().skipCounts["com.example.c"]?[.systemAgent] == 1)
  }

  static func emptyReport(_ bundle: BundleInfo) -> DiagnosticsReport {
    Diagnostics.report(
      bundle: bundle, permission: .granted, tap: .alive, topology: nil, assignments: [:],
      prefs: .defaults, ring: EventRing())
  }

  @Test func reportNamesSigningIdentity() {
    let os = OperatingSystemVersion(majorVersion: 14, minorVersion: 5, patchVersion: 1)
    let info: [String: Any] = ["CFBundleShortVersionString": "1.2.3", "CFBundleVersion": "45"]
    let named = BundleInfo.make(
      infoDictionary: info, signingCommonName: "Developer ID Application: Example (TEAM123)", osVersion: os)
    #expect(named.signingIdentity == "Developer ID Application: Example (TEAM123)")
    #expect(named.version == "1.2.3")
    #expect(named.build == "45")
    #expect(named.macOS == "14.5.1")
    let lines = Self.emptyReport(named).render().split(separator: "\n").map(String.init)
    #expect(lines.contains("signingIdentity: Developer ID Application: Example (TEAM123)"))

    for name in [nil, ""] as [String?] {
      let adhoc = BundleInfo.make(infoDictionary: info, signingCommonName: name, osVersion: os)
      #expect(adhoc.signingIdentity == "ad-hoc")
      #expect(Self.emptyReport(adhoc).render().split(separator: "\n").contains("signingIdentity: ad-hoc"))
    }

    let missing = BundleInfo.make(infoDictionary: nil, signingCommonName: nil, osVersion: os)
    #expect(missing.version == "unknown")
    #expect(missing.build == "unknown")

    #expect(!BundleInfo.current().signingIdentity.isEmpty)
  }
}
