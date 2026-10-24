import AppKit
import ApplicationServices
import Foundation

// WriteProbe: size, position, size writes with read-back (ADR-0022). Spike only; not shipped.

enum Policy: String { case toggle, leave }

struct Options {
  var bundle: String?
  var pid: pid_t?
  var target: CGRect?
  var policy: Policy = .toggle
  var runs = 1
  var json = false
  var trust = false
  var pauseMs = 0       // sleep after the window is picked and before the first run (lets a script SIGSTOP the app)
  var describe = false  // read-only: list the app's windows with role, subrole, fullscreen, settable flags
  var seedEUI = false   // VO-off stand-in: set AXEnhancedUserInterface=true for the run set, then put the prior value back
}

func usage() -> Never {
  FileHandle.standardError.write(Data("""
    usage: WriteProbe --bundle <id> | --pid <n>  --target x,y,w,h  [--policy toggle|leave]  [--runs N]  [--json]  [--seed-eui]
           WriteProbe --trust
    """.utf8 + [10]))
  exit(64)
}

func parse(_ args: [String]) -> Options {
  var o = Options()
  var i = 0
  func next() -> String {
    i += 1
    guard i < args.count else { usage() }
    return args[i]
  }
  while i < args.count {
    switch args[i] {
    case "--bundle": o.bundle = next()
    case "--pid": guard let p = Int32(next()) else { usage() }; o.pid = p
    case "--target":
      let v = next().split(separator: ",").compactMap { Double($0) }
      guard v.count == 4 else { usage() }
      o.target = CGRect(x: v[0], y: v[1], width: v[2], height: v[3])
    case "--policy": guard let p = Policy(rawValue: next()) else { usage() }; o.policy = p
    case "--runs": guard let n = Int(next()), n > 0 else { usage() }; o.runs = n
    case "--json": o.json = true
    case "--trust": o.trust = true
    case "--pause-ms": guard let n = Int(next()), n >= 0 else { usage() }; o.pauseMs = n
    case "--describe": o.describe = true
    case "--seed-eui": o.seedEUI = true
    default: usage()
    }
    i += 1
  }
  return o
}

let options = parse(Array(CommandLine.arguments.dropFirst()))

if options.trust {
  print(AXIsProcessTrusted())
  exit(0)
}

// Safety: refuse to run without --target (and an app to aim at).
guard options.bundle != nil || options.pid != nil, options.target != nil || options.describe else { usage() }
let target = options.target ?? .zero

// MARK: AX helpers

func axCopy(_ el: AXUIElement, _ attr: String) -> (AXError, CFTypeRef?) {
  var v: CFTypeRef?
  let e = AXUIElementCopyAttributeValue(el, attr as CFString, &v)
  return (e, v)
}

func readFrame(_ w: AXUIElement) -> (AXError, CGRect?) {
  let (e1, pv) = axCopy(w, kAXPositionAttribute)
  guard e1 == .success, let pv else { return (e1, nil) }
  let (e2, sv) = axCopy(w, kAXSizeAttribute)
  guard e2 == .success, let sv else { return (e2, nil) }
  var p = CGPoint.zero, sz = CGSize.zero
  AXValueGetValue(pv as! AXValue, .cgPoint, &p)
  AXValueGetValue(sv as! AXValue, .cgSize, &sz)
  return (.success, CGRect(origin: p, size: sz))
}

func writePoint(_ w: AXUIElement, _ p: CGPoint) -> AXError {
  var p = p
  guard let v = AXValueCreate(.cgPoint, &p) else { return .failure }
  return AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, v)
}

func writeSize(_ w: AXUIElement, _ s: CGSize) -> AXError {
  var s = s
  guard let v = AXValueCreate(.cgSize, &s) else { return .failure }
  return AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, v)
}

func monotonicMs() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000 }

func pickWindow(_ app: AXUIElement) -> AXUIElement? {
  func isStandard(_ w: AXUIElement) -> Bool { axCopy(w, kAXSubroleAttribute).1 as? String == "AXStandardWindow" }
  let (e, v) = axCopy(app, kAXFocusedWindowAttribute)
  if e == .success, let v, isStandard(v as! AXUIElement) { return (v as! AXUIElement) }
  let (e2, ws) = axCopy(app, kAXWindowsAttribute)
  if e2 == .success, let arr = ws as? [AXUIElement] { return arr.first(where: isStandard) ?? arr.first }
  return nil
}

