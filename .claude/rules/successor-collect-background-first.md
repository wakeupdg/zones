---
scope: repo
triggerKeywords: [successor, state card, handoff, clear, background session, subagent, background agent, 450k, ceiling]
actor: DG
learnedAt: 2026-10-25T05:14:15Z
sourceRef: /learn, session ea6ebdcd-375d-48b9-bdbd-b88365a8a845
supersedes: []
status: live
pinned: false
trigger: always_on
description: Before you write your own successor card, collect a successor card from every background session or agent you started.
---
# Collect background successor cards before your own

DG, 2026-10-25 (via /learn): "whenever you call successor, the order is for any background sessions to call successor first and report their successor output to you before you call successor so you can spawn the background sessions back to where they were in the new cleared sessions"

**Why:** background agents and sessions die or lose their report path when the parent is cleared. Without their own cards, the successor cannot restart them where they stopped.

**How to apply:**
- Before you invoke `successor`, list every running background session, subagent or workflow you started (SendMessage targets, Agent task ids, sessions).
- Send each one: stop at the next safe point, invoke `successor`, and send the full card back to you.
- Wait for every card. Do not write your own card first.
- In your card, under RE-ARM FIRST, paste each child card (or its path) and the exact way to restart it (agent type, model, effort, the card as its brief).
- If a child cannot answer (finished, stuck, no inbox), say so in RE-ARM FIRST with how to check its output.
