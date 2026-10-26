export const meta = {
  name: 'zones-ticket-graph',
  description: 'Phase 2: architect writes CONTRACTS.md and the ticket graph; JS validates acyclicity, AC coverage and waves; brief writers + Haiku sizer per ticket',
  phases: [
    { title: 'Architect', detail: 'one agent: docs/CONTRACTS.md + ticket graph (structured)' },
    { title: 'Validate', detail: 'JS: acyclic, every AC exactly once, waves; repair agent if needed' },
    { title: 'Briefs', detail: 'one brief writer per ticket (Sonnet) then a Haiku sizer', model: 'sonnet' },
  ],
}

const AC_COUNT = args.acCount
const TICKET = {
  type: 'object',
  properties: {
    id: { type: 'string' }, title: { type: 'string' }, kind: { type: 'string', enum: ['prefactor', 'spike', 'build'] },
    delivers: { type: 'string' }, acceptance_ids: { type: 'array', items: { type: 'string' } },
    blocked_by: { type: 'array', items: { type: 'string' } }, files_expected: { type: 'array', items: { type: 'string' } },
    files_to_read: { type: 'array', items: { type: 'string' } }, contracts: { type: 'array', items: { type: 'string' } },
    est_tokens: { type: 'number' }, notes: { type: 'string' },
  },
  required: ['id', 'title', 'kind', 'delivers', 'acceptance_ids', 'blocked_by', 'files_expected', 'files_to_read', 'contracts', 'est_tokens'],
}
const GRAPH_SCHEMA = { type: 'object', properties: { tickets: { type: 'array', items: TICKET }, contracts_lines: { type: 'number' }, summary: { type: 'string' } }, required: ['tickets', 'summary'] }
const SIZE_SCHEMA = { type: 'object', properties: { est_tokens: { type: 'number' }, brief_tokens: { type: 'number' }, over_180k: { type: 'boolean' }, split_suggestion: { type: 'string' } }, required: ['est_tokens', 'brief_tokens', 'over_180k'] }

const COMMON = `You work in the Zones repository (cwd; the path has "!" and a space, quote paths). Zones is a FancyZones-style window manager for macOS 14+ in Swift 6 with strict concurrency: SPM packages ZonesCore, ZonesLayout, ZonesWindowing (one root Package.swift, ADR-0002) plus an XcodeGen app target under App/. Read with sed -n line ranges; never cat a directory; never run git; do not create worktrees; write only the files you are told to write. Your final text is data for an orchestrator.`

const ARCHITECT = `${COMMON}
You are the TICKET ARCHITECT. Inputs (read all): docs/BRIEF.md; CONTEXT.md; all 25 ADRs (for f in docs/adr/*.md; do echo "## $f"; cat "$f"; done — note the Amendment sections); docs/LESSONS.md; docs/LOCKED-SPEC.md in full, in 250-line chunks (1148 lines: sections 3 Lock invariants, 5 Acceptance statements AC-001..AC-${AC_COUNT} with auto|manual tags and Covers/Verify lines, 7 Spikes SPK-001..018, 8 Resolved disagreements); the "## Implications for Zones" sections of the six docs/research/*.md files; and the repo layout (ls; ls scripts docs). There is no Swift code yet.

TASK 1 — write docs/CONTRACTS.md (Swift, 250-450 lines): the shared interface contracts that let parallel ticket agents build pieces that fit together without reading each other's code. Include: the module dependency direction (ZonesCore -> ZonesLayout -> ZonesWindowing -> App); core value types with their fields (Layout, split tree node, Zone, Margin/Gap, surround, Template, Assignment, DisplayKey, WindowRef/WindowRecord, Original Frame registry entry, Drag Session states, Snap plan, Exclusion rule, Shortcut, Appearance); the protocol seams around the OS, each with method signatures (WindowSystem (AX), WindowEnumerator (CG), InputSource (event tap), DisplayProvider, OverlayPresenter, HotkeyRegistrar, LoginItemService, PermissionProbe, Clock) and the rule "one production impl, one scriptable fake in ZonesTestSupport"; the WindowActor boundary (ADR-0015 + amendment); the JSON documents v1 (layouts.json, assignments.json) with field names; the pure-function names for the rules in LI-020 (zone numbering, hit test, span union, snap plan, exclusion, drag reducer, cycle base, permission reducer, template generation, migration); the ZonesTestSupport seeded generator API. Use Sendable value types and typed errors. This file is the contract; keep names stable and short.

TASK 2 — return the ticket graph (structured output). Rules:
- Vertical slices (model -> engine -> UI -> tests), each demoable alone, each sized to fit one fresh Sonnet context: est_tokens <= 150000 (hard cap 180000). 26-40 tickets.
- Ids T01, T02, ... in dependency order (blockers have lower numbers). kind: prefactor (scaffold/infrastructure first: T01 = Package.swift with the three targets + ZonesTestSupport + test targets + project.yml + a menu-bar app shell that launches and quits + scripts/bootstrap.sh green), spike (one per SPK the dependents need before building: at least SPK-001 witness windows, SPK-002 click-through panel, SPK-003 listen-only tap, SPK-004 windowNumber; a spike ticket delivers docs/spikes/SPK-nnn.md with a verdict and a tiny throwaway probe target that is deleted or kept under Spikes/), build (features).
- acceptance_ids: every AC-001..AC-${AC_COUNT} (both auto and manual) appears in EXACTLY ONE ticket; manual ACs go to the ticket that implements the behavior (a human verifies later). Spike tickets carry no ACs unless an AC is literally about the spike note.
- blocked_by: only tickets whose output this ticket needs (contracts, types, seams, spike verdicts). Prefer width: many tickets should be ready after T01.
- files_expected: the Swift files/dirs the ticket will create or edit. files_to_read: the exact files (with line ranges where helpful, e.g. "docs/CONTRACTS.md:1-120") a fresh agent must read; never LOCKED-SPEC.md as a whole.
- contracts: the names from CONTRACTS.md the ticket implements or consumes.
- A wide refactor, if any, is sequenced expand -> migrate batches -> contract.
Return {tickets, contracts_lines, summary}.`

