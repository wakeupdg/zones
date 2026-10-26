import CoreGraphics
import Foundation
import Testing
import ZonesCore

@Test func constantsMatchContract() {
  #expect(Constants.documentVersion == 1)
  #expect(Constants.preferencesSchema == 1)
  #expect(Constants.minFraction == 1.0 / 12)
  #expect(Constants.sampleInterval == 1.0 / 60)
  #expect(Constants.ringCapacity == 200)
  #expect(Constants.candidateCap == 4)
  #expect(Constants.settleSamples == 3)
  #expect(Constants.frameTolerance == 1)
  #expect(Constants.cycleTolerance == 2)
  #expect(Constants.usableSize == CGSize(width: 120, height: 80))
}
