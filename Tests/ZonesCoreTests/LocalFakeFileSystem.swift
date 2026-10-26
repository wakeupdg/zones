import Foundation
import ZonesCore
import os

/// In-memory `FileSystem`. `failAfterBytes` makes any write larger than the limit fail mid-write: the
/// partial temp file is discarded and the destination keeps its old bytes, like a real atomic write.
final class LocalFakeFileSystem: FileSystem, Sendable {
  struct Move: Hashable, Sendable {
    var from: URL
    var to: URL
  }

  private struct State {
    var files: [URL: Data] = [:]
    var failAfterBytes: Int?
    var writes: [URL] = []
    var moves: [Move] = []
  }

  private let state = OSAllocatedUnfairLock(initialState: State())

  init(files: [URL: Data] = [:]) { state.withLock { $0.files = files } }

  var failAfterBytes: Int? {
    get { state.withLock { $0.failAfterBytes } }
    set { state.withLock { $0.failAfterBytes = newValue } }
  }

  /// Every successful or failed write attempt, in order.
  var writeLog: [URL] { state.withLock { $0.writes } }
  var moveLog: [Move] { state.withLock { $0.moves } }
  var paths: Set<URL> { state.withLock { Set($0.files.keys) } }

  func contents(_ url: URL) -> Data? { state.withLock { $0.files[url] } }

  func read(_ url: URL) throws -> Data {
    try state.withLock { s in
      guard let data = s.files[url] else { throw CocoaError(.fileNoSuchFile) }
      return data
    }
  }

  func writeAtomic(_ data: Data, to url: URL) throws {
    try state.withLock { s in
      s.writes.append(url)
      if let limit = s.failAfterBytes, data.count > limit { throw CocoaError(.fileWriteOutOfSpace) }
      s.files[url] = data
    }
  }

  func move(_ from: URL, to: URL) throws {
    try state.withLock { s in
      guard let data = s.files[from] else { throw CocoaError(.fileNoSuchFile) }
      s.files[from] = nil
      s.files[to] = data
      s.moves.append(Move(from: from, to: to))
    }
  }

  func exists(_ url: URL) -> Bool { state.withLock { $0.files[url] != nil } }

  func remove(_ url: URL) throws {
    try state.withLock { s in
      guard s.files.removeValue(forKey: url) != nil else { throw CocoaError(.fileNoSuchFile) }
    }
  }
}
