import ApplicationServices
import Foundation
import os

setvbuf(stdout, nil, _IOLBF, 0)

// Flags: --seconds N (auto-exit), --selftest-shift (post synthetic Shift flagsChanged, no mouse events).
let args = CommandLine.arguments
let seconds = args.firstIndex(of: "--seconds").flatMap { Double(args[safe: $0 + 1] ?? "") }
let selftestShift = args.contains("--selftest-shift")
let selftestResolve = args.contains("--selftest-resolve")
let listNow = args.contains("--list-now")  // read the window list once at startup, no mouse event needed

extension Array {
  subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// Preflight: read-only Accessibility check. Never prompt, never touch Screen Recording / Input Monitoring APIs.
let config = TapConfig.production
print("PREFLIGHT AXIsProcessTrusted=\(AXIsProcessTrusted()) pid=\(getpid())")
print("CONFIG listenOnly=\(config.listenOnly) mask=\(config.mask.map(\.rawValue).sorted()) place=tailAppendEventTap tap=session")
print("os=\(ProcessInfo.processInfo.operatingSystemVersionString)")

let stopFlag = OSAllocatedUnfairLock(initialState: false)
signal(SIGINT, SIG_IGN)
let sigSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
sigSource.setEventHandler { stopFlag.withLock { $0 = true } }
sigSource.resume()

let recorder = Recorder()
let runner = TapRunner(config: config, recorder: recorder)
let tapCreated = runner.start()
print("TAP created=\(tapCreated)")
guard tapCreated else {
  print("TAP FAILED: tapCreate returned nil (Accessibility not granted to this process or its host?)")
  exit(2)
}

func format(_ s: Sample) -> String {
  let win = s.windowUnderPointer.map(String.init) ?? "nil"
  return String(
    format: "EVENT kind=%@ point=(%.1f,%.1f) flags=0x%llx windowUnderPointer=%@ time=%.6f delayMs=%.3f callbackMs=%.4f",
    s.kind.rawValue, s.point.x, s.point.y, s.flags, win, s.time, s.delayMs, s.callbackMs)
}

if selftestShift {
  print("SYNTHETIC posting Shift flagsChanged down/up (no mouse events)")
  Synthetic.shiftTap()
}

let start = Date()
var all = [Sample]()
var tapLines = [String]()
var lastTapList = Date()
// Drag resolution state (main thread only): baseline at mouse-down, compared after ~10 dragged events or at mouse-up.
struct DragState {
  var downPoint: CGPoint
  var candidates: [WindowInfo]
  var fieldID: UInt32?
  var dragged = 0
}
var drag: DragState?
let resolveAfterDrags = 10

@MainActor func finishResolution(reason: String) {
  guard let state = drag else { return }
  drag = nil
  guard state.dragged > 0 else { print("RESOLVE-SKIPPED reason=no-dragged-events (\(reason))"); return }
  let after = WindowList.read().layer0
  let result = Resolver.resolve(before: state.candidates, after: after, fieldID: state.fieldID)
  print("RESOLVE candidates=\(state.candidates.count) draggedEvents=\(state.dragged) fieldID=\(state.fieldID.map(String.init) ?? "nil") trigger=\(reason)")
  print(Resolver.line(result))
  resolutions.append(result)
}
var resolutions = [Resolution]()
var listReads = 0
var listTotals = (windows: 0, layer0: 0, named: 0, nonEmpty: 0, ownerNamed: 0, missing: 0)
@MainActor @discardableResult func onMouseDown() -> ListReport {
  let report = WindowList.read()
  listReads += 1
  listTotals.windows += report.total
  listTotals.layer0 += report.layer0.count
  listTotals.named += report.namedCount
  listTotals.nonEmpty += report.nonEmptyNamedCount
  listTotals.ownerNamed += report.ownerNamedCount
  listTotals.missing += report.missingBounds + report.missingLayer + report.missingPid + report.missingNumber
  print(WindowList.describe(report))
  if listReads == 1 { for w in report.layer0.prefix(5) { print(WindowList.describe(w)) } }
  return report
}
@MainActor func pump() {
  for sample in recorder.drain() {
    all.append(sample)
    print(format(sample))
    switch sample.kind {
    case .leftDown:
      drag = nil
      let report = onMouseDown()
      drag = DragState(
        downPoint: sample.point, candidates: Resolver.candidates(in: report.windows, under: sample.point),
        fieldID: sample.windowUnderPointer)
    case .leftDragged:
      guard var state = drag else { break }
      state.dragged += 1
      if state.fieldID == nil { state.fieldID = sample.windowUnderPointer }  // first dragged event supplies the id if mouse-down had none
      drag = state
      if state.dragged == resolveAfterDrags { finishResolution(reason: "\(resolveAfterDrags)-drags") }
    case .leftUp:
      finishResolution(reason: "mouse-up")
    case .flagsChanged:
      break
    }
  }
}
if selftestResolve { print("SYNTHETIC-LOGIC resolver self-test on fabricated lists: \(Resolver.selfTest() ? "PASS" : "FAIL")") }
if listNow { print("SYNTHETIC window list read at startup (no mouse-down)"); onMouseDown() }
while !stopFlag.withLock({ $0 }) {
  if let seconds, Date().timeIntervalSince(start) >= seconds { break }
  RunLoop.current.run(until: Date().addingTimeInterval(0.05))
  pump()
  if Date().timeIntervalSince(lastTapList) >= 1 {
    lastTapList = Date()
    if let line = Stats.ownTapLine() { tapLines.append(line); print(line) }
  }
}
pump()
if let line = Stats.ownTapLine() { tapLines.append(line); print(line) }
runner.stop()
for line in Stats.summary(all, tapLines: tapLines, seconds: Date().timeIntervalSince(start)) { print(line) }
print("SUMMARY windowlist reads=\(listReads) totalEntries=\(listTotals.windows) layer0=\(listTotals.layer0) entriesMissingKeys=\(listTotals.missing) kCGWindowName-non-nil=\(listTotals.named) kCGWindowName-non-empty=\(listTotals.nonEmpty) kCGWindowOwnerName-non-nil=\(listTotals.ownerNamed)")
print("SUMMARY resolutions=\(resolutions.count) byPidFrame=\(resolutions.filter(\.byPidFrame).count) byField=\(resolutions.filter(\.byField).count)")
print("DONE tapDisabledEvents=\(recorder.disabledEvents)")
