import ApplicationServices
import Foundation
import os

setvbuf(stdout, nil, _IOLBF, 0)

// Flags: --seconds N (auto-exit), --selftest-shift (post synthetic Shift flagsChanged, no mouse events).
let args = CommandLine.arguments
let seconds = args.firstIndex(of: "--seconds").flatMap { Double(args[safe: $0 + 1] ?? "") }
let selftestShift = args.contains("--selftest-shift")
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
var listReads = 0
var listTotals = (windows: 0, layer0: 0, named: 0, nonEmpty: 0, ownerNamed: 0, missing: 0)
@MainActor func onMouseDown() {
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
}
@MainActor func pump() {
  for sample in recorder.drain() {
    all.append(sample)
    print(format(sample))
    if sample.kind == .leftDown { onMouseDown() }
  }
}
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
print("DONE tapDisabledEvents=\(recorder.disabledEvents)")
