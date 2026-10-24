# Frame writes go size, position, size; read back; toggle AXEnhancedUserInterface off during the write

There is no atomic AX frame call and writes report success even when clamped (research: ax-window-moves.md). Zones writes size, then position, then size again, reads the frame back, and keeps whatever the app accepted. Before a write it turns `AXEnhancedUserInterface` off on the app element and restores it after, to avoid animated or ignored moves in Chromium and Electron apps.
