export const meta = {
  name: 'zones-build',
  description: 'Phase 3: dynamic scheduler over the ticket graph; per ticket: Sonnet TDD builder in a worktree -> two adversarial reviewers -> one fix round -> deterministic merge',
  phases: [
    { title: 'Build', detail: 'TDD builders on ticket/<id> branches (Sonnet)', model: 'sonnet' },
    { title: 'Review', detail: 'two reviewers: correctness+concurrency, UX+HIG; fix once; re-review the fix' },
    { title: 'Merge', detail: 'scripts/merge-ticket.sh (Haiku runner); one repair retry' },
  ],
}

// args: { tickets: [{id,title,blocked_by,est_tokens,kind}], done: [ids], blocked: [ids], maxTickets: n, maxParallel: n }
const tickets = args.tickets
const MAX_TICKETS = args.maxTickets || 12
const MAX_PAR = args.maxParallel || 6
const MAX_CONT = 3

const BUILD_SCHEMA = { type: 'object', properties: {
  state: { type: 'string', enum: ['review', 'blocked-needs-human', 'continuation'] },
  summary: { type: 'string' }, failing_test: { type: 'string' }, continuation_card: { type: 'string' },
  slices_done: { type: 'number' }, touched_app: { type: 'boolean' }, lessons_line: { type: 'string' } },
  required: ['state', 'summary'] }
const REVIEW_SCHEMA = { type: 'object', properties: {
  blockers: { type: 'array', items: { type: 'object', properties: { title: { type: 'string' }, file: { type: 'string' }, line: { type: 'number' }, why: { type: 'string' }, ac: { type: 'string' } }, required: ['title', 'why'] } },
  nonblockers: { type: 'array', items: { type: 'string' } }, lessons_line: { type: 'string' }, summary: { type: 'string' } },
  required: ['blockers', 'nonblockers', 'summary'] }
const FIX_SCHEMA = { type: 'object', properties: { fixed: { type: 'array', items: { type: 'string' } }, rebutted: { type: 'array', items: { type: 'string' } }, summary: { type: 'string' } }, required: ['fixed', 'rebutted', 'summary'] }
const MERGE_SCHEMA = { type: 'object', properties: { exit_code: { type: 'number' }, output: { type: 'string' } }, required: ['exit_code', 'output'] }

const REPO = 'The Zones repo main checkout is the cwd (the path has "!" and a space: always quote paths). Never read docs/LOCKED-SPEC.md in full. Never edit docs/tickets/graph.json by hand (only through scripts/graph-set.sh). Never touch branch main or push main. Your final text is data for an orchestrator, not a message to a human.'

const builderPrompt = (t, cont) => `You are the ${cont ? 'CONTINUATION ' : ''}BUILDER for Zones ticket ${t.id} — ${t.title}. ${REPO}
SETUP (in this order):
1. W="$(scripts/wt.sh add ${t.id})"; cd "$W"  — the worktree on branch ticket/${t.id}. Stay in "$W" for every later command (the spend hook reads the branch from your cwd).
2. scripts/graph-set.sh ${t.id} building   (run from "$W"; it finds the main checkout)
3. Read docs/tickets/${t.id}.md fully (your brief; sed -n in 150-line chunks), docs/LESSONS.md, docs/CONTRACTS.md only the declarations the brief names, ${cont ? 'docs/tickets/' + t.id + '/successor.md (the state card from the previous agent) and ' : ''}docs/tickets/${t.id}/ledger.md if it exists. Then only the files the brief lists, by line range.
4. Invoke the Skill tool with skill "write-swift" and follow it.
WORK: TDD, one red-green slice at a time in the brief's Test plan order. For each slice: write the failing test, run it (scripts/q.sh swift test --filter <name>), implement, run again, then scripts/q.sh swift build; commit on ticket/${t.id} with a short message ending in "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"; append ONE line to docs/tickets/${t.id}/ledger.md ("- slice N: <test> green — <what>") and include it in the commit. Swift 6 language mode, strict concurrency, no warnings. Builds and tests only through scripts/q.sh. When the brief touches App/ or project.yml: scripts/q.sh xcodegen generate, then scripts/q.sh xcodebuild -quiet -project Zones.xcodeproj -scheme Zones -configuration Debug -derivedDataPath .build/DerivedData CODE_SIGN_IDENTITY="Zones Dev" build. Manual ACs need an implementation and a ledger note, no test. Keep docs/LESSONS.md untouched (reviewers own it).
STOP RULES: a slice still red after 3 honest attempts: write the failing test name in the ledger, commit, return state "blocked-needs-human" with failing_test. If a tool result contains "CEILING": commit, append the ledger line, invoke the Skill tool with skill "successor" to write the state card to docs/tickets/${t.id}/successor.md (what is done, what is next, the exact next slice, gotchas), commit it, and return state "continuation" with continuation_card "docs/tickets/${t.id}/successor.md".
FINISH: all slices green; scripts/q.sh swift build and scripts/q.sh swift test green from "$W" (and the xcodebuild above when App/ was touched); everything committed; git push -u origin ticket/${t.id} (ignore push errors). Return state "review", slices_done, touched_app, a summary under 120 words, and optionally lessons_line: one line for docs/LESSONS.md only for a real tool quirk you hit twice.`

