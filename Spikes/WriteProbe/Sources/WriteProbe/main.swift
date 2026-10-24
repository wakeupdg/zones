import ApplicationServices
import Foundation

// WriteProbe: size, position, size writes with read-back (ADR-0022). Spike only; not shipped.

enum Policy: String { case toggle, leave }

struct Options {
  var bundle: String?
  var pid: pid_t?
  var target: CGRect?
  var policy: Policy = .toggle
  var runs = 1
  var json = false
  var trust = false
}

func usage() -> Never {
  FileHandle.standardError.write(Data("""
    usage: WriteProbe --bundle <id> | --pid <n>  --target x,y,w,h  [--policy toggle|leave]  [--runs N]  [--json]
           WriteProbe --trust
    """.utf8 + [10]))
  exit(64)
}

func parse(_ args: [String]) -> Options {
  var o = Options()
  var i = 0
  func next() -> String {
    i += 1
    guard i < args.count else { usage() }
    return args[i]
  }
  while i < args.count {
    switch args[i] {
    case "--bundle": o.bundle = next()
    case "--pid": guard let p = Int32(next()) else { usage() }; o.pid = p
    case "--target":
      let v = next().split(separator: ",").compactMap { Double($0) }
      guard v.count == 4 else { usage() }
      o.target = CGRect(x: v[0], y: v[1], width: v[2], height: v[3])
    case "--policy": guard let p = Policy(rawValue: next()) else { usage() }; o.policy = p
    case "--runs": guard let n = Int(next()), n > 0 else { usage() }; o.runs = n
    case "--json": o.json = true
    case "--trust": o.trust = true
    default: usage()
    }
    i += 1
  }
  return o
}

let options = parse(Array(CommandLine.arguments.dropFirst()))

if options.trust {
  print(AXIsProcessTrusted())
  exit(0)
}

// Safety: refuse to run without --target (and an app to aim at).
guard options.target != nil, options.bundle != nil || options.pid != nil else { usage() }
FileHandle.standardError.write(Data("write path not implemented yet\n".utf8))
exit(2)