phase('Architect')
let graph = await agent(ARCHITECT, { label: 'architect', phase: 'Architect', schema: GRAPH_SCHEMA })
if (!graph) throw new Error('architect returned null')
log(`architect: ${graph.tickets.length} tickets; ${graph.summary.slice(0, 200)}`)

function validate(tickets) {
  const problems = []
  const ids = tickets.map(t => t.id)
  const dup = ids.filter((x, i) => ids.indexOf(x) !== i)
  if (dup.length) problems.push(`duplicate ids: ${dup.join(', ')}`)
  const idSet = new Set(ids)
  for (const t of tickets) for (const b of t.blocked_by) if (!idSet.has(b)) problems.push(`${t.id} blocked_by unknown ${b}`)
  for (const t of tickets) if (t.blocked_by.includes(t.id)) problems.push(`${t.id} blocks itself`)
  // AC coverage
  const acOwner = {}
  for (const t of tickets) for (const a of t.acceptance_ids) { (acOwner[a] = acOwner[a] || []).push(t.id) }
  const missing = [], multi = []
  for (let i = 1; i <= AC_COUNT; i++) { const k = `AC-${String(i).padStart(3, '0')}`; if (!acOwner[k]) missing.push(k); else if (acOwner[k].length > 1) multi.push(`${k}:${acOwner[k].join('+')}`) }
  for (const k of Object.keys(acOwner)) { const n = parseInt(k.replace('AC-', ''), 10); if (!(n >= 1 && n <= AC_COUNT)) problems.push(`unknown AC ${k} in ${acOwner[k].join(',')}`) }
  if (missing.length) problems.push(`ACs with no ticket: ${missing.join(', ')}`)
  if (multi.length) problems.push(`ACs in more than one ticket: ${multi.join(', ')}`)
  for (const t of tickets) if (t.est_tokens > 180000) problems.push(`${t.id} est_tokens ${t.est_tokens} > 180k`)
  // Kahn waves
  const indeg = {}, level = {}
  for (const t of tickets) indeg[t.id] = t.blocked_by.filter(b => idSet.has(b)).length
  let frontier = tickets.filter(t => indeg[t.id] === 0).map(t => t.id)
  const waves = []
  let seen = 0
  while (frontier.length) {
    waves.push(frontier)
    seen += frontier.length
    const next = []
    for (const id of frontier) level[id] = waves.length
    for (const t of tickets) {
      if (level[t.id]) continue
      if (t.blocked_by.some(b => frontier.includes(b))) {
        indeg[t.id] -= t.blocked_by.filter(b => frontier.includes(b)).length
        if (indeg[t.id] === 0) next.push(t.id)
      }
    }
    frontier = next
  }
  if (seen !== tickets.length) problems.push(`cycle detected: ${tickets.filter(t => !level[t.id]).map(t => t.id).join(', ')}`)
  const width = Math.max(0, ...waves.map(w => w.length))
  return { problems, waves, width }
}

phase('Validate')
let v = validate(graph.tickets)
for (let attempt = 1; attempt <= 2 && v.problems.length; attempt++) {
  log(`validation problems (${v.problems.length}): ${v.problems.join(' | ').slice(0, 600)}`)
  const repaired = await agent(`${COMMON}\nYou REPAIR a ticket graph for Zones. docs/CONTRACTS.md already exists (read it). The graph below has these validation problems:\n${v.problems.join('\n')}\nRules: every AC-001..AC-${AC_COUNT} in exactly one ticket (read docs/LOCKED-SPEC.md section 5 headers with: grep -n '^### AC-' docs/LOCKED-SPEC.md, and read the statements of any AC you must place); no cycles; blocked_by ids exist; est_tokens <= 180000 (split a ticket and re-link edges if needed, keeping ids in dependency order — you may append new ids like T31b). Keep every other field. Return the full corrected graph.\nGRAPH:\n${JSON.stringify(graph.tickets)}`,
    { label: `repair:${attempt}`, phase: 'Validate', schema: GRAPH_SCHEMA })
  if (!repaired) break
  graph = repaired
  v = validate(graph.tickets)
}
log(`validate: ${v.problems.length} problems; ${v.waves.length} waves; max width ${v.width}`)