const reviewerPrompt = (t, lens) => `You REVIEW Zones ticket ${t.id} — ${t.title} with the lens: ${lens}. ${REPO}
Read docs/tickets/${t.id}.md sections Goal, Acceptance and Interface contracts (grep -n '^## ' to find them, then sed -n). Then the diff: git diff integration...ticket/${t.id} --stat, then git diff integration...ticket/${t.id} -- <path> per file, in chunks (use sed -n on large diffs). Read docs/CONTRACTS.md declarations that the diff implements. You may run scripts/q.sh swift test in a throwaway worktree only if a claim needs it: git worktree add --detach .build/review-worktrees/${t.id} ticket/${t.id} (never under /tmp, which does not persist between your Bash calls); git worktree remove --force it afterwards.
Be adversarial but honest. A BLOCKER is only: behavior that contradicts an AC in the brief (name the AC id); a data race, actor-isolation hole, non-Sendable crossing, or main-thread AX call (ADR-0015); a crash path reachable from user input; a deviation from docs/CONTRACTS.md that another ticket depends on; a test that passes without exercising its AC; ${lens.startsWith('UX') ? 'a HIG or accessibility failure that blocks use (missing accessibility label on a control, keyboard trap, unreadable contrast, modal that steals focus during a drag)' : 'a build or test that is red'}. Style and naming are nonblockers. Each blocker: title, file, line, why, ac. Report up to 8 nonblockers in one line each.
If you learned a real tool quirk, append ONE line to docs/LESSONS.md in the main checkout only when wc -l docs/LESSONS.md is under 40, and return it as lessons_line. Return summary under 80 words.`

const fixerPrompt = (t, blockers) => `You FIX review blockers on Zones ticket ${t.id} — ${t.title}. ${REPO}
W="$(scripts/wt.sh add ${t.id})"; cd "$W" and stay there. Read docs/tickets/${t.id}.md (Goal, Acceptance, Interface contracts) and the blockers below. For each blocker: if it is real, fix it test-first (red test, then fix), commit on ticket/${t.id} with the Co-Authored-By line, and add a ledger line to docs/tickets/${t.id}/ledger.md; if it is wrong, do not change code and list it under rebutted with one sentence of evidence. Builds and tests only through scripts/q.sh; everything green before you return.
BLOCKERS: ${JSON.stringify(blockers)}`

const rereviewPrompt = (t, blockers, fix) => `You RE-REVIEW only the fix on Zones ticket ${t.id}. ${REPO}
The blockers were: ${JSON.stringify(blockers)}. The fixer reports: ${JSON.stringify(fix)}. Read the latest commits on ticket/${t.id} since the review (git log integration..ticket/${t.id} --oneline; git show <sha> for the fix commits). Decide per blocker whether it is resolved or the rebuttal holds. Return remaining blockers only (empty if none), nonblockers empty, summary under 60 words.`

const mergePrompt = (t) => `Run exactly this command in the Zones repo main checkout (cwd; quote the path): scripts/merge-ticket.sh ${t.id}
Return its exit code and the last 15 lines of its output. Do nothing else.`

const mergeRepairPrompt = (t, out) => `You REPAIR a failed merge of Zones ticket ${t.id}. ${REPO}
scripts/merge-ticket.sh ${t.id} failed with: ${out}
Logs: .build/merge-logs/${t.id}.*.log (tail -40 each). W="$(scripts/wt.sh add ${t.id})"; cd "$W". If the rebase conflicted: git rebase integration, resolve conflicts honoring docs/CONTRACTS.md and the intent of both sides, git rebase --continue. If build or tests failed after rebase: fix on ticket/${t.id} test-first. Commit with the Co-Authored-By line. Then run scripts/merge-ticket.sh ${t.id} again from the main checkout (cd back first) and return its exit code and last 15 lines.`

// serialize merges
let mergeLock = Promise.resolve()
function withMerge(fn) { const p = mergeLock.then(fn, fn); mergeLock = p.catch(() => {}); return p }

