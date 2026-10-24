# Original frame is captured at first snap, restored by shortcut or by a modifier-drag that ends over no zone

Zones records a window frame the first time it snaps that window and forgets it when the window closes. Restore happens on the Restore shortcut, or when an activation-modifier drag ends outside every zone. A plain drag without the modifier never restores (the user is positioning by hand). Rejected: restore on any drag (surprising) and shortcut-only (no mouse path).
