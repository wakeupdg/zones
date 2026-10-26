import CoreGraphics
import Foundation
import os

/// Mirrors CONTRACTS.md InputEvent field names (kind, point, flags, windowUnderPointer, time) plus latency fields.
struct Sample: Sendable {
  var kind: InputKind
  var point: CGPoint
  var flags: UInt64
  var windowUnderPointer: UInt32?
  var time: TimeInterval  // event timestamp in seconds (mach ticks converted)
  var delayMs: Double  // callback entry minus event timestamp
  var callbackMs: Double  // callback body duration
}

enum Mach {
  static let timebase: mach_timebase_info_data_t = {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    return info
  }()

  static func ticksToNs(_ ticks: UInt64) -> Double {
    Double(ticks) * Double(timebase.numer) / Double(timebase.denom)
  }
}

/// Lock-protected buffer shared by the tap thread (producer) and the main thread (consumer).
final class Recorder: @unchecked Sendable {
  private let samples = OSAllocatedUnfairLock(initialState: [Sample]())
  private let portLock = NSLock()
  private nonisolated(unsafe) var portStorage: CFMachPort?
  private let disabledCount = OSAllocatedUnfairLock(initialState: 0)

  var port: CFMachPort? {
    get { portLock.withLock { portStorage } }
    set { portLock.withLock { portStorage = newValue } }
  }
  var disabledEvents: Int { disabledCount.withLock { $0 } }

  func noteDisabled() { disabledCount.withLock { $0 += 1 } }
  func append(_ sample: Sample) { samples.withLock { $0.append(sample) } }
  func drain() -> [Sample] { samples.withLock { let out = $0; $0 = []; return out } }
}