let enhancedAttr = "AXEnhancedUserInterface"

func readEnhanced(_ app: AXUIElement) -> Bool? {
  let (e, v) = axCopy(app, enhancedAttr)
  guard e == .success, let v else { return nil }
  return (v as? Bool) ?? ((v as? NSNumber)?.boolValue)
}

func setEnhanced(_ app: AXUIElement, _ on: Bool) -> AXError {
  AXUIElementSetAttributeValue(app, enhancedAttr as CFString, on as CFBoolean)
}

// MARK: One Snap (mirror of FrameWriting.write, probe-local)

struct SnapOutcome {
  var result: String          // applied | clamped | refused(code) | timedOut | elementGone
  var codes: [Int32]          // return code of each write, in order
  var readBack: CGRect?
  var delta: [Double]         // x, y, w, h (readBack - target)
  var wallMs: Double
  var attempts: Int           // 1 normally, 2 after a retry
  var attemptMs: [Double]
  var enhBefore: Bool?
  var enhDuring: Bool?
  var enhAfter: Bool?
  var restored: Bool
  var topLeftAligned: Bool
  var enhOffCode: Int32?   // AXError of the toggle-off write (nil when not attempted)
  var enhOnCode: Int32?    // AXError of the restore write (nil when not attempted)
}

enum Seq { case ok([Int32]), timeout([Int32]), gone([Int32]), refused([Int32], Int32) }

func writeSequence(_ w: AXUIElement, _ t: CGRect) -> Seq {
  var codes: [Int32] = []
  let steps: [() -> AXError] = [
    { writeSize(w, t.size) }, { writePoint(w, t.origin) }, { writeSize(w, t.size) },
  ]
  for (i, step) in steps.enumerated() {
    let e = step()
    codes.append(e.rawValue)
    switch e {
    case .success: continue
    case .cannotComplete: return .timeout(codes)
    case .invalidUIElement: return .gone(codes)
    default:
      // A refused size write (fixed-size windows such as Calculator) must not stop the position write.
      // Only a refused position write (step 1) makes the whole Snap refused.
      if i == 1 { return .refused(codes, e.rawValue) }
      continue
    }
  }
  return .ok(codes)
}

func snap(app: AXUIElement, window: AXUIElement, target t: CGRect, policy: Policy) -> SnapOutcome {
  let start = monotonicMs()
  let before = readEnhanced(app)
  var toggled = false
  var offCode: Int32?
  var onCode: Int32?
  var during: Bool? = before
  if policy == .toggle, before == true {
    let oe = setEnhanced(app, false)
    offCode = oe.rawValue
    // Some apps answer the set with AXError -25208 yet apply it: trust the read-back, not the return code.
    during = readEnhanced(app)
    toggled = (during == false)
  }
  var restored = true
  // Single-exit function: no early return between the toggle and the restore below, so the restore runs on every path.
  var attemptMs: [Double] = []
  var codes: [Int32] = []
  var result = "applied"
  var attempts = 0
  var rb: CGRect?
  loop: while true {
    attempts += 1
    let a0 = monotonicMs()
    let seq = writeSequence(window, t)
    switch seq {
    case .ok(let c):
      codes = c
      let (e, f) = readFrame(window)
      rb = f
      if e == .cannotComplete { result = "timedOut"; attemptMs.append(monotonicMs() - a0); if attempts < 2 { continue loop }; break loop }
      if e == .invalidUIElement { result = "elementGone" }
      attemptMs.append(monotonicMs() - a0)
      break loop
    case .timeout(let c):
      codes = c; result = "timedOut"
      attemptMs.append(monotonicMs() - a0)
      if attempts < 2 { continue loop }  // retry once; a second consecutive timeout aborts (ADR-0015 C7)
      break loop
    case .gone(let c): codes = c; result = "elementGone"; attemptMs.append(monotonicMs() - a0); break loop
    case .refused(let c, let code): codes = c; result = "refused(\(code))"; attemptMs.append(monotonicMs() - a0); break loop
    }
  }
  let wall = monotonicMs() - start
  if toggled {
    let e = setEnhanced(app, true)
    onCode = e.rawValue
  }
  let after = readEnhanced(app)
  restored = (after == before)  // the prior value is back (or was never changed)
  var delta: [Double] = []
  var aligned = false
  if result == "applied", let rb {
    delta = [rb.minX - t.minX, rb.minY - t.minY, rb.width - t.width, rb.height - t.height]
    if delta.map({ abs($0) }).max()! > 1 { result = "clamped" }
    aligned = abs(delta[0]) <= 1 && abs(delta[1]) <= 1
  }
  return SnapOutcome(result: result, codes: codes, readBack: rb, delta: delta, wallMs: wall, attempts: attempts,
                     attemptMs: attemptMs, enhBefore: before, enhDuring: during, enhAfter: after,
                     restored: restored, topLeftAligned: aligned, enhOffCode: offCode, enhOnCode: onCode)
}

