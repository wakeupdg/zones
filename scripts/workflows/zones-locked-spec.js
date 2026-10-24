export const meta = {
  name: 'zones-locked-spec',
  description: 'Phase 1: three persona specs, three cross-critique rounds, one synthesized LOCKED-SPEC.md, completeness check',
  phases: [
    { title: 'Draft', detail: 'three persona drafters write independent specs' },
    { title: 'Critique', detail: 'three rounds; each persona attacks the other two and revises its own draft' },
    { title: 'Synthesize', detail: 'one synthesizer writes docs/LOCKED-SPEC.md with AC-nnn' },
    { title: 'Verify', detail: 'completeness critic finds stories without acceptance statements; fixer amends' },
  ],
}

const PERSONAS = [
  { key: 'power-user', title: 'power-user ergonomics',
    lens: 'You are a demanding keyboard-and-mouse power user who has used FancyZones on Windows for years and now lives on a 3-display Mac. You care about speed, predictability, discoverability, zero surprise during drags, multi-display and multi-window flows, shortcuts that never collide, and an editor that is faster than fiddling with numbers. Write the user stories a power user would actually demand, including awkward ones (dragging across displays, dropping on a gap, spanning diagonal zones, window that refuses to resize).' },
  { key: 'platform', title: 'macOS-platform correctness',
    lens: 'You are a senior macOS engineer who has shipped Accessibility-API window tools. You care about TCC permission flows and revocation, AX write quirks (clamping, Enhanced UI, hung apps), CGWindowList matching without titles, Spaces and full-screen behavior, Stage Manager, display topology changes, sleep/wake, Electron/Chromium/Java windows, performance under a 120 Hz drag, HIG compliance for a menu-bar app, and correct SwiftUI/AppKit integration. Write stories and decisions that make the app correct on real Macs, not just the happy path.' },
  { key: 'maintainer', title: 'long-term maintainability',
    lens: 'You are the engineer who will maintain Zones for five years. You care about deep modules with small interfaces, headless testability of every rule, protocol seams around AX/CG/AppKit so logic tests never need a GUI, versioned data formats with migration, diagnostics a user can paste into a bug report, error handling that never crashes the menu bar, strict-concurrency-clean code, and a ticket graph that lets fresh agents build pieces without reading everything. Write the stories and implementation/testing decisions that keep the codebase healthy.' },
]

const COMMON = `
You work in the Zones repository (current working directory; the path contains "!" and a space, so quote paths). Zones is a FancyZones-style window manager for macOS 14+ in Swift 6.
Read, in this order, using line ranges (sed -n) and never whole directories:
1. docs/BRIEF.md (whole file) — the locked product brief and MVP feature set.
2. CONTEXT.md (whole file) — the glossary. Use its terms exactly; avoid the listed synonyms.
3. Every file in docs/adr/ (25 short files; cat them all at once with: for f in docs/adr/*.md; do echo "## $f"; cat "$f"; done). These decisions are LOCKED. Do not contradict them. If you believe one is wrong, write it under a "Challenges to ADRs" section with evidence; do not silently deviate.
4. The "## Implications for Zones" section of each of the six files in docs/research/ (use grep -n "Implications" to find the line, then sed -n for ~25 lines after it). Read a "## Gotchas" section too when relevant. Do not read the whole research files.
Rules: do not run git commands; do not create worktrees; write only the file(s) you are told to write; no file paths or code snippets in the spec (type shapes and state machines are allowed when they encode a decision); keep prose tight. Your final text return is data for an orchestrator, not a message to a human.
`

const SPEC_TEMPLATE = `
Write the spec with exactly these sections (the to-spec template):
## Problem Statement — from the user's perspective.
## Solution — from the user's perspective.
## User Stories — a LONG numbered list, each "As a <actor>, I want <feature>, so that <benefit>". Cover every MVP feature in docs/BRIEF.md and every edge case your persona cares about. Aim for 60-120 stories. Number them US-001.. in your own file (the synthesizer renumbers).
## Implementation Decisions — modules and their interfaces, state machines, data shapes, interactions; consistent with the ADRs; no paths, no code.
## Testing Decisions — what makes a good test here, which modules get property tests, which behaviors are verifiable headless on the build machine vs need a human or a second machine.
## Out of Scope — explicit list.
## Further Notes — including "Challenges to ADRs" if any, and "Open questions the spike tickets must answer".
Target length 300-450 lines.
`

