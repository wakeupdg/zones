import Foundation
import ZonesCore
import os

public enum FakeFileSystemError: Error, Hashable, Sendable {
  case diskFull
  case notFound(URL)
}

/// An in-memory `FileSystem`. `writeAtomic` replaces a file whole or not at all. Bytes written are
/// totalled across successful writes; a write that would take the total past `failAfterBytes`
/// throws `diskFull` and leaves the previous content alone. A queued `.error` fails the next call.
public final class FakeFileSystem: FileSystem, Sendable {
  public enum Call: Hashable, Sendable {
    case read(URL), writeAtomic(URL, byteCount: Int), move(URL, to: URL), exists(URL), remove(URL)
  }

  public enum Response: Sendable { case error(FakeFileSystemError) }

  private struct State {
    var files: [URL: Data] = [:]
    var bytesWritten = 0
  }

  public let failAfterBytes: Int?
  private let queue = ResponseQueue<Response>()
  private let recorder: CallRecorder<Call>
  private let state = OSAllocatedUnfairLock(initialState: State())

  public init(failAfterBytes: Int? = nil, clock: FakeClock = FakeClock()) {
    self.failAfterBytes = failAfterBytes
    recorder = CallRecorder(clock: clock)
  }

  public func enqueue(_ response: Response) { queue.enqueue(response) }
  public var calls: [Call] { recorder.calls }
  /// Calls whose `latency` has elapsed on the clock.
  public var completed: [Call] { recorder.completed }
  public var inFlight: Int { recorder.inFlight }
  public var latency: TimeInterval {
    get { recorder.latency }
    set { recorder.latency = newValue }
  }
  /// A copy of every stored file.
  public var files: [URL: Data] { state.withLock { $0.files } }

  public func reset() {
    queue.reset()
    recorder.reset()
    state.withLock { $0 = State() }
  }

  private func scriptedError() -> FakeFileSystemError? {
    queue.take { if case .error(let e) = $0 { e } else { nil } }
  }

  public func read(_ url: URL) throws -> Data {
    recorder.record(.read(url))
    if let error = scriptedError() { throw error }
    guard let data = state.withLock({ $0.files[url] }) else { throw FakeFileSystemError.notFound(url) }
    return data
  }

  public func writeAtomic(_ data: Data, to url: URL) throws {
    recorder.record(.writeAtomic(url, byteCount: data.count))
    if let error = scriptedError() { throw error }
    let limit = failAfterBytes
    let accepted = state.withLock { s -> Bool in
      if let limit, s.bytesWritten + data.count > limit { return false }
      s.bytesWritten += data.count
      s.files[url] = data
      return true
    }
    if !accepted { throw FakeFileSystemError.diskFull }
  }

  public func move(_ from: URL, to: URL) throws {
    recorder.record(.move(from, to: to))
    if let error = scriptedError() { throw error }
    let moved = state.withLock { s -> Bool in
      guard let data = s.files.removeValue(forKey: from) else { return false }
      s.files[to] = data
      return true
    }
    if !moved { throw FakeFileSystemError.notFound(from) }
  }

  public func exists(_ url: URL) -> Bool {
    recorder.record(.exists(url))
    _ = scriptedError()  // `exists` cannot throw; a queued error is spent here so the script stays aligned.
    return state.withLock { $0.files[url] != nil }
  }

  public func remove(_ url: URL) throws {
    recorder.record(.remove(url))
    if let error = scriptedError() { throw error }
    let removed = state.withLock { $0.files.removeValue(forKey: url) != nil }
    if !removed { throw FakeFileSystemError.notFound(url) }
  }
}
