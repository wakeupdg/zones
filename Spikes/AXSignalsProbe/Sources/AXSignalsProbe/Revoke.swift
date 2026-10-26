import ApplicationServices
import Foundation

// MARK: - Pure summary (selftest-covered)

struct RevokeRow: Sendable {
  var t: Double
  var raw: Int32
  var status: AXStatus
  var trusted: Bool
  var tapEnabled: Bool
  var tapEvents: Int
  var altRaw: Int32 = 0
}

struct RevokeSummary: Equatable {
  var firstApiDisabledLatency: Double?
  var firstAltApiDisabledLatency: Double?
  var heartbeatPass: Bool?
  var trustedValuesAfter10s: [Bool]
  var tapEventsAfterMarker: Int
  var tapEnabledAtEnd: Bool?
}

/// `heartbeatPass` is true only when apiDisabled was first seen at most 5.0 s after the marker.
func summarizeRevoke(rows: [RevokeRow], markerT: Double?) -> RevokeSummary {
  guard let m = markerT else {
    return RevokeSummary(
      firstApiDisabledLatency: nil, firstAltApiDisabledLatency: nil, heartbeatPass: nil, trustedValuesAfter10s: [],
      tapEventsAfterMarker: 0, tapEnabledAtEnd: rows.last?.tapEnabled)
  }
  let after = rows.filter { $0.t >= m }
  let latency = after.first(where: { $0.status == .apiDisabled }).map { $0.t - m }
  let altLatency = after.first(where: { AXStatus(raw: $0.altRaw) == .apiDisabled }).map { $0.t - m }
  var trusted: [Bool] = []
  for r in after where r.t <= m + 10 && trusted.last != r.trusted { trusted.append(r.trusted) }
  return RevokeSummary(
    firstApiDisabledLatency: latency, firstAltApiDisabledLatency: altLatency, heartbeatPass: latency.map { $0 <= 5.0 } ?? false,
    trustedValuesAfter10s: trusted, tapEventsAfterMarker: after.reduce(0) { $0 + $1.tapEvents },
    tapEnabledAtEnd: rows.last?.tapEnabled)
}

// MARK: - revoke mode

/// Spike-only: lock-guarded rows and marker shared between the main-loop timer and the stdin thread.
final class RevokeRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var rows: [RevokeRow] = []
  private var marker: Double?
  func add(_ r: RevokeRow) { lock.lock(); rows.append(r); lock.unlock() }
  func mark() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if marker == nil { marker = now() }
    return true
  }
  var snapshot: (rows: [RevokeRow], marker: Double?) {
    lock.lock()
    defer { lock.unlock() }
    return (rows, marker)
  }
}

func runRevokeMode(_ args: [String]) -> Int32 {
  let seconds = Double(argValue("--seconds", in: args) ?? "90") ?? 90
  probeLog.open(mode: "revoke", app: "system")
  let trusted0 = AXIsProcessTrusted()
  probeLog.emit([
    "event": "start", "mode": "revoke", "seconds": seconds, "trusted": trusted0,
    "note": "responsible process is the host app that launched this probe (e.g. Terminal); its Accessibility grant is what is tested",
  ])
  print("AXIsProcessTrusted=\(trusted0). Responsible process = the app that launched this probe; its grant is what you revoke.")
  print("Press Return at the instant you turn the Accessibility toggle OFF; keep moving the mouse.")

  let rec = RevokeRecorder()
  let tap = ListenOnlyTap { _ in }
  let tapOK = tap.install(types: [.mouseMoved, .leftMouseDragged, .flagsChanged])
  probeLog.emit(["event": "tap", "created": tapOK])
  if !tapOK { probeLog.emit(["event": "tapNil"]) }

  // Return on stdin = the revoke marker. EOF (no terminal) just ends the reader.
  let reader = Thread {
    while readLine() != nil {
      if rec.mark() { probeLog.emit(["marker": "revoked-now"]) }
    }
  }
  reader.name = "revoke-stdin"
  reader.start()

  let timer = Timer(timeInterval: 0.25, repeats: true) { _ in
    let r = trivialRead()
    let alt = altTrivialRead()
    let row = RevokeRow(
      t: now(), raw: r.raw, status: r.status, trusted: AXIsProcessTrusted(),
      tapEnabled: tap.isEnabled, tapEvents: tap.takeCount(), altRaw: alt.raw)
    rec.add(row)
    probeLog.emit([
      "event": "row", "raw": Int(row.raw), "rawName": rawAXErrorName(row.raw), "status": row.status.name,
      "altRaw": Int(alt.raw), "altRawName": rawAXErrorName(alt.raw), "altStatus": alt.status.name,
      "trusted": row.trusted, "tapEnabled": row.tapEnabled, "tapEvents": row.tapEvents,
    ])
  }
  RunLoop.main.add(timer, forMode: .common)
  CFRunLoopRunInMode(.defaultMode, seconds, false)
  timer.invalidate()

  let snap = rec.snapshot
  let s = summarizeRevoke(rows: snap.rows, markerT: snap.marker)
  func lat(_ v: Double?) -> Any { v.map { Decimal(string: String(format: "%.3f", $0)) ?? 0 } ?? NSNull() }
  probeLog.emit([
    "event": "summary", "rows": snap.rows.count, "markerPressed": snap.marker != nil,
    "firstApiDisabledLatencySec": lat(s.firstApiDisabledLatency),
    "firstAltApiDisabledLatencySec": lat(s.firstAltApiDisabledLatency),
    "heartbeatPass": s.heartbeatPass.map { $0 as Any } ?? NSNull(),
    "trustedValuesAfter10s": s.trustedValuesAfter10s, "tapEventsAfterMarker": s.tapEventsAfterMarker,
    "tapEnabledAtEnd": s.tapEnabledAtEnd.map { $0 as Any } ?? NSNull(), "tapCreated": tapOK,
  ])
  print("revoke rows=\(snap.rows.count) marker=\(snap.marker != nil) tap=\(tapOK ? "created" : "tapNil")")
  if snap.marker != nil {
    print("  first apiDisabled after marker: \(s.firstApiDisabledLatency.map { String(format: "%.2f s", $0) } ?? "never") heartbeatPass=\(s.heartbeatPass == true)")
    print("  first apiDisabled via alt read (system-wide AXRole): \(s.firstAltApiDisabledLatency.map { String(format: "%.2f s", $0) } ?? "never")")
    print("  AXIsProcessTrusted in 10 s after marker: \(s.trustedValuesAfter10s)")
    print("  tap events after marker: \(s.tapEventsAfterMarker), tap enabled at end: \(s.tapEnabledAtEnd.map(String.init) ?? "n/a")")
  } else {
    print("  no marker pressed; rows only")
  }
  withExtendedLifetime(tap) {}
  return 0
}
