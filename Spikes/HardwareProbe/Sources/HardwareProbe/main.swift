import AppKit
import Foundation

// HardwareProbe: throwaway spike for T08 (SPK-011, SPK-012, SPK-014, SPK-018).
// Each subcommand runs alone. Output is timestamped plain text.

func stamp() -> String {
  let f = DateFormatter()
  f.locale = Locale(identifier: "en_US_POSIX")
  f.timeZone = TimeZone(identifier: "America/Los_Angeles")
  f.dateFormat = "h:mm:ss a 'PT'"
  return f.string(from: Date())
}

func log(_ message: String) {
  print("[\(stamp())] \(message)")
  fflush(stdout)
}

let usage = """
  HardwareProbe <command> [options]

  login      [status|register|unregister|open-settings]   SPK-011
  displays                                                SPK-012
  hotkey     [--activate|--no-activate]                   SPK-014
  sleepwake                                               SPK-018
  post-wake                                               SPK-018 (re-print state)
  """

@MainActor
func run(_ args: [String]) -> Int32 {
  guard let command = args.first else {
    print(usage)
    return 64
  }
  switch command {
  case "-h", "--help", "help":
    print(usage)
    return 0
  default:
    FileHandle.standardError.write(Data("unknown command: \(command)\n\(usage)\n".utf8))
    return 64
  }
}

exit(run(Array(CommandLine.arguments.dropFirst())))
