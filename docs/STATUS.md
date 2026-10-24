# Zones — STATUS

Phase: 3 (build), run 2 complete (waves 4-5 plus T25)
Updated: 2026-10-24, end of run 2

## Phase results so far
- Phase 0/1/2: see git history (ADRs, LOCKED-SPEC 169 AC, CONTRACTS, 39 tickets).
- Phase 3 run 1: 12 tickets merged (T01 T01b T02 T03 T04 T05 T06 T07 T08 T09 T10 T11). 50 agents. 74 tests.
- Phase 3 run 2: 11 tickets merged (T12 T13 T15 T16 T17 T18 T19 T24 T25 T26 T38). 59 agents, 0 errors. Root `swift test` at the last merge (T25): 152 tests green. T38 produced a verified ad-hoc DMG via scripts/release.sh.
- T14 stopped before slice 1: its brief forbade editing `AppHealth`, whose methods T15 added later. Orchestrator reset T14 to todo, added T15 to its blocked_by, deleted branch ticket/T14 (ledger kept under docs/tickets/T14/). Run 3 builds it.

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
- done: 23 — T01 T01b T02 T03 T04 T05 T06 T07 T08 T09 T10 T11 T12 T13 T15 T16 T17 T18 T19 T24 T25 T26 T38
- todo: 16 — T14 T20 T21 T22 T23 T27 T28 T29 T30 T31 T32 T33 T34 T35 T36 T37
- ready for run 3 at start: T14 T20 T22 T23 T27 T28 T30 T31

## Spike verdicts (docs/spikes/)
- PASS: SPK-003, SPK-004, SPK-008, SPK-012, SPK-013, SPK-015 (T18 golden table), SPK-017, SPK-018.
- PARTIAL: SPK-005 (3-rebuild grant check needs a human), SPK-010 (8 apps recorded; VoiceOver run needs a human).
- PENDING-HUMAN-RUN: SPK-001, SPK-002, SPK-006, SPK-007, SPK-009. Each file holds the operator commands. Listed as manual items in the final report.

## Manual ACs noted by builders (need a human run)
AC-075 (T19), AC-078 (T15), AC-096 (T24), AC-119 (T25), AC-144 (T14). Live AX paths of T13 could not run under `swift test` (sandbox: trivialRead timed out).

## Open items for Phase 4 (reviewer non-blockers worth a fix ticket)
- T13: `AXObserverBridge` keeps a dangling refcon after `forget`; `element(at:)` keeps issuing AX calls after a timeout; private AX helpers lack `@WindowActor`.
- T13: Seams/WindowHandle.swift (T01) still has `import ApplicationServices`; AC-162 grep lists it.
- T12: `Templates.generate(.grid, count:)` silently builds 2x2 for counts outside {4, 9}; `display(at:)` is half-open at the top edge.
- T38: ticket-lint (AC-167) needs `protocol`, `fake`, `tests` fields on every graph.json ticket; orchestrator is adding them.
- T17: `LayoutValidator` never returns `.overlap`, so the AC-151 overlap variant is untested.

## Open blockers
none

## Token spend — two metrics
- Hook metric (tool-result bytes/4, enforced ceilings): ~4.52M of 12M (run-1 tickets show 0 because the ticket mapping landed after run 1; their spend is in the archived orchestrator log).
- Workflow billing metric: research 0.8M + P1 3.15M + P2 7.08M + run1 5.05M + run2 5.60M → ~21.7M

## LESSONS line count
19
