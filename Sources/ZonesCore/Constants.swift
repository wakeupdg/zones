import CoreGraphics
import Foundation

public enum Constants {
  public static let documentVersion = 1, preferencesSchema = 1
  public static let perAppTimeout = 0.25, processTimeout = 1.0, unresponsiveCooldown = 10.0, suspectWindow = 3.0
  public static let relaunchGateFailures = 3, relaunchGateWindow = 10.0, topologyDebounce = 0.2, reenableLimit = 5,
    reenableWindow = 60.0
  public static let deadTapRetry = 30.0, healthTick = 5.0, trustPoll = 1.0, sampleInterval = 1.0 / 60,
    candidateCap = 4, settleSamples = 3
  public static let minFraction = 1.0 / 12, usableSize = CGSize(width: 120, height: 80), dividerSnapRadius = 6.0
  public static let focusSurround = 0.2, surroundMax = 0.45, ringCapacity = 200, frameTolerance = 1.0,
    cycleTolerance = 2.0, numberingEpsilon = 1e-6
}
