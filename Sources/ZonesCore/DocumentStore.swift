import Foundation

/// Directory = ~/Library/Application Support/Zones. Writes are synchronous and atomic (AC-150).
public struct DocumentStore: Sendable {
  let fs: any FileSystem
  let directory: URL
  let clock: any Clock
  let currentVersion: Int
  let steps: [Int: Migrator.Step]

  public init(fs: any FileSystem, directory: URL, clock: any Clock) {
    self.init(
      fs: fs, directory: directory, clock: clock, currentVersion: Constants.documentVersion,
      steps: Migrator.steps)
  }

  init(
    fs: any FileSystem, directory: URL, clock: any Clock, currentVersion: Int, steps: [Int: Migrator.Step]
  ) {
    self.fs = fs
    self.directory = directory
    self.clock = clock
    self.currentVersion = currentVersion
    self.steps = steps
  }

  func url(_ kind: DocumentKind) -> URL { directory.appending(path: kind.rawValue) }

  public func load(_ kind: DocumentKind) -> LoadResult {
    let target = url(kind)
    guard fs.exists(target) else { return .loaded(ZonesDocument(version: currentVersion)) }
    guard let raw = try? fs.read(target) else { return .loaded(ZonesDocument(version: currentVersion)) }
    switch Migrator.migrate(raw, current: currentVersion, steps: steps) {
    case .success(let (document, _)): return .loaded(document)
    case .failure: return .loaded(ZonesDocument(version: currentVersion))
    }
  }

  public func save(_ document: ZonesDocument, as kind: DocumentKind) throws(DocumentError) {
    let data: Data
    do { data = try document.encoded(for: kind) } catch { throw .io("encode failed: \(error)") }
    do { try fs.writeAtomic(data, to: url(kind)) } catch { throw .io(String(describing: error)) }
  }
}
