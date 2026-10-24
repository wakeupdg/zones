import Foundation
import Testing

// Drives the release and gate scripts under scripts/ through Process.

struct ScriptResult: Sendable {
  var stdout: String
  var stderr: String
  var status: Int32
}

func repoRoot(from file: String = #filePath) -> URL {
  var dir = URL(fileURLWithPath: file).deletingLastPathComponent()
  while dir.path != "/" {
    if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
      return dir
    }
    dir = dir.deletingLastPathComponent()
  }
  return URL(fileURLWithPath: file).deletingLastPathComponent()
}

func runScript(
  _ script: String, _ args: [String] = [], env: [String: String] = [:],
  unset: [String] = [], cwd: URL? = nil
) throws -> ScriptResult {
  let root = repoRoot()
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = ["bash", root.appendingPathComponent(script).path] + args
  var environment = ProcessInfo.processInfo.environment
  for key in unset { environment.removeValue(forKey: key) }
  for (key, value) in env { environment[key] = value }
  process.environment = environment
  process.currentDirectoryURL = cwd ?? root
  let out = FileManager.default.temporaryDirectory.appendingPathComponent("gate-\(UUID().uuidString).out")
  let err = FileManager.default.temporaryDirectory.appendingPathComponent("gate-\(UUID().uuidString).err")
  FileManager.default.createFile(atPath: out.path, contents: nil)
  FileManager.default.createFile(atPath: err.path, contents: nil)
  defer {
    try? FileManager.default.removeItem(at: out)
    try? FileManager.default.removeItem(at: err)
  }
  let outHandle = try FileHandle(forWritingTo: out)
  let errHandle = try FileHandle(forWritingTo: err)
  process.standardOutput = outHandle
  process.standardError = errHandle
  try process.run()
  process.waitUntilExit()
  try? outHandle.close()
  try? errHandle.close()
  return ScriptResult(
    stdout: String(decoding: (try? Data(contentsOf: out)) ?? Data(), as: UTF8.self),
    stderr: String(decoding: (try? Data(contentsOf: err)) ?? Data(), as: UTF8.self),
    status: process.terminationStatus)
}

func makeScratchDir() throws -> URL {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent("zones-gate-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  return dir
}

func write(_ text: String, to url: URL) throws {
  try FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
  try text.write(to: url, atomically: true, encoding: .utf8)
}

@Suite struct GateScriptTests {
  static let zeroLines = "unsafe-ops: 0\nax-imports: 0\ncgwindowlist-uses: 0\n"

  // MARK: slice 1, hygiene-gate (AC-162)

  func hygiene(_ source: String, file: String = "App/A.swift") throws -> ScriptResult {
    let dir = try makeScratchDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    try write(source, to: dir.appendingPathComponent(file))
    try write("import Foundation\n", to: dir.appendingPathComponent("App/Clean.swift"))
    return try runScript("scripts/hygiene-gate.sh", [dir.path])
  }

  @Test func hygieneCleanTreePrintsThreeZeroLines() throws {
    let result = try hygiene("import Foundation\nlet x = 1\n")
    #expect(result.stdout == Self.zeroLines)
    #expect(result.status == 0)
  }

  @Test(arguments: ["let x = try! f()", "let x = y as! Int", "fatalError(\"no\")"])
  func hygieneUnsafeOpExitsOne(line: String) throws {
    let result = try hygiene(line + "\n")
    #expect(result.stdout.split(separator: "\n").first == "unsafe-ops: 1")
    #expect(result.status == 1)
  }

  @Test func hygieneAllowMarkerExempts() throws {
    let result = try hygiene("let x = try! f() // zones:allow\n")
    #expect(result.stdout == Self.zeroLines)
    #expect(result.status == 0)
  }

  @Test func hygieneCountsAxImportAndCGWindowList() throws {
    let ax = try hygiene("import ApplicationServices\n")
    #expect(ax.stdout == "unsafe-ops: 0\nax-imports: 1\ncgwindowlist-uses: 0\n")
    #expect(ax.status == 1)
    let cg = try hygiene("let w = CGWindowListCopyWindowInfo(a, b)\n")
    #expect(cg.stdout == "unsafe-ops: 0\nax-imports: 0\ncgwindowlist-uses: 1\n")
    #expect(cg.status == 1)
  }

  @Test func hygieneIgnoresAdapters() throws {
    let bad = "import ApplicationServices\nlet a = try! f()\nlet w = CGWindowListCopyWindowInfo(a, b)\n"
    let result = try hygiene(bad, file: "Sources/ZonesWindowing/Adapters/X.swift")
    #expect(result.stdout == Self.zeroLines)
    #expect(result.status == 0)
  }

  @Test func hygieneMissingAppDirExitsTwo() throws {
    let dir = try makeScratchDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let result = try runScript("scripts/hygiene-gate.sh", [dir.path])
    #expect(result.status == 2)
    #expect(result.stdout.isEmpty)
  }

  @Test func hygieneRealRepoIsClean() throws {
    let result = try runScript("scripts/hygiene-gate.sh")
    #expect(result.stdout == Self.zeroLines)
    #expect(result.status == 0)
  }
}
