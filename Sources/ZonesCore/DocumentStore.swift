import Foundation

/// Directory = ~/Library/Application Support/Zones. Writes are synchronous and atomic (AC-150).
public struct DocumentStore: Sendable {
  let fs: any FileSystem
  let directory: URL
  let clock: any Clock
  let currentVersion: Int
  let steps: [Int: Migrator.Step]
  /// Seconds since 1970, used only to build backup and quarantine file names. `Clock.now` is monotonic.
  let wallClock: @Sendable () -> TimeInterval
  let sink: (any LogSink)?

  public init(fs: any FileSystem, directory: URL, clock: any Clock) {
    self.init(fs: fs, directory: directory, clock: clock, sink: nil)
  }

  /// `sink` receives the notice events (corrupt file moved aside, newer version left untouched).
  public init(fs: any FileSystem, directory: URL, clock: any Clock, sink: (any LogSink)?) {
    self.init(
      fs: fs, directory: directory, clock: clock, currentVersion: Constants.documentVersion,
      steps: Migrator.steps, wallClock: { Date().timeIntervalSince1970 }, sink: sink)
  }

  /// Test seam: injects the version, the step table and the wall clock.
  init(
    fs: any FileSystem, directory: URL, clock: any Clock, currentVersion: Int = Constants.documentVersion,
    steps: [Int: Migrator.Step] = Migrator.steps,
    wallClock: @escaping @Sendable () -> TimeInterval, sink: (any LogSink)? = nil
  ) {
    self.fs = fs
    self.directory = directory
    self.clock = clock
    self.currentVersion = currentVersion
    self.steps = steps
    self.wallClock = wallClock
    self.sink = sink
  }

  func url(_ kind: DocumentKind) -> URL { directory.appending(path: kind.rawValue) }

  public func load(_ kind: DocumentKind) -> LoadResult {
    let target = url(kind)
    guard fs.exists(target) else { return .loaded(ZonesDocument(version: currentVersion)) }
    let raw: Data
    do { raw = try fs.read(target) } catch { return quarantine(kind, reason: "unreadable: \(error)") }
    switch Migrator.migrate(raw, current: currentVersion, steps: steps) {
    case .success(let (document, from)) where from == document.version && from == currentVersion:
      return .loaded(document)
    case .success(let (document, from)): return persistMigration(document, from: from, original: raw, kind: kind)
    case .failure(.newerVersion(let found, let supported)):
      emit(
        .notice,
        "\(kind.rawValue) left untouched: "
          + DocumentError.newerVersion(found: found, supported: supported).message)
      return .newerLeftUntouched(version: found)
    case .failure(let error): return quarantine(kind, reason: error.message)
    }
  }

  /// Backup first, then the migrated file. If the backup cannot be written the disk is left alone.
  private func persistMigration(
    _ document: ZonesDocument, from: Int, original: Data, kind: DocumentKind
  ) -> LoadResult {
    let backup = backupName(kind, now: wallClock())
    do { try fs.writeAtomic(original, to: directory.appending(path: backup)) } catch {
      emit(.error, "\(kind.rawValue) migration skipped: backup \(backup) failed: \(error)")
      return .loaded(document)
    }
    do { try fs.writeAtomic(document.encoded(for: kind), to: url(kind)) } catch {
      emit(.error, "\(kind.rawValue) migrated in memory only: write failed: \(error)")
    }
    emit(.notice, "\(kind.rawValue) migrated from version \(from) to \(document.version); backup \(backup)")
    return .migrated(document, from: from, backup: backup)
  }

  /// `<kind>.<yyyyMMdd-HHmmss>.bak`, UTC, from seconds since 1970.
  public func backupName(_ kind: DocumentKind, now: TimeInterval) -> String {
    Self.stampedName(kind, now: now, suffix: "bak")
  }

  static func stampedName(_ kind: DocumentKind, now: TimeInterval, suffix: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let stem = kind.rawValue.hasSuffix(".json") ? String(kind.rawValue.dropLast(5)) : kind.rawValue
    return "\(stem).\(formatter.string(from: Date(timeIntervalSince1970: now))).\(suffix)"
  }

  /// Moves an undecodable file aside, emits one notice, and returns defaults.
  private func quarantine(_ kind: DocumentKind, reason: String) -> LoadResult {
    let now = wallClock()
    var name = Self.stampedName(kind, now: now, suffix: "corrupt")
    var attempt = 1
    while fs.exists(directory.appending(path: name)) {
      attempt += 1
      name = Self.stampedName(kind, now: now, suffix: "\(attempt).corrupt")
    }
    do {
      try fs.move(url(kind), to: directory.appending(path: name))
      emit(.notice, "\(kind.rawValue) could not be read (\(reason)); moved aside as \(name)")
    } catch {
      emit(.error, "\(kind.rawValue) could not be read (\(reason)) and could not be moved aside: \(error)")
    }
    return .defaults(quarantined: name)
  }

  private func emit(_ level: LogLevel, _ message: String) {
    sink?.write(LogEvent(time: clock.now, category: .core, level: level, message: message))
  }

  public func save(_ document: ZonesDocument, as kind: DocumentKind) throws(DocumentError) {
    if let existing = try? fs.read(url(kind)),
      let object = (try? JSONSerialization.jsonObject(with: existing)) as? [String: Any],
      let found = Migrator.sniffVersion(object), found > currentVersion
    {
      throw .newerVersion(found: found, supported: currentVersion)
    }
    let data: Data
    do { data = try document.encoded(for: kind) } catch { throw .io("encode failed: \(error)") }
    do { try fs.writeAtomic(data, to: url(kind)) } catch { throw .io(String(describing: error)) }
  }
}
