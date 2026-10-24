# One click-through NSPanel per screen at level screenSaver that is never key

Each screen gets one `NSPanel` (borderless, non-activating, `level = .screenSaver`, `canJoinAllSpaces`, `fullScreenAuxiliary`, `stationary`, `ignoresCycle`, `ignoresMouseEvents`, no shadow, clear background, `canBecomeKey` false) sized to `screen.frame`, created once and reused. Zones are drawn in `visibleFrame` coordinates with one CALayer per zone plus a highlight layer. Rejected: `.floating`/`.statusBar` (hidden by full-screen apps) and SwiftUI for the hot path until benchmarked.
