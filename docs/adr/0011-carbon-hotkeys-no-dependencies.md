# Global hotkeys use Carbon RegisterEventHotKey; zero third-party dependencies in v1

`RegisterEventHotKey` needs no TCC permission and is still exported in the macOS 27 SDK (research: event-taps-tcc.md). The recorder UI is our own (~200 lines). Rejected: the KeyboardShortcuts package (fine library, but a dependency for a small surface) and event-tap hotkeys (needs the tap alive for keys).
