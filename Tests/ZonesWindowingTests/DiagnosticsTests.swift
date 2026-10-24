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

  @Test func reportContentsAndPreviewFirst() throws {
    let os = OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
    let bundle = BundleInfo.make(
      infoDictionary: ["CFBundleShortVersionString": "2.0", "CFBundleVersion": "7"], signingCommonName: nil,
      osVersion: os)
    let topology = Fixtures.threeDisplays
    let a = Assignment(
      layout: LayoutID(rawValue: "grid-2x2"), displayName: "Primary 1x",
      lastVisibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055), lastScale: 1, lastSeen: nil)
    let b = Assignment(
      layout: LayoutID(rawValue: "cols-3"), displayName: "Left 2x",
      lastVisibleFrame: CGRect(x: -1440, y: 0, width: 1440, height: 900), lastScale: 2, lastSeen: nil)
    let assignments = ["11111111-1111-4111-8111-111111111111": a, "22222222-2222-4222-8222-222222222222": b]
    var ring = EventRing()
    let bundles = ["com.example.a", "com.example.b"]
    for i in 0..<250 {
      let skip: SkipReason? = i % 2 == 0 ? .fullScreen : nil
      ring.append(
        LogEvent(
          time: Double(i), category: .snap, level: .info, message: "e\(i)", bundleID: bundles[i % 2],
          pid: 5, skip: skip))
    }

    let report = Diagnostics.report(
      bundle: bundle, permission: .granted, tap: .alive, topology: topology, assignments: assignments,
      prefs: .defaults, ring: ring)
    #expect(report.version == "2.0")
    #expect(report.build == "7")
    #expect(report.signingIdentity == "ad-hoc")
    #expect(report.macOS == "15.0.0")
    #expect(report.permission == "granted")
    #expect(report.tap == "alive")
    #expect(report.displays.count == 3)
    for (shown, source) in zip(report.displays, topology.displays) {
      guard case .uuid(let key) = source.key else { Issue.record("fixture key is not a uuid"); continue }
      #expect(shown.key == key)
      #expect(shown.frame == source.frame)
      #expect(shown.visibleFrame == source.visibleFrame)
      #expect(shown.scale == source.scale)
    }
    #expect(report.assignments == assignments)
    #expect(report.preferences == .defaults)
    #expect(report.events.count == 200)
    #expect(report.events.first?.time == 50)
    #expect(report.skipCounts == ring.skipCounts)
    #expect(report.skipCounts["com.example.a"]?[.fullScreen] == 125)

    let text = report.render()
    for d in report.displays { #expect(text.contains(d.key)) }
    for key in assignments.keys { #expect(text.contains(key)) }
    for bundleID in report.skipCounts.keys { #expect(text.contains(bundleID)) }
    #expect(text == report.render())

    let empty = Diagnostics.report(
      bundle: bundle, permission: .notGranted, tap: .unavailable, topology: nil, assignments: [:],
      prefs: .defaults, ring: EventRing())
    #expect(empty.displays.isEmpty)

    let data = try JSONEncoder().encode(report)
    let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let events = try #require(root["events"] as? [[String: Any]])
    let keys = Set(events.flatMap { $0.keys })
    #expect(keys == ["time", "category", "level", "message", "bundleID", "pid", "skip"])
    #expect(!keys.contains("title") && !keys.contains("name"))

    let effects = Diagnostics.effects(for: report)
    #expect(effects == [.preview(text), .copy(text)])
  }
}
