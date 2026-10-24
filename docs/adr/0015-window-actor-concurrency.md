# All AX calls run on a dedicated WindowActor with a 250 ms messaging timeout; UI on MainActor

AX calls can block when the target app hangs. Zones performs every AX read/write on a serial `WindowActor` and sets `AXUIElementSetMessagingTimeout` to 0.25 s so the overlay and menu never freeze. UI, panels and SwiftUI stay on `MainActor`. Rejected: everything on MainActor (freezes).
