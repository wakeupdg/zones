# T25 ledger
- contract additions: `TopologyState.mirrorMaster` + memberwise init, `TopologyMonitor.nilUUIDRetryLimit/nilUUIDRetryInterval/nilUUIDCount(in:)`, `LayoutsPaneModel.notSavedLabel/forgetTitle/copyTitle(_:)` (the last lands in slice 9).
- `TopologyEvent`, `TopologyEffect` did not exist in Sources; declared in Topology/TopologyMonitor.swift exactly as in the brief. `TopologySnapshot.display(_:)` was missing; added in Sources/ZonesCore/Display.swift.
- slice 1: stormCoalescesAndResizes part 1 green — debounce reducer, harness (test passed on first run: reducer written with the types)
- slice 2: stormCoalescesAndResizes part 2 green — resize commits topologyChanged+resizePanels, identical snapshot no effects
- slice 3: assignmentsSurviveReconnect green — passed with the slice-1 reducer (it never touches records, no move effect case exists)
- slice 4: persistsNameFrameScale green — one persistAssignment per drifted known UUID, before topologyChanged
