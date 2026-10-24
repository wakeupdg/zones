import Foundation

public protocol FileSystem: Sendable {
  func read(_ url: URL) throws -> Data
  func writeAtomic(_ data: Data, to url: URL) throws
  func move(_ from: URL, to: URL) throws
  func exists(_ url: URL) -> Bool
  func remove(_ url: URL) throws
}