const DRAFT_SCHEMA = { type: 'object', properties: { stories: { type: 'number' }, lines: { type: 'number' }, adr_challenges: { type: 'number' }, summary: { type: 'string' } }, required: ['stories', 'lines', 'summary'] }
const ROUND_SCHEMA = { type: 'object', properties: { attacks: { type: 'number' }, accepted: { type: 'number' }, rebutted: { type: 'number' }, summary: { type: 'string' } }, required: ['attacks', 'summary'] }
const CRITIC_SCHEMA = { type: 'object', properties: { ok: { type: 'boolean' }, missing_stories: { type: 'array', items: { type: 'object', properties: { us_id: { type: 'string' }, title: { type: 'string' }, suggested_ac: { type: 'string' } }, required: ['us_id', 'suggested_ac'] } }, malformed_acs: { type: 'array', items: { type: 'string' } }, notes: { type: 'string' } }, required: ['ok', 'missing_stories', 'malformed_acs'] }

phase('Draft')
log('Three persona drafters write independent specs under docs/spec/drafts/')
const drafts = await parallel(PERSONAS.map(p => () => agent(
  `${COMMON}\nPERSONA: ${p.title}. ${p.lens}\n${SPEC_TEMPLATE}\nWrite your spec to docs/spec/drafts/${p.key}.md (create docs/spec/drafts if needed). Then return the counts.`,
  { label: `draft:${p.key}`, phase: 'Draft', schema: DRAFT_SCHEMA })))
drafts.forEach((d, i) => log(d ? `draft ${PERSONAS[i].key}: ${d.stories} stories, ${d.lines} lines` : `draft ${PERSONAS[i].key}: FAILED`))

for (let r = 1; r <= 3; r++) {
  phase('Critique')
  log(`Critique round ${r} of 3`)
  const results = await parallel(PERSONAS.map(p => () => {
    const others = PERSONAS.filter(o => o.key !== p.key)
    const received = r === 1 ? 'There are no critiques of your draft yet.' :
      `Critiques of YOUR draft from the previous round are in: ${others.map(o => `docs/spec/critique/round${r - 1}-${o.key}.md`).join(' and ')} (read the sections aimed at "${p.key}").`
    return agent(
      `${COMMON}\nPERSONA: ${p.title}. ${p.lens}\nYour own draft is docs/spec/drafts/${p.key}.md. The other two drafts are ${others.map(o => `docs/spec/drafts/${o.key}.md (persona ${o.key})`).join(' and ')}. Read all three fully.\n${received}\n\nTASK A — ATTACK (round ${r}): write docs/spec/critique/round${r}-${p.key}.md with one section per other persona ("## Attacks on ${others[0].key}", "## Attacks on ${others[1].key}"). Each attack is numbered and has: the claim or story you attack (quote its id), why it is wrong, missing, untestable, contradicts an ADR or the glossary, or will hurt users or maintainers, and a concrete proposed fix. Be adversarial and specific; 8-20 attacks per persona. Also list what the other draft got right that yours lacks ("## Steal list").\n\nTASK B — REVISE: ${r === 1 ? 'Add the items from your Steal list to your own draft where they fit, keeping the template sections.' : 'Rewrite docs/spec/drafts/' + p.key + '.md in place: for every critique you received, either accept it (change the draft) or rebut it (keep the draft). Append or update a final section "## Response log" with one line per received critique: ACCEPTED <what changed> or REBUTTED <why>. Also add the items from your Steal list.'} Keep the template sections and the 300-450 line target.\nReturn counts: attacks written, critiques accepted, critiques rebutted, and a 2-sentence summary.`,
      { label: `round${r}:${p.key}`, phase: 'Critique', schema: ROUND_SCHEMA })
  }))
  results.forEach((x, i) => log(x ? `round ${r} ${PERSONAS[i].key}: ${x.attacks} attacks, ${x.accepted ?? 0} accepted, ${x.rebutted ?? 0} rebutted` : `round ${r} ${PERSONAS[i].key}: FAILED`))
}

