import ApplicationServices
import CoreGraphics
import Foundation

/// Throwaway analogue of InputSource: a listen-only session tap on a dedicated .userInteractive thread.
final class TapRunner: @unchecked Sendable {
  let config: TapConfig
  let recorder: Recorder
  private var thread: Thread?
  private var runLoop: CFRunLoop?
  private let ready = DispatchSemaphore(value: 0)
  private var created = false

  init(config: TapConfig, recorder: Recorder) {
    self.config = config
    self.recorder = recorder
  }

  /// Returns true when CGEvent.tapCreate returned non-nil.
  func start() -> Bool {
    let thread = Thread { [self] in
      let userInfo = Unmanaged.passUnretained(recorder).toOpaque()
      guard
        let port = CGEvent.tapCreate(
          tap: .cgSessionEventTap, place: .tailAppendEventTap, options: config.options,
          eventsOfInterest: config.eventMask, callback: tapCallback, userInfo: userInfo)
      else {
        ready.signal()
        return
      }
      recorder.port = port
      let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
      runLoop = CFRunLoopGetCurrent()
      CFRunLoopAddSource(runLoop, source, .commonModes)
      CGEvent.tapEnable(tap: port, enable: true)
      created = true
      ready.signal()
      CFRunLoopRun()
      CFMachPortInvalidate(port)  // research item 7: invalidate, not just release
    }
    thread.qualityOfService = .userInteractive
    thread.name = "TapProbe.tap"
    self.thread = thread
    thread.start()
    ready.wait()
    return created
  }

  func stop() {
    if let runLoop { CFRunLoopStop(runLoop) }
  }
}

private let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
  let entry = mach_absolute_time()
  guard let userInfo else { return Unmanaged.passUnretained(event) }
  let recorder = Unmanaged<Recorder>.fromOpaque(userInfo).takeUnretainedValue()
  if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
    recorder.noteDisabled()
    if let port = recorder.port { CGEvent.tapEnable(tap: port, enable: true) }
    return Unmanaged.passUnretained(event)
  }
  guard let kind = InputKind(type) else { return Unmanaged.passUnretained(event) }
  let windowField = event.getIntegerValueField(.mouseEventWindowUnderMousePointer)
  // Observed on macOS 27 / Apple Silicon: CGEvent.timestamp is already in nanoseconds of mach uptime,
  // NOT mach ticks (the research note assumed ticks). Only the callback-entry clock needs the timebase.
  let eventTicks = event.timestamp
  let sample = Sample(
    kind: kind, point: event.location, flags: event.flags.rawValue,
    windowUnderPointer: windowField > 0 ? UInt32(truncatingIfNeeded: windowField) : nil,
    time: Double(eventTicks) / 1e9,
    delayMs: (Mach.ticksToNs(entry) - Double(eventTicks)) / 1e6,
    callbackMs: 0)
  var finished = sample
  finished.callbackMs = (Mach.ticksToNs(mach_absolute_time()) - Mach.ticksToNs(entry)) / 1e6
  recorder.append(finished)
  return Unmanaged.passUnretained(event)  // listen-only: return value ignored, never alters the gesture
}