// MARK: Run

func resolvePid() -> pid_t? {
  if let p = options.pid { return p }
  guard let b = options.bundle else { return nil }
  return NSRunningApplication.runningApplications(withBundleIdentifier: b).first?.processIdentifier
}

func fmt(_ r: CGRect?) -> String { r.map { "\($0.minX),\($0.minY),\($0.width),\($0.height)" } ?? "nil" }

guard AXIsProcessTrusted() else {
  FileHandle.standardError.write(Data("not trusted for Accessibility; run --trust\n".utf8)); exit(3)
}
guard let pid = resolvePid() else {
  FileHandle.standardError.write(Data("target app not running (bundle/pid not found)\n".utf8)); exit(4)
}
let appEl = AXUIElementCreateApplication(pid)
AXUIElementSetMessagingTimeout(appEl, 0.25)  // ADR-0015
if options.describe {
  let (we, ws) = axCopy(appEl, kAXWindowsAttribute)
  let arr = (ws as? [AXUIElement]) ?? []
  print("pid \(pid) AXWindows err=\(we.rawValue) count=\(arr.count)")
  func describeOne(_ label: String, _ w: AXUIElement) {
    func str(_ a: String) -> String { let (e, v) = axCopy(w, a); return e == .success ? "\(v!)" : "err\(e.rawValue)" }
    func settable(_ a: String) -> String { var b: DarwinBoolean = false; let e = AXUIElementIsAttributeSettable(w, a as CFString, &b); return e == .success ? "\(b.boolValue)" : "err\(e.rawValue)" }
    let f = readFrame(w)
    print("  \(label) title=\(str(kAXTitleAttribute)) role=\(str(kAXRoleAttribute)) sub=\(str(kAXSubroleAttribute)) fullscreen=\(str("AXFullScreen")) minimized=\(str(kAXMinimizedAttribute)) frame=\(fmt(f.1)) (err \(f.0.rawValue)) posSettable=\(settable(kAXPositionAttribute)) sizeSettable=\(settable(kAXSizeAttribute))")
  }
  for (i, w) in arr.enumerated() { describeOne("[\(i)]", w) }
  let (fe, fv) = axCopy(appEl, kAXFocusedWindowAttribute)
  print("  AXFocusedWindow err=\(fe.rawValue) \(fv == nil ? "nil" : "present")")
  if let fv { describeOne("focused", fv as! AXUIElement) }
  exit(0)
}
guard let win = pickWindow(appEl) else {
  FileHandle.standardError.write(Data("no window found (or AX read timed out)\n".utf8)); exit(5)
}
AXUIElementSetMessagingTimeout(win, 0.25)
let (origErr, originalOpt) = readFrame(win)
guard let original = originalOpt else {
  FileHandle.standardError.write(Data("cannot read original frame (AX error \(origErr.rawValue))\n".utf8)); exit(6)
}

