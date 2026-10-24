# Snap target is the zone under the cursor; snap requires the activation modifier at drop; zones may hold many windows

While the activation modifier is held during a drag, the overlay shows and the highlighted zone is the one under the cursor (not the window center). The snap happens only if the modifier is still down at mouse-up; releasing it first hides the overlay and cancels. Zones snaps, it does not tile: a snap never moves another window, and several windows may occupy one zone.
