import Testing
import ZonesCore

@testable import ZonesWindowing

/// QA-2.5: Delete and Forward Delete clear the focused recorder's shortcut, armed or not.
@Suite struct RecorderKeyMapTests {
  private let delete: UInt16 = 51
  private let forwardDelete: UInt16 = 117
  private let command: UInt64 = 1 << 20
  private let shift: UInt64 = 1 << 17

  @Test func deleteClears() {
    for code in [delete, forwardDelete] {
      #expect(RecorderKeyMap.disposition(keyCode: code, rawFlags: 0, recording: false) == .clear)
      #expect(RecorderKeyMap.disposition(keyCode: code, rawFlags: 0, recording: true) == .clear)
    }
  }

  @Test func deleteWithModifiersDoesNotClear() {
    for code in [delete, forwardDelete] {
      #expect(RecorderKeyMap.disposition(keyCode: code, rawFlags: command, recording: false) == .passThrough)
      #expect(RecorderKeyMap.disposition(keyCode: code, rawFlags: shift, recording: false) == .passThrough)
      #expect(RecorderKeyMap.disposition(keyCode: code, rawFlags: command, recording: true) == .reject)
    }
  }
}