phase('Synthesize')
log('Synthesizer writes docs/LOCKED-SPEC.md')
const synth = await agent(
  `${COMMON}\nYou are the SYNTHESIZER. Inputs: the three persona drafts docs/spec/drafts/power-user.md, platform.md, maintainer.md (read fully), and the nine critique files docs/spec/critique/round{1,2,3}-{power-user,platform,maintainer}.md (read fully; the round-3 attacks were never answered, so weigh them yourself). Resolve conflicts in favor of the ADRs; where personas still disagree, pick one answer and record it under "Resolved disagreements".

Write docs/LOCKED-SPEC.md with exactly these sections:
# Zones — Locked Specification
## 1. Problem Statement
## 2. Solution
## 3. Lock invariants — numbered LI-nnn: statements that cannot change without a new ADR (e.g. "Zones never requests Screen Recording", "A Layout always tiles its display with no gaps and no overlaps"). 10-20 items.
## 4. User stories — merged and deduplicated from all three drafts, renumbered US-001.., grouped by feature area. Keep every distinct story; merge true duplicates.
## 5. Acceptance statements — grouped by feature area. Each is:
### AC-nnn (auto|manual) — <short title>
Statement: one falsifiable sentence or a Given/When/Then triple with concrete values (numbers, keys, counts, states). Never "works correctly".
Covers: US-xxx, US-yyy
Verify: for auto — the exact headless check a build-machine agent can run (a named Swift Testing test case, a swift test filter, a CLI invocation, or a scripted AX/CG probe against the built app with no human); for manual — the human procedure and expected observation.
Tag auto only if it can run on the build machine with no human and no second machine; otherwise manual. Every US must be covered by at least one AC. Aim for 120-220 ACs. Number sequentially with no gaps.
## 6. Out of scope — explicit, merged from all drafts and docs/BRIEF.md.
## 7. Spikes — SPK-nnn with a pass/fail criterion and which ACs depend on the outcome (at minimum: per-Space identification via hidden windows per ADR-0013; click-through panel does not interrupt a drag per research; listen-only mouse tap needs only Accessibility; NSWindow.windowNumber equals the CGWindowID).
## 8. Resolved disagreements — one line each: topic, the options, the choice, why.
## 9. Traceability — a table US → AC ids.
Target 700-1200 lines. No code, no file paths. Then return a 5-line summary with counts of US, AC auto, AC manual, LI, SPK.`,
  { label: 'synthesize', phase: 'Synthesize' })
log(`synthesizer: ${String(synth).slice(0, 300)}`)

phase('Verify')
let critic = null
for (let i = 1; i <= 2; i++) {
  critic = await agent(
    `You are the COMPLETENESS CRITIC for docs/LOCKED-SPEC.md in the Zones repo (cwd; quote paths). Read the whole file in line-range chunks of 300 lines. Questions: (1) Which user story (US-nnn in section 4) has no acceptance statement that lists it under "Covers"? Build the set mechanically: grep -o 'US-[0-9]*' over section 4 and over the Covers lines, and diff them. (2) Which AC is not falsifiable (no concrete values, vague verbs like "works", "properly"), has a wrong tag (tagged auto but needs a human or second machine, or tagged manual but a headless test exists), or has a Verify line that an agent could not execute? (3) Are AC numbers sequential with no gaps or duplicates? (4) Does any AC contradict an ADR in docs/adr/ (read the titles: head -1 docs/adr/*.md)? Return ok=true only when (1) is empty and (2)-(4) found nothing. Otherwise list each missing story with a suggested AC statement and each malformed AC id with the problem. Do not edit any file.`,
    { label: `critic:${i}`, phase: 'Verify', schema: CRITIC_SCHEMA })
  if (!critic) { log('critic failed'); break }
  log(`critic ${i}: ok=${critic.ok}, missing=${critic.missing_stories.length}, malformed=${critic.malformed_acs.length}`)
  if (critic.ok) break
  await agent(
    `You FIX docs/LOCKED-SPEC.md in the Zones repo (cwd; quote paths). Read it in 300-line chunks. The completeness critic found these problems; fix every one in place, keeping the section structure, the AC format ("### AC-nnn (auto|manual) — title" / Statement / Covers / Verify), sequential numbering (append new ACs at the end of the relevant feature group and renumber if needed, then update section 9 Traceability), and the ADRs in docs/adr/.\nMissing stories (add at least one AC each): ${JSON.stringify(critic.missing_stories)}\nMalformed ACs: ${JSON.stringify(critic.malformed_acs)}\nNotes: ${critic.notes || ''}\nDo not run git. Return the list of AC ids you added or changed.`,
    { label: `fix:${i}`, phase: 'Verify' })
}
return { drafts, synth: String(synth), critic }