phase('Briefs')
const sized = await pipeline(graph.tickets,
  t => agent(`${COMMON}\nYou write the brief for ticket ${t.id} — ${t.title}. Write docs/tickets/${t.id}.md (create docs/tickets if needed). A fresh Sonnet agent will build this ticket from the brief alone plus the files it names; the whole brief must stay under 8000 tokens (about 320 lines), so copy only what is needed.
Ticket data: ${JSON.stringify(t)}
Sections, in order:
# ${t.id}: ${t.title}
## Goal — 3-6 sentences: what works end to end when this ticket is done (from ${JSON.stringify(t.delivers)}).
## Acceptance — for EACH id in acceptance_ids, copy the AC block VERBATIM from docs/LOCKED-SPEC.md (find it with grep -n '^### AC-nnn' docs/LOCKED-SPEC.md and sed -n the lines up to the next '### '): the header with its auto|manual tag, Statement, Covers, Verify. For a spike ticket, copy the SPK block from section 7 instead (grep -n 'SPK-nnn' docs/LOCKED-SPEC.md).
## Interface contracts — copy from docs/CONTRACTS.md only the type and protocol declarations named in ${JSON.stringify(t.contracts)} (grep -n for each name, then sed -n the declaration). State which ones this ticket IMPLEMENTS and which it CONSUMES.
## ADRs — one line per relevant ADR: number and title (head -1 docs/adr/*.md); include any Amendment line that applies.
## Files to read — the exact list from files_to_read (verify each path exists with ls; replace a missing one with the right path or drop it), plus docs/LESSONS.md and docs/tickets/${t.id}/ledger.md.
## Files to create or edit — from files_expected, one line each with one sentence of purpose.
## Test plan — the red-green slices in order (each slice: test name, what it asserts, which contract it exercises); property tests where the AC says so; which ACs are manual and therefore need no test, only an implementation and a note.
## Done check — the exact commands: scripts/q.sh swift build; scripts/q.sh swift test (with --filter where useful); scripts/q.sh xcodebuild -quiet -project Zones.xcodeproj -scheme Zones build when App/ is touched; plus the per-AC Verify commands that are runnable.
## Working rules — copy these lines: "Commit on branch ticket/${t.id} only. One red-green slice per commit. Append one line to docs/tickets/${t.id}/ledger.md per completed slice. Never edit docs/tickets/graph.json or docs/LOCKED-SPEC.md. Never read LOCKED-SPEC.md in full. Run builds and tests only through scripts/q.sh. Follow the write-swift skill. A slice still red after 3 attempts: stop, write the failing test name in the ledger, return state blocked-needs-human. On CEILING from the hook: append the ledger line, run the successor skill, return a continuation object."
Return the brief line count and its approximate token count.`,
    { label: `brief:${t.id}`, phase: 'Briefs', model: 'sonnet' }),
  (r, t) => agent(`You are the SIZER for Zones ticket ${t.id}. Read docs/tickets/${t.id}.md (the brief) with sed -n in 150-line chunks and docs/CONTRACTS.md headers (grep -n '^##\\|^public\\|^protocol\\|^struct\\|^enum\\|^actor' docs/CONTRACTS.md | head -80). Estimate: brief_tokens = brief characters / 4; est_tokens = total tokens a Sonnet agent spends to build it with TDD, including reading the files listed, writing roughly ${Math.max(2, t.files_expected.length)} Swift files, 4-10 build/test cycles through scripts/q.sh (about 1500 tokens each), and two review rounds. Use: 25000 base + 6000 per Swift file created + 2000 per AC + brief_tokens + 20000 if the ticket touches App/ or AppKit. over_180k is true if est_tokens > 180000; then give a split_suggestion (two titles and which ACs go where). Return numbers only.`,
    { label: `size:${t.id}`, phase: 'Briefs', model: 'haiku', schema: SIZE_SCHEMA }))

const tickets = graph.tickets.map((t, i) => ({ ...t, est_tokens: sized[i] ? sized[i].est_tokens : t.est_tokens, brief_tokens: sized[i] ? sized[i].brief_tokens : null, over_180k: sized[i] ? sized[i].over_180k : null, split_suggestion: sized[i] ? sized[i].split_suggestion || '' : 'sizer failed' }))
const over = tickets.filter(t => t.over_180k)
if (over.length) log(`SIZER: ${over.length} tickets over 180k: ${over.map(t => t.id).join(', ')} — orchestrator must split`)
return { tickets, waves: v.waves, width: v.width, problems: v.problems, contracts_lines: graph.contracts_lines }