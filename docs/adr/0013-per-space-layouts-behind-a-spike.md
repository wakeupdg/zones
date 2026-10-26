# Per-display layouts ship in v1; per-Space layouts depend on a spike of the hidden-window method

No public API yields a Space identifier and the `com.apple.spaces` file lags and holds stale entries (research: spaces-and-displays.md). Zones ships per-display assignments. A spike ticket tests identifying Spaces with one hidden window per Space and `NSWindow.isOnActiveSpace`; if it passes, per-Space assignments become tickets, else they move to out-of-scope. Private CGS calls are not an option (ADR-0001).
