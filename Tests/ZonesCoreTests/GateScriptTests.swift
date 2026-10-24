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

  @Test func sourcesAXImportOutsideAdaptersFails() throws {
    let result = try hygiene(
      "import ApplicationServices\n", file: "Sources/ZonesWindowing/Seams/X.swift")
    #expect(result.stdout == Self.zeroLines + "sources-ax-imports: 1\n")
    #expect(result.status == 1)
  }

  @Test func sourcesAXImportInAdaptersIsAllowed() throws {
    let result = try hygiene(
      "import ApplicationServices\n", file: "Sources/ZonesWindowing/Adapters/X.swift")
    #expect(result.stdout == Self.zeroLines)
    #expect(result.status == 0)
  }

  @Test func realSourcesHaveAXImportsOnlyInAdapters() throws {
    let sources = repoRoot().appendingPathComponent("Sources")
    let walker = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
    var offenders: [String] = []
    for case let url as URL in walker where url.pathExtension == "swift" {
      let text = try String(contentsOf: url, encoding: .utf8)
      let hasImport = text.split(separator: "\n").contains {
        $0.trimmingCharacters(in: .whitespaces).hasPrefix("import ApplicationServices")
      }
      if hasImport && !url.path.contains("/Adapters/") { offenders.append(url.path) }
    }
    #expect(offenders.isEmpty, "\(offenders)")
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
  // MARK: T51, dev-cert.sh hardening (QA-2.1)

  func devCertText() throws -> String {
    try String(contentsOf: repoRoot().appendingPathComponent("scripts/dev-cert.sh"), encoding: .utf8)
  }

  @Test func devCertParsesAndHasNoHardcodedPassword() throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["bash", "-n", repoRoot().appendingPathComponent("scripts/dev-cert.sh").path]
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    let code = try devCertText().components(separatedBy: "\n").filter { !$0.hasPrefix("#") }.joined(separator: "\n")
    #expect(!code.components(separatedBy: "\n").contains { $0.hasPrefix("PASS=") })
    #expect(code.contains("openssl rand"))
    #expect(code.contains("add-generic-password"))
    #expect(code.contains("zones-dev-keychain"))
  }

  @Test func devCertAutoLocksAndDropsCodesignPartition() throws {
    let code = try devCertText().components(separatedBy: "\n").filter { !$0.hasPrefix("#") }.joined(separator: "\n")
    #expect(code.contains("set-keychain-settings -t"))
    #expect(code.contains("-l"))
    #expect(!code.contains("apple-tool:,apple:,codesign:"))
    #expect(code.contains("-T /usr/bin/codesign"))
  }

  @Test func devCertDryRunHardenNeverPrintsThePassword() throws {
    let home = try makeScratchDir()
    defer { try? FileManager.default.removeItem(at: home) }
    try write("", to: home.appendingPathComponent("Library/Keychains/zones-dev.keychain-db"))
    let result = try runScript("scripts/dev-cert.sh", ["--dry-run", "--harden"], env: ["HOME": home.path])
    #expect(result.status == 0)
    let hardened = result.stdout.contains("already hardened")
    #expect(hardened || result.stdout.contains("set-keychain-password -o zones-dev -p <password>"))
    #expect(result.stdout.range(of: "[0-9a-f]{48}", options: .regularExpression) == nil)
  }

  // MARK: slice 2, ticket-lint (AC-167)

  static func ticket(
    _ id: String, protocol proto: String? = "none", fake: String? = "none",
    tests: String? = "FooTests"
  ) -> String {
    var fields = ["\"id\": \"\(id)\""]
    if let proto { fields.append("\"protocol\": \"\(proto)\"") }
    if let fake { fields.append("\"fake\": \"\(fake)\"") }
    if let tests { fields.append("\"tests\": \"\(tests)\"") }
    return "{" + fields.joined(separator: ", ") + "}"
  }

  func lint(_ tickets: [String]) throws -> ScriptResult {
    let dir = try makeScratchDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("graph.json")
    try write("[" + tickets.joined(separator: ",") + "]", to: file)
    return try runScript("scripts/ticket-lint.sh", [file.path])
  }

  @Test func lintPassesOnCompleteFixture() throws {
    let result = try lint([
      Self.ticket("T01", protocol: "none", fake: "none"),
      Self.ticket("T02", protocol: "WindowServer", fake: "FakeWindowServer"),
      Self.ticket("T03"),
    ])
    #expect(result.stdout == "tickets: 3, missing-fields: 0\n")
    #expect(result.status == 0)
  }

  @Test func lintNamesFirstTicketMissingFake() throws {
    let result = try lint([
      Self.ticket("T01"), Self.ticket("T02", fake: nil), Self.ticket("T03", fake: nil),
    ])
    let lines = result.stdout.split(separator: "\n").map(String.init)
    #expect(lines.first == "tickets: 3, missing-fields: 2")
    #expect(lines.dropFirst().first == "FAIL T02: fake")
    #expect(lines.count == 3)
    #expect(result.status == 1)
  }

  @Test func lintRejectsNoneTests() throws {
    let result = try lint([Self.ticket("T01", tests: " None ")])
    #expect(result.stdout.contains("FAIL T01: tests"))
    #expect(result.status == 1)
  }

  @Test func lintRejectsEmptyAndNonString() throws {
    let dir = try makeScratchDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("graph.json")
    try write(
      """
      [{"id":"A","protocol":"  ","fake":"none","tests":"X"},
       {"id":"B","protocol":"none","fake":7,"tests":"X"},
       {"id":"C","protocol":"none","fake":"none","tests":null}]
      """, to: file)
    let result = try runScript("scripts/ticket-lint.sh", [file.path])
    let lines = result.stdout.split(separator: "\n").map(String.init)
    #expect(lines == ["tickets: 3, missing-fields: 3", "FAIL A: protocol", "FAIL B: fake", "FAIL C: tests"])
    #expect(result.status == 1)
  }

  @Test func lintMissingFileExitsTwo() throws {
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID().uuidString).json")
    let result = try runScript("scripts/ticket-lint.sh", [missing.path])
    #expect(result.status == 2)
    #expect(!result.stderr.isEmpty)
    let dir = try makeScratchDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let notArray = dir.appendingPathComponent("g.json")
    try write("{\"id\":\"T01\"}", to: notArray)
    #expect(try runScript("scripts/ticket-lint.sh", [notArray.path]).status == 2)
  }
  // MARK: slice 3, check-symbols (AC-003)

  /// Compiles `source` with clang into `dir/name`. Returns nil when compile or link fails.
  func compile(_ source: String, name: String, in dir: URL, frameworks: [String] = []) throws -> URL? {
    let src = dir.appendingPathComponent("\(name).c")
    try write(source, to: src)
    let out = dir.appendingPathComponent(name)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments =
      ["clang", "-o", out.path, src.path] + frameworks.flatMap { ["-framework", $0] }
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus == 0 ? out : nil
  }

  @Test func symbolsCleanBinaryPasses() throws {
    let dir = try makeScratchDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let bin = try #require(try compile("int main(void){return 0;}\n", name: "clean", in: dir))
    let result = try runScript("scripts/check-symbols.sh", [bin.path])
    #expect(result.status == 0)
    #expect(result.stdout.contains("symbols: ok"))
  }

  @Test func symbolsForbiddenBinaryFails() throws {
    let dir = try makeScratchDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let bin = try #require(
      try compile(
        "#include <stdbool.h>\nextern bool CGPreflightScreenCaptureAccess(void);\nint main(void){return CGPreflightScreenCaptureAccess();}\n",
        name: "forbidden", in: dir, frameworks: ["CoreGraphics"]))
    let result = try runScript("scripts/check-symbols.sh", [bin.path])
    #expect(result.status == 1)
    #expect(result.stdout.contains("CGPreflightScreenCaptureAccess"))
    #expect(!result.stdout.contains("symbols: ok"))
  }

  @Test func symbolsPrivateCGSBinaryFails() throws {
    let dir = try makeScratchDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    // The private symbol may not link on every SDK; return early (recorded in the ledger).
    guard
      let bin = try compile(
        "extern int CGSMainConnectionID(void);\nint main(void){return CGSMainConnectionID();}\n",
        name: "cgs", in: dir, frameworks: ["CoreGraphics"])
    else { return }
    let result = try runScript("scripts/check-symbols.sh", [bin.path])
    #expect(result.status == 1)
    #expect(result.stdout.contains("CGSMainConnectionID"))
  }

  @Test func symbolsCGSizeIsNotForbidden() throws {
    let dir = try makeScratchDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let bin = try #require(
      try compile(
        "#include <CoreGraphics/CoreGraphics.h>\nint main(void){CGSize s={1,2}; CFDictionaryRef d=CGSizeCreateDictionaryRepresentation(s); return d==NULL;}\n",
        name: "cgsize", in: dir, frameworks: ["CoreGraphics", "CoreFoundation"]))
    let result = try runScript("scripts/check-symbols.sh", [bin.path])
    #expect(result.status == 0)
    #expect(result.stdout.contains("symbols: ok"))
  }

  @Test func plistKeyFails() throws {
    let dir = try makeScratchDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let bin = try #require(try compile("int main(void){return 0;}\n", name: "Skel", in: dir))
    let app = dir.appendingPathComponent("Skel.app/Contents")
    try FileManager.default.createDirectory(
      at: app.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: bin, to: app.appendingPathComponent("MacOS/Skel"))
    try write(
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0"><dict><key>CFBundleExecutable</key><string>Skel</string>
      <key>NSScreenCaptureUsageDescription</key><string>x</string></dict></plist>
      """, to: app.appendingPathComponent("Info.plist"))
    let result = try runScript("scripts/check-symbols.sh", [dir.appendingPathComponent("Skel.app").path])
    #expect(result.status == 1)
    #expect(result.stdout.contains("NSScreenCaptureUsageDescription"))
  }

  @Test func plistCleanAppPasses() throws {
    let dir = try makeScratchDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let bin = try #require(try compile("int main(void){return 0;}\n", name: "Skel", in: dir))
    let app = dir.appendingPathComponent("Skel.app/Contents")
    try FileManager.default.createDirectory(
      at: app.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: bin, to: app.appendingPathComponent("MacOS/Skel"))
    try write(
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0"><dict><key>CFBundleExecutable</key><string>Skel</string></dict></plist>
      """, to: app.appendingPathComponent("Info.plist"))
    let result = try runScript("scripts/check-symbols.sh", [dir.appendingPathComponent("Skel.app").path])
    #expect(result.status == 0)
    #expect(result.stdout.contains("symbols: ok"))
  }
  // MARK: slice 4, release.sh dry run (AC-014, ADR-0025 amendment)

  static let skipBuild = ["ZONES_RELEASE_SKIP_BUILD": "1"]

  func adHocLines(_ text: String) -> Int {
    text.split(separator: "\n").filter { $0.contains("ad-hoc") }.count
  }

  @Test func dryRunAdHocPrintsExactlyOneStderrLine() throws {
    let result = try runScript(
      "scripts/release.sh", ["--dry-run"], env: Self.skipBuild, unset: ["ZONES_SIGN_IDENTITY"])
    #expect(adHocLines(result.stderr) == 1)
    #expect(result.stdout.contains("[release] signing: ad-hoc"))
    #expect(result.status == 0)
  }

  @Test func dryRunWithIdentityPrintsNoAdHocOnStderr() throws {
    var env = Self.skipBuild
    env["ZONES_SIGN_IDENTITY"] = "Developer ID Application: Example"
    let result = try runScript("scripts/release.sh", ["--dry-run"], env: env)
    #expect(adHocLines(result.stderr) == 0)
    #expect(result.stdout.contains("[release] signing: Developer ID Application: Example (Developer ID)"))
    #expect(result.status == 0)
  }

  @Test func dryRunSkipsSigningNotarizationAndDMG() throws {
    let dir = try makeScratchDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let log = dir.appendingPathComponent("calls.log")
    let bin = dir.appendingPathComponent("bin")
    for tool in ["codesign", "hdiutil", "xcrun", "notarytool", "stapler"] {
      let shim = bin.appendingPathComponent(tool)
      try write("#!/bin/sh\necho \(tool) >> '\(log.path)'\nexit 1\n", to: shim)
      try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shim.path)
    }
    let dist = repoRoot().appendingPathComponent("dist")
    let before = (try? FileManager.default.contentsOfDirectory(atPath: dist.path))?.filter { $0.hasSuffix(".dmg") } ?? []
    var env = Self.skipBuild
    env["PATH"] = bin.path + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")
    env["ZONES_SIGN_IDENTITY"] = "Developer ID Application: Example"
    env["ZONES_NOTARY_PROFILE"] = "profile"
    let result = try runScript("scripts/release.sh", ["--dry-run"], env: env)
    #expect(result.status == 0)
    let calls = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
    #expect(calls.isEmpty)
    let after = (try? FileManager.default.contentsOfDirectory(atPath: dist.path))?.filter { $0.hasSuffix(".dmg") } ?? []
    #expect(after == before)
    #expect(result.stdout.contains("dry-run: skipped signing, notarization, dmg"))
  }

  @Test func unknownFlagExits64() throws {
    let result = try runScript("scripts/release.sh", ["--bogus"], env: Self.skipBuild)
    #expect(result.status == 64)
    #expect(!result.stderr.isEmpty)
  }
  // MARK: slice 5, CI (AC-160, AC-162)

  @Test func ciRunsHygieneGateAfterSwiftTest() throws {
    let workflows = repoRoot().appendingPathComponent(".github/workflows")
    let files = try FileManager.default.contentsOfDirectory(atPath: workflows.path)
    #expect(files.count == 1)
    let text = try String(contentsOf: workflows.appendingPathComponent("ci.yml"), encoding: .utf8)
    let lines = text.components(separatedBy: "\n")
    let testIndex = try #require(lines.firstIndex { $0.contains("swift test") })
    let gateIndex = try #require(lines.firstIndex { $0.contains("scripts/hygiene-gate.sh") })
    #expect(gateIndex > testIndex)
  }
  /// AC-160 as amended by ADR-0026 (challenge C11): CI runs on pull requests to main and on manual dispatch only;
  /// every merge into integration runs the same gates locally through scripts/merge-ticket.sh.
  @Test func ciTriggersArePullRequestToMainAndManual() throws {
    let text = try String(
      contentsOf: repoRoot().appendingPathComponent(".github/workflows/ci.yml"), encoding: .utf8)
    let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    #expect(!lines.contains("push:"), "push triggers spend Actions minutes on every ticket push (ADR-0026)")
    let pr = try #require(lines.firstIndex(of: "pull_request:"))
    #expect(lines[pr + 1] == "branches: [main]")
    #expect(lines.contains("workflow_dispatch:"))
    let merge = try String(
      contentsOf: repoRoot().appendingPathComponent("scripts/merge-ticket.sh"), encoding: .utf8)
    #expect(merge.contains("swift build") && merge.contains("swift test") && merge.contains("xcodebuild"))
  }
  @Test func ciPipedStepsUsePipefail() throws {
    let text = try String(
      contentsOf: repoRoot().appendingPathComponent(".github/workflows/ci.yml"), encoding: .utf8)
    let lines = text.components(separatedBy: "\n")
    let jobShellBash = lines.contains { $0.trimmingCharacters(in: .whitespaces) == "shell: bash" }
    var uncovered: [String] = []
    for (index, line) in lines.enumerated() {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard trimmed.hasPrefix("run:") || trimmed.hasPrefix("- run:") else { continue }
      // A run step is its own line plus any deeper-indented block lines after it.
      let indent = line.prefix { $0 == " " }.count
      var block = [trimmed]
      for next in lines[(index + 1)...] {
        let nextIndent = next.prefix { $0 == " " }.count
        if next.trimmingCharacters(in: .whitespaces).isEmpty || nextIndent > indent {
          block.append(next)
        } else {
          break
        }
      }
      let joined = block.joined(separator: "\n")
      let piped = joined.replacingOccurrences(of: "||", with: "").contains("|")
      if piped && !jobShellBash && !joined.contains("set -o pipefail") { uncovered.append(trimmed) }
    }
    #expect(uncovered.isEmpty, "piped steps without pipefail: \(uncovered)")
  }

  // MARK: slice 6, release files (AC-168 structure, Casks)

  func matchCount(_ text: String, _ pattern: String) throws -> Int {
    let regex = try NSRegularExpression(pattern: pattern)
    return text.components(separatedBy: "\n").filter {
      regex.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil
    }.count
  }

  @Test func checklistHasFifteenRowsAndNoFail() throws {
    let url = repoRoot().appendingPathComponent("docs/release-checklist.md")
    let text = try String(contentsOf: url, encoding: .utf8)
    #expect(try matchCount(text, "AC-[0-9]{3}") == 15)
    let rows = text.components(separatedBy: "\n").filter {
      $0.hasPrefix("|") && $0.hasSuffix("|") && $0.range(of: "AC-[0-9]{3}", options: .regularExpression) != nil
    }
    #expect(rows.count == 15)
    #expect(try matchCount(text, "\\|\\s*fail\\s*\\|") == 0)
    #expect(text.contains("Release tag"))
    #expect(text.contains("macOS version"))
    #expect(text.contains("Tester"))
  }

  @Test func caskParses() throws {
    let cask = repoRoot().appendingPathComponent("Casks/zones.rb")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["ruby", "-c", cask.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    let text = try String(contentsOf: cask, encoding: .utf8)
    #expect(text.contains("app \"Zones.app\""))
  }
  // MARK: slice 7, bundle checks on a real Debug build (AC-002, AC-003, AC-013)

  static let debugApp: URL = repoRoot().appendingPathComponent(
    ".build/DerivedData/Build/Products/Debug/Zones.app")

  static let canCheckBundle: Bool = {
    guard FileManager.default.fileExists(atPath: debugApp.path) else { return false }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = ["find-identity", "-p", "codesigning"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return false }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self).contains("\"Zones Dev\"")
  }()

  @Test(.enabled(if: GateScriptTests.canCheckBundle))
  func devBuildSignatureHasIdentifierAndNoCdhash() throws {
    let result = try runScript("scripts/check-symbols.sh", ["--signature", Self.debugApp.path])
    #expect(result.status == 0, "\(result.stdout)")
  }

  @Test(.enabled(if: GateScriptTests.canCheckBundle))
  func devBuildHasNoForbiddenSymbols() throws {
    let result = try runScript("scripts/check-symbols.sh", [Self.debugApp.path])
    #expect(result.status == 0, "\(result.stdout)")
    #expect(result.stdout.contains("symbols: ok"))
  }

  @Test func projectYmlPinsSigningKeys() throws {
    let text = try String(contentsOf: repoRoot().appendingPathComponent("project.yml"), encoding: .utf8)
    let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    for line in [
      "PRODUCT_BUNDLE_IDENTIFIER: com.dganesh.zones", "ENABLE_HARDENED_RUNTIME: YES",
      "CODE_SIGN_STYLE: Manual", "CODE_SIGN_IDENTITY: \"Zones Dev\"",
      "CODE_SIGN_ENTITLEMENTS: App/Zones.entitlements", "MARKETING_VERSION: \"0.1.0\"",
      "CURRENT_PROJECT_VERSION: \"1\"",
    ] {
      #expect(lines.contains(line), "missing \(line)")
    }
  }
}
