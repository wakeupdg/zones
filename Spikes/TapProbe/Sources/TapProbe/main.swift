import ApplicationServices
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)

// Preflight: read-only Accessibility check. Never prompt, never touch Screen Recording / Input Monitoring APIs.
let config = TapConfig.production
print("PREFLIGHT AXIsProcessTrusted=\(AXIsProcessTrusted()) pid=\(getpid())")
print("CONFIG listenOnly=\(config.listenOnly) mask=\(config.mask.map(\.rawValue).sorted()) place=tailAppendEventTap tap=session")
print("os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
// Slice 1 stub: tap code arrives in the next slice.
print("STUB tap not started")
