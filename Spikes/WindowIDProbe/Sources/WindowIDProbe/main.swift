import Foundation

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "spk004", "spk008", "spk016":
    print("FAIL \(args.first!): unimplemented")
    exit(1)
default:
    print("usage: WindowIDProbe spk004|spk008|spk016")
    exit(64)
}
