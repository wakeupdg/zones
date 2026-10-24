# Zones — STATUS

Phase: 3 (build) COMPLETE — all 40 tickets done; Phase 4 (QA) starting
Updated: 2026-10-24, end of Phase 3

## Phase results so far
- Phase 0/1/2: see git history (ADRs, LOCKED-SPEC 169 AC, CONTRACTS, 39 tickets).
- Phase 3 run 1: 12 tickets merged (T01 T01b T02 T03 T04 T05 T06 T07 T08 T09 T10 T11). 50 agents. 74 tests.
- Phase 3 run 2: 11 tickets merged (T12 T13 T15 T16 T17 T18 T19 T24 T25 T26 T38). 59 agents, 0 errors. Root `swift test` at the last merge (T25): 152 tests green. T38 produced a verified ad-hoc DMG via scripts/release.sh.
- Phase 3 run 3: 11 tickets merged (T14 T20 T21 T22 T23 T27 T28 T29 T30 T31 T32). 76 agents, 0 errors. Root `swift test` at the last merge (T32): 294 tests green; xcodebuild with the Zones Dev identity green; AppTests load under the hardened host via a Debug entitlements file.
- T37 (invariants) returned blocked-needs-human: its AC-082 property found a real reducer bug (after `topologyChanged` removes the cursor's Display the highlight is empty while a mouseUp snaps to the nearest remaining Zone; seeds 82/132/160/212/237). Orchestrator ruling: LI-009 and AC-082 stand; the reducer fix is new ticket T39 (armed stores the last cursor point); T37 is re-blocked on T39 and resumes after it (resume note in its ledger). No spec amendment.
- Phase 3 run 4 (two parts; the first stopped at a usage limit): 6 tickets merged (T33 T39 T34 T35 T36 T37). 64 agents. Final integration gates: `swift test` 321 tests in 64 suites green (1 known issue: AppLaunchTests.loginLaunchShowsNoWindow, T29 deviation on the login-path badge); Debug xcodebuild with the Zones Dev identity green; hygiene-gate 0/0/0; ticket-lint 0 missing.
- T14 stopped before slice 1 in run 2: its brief forbade editing `AppHealth`, whose methods T15 added later. Orchestrator reset T14 to todo, added T15 to its blocked_by, deleted branch ticket/T14 (ledger kept under docs/tickets/T14/). Run 3 builds it.

## Wave plan (max width 10)
wave 1: T01
wave 2: T01b
wave 3: T02 T03 T04 T05 T06 T07 T08 T09 T10 T11
wave 4: T12 T13 T14 T15 T38
wave 5: T16 T17 T18 T19 T24 T26
wave 6: T20 T21 T22 T23 T25 T27 T28 T30 T31
wave 7: T29 T37
wave 8: T32 T36
wave 9: T33 T34 T35

## Per-ticket state
- done: 40 — every ticket T01..T39 (T01b and the T39 fix included)
- todo/blocked: none

## Spike verdicts (docs/spikes/)
- PASS: SPK-003, SPK-004, SPK-008, SPK-012, SPK-013, SPK-015 (T18 golden table), SPK-017, SPK-018.
- PARTIAL: SPK-005 (3-rebuild grant check needs a human), SPK-010 (8 apps recorded; VoiceOver run needs a human).
- PENDING-HUMAN-RUN: SPK-001, SPK-002, SPK-006, SPK-007, SPK-009. Each file holds the operator commands. Listed as manual items in the final report.

## Manual ACs noted by builders (need a human run)
AC-075 (T19), AC-078 (T15), AC-096 (T24), AC-119 (T25), AC-144 (T14), AC-057 (T21), AC-066 (T23), AC-085 (T22), AC-009/010/025 (T20), AC-040/044/046/061/064 (T31), AC-023/028/030 (T32), AC-004/005/020 (T33), AC-141 (T34), AC-126/139 (T35), AC-070/157 (T36). Live AX paths of T13 could not run under `swift test` (sandbox: trivialRead timed out).

## Open items for Phase 4 (reviewer non-blockers worth a fix ticket)
- T13: `AXObserverBridge` keeps a dangling refcon after `forget`; `element(at:)` keeps issuing AX calls after a timeout; private AX helpers lack `@WindowActor`.
- T13: Seams/WindowHandle.swift (T01) still has `import ApplicationServices`; AC-162 grep lists it.
- T12: `Templates.generate(.grid, count:)` silently builds 2x2 for counts outside {4, 9}; `display(at:)` is half-open at the top edge.
- T17: `LayoutValidator` never returns `.overlap`, so the AC-151 overlap variant is untested.
- T21: moving/armed carry no SnapMode, so `allow(.positionOnly)` still produces `SnapPlan.mode == .full`.
- T23: `EventTapInputSource` streams use unbounded buffers; `reenable()` runs outside the lifecycle lock; `start() == .unavailable` emits no TapSignal (driver must feed `.recreated(false)`).
- T14: `ExclusionsPaneModel.rows` sorts with `caseInsensitiveCompare`, not `localizedStandardCompare`.
- T33: Back/Next are dimmed but enabled (HIG); status item ignores `isTemplate`; `relaunchApp` terminates even when `openApplication` fails; `show()` always activates (focus steal on revocation).
- T39 review: after `topologyChanged`, `span.zones` keep OLD-layout Zone numbers; a number missing from the new Layout shrinks the drop rect silently.
- T28/T30: `EditorError` has no case for empty-name or surround validator faults (mapped to `.invalidRatio`).

## Open blockers
- GitHub Actions CI does not start: "The job was not started because recent account payments have failed or your spending limit needs to be increased" (every push to integration since run 3). blocked-needs-human: fix Billing & plans for wakeupdg, then re-run the latest CI run. Local equivalents of every CI step are green.

## Token spend — two metrics
- Hook metric (tool-result bytes/4, enforced ceilings): ~6.59M of 12M.
- Workflow billing metric: research 0.8M + P1 3.15M + P2 7.08M + run1 5.05M + run2 5.60M + run3 7.27M + run4 2.57M + 3.58M → ~35.1M

## LESSONS line count
33
