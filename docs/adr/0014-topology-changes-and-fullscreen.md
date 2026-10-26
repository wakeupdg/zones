# No re-layout on display topology change; nothing happens in full-screen Spaces

When a display is added or removed, Zones keeps assignments by UUID and does not move windows; re-snap is out of scope for v1. When the focused window is full-screen (`AXFullScreen`), shortcuts and the overlay do nothing, silently.
