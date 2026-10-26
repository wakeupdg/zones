# T67 ledger
- slice 1: repro red: SpanTopologyTests.spanNumbersFromOldLayoutNeverReachTheDrop (Span {5,6} on nine-Zone A, A goes to two columns: drop {5,2,6} against Zones {1,2}).
- DG decision (via orchestrator): option A, T67 edits the one reducer line.
- slice 2: SpanLogic.rebase + reducer topologyChanged rebases before accumulate; DragSessionReducerTests.topologyChangeAccumulatesSpanAtRehit expects {1}. swift test 357/67 green; xcodegen + Debug xcodebuild (unsigned) green.
