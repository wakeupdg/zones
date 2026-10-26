import Foundation

/// No-permission checks: AXError mapping table and the statistics helper.
func runSelfTest() -> Int32 {
  var failures = 0
  func check(_ ok: Bool, _ what: String) {
    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL") \(what)")
  }
  check(AXStatus(raw: -25211) == .apiDisabled, "-25211 -> apiDisabled")
  check(AXStatus(raw: 0) == .ok, "0 -> ok")
  check(AXStatus(raw: -25202) == .elementGone, "-25202 -> elementGone")
  check(AXStatus(raw: -25200) == .refused(-25200), "-25200 -> refused(-25200)")
  check(AXStatus(raw: -25204) == .refused(-25204), "-25204 -> refused(-25204)")
  check(AXStatus(raw: -25211).name == "apiDisabled", "name apiDisabled")
  check(AXStatus(raw: 7).name == "refused(7)", "name refused(7)")
  check(rawAXErrorName(-25211) == "apiDisabled", "raw name -25211")
  check(seriesStats([]) == nil, "stats of empty is nil")
  check(seriesStats([5, 1, 3]) == SeriesStats(count: 3, min: 1, median: 3, max: 5), "stats odd list")
  check(seriesStats([4, 1, 3, 2]) == SeriesStats(count: 4, min: 1, median: 2.5, max: 4), "stats even list")
  let gaps = interArrivalMs([0, 0.010, 0.030, 0.060])
  check(gaps.count == 3 && abs(gaps[0] - 10) < 1e-9 && abs(gaps[2] - 30) < 1e-9, "interArrivalMs")
  check(interArrivalMs([1]).isEmpty, "interArrivalMs single")
  // Cadence summary: one gesture down=1.0 up=2.0; end-of-gesture events land at 2.01 / 2.03.
  let endOnly = summarizeCadence(
    events: [CadenceEvent(name: "AXWindowMoved", t: 2.01), CadenceEvent(name: "AXWindowMoved", t: 2.03)],
    downs: [1.0], ups: [2.0])
  check(endOnly.count == 1 && endOnly[0].count == 2 && endOnly[0].betweenDownUp == 0
    && endOnly[0].within50msAfterUp == 2 && endOnly[0].verdict == "end-of-gesture-only", "cadence end-of-gesture-only")
  let cont = summarizeCadence(
    events: (0..<10).map { CadenceEvent(name: "AXWindowMoved", t: 1.1 + Double($0) * 0.1) },
    downs: [1.0], ups: [2.5])
  check(cont[0].betweenDownUp == 10 && cont[0].verdict == "continuous"
    && abs((cont[0].interArrival?.median ?? 0) - 100) < 1e-6, "cadence continuous + median 100 ms")
  let none = summarizeCadence(events: [], downs: [], ups: [])
  check(none.isEmpty, "cadence no events -> empty summary")
  check(cadenceVerdict(count: 0, betweenDownUp: 0, gestures: 0) == "no-data", "verdict no-data")
  // Revoke summary: marker at t=10; apiDisabled first seen at t=12.5; tap silent afterwards.
  func row(_ t: Double, _ raw: Int32, _ trusted: Bool, _ tapOn: Bool, _ ev: Int) -> RevokeRow {
    RevokeRow(t: t, raw: raw, status: AXStatus(raw: raw), trusted: trusted, tapEnabled: tapOn, tapEvents: ev)
  }
  let rs = summarizeRevoke(
    rows: [row(9.5, 0, true, true, 5), row(10.5, 0, true, true, 4), row(12.5, -25211, true, true, 3), row(13, -25211, true, true, 0)],
    markerT: 10)
  check(rs.firstApiDisabledLatency == 2.5 && rs.heartbeatPass == true, "revoke latency 2.5 s passes 5 s rule")
  check(rs.trustedValuesAfter10s == [true] && rs.tapEventsAfterMarker == 7 && rs.tapEnabledAtEnd == true, "revoke trusted/tap fields")
  let late = summarizeRevoke(rows: [row(10.5, 0, true, true, 0), row(17, -25211, false, false, 0)], markerT: 10)
  check(late.firstApiDisabledLatency == 7 && late.heartbeatPass == false && late.trustedValuesAfter10s == [true, false], "revoke 7 s fails the rule")
  check(summarizeRevoke(rows: [row(1, 0, true, true, 0)], markerT: nil).firstApiDisabledLatency == nil, "revoke without marker")
  print(failures == 0 ? "selftest OK" : "selftest FAILED (\(failures))")
  return failures == 0 ? 0 : 1
}
