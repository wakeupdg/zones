# Zones — STATUS

Phase: 2 complete → 3 (build) starting
Updated: end of Phase 2, 2026-10-24

## Phase results
- Phase 0: 25 ADRs (+ amendments), CONTEXT.md, BRIEF.md, 6 research notes, mechanics + hooks, CI, dev-cert. Remote wakeupdg/zones.
- Phase 1: docs/LOCKED-SPEC.md — 146 US, 169 AC (139 auto / 30 manual), 20 LI, 18 SPK. 17 agents.
- Phase 2: docs/CONTRACTS.md (449 lines), 39 tickets (T01 split into T01 + T01b; est > 180k), 38 briefs written + sized, graph validated (acyclic, every AC in exactly one ticket). 77 agents.

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

## Tickets
all 39 todo. Sum of est_tokens: ~3.2M (hook metric).

## Open blockers
none

## Token spend — two metrics
The brief's per-agent ceilings (250k/200k) are enforced by the PostToolUse hook, which counts tool-result bytes/4. The run budget (12M, soft stop 10M) is tracked in that same hook metric, since it is the only one the mechanics can measure. The Workflow tool also reports a billing-style total that counts every turn's full input; it runs about 3x higher.
- Hook metric (all spend logs): ~3.15M of 12M
- Workflow-reported metric: research ~0.8M, Phase 1 ~3.15M, Phase 2 ~7.08M → ~11.0M
Decision: continue to Phase 3 on the hook metric; report both at every wave end.

## LESSONS line count
7
