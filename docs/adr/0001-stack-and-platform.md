# Swift 6.2, SwiftUI + AppKit panels, Accessibility API, macOS 14+, no private APIs

Zones targets macOS 14+ as a universal binary. Logic lives in SPM packages built with Swift 6.2 strict concurrency; settings and the layout editor are SwiftUI; zone overlays are AppKit `NSPanel`s; window moves use the public Accessibility API (`AXUIElement`). No private APIs (no SkyLight/CGS calls), so the app can be notarized and survives OS updates. Rejected: yabai-style private APIs (needs SIP changes) and Electron.