let runSetStart = monotonicMs()
var seedNote = ""
let seedPrior = readEnhanced(appEl)
if options.seedEUI {
  if seedPrior == true { seedNote = "seed: already true" } else {
    let e = setEnhanced(appEl, true)
    seedNote = "seed: set true -> AXError \(e.rawValue) (prior \(seedPrior.map { String($0) } ?? "absent"))"
  }
}
if options.pauseMs > 0 { Thread.sleep(forTimeInterval: Double(options.pauseMs) / 1000) }
var outcomes: [SnapOutcome] = []
for n in 1...options.runs {
  // Alternate between the target and the original so each run actually moves the window.
  let t = (n % 2 == 1) ? target : original
  let o = snap(app: appEl, window: win, target: t, policy: options.policy)
  outcomes.append(o)
  if options.json {
    let d: [String: Any] = [
      "run": n, "pid": Int(pid), "policy": options.policy.rawValue, "result": o.result,
      "target": fmt(t), "readBack": fmt(o.readBack), "delta": o.delta, "codes": o.codes.map { Int($0) },
      "wallMs": (o.wallMs * 10).rounded() / 10, "attempts": o.attempts,
      "attemptMs": o.attemptMs.map { ($0 * 10).rounded() / 10 },
      "enhBefore": o.enhBefore.map { $0 as Any } ?? NSNull(), "enhDuring": o.enhDuring.map { $0 as Any } ?? NSNull(),
      "enhAfter": o.enhAfter.map { $0 as Any } ?? NSNull(), "restored": o.restored,
      "topLeftAligned": o.topLeftAligned,
      "enhOffCode": o.enhOffCode.map { Int($0) as Any } ?? NSNull(), "enhOnCode": o.enhOnCode.map { Int($0) as Any } ?? NSNull(),
    ]
    if let data = try? JSONSerialization.data(withJSONObject: d, options: [.sortedKeys]) {
      print(String(decoding: data, as: UTF8.self))
    }
  }
}

// Always restore the original frame at the end of the run set.
let restoreOutcome = snap(app: appEl, window: win, target: original, policy: options.policy)
let readStart = monotonicMs()
let (finalErr, finalFrame) = readFrame(win)
let finalReadMs = monotonicMs() - readStart
let totalMs = monotonicMs() - runSetStart
if options.seedEUI, seedPrior != true {
  let e = setEnhanced(appEl, seedPrior ?? false)
  seedNote += "; seed restore -> AXError \(e.rawValue), now \(readEnhanced(appEl).map { String($0) } ?? "absent")"
}

// Markdown row: app | policy | runs | applied/clamped/refused/timedOut | median ms | max ms | max |delta| | enh before->after | restored
func count(_ all: [SnapOutcome], _ p: (String) -> Bool) -> Int { all.filter { p($0.result) }.count }
let walls = outcomes.map(\.wallMs).sorted()
let median = walls.isEmpty ? 0 : walls[walls.count / 2]
let maxDelta = outcomes.flatMap(\.delta).map { abs($0) }.max() ?? 0
let enhB = outcomes.first?.enhBefore.map { String($0) } ?? "absent"
let enhA = outcomes.last?.enhAfter.map { String($0) } ?? "absent"
let allRestored = outcomes.allSatisfy(\.restored) && restoreOutcome.restored
let frameBack = finalFrame.map { abs($0.minX - original.minX) <= 1 && abs($0.minY - original.minY) <= 1
  && abs($0.width - original.width) <= 1 && abs($0.height - original.height) <= 1 } ?? false
let label = options.bundle ?? "pid\(pid)"
print("| \(label) | \(options.policy.rawValue) | \(outcomes.count) | \(count(outcomes) { $0 == "applied" })/\(count(outcomes) { $0 == "clamped" })/\(count(outcomes) { $0.hasPrefix("refused") })/\(count(outcomes) { $0 == "timedOut" }) | \(String(format: "%.1f", median)) | \(String(format: "%.1f", walls.last ?? 0)) | \(String(format: "%.1f", maxDelta)) | \(enhB)->\(enhA) | \(allRestored ? "yes" : "no") | frame restored: \(frameBack ? "yes" : "no") | \(seedNote) | final read: AXError \(finalErr.rawValue) in \(String(format: "%.1f", finalReadMs)) ms; run set wall \(String(format: "%.0f", totalMs)) ms |")
