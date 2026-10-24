import Foundation

let usage = """
usage: AXSignalsProbe <mode> [options]
  selftest
  revoke  [--seconds 90]
  cadence --app finder|safari|chrome [--seconds 40]
  thread  [--idle 60] [--target calculator]
"""

let args = Array(CommandLine.arguments.dropFirst())
guard let mode = args.first else { fail(usage, code: 64) }
switch mode {
case "selftest": exit(runSelfTest())
default: fail("unknown mode: \(mode)\n\(usage)", code: 64)
}
