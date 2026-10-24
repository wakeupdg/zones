import Foundation

let usage = """
usage: AXSignalsProbe <mode> [options]
  selftest
  revoke  [--seconds 90]
  cadence --app finder|safari|chrome [--seconds 40]
  thread  [--idle 60] [--target calculator]
"""

let args = Array(CommandLine.arguments.dropFirst())
guard let mode = args.first else {
  FileHandle.standardError.write(Data((usage + "\n").utf8))
  exit(64)
}
FileHandle.standardError.write(Data("unknown mode: \(mode)\n\(usage)\n".utf8))
exit(64)
