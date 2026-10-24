import Foundation

/// `thread` mode. Part A: custom run-loop source on the dedicated thread, signalled at t=0
/// and again after `--idle` seconds. Part B (needs AX trust) is added in the next slice.
func runThreadMode(_ args: [String]) -> Int32 {
  let idle = Double(argValue("--idle", in: args) ?? "60") ?? 60
  probeLog.open(mode: "thread", app: "calculator")
  probeLog.emit(["event": "start", "mode": "thread", "idle": idle])

  let th = ObserverThread()
  th.start()

  th.signalCustom()
  Thread.sleep(forTimeInterval: 0.5)
  probeLog.emit(["event": "idle-begin", "seconds": idle])
  Thread.sleep(forTimeInterval: idle)
  probeLog.emit(["event": "idle-end"])
  th.signalCustom()
  Thread.sleep(forTimeInterval: 0.5)

  let custom = th.recorded.filter { $0.source == "custom" }
  let allOnThread = custom.allSatisfy { $0.onObserverThread && !$0.onMain && $0.threadName == ObserverThread.threadName }
  let early = th.returnedEarly
  th.stop()
  Thread.sleep(forTimeInterval: 0.2)

  let partA = custom.count == 2 && allOnThread && !early
  probeLog.emit([
    "event": "partA", "pass": partA, "callbacks": custom.count,
    "allOnAxObserver": allOnThread, "runLoopReturnedEarly": early,
  ])
  print("partA: \(partA ? "PASS" : "FAIL") callbacks=\(custom.count) allOnAxObserver=\(allOnThread) runLoopReturnedEarly=\(early)")
  return partA ? 0 : 1
}
