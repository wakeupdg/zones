# All AX calls run on a dedicated WindowActor with a 250 ms messaging timeout; UI on MainActor

AX calls can block when the target app hangs. Zones performs every AX read/write on a serial `WindowActor` and sets `AXUIElementSetMessagingTimeout` to 0.25 s so the overlay and menu never freeze. UI, panels and SwiftUI stay on `MainActor`. Rejected: everything on MainActor (freezes).

## Amendment 2026-10-24 (LOCKED-SPEC challenge C7)

A second consecutive timeout against the same app aborts the current Snap sequence (one retry only), so a hung app costs at most 0.5 s on the serial actor, and the app enters a short unresponsive cooldown.