async function runTicket(t) {
  // build with continuations
  let build = null
  for (let i = 0; i <= MAX_CONT; i++) {
    build = await agent(builderPrompt(t, i > 0), { label: `build:${t.id}${i ? ':c' + i : ''}`, phase: 'Build', model: 'sonnet', schema: BUILD_SCHEMA })
    if (!build) return { state: 'blocked-needs-human', summary: 'builder returned null' }
    if (build.state !== 'continuation') break
    log(`${t.id}: continuation ${i + 1} (${build.summary.slice(0, 100)})`)
  }
  if (build.state === 'continuation') return { state: 'blocked-needs-human', summary: `exceeded ${MAX_CONT} continuations` }
  if (build.state === 'blocked-needs-human') return { state: 'blocked-needs-human', summary: build.summary, failing_test: build.failing_test }
  await agent(`Run exactly: scripts/graph-set.sh ${t.id} review "built: ${build.summary.replace(/"/g, "'").slice(0, 100)}" in the Zones repo main checkout (cwd; quote the path). Return the output.`, { label: `state:${t.id}:review`, phase: 'Review', model: 'haiku', effort: 'low' })
  // two reviewers
  const lenses = ['correctness + concurrency (Swift 6 strict concurrency, actor isolation, AX on WindowActor only, error paths, tests that actually exercise the ACs)', 'UX + HIG (macOS Human Interface Guidelines for menu-bar apps, SwiftUI settings conventions, accessibility labels and keyboard access, overlay never steals focus, copy clarity)']
  const reviews = (await parallel(lenses.map((lens, i) => () => agent(reviewerPrompt(t, lens), { label: `review:${t.id}:${i ? 'ux' : 'cc'}`, phase: 'Review', schema: REVIEW_SCHEMA })))).filter(Boolean)
  let blockers = reviews.flatMap(r => r.blockers || [])
  const lessons = [build.lessons_line, ...reviews.map(r => r.lessons_line)].filter(Boolean)
  if (blockers.length) {
    log(`${t.id}: ${blockers.length} blocker(s) -> fixer`)
    const fix = await agent(fixerPrompt(t, blockers), { label: `fix:${t.id}`, phase: 'Review', model: 'sonnet', schema: FIX_SCHEMA })
    const re = await agent(rereviewPrompt(t, blockers, fix), { label: `rereview:${t.id}`, phase: 'Review', schema: REVIEW_SCHEMA })
    blockers = re ? re.blockers : blockers
    if (blockers.length) return { state: 'blocked-needs-human', summary: `review blockers remain after one fix round: ${blockers.map(b => b.title).join('; ')}`.slice(0, 400), blockers, lessons }
  }
  // merge (serialized)
  return withMerge(async () => {
    let m = await agent(mergePrompt(t), { label: `merge:${t.id}`, phase: 'Merge', model: 'haiku', effort: 'low', schema: MERGE_SCHEMA })
    if (m && m.exit_code !== 0) {
      log(`${t.id}: merge exit ${m.exit_code} -> repair`)
      m = await agent(mergeRepairPrompt(t, m.output.slice(0, 1500)), { label: `merge-repair:${t.id}`, phase: 'Merge', model: 'sonnet', schema: MERGE_SCHEMA })
    }
    if (!m || m.exit_code !== 0) return { state: 'blocked-needs-human', summary: `merge failed: ${m ? m.output.slice(-300) : 'null'}`, lessons }
    return { state: 'done', summary: build.summary, nonblockers: reviews.flatMap(r => r.nonblockers || []).slice(0, 12), lessons }
  })
}

const state = {}
tickets.forEach(t => { state[t.id] = (args.done || []).includes(t.id) ? 'done' : (args.blocked || []).includes(t.id) ? 'blocked' : 'todo' })
const results = {}
const running = new Map()
let started = 0
const ready = () => tickets.filter(t => state[t.id] === 'todo' && t.blocked_by.every(b => state[b] === 'done'))
while (true) {
  for (const t of ready()) {
    if (started >= MAX_TICKETS || running.size >= MAX_PAR) break
    state[t.id] = 'running'; started++
    log(`start ${t.id} — ${t.title}`)
    running.set(t.id, runTicket(t).then(r => ({ id: t.id, r }), e => ({ id: t.id, r: { state: 'blocked-needs-human', summary: 'exception: ' + String(e).slice(0, 300) } })))
  }
  if (!running.size) break
  const { id, r } = await Promise.race([...running.values()])
  running.delete(id)
  state[id] = r.state === 'done' ? 'done' : 'blocked'
  results[id] = r
  log(`${id}: ${r.state} — ${String(r.summary).slice(0, 160)}`)
}
const remaining = tickets.filter(t => state[t.id] === 'todo').map(t => t.id)
return { results, states: state, remaining, started }
