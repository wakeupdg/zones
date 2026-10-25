# T60 READY

- Status: READY
- Branch: ticket/T60, head 3201e34 (base integration 19c1bb1)
- Files: AppTests/PermissionDriverTests.swift, AppTests/ShortcutsAccessibilityTests.swift (tests only, no App/ code)

## Per test
1. `PermissionDriverTests.disabledTapIsReenabledThenDeclaredLost` (line 120, "expected suspect, got .granted")
   - Cause: stale test after T55 (C12 / SPK-006). After `tapRecreated(true)` the driver asks the trust probe. The fake probe is sticky and still read true, so the machine went to granted. Not related to the real AX grant.
   - Change: reset the probe (reads false) before the lost-tap signal; also assert the driver asks the probe once. Still asserts suspect.
2. `PermissionDriverTests.heartbeatAfterRecreateIsTaggedTrivialRead` (line 146, `h.windows.calls` empty)
   - Cause: same. T55 removed the post-recreate heartbeat; the probe resolves suspect now.
   - Change: replaced by `probeAfterRecreateResolvesSuspect` (recreate, one probe, granted, no AX read) and `trivialReadDoesNotResolveSuspect` (an ok trivial read in suspect stays suspect).
3. `ShortcutsAccessibilityTests.clearButtonsNameTheirAction` (line 176, `#require(AXIsProcessTrusted())`)
   - Cause: an unneeded precondition. The AX walk on the host's own pid succeeds with `AXIsProcessTrusted()` false (probe: AXChildren err 0).
   - Change: removed the precondition. The label count check still fails an empty walk. Passed 3 of 3 isolated runs plus the full run.

## Counts
- AppTests (unsigned Debug, untrusted host): before 101 tests, 3 fail; after 102 tests, 0 fail.
- `swift test`: 340 tests, 0 fail (after the unsigned Zones.app was deleted).
- hygiene gate: 0 / 0 / 0.

## CI
- `.github/workflows/ci.yml` runs on PR to main and manual only: `swift test`, hygiene gate, unsigned `xcodebuild build`. It does NOT run AppTests.

## Not verified
- AppTests on a host where the test host IS trusted (expected to pass, not run).
- AppTests on a CI runner.

## Cleanup
- Unsigned `.build/DerivedData/Build/Products/Debug/Zones.app` deleted after the last xcodebuild.
