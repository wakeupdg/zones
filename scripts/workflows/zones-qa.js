export const meta = {
  name: 'zones-qa-round',
  description: 'Phase 4 QA round: lens finders (screens, auto ACs, security, accessibility, performance, onboarding, ledger triage) -> dedup -> three-vote adversarial verify',
  phases: [
    { title: 'Find', detail: 'one finder per lens; AC walkers in chunks' },
    { title: 'Dedup', detail: 'merge near-duplicates across finders and against seen' },
    { title: 'Verify', detail: 'three refuters per fresh finding' },
  ],
}

// args: { round, repo, seen: [{key,title}], acChunks: [[{id,title,statement,verify}], ...], preflight: string, lessons: string, acWalkerModel }
const R = args.round
const REPO = args.repo
const SEEN = args.seen || []
const PRE = args.preflight || '(no preflight facts)'
const LESSONS = args.lessons || ''

const FINDING = {
  type: 'object',
  properties: {
    title: { type: 'string', description: 'one line, concrete, names the symptom' },
    severity: { type: 'string', enum: ['blocker', 'major', 'minor'] },
    area: { type: 'string', description: 'drag|snap|overlay|editor|settings|shortcuts|onboarding|permission|topology|security|accessibility|performance|release|docs|build' },
    file: { type: 'string' },
    line: { type: 'integer' },
    ac: { type: 'string', description: 'AC-nnn or LI-nnn this violates, if any' },
    evidence: { type: 'string', description: 'what you observed: command + output, screenshot path, code excerpt' },
    repro: { type: 'string', description: 'exact steps or command to reproduce' },
    fix_hint: { type: 'string' },
  },
  required: ['title', 'severity', 'area', 'evidence', 'repro'],
}
const FINDINGS_SCHEMA = {
  type: 'object',
  properties: {
    findings: { type: 'array', items: FINDING },
    acResults: { type: 'array', items: { type: 'object', properties: { id: { type: 'string' }, pass: { type: 'boolean' }, note: { type: 'string' } }, required: ['id', 'pass', 'note'] } },
    screenshots: { type: 'array', items: { type: 'string' } },
    coverage: { type: 'string', description: 'what this lens covered and what it could NOT cover on this machine, with the reason' },
  },
  required: ['findings', 'coverage'],
}
const DEDUP_SCHEMA = {
  type: 'object',
  properties: {
    groups: { type: 'array', items: { type: 'object', properties: {
      canonical: { type: 'integer', description: 'index into the fresh list of the finding to keep' },
      duplicates: { type: 'array', items: { type: 'integer' } },
      matchesSeenKey: { type: 'string', description: 'key of an already-seen finding this group duplicates, else empty' },
      reason: { type: 'string' },
    }, required: ['canonical', 'duplicates', 'reason'] } },
  },
  required: ['groups'],
}
const VERDICT_SCHEMA = {
  type: 'object',
  properties: {
    refuted: { type: 'boolean' },
    confidence: { type: 'number' },
    reason: { type: 'string', description: 'what you checked (commands, files, lines) and why it holds or fails' },
    severity: { type: 'string', enum: ['blocker', 'major', 'minor'] },
  },
  required: ['refuted', 'confidence', 'reason'],
}

const COMMON = `Repo: "${REPO}" (quote the path: it has "!" and a space). Branch integration, read-only for you: never edit tracked files, never commit, never touch docs/tickets/graph.json. Run every build/test only as \`scripts/q.sh <cmd>\` (a hook enforces it; read the \`[q.sh] exit=N\` line). Read files by line range (sed -n 'a,bp'); never cat a directory or LOCKED-SPEC.md whole (grep -n for AC ids, then sed the 4-line block). Scratch files go under /private/tmp/claude-501/-Users-dganesh--MY-PROJECTS-open-source-clones-fancy-zones/faae5a4c-2276-4507-97e4-667cc6d49ef2/scratchpad/qa/round${R}/<lens>/ (mkdir -p it; it persists between your Bash calls; /tmp does not).
Preflight facts about this machine (established before this round; trust them):
${PRE}
LESSONS (tool quirks, obey):
${LESSONS}
Report ONLY real defects you observed or proved: a failing command, a wrong screenshot, a code path you traced to a concrete wrong behavior. Each finding needs evidence and a repro. No style nits, no speculation, no "consider". If a check is impossible on this machine (no Accessibility grant, no second display), say so in coverage and do not invent a finding. Return the structured output.`

const finders = []

// Lens 1: screens
finders.push({ key: 'screens', model: undefined, prompt: `${COMMON}
Lens: SCREENS (UX + HIG). screencapture and System Events do NOT work on this host (see preflight), so render every screen IN-PROCESS: create a throwaway worktree (\`git worktree add --detach .build/review-worktrees/qa-screens integration\`, run \`xcodegen generate\` there), add ONE scratch test file under AppTests/ (e.g. AppTests/QAScreenshots.swift, @MainActor XCTest or swift-testing like the existing AppTests files; read AppTests/*.swift headers first for the pattern and the host-app guard) that instantiates each SwiftUI root view (App/Settings/SettingsView.swift with every pane selected: General, Layouts, Shortcuts, Appearance, Exclusions, About; App/Onboarding/OnboardingView.swift both pages and the CheatSheetView; App/Editor editor view at a real Display size; App/Overlay ZoneLayerView/ZoneOverlayPanel content with a 9-Zone layout and a highlight) in both light and dark appearance (\`NSApp.appearance = NSAppearance(named: .darkAqua)\` or \`.environment(\\.colorScheme, .dark)\`), renders it with \`ImageRenderer(content:)\` (scale 2) or an NSHostingView + \`bitmapImageRepForCachingDisplay\`, and writes PNGs to your scratch dir. Run it with \`scripts/q.sh xcodebuild -project Zones.xcodeproj -scheme Zones -configuration Debug -derivedDataPath .build/DerivedData CODE_SIGN_IDENTITY="Zones Dev" -only-testing:AppTests/QAScreenshots test\` with Q_LOG so you can grep the log. Then LOOK at every PNG with the Read tool and list their paths. Remove the worktree at the end (\`git worktree remove --force\`). Also launch the real app once (\`open -n <Zones.app>\`, 5 s) and use a compiled swift tool (swiftc, not \`swift file.swift\`) calling CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) filtered by the Zones pid to list its on-screen window bounds and layer (no names needed) as evidence of which windows exist; then \`pkill -x Zones\`. Compare each screen against its ticket brief's Acceptance text (docs/tickets/T29.md T32.md T33.md T34.md T35.md T31.md: grep -n "^### AC-" then sed the blocks) and macOS HIG: truncated text, clipped controls, missing focus ring, wrong window placement (AC-021 cursor Display), dimmed-but-enabled controls, empty states, dark-mode legibility (toggle with \`osascript -e 'tell app "System Events" to tell appearance preferences to set dark mode to not dark mode'\` if Automation is allowed, else skip and say so). Quit the app at the end (pkill -x Zones).` })

// Lens 2..n: AC walkers (Sonnet)
;(args.acChunks || []).forEach((chunk, i) => {
  const list = chunk.join(', ')
  finders.push({ key: `acs${i + 1}`, model: args.acWalkerModel || 'sonnet', prompt: `${COMMON}
Lens: AUTO ACCEPTANCE WALK, chunk ${i + 1}. The ACs are listed by id below. For each id read ONLY its 4-line block from docs/LOCKED-SPEC.md: \`n=$(grep -n "^### AC-nnn " docs/LOCKED-SPEC.md | cut -d: -f1); sed -n "${'$'}{n},$((n+3))p" docs/LOCKED-SPEC.md\` (lines: heading with title, Statement, Covers, Verify). Batch several ids per Bash call. For EACH AC run its Verify command exactly (through scripts/q.sh when it is a build/test; use \`bash -c '...'\` for commands that split stderr from stdout; anchor swift-testing filters with $ when one test is meant). A test filter that runs 0 tests is a FAIL (note "0 tests ran"). When the Verify is a grep or script, run it and judge the output against the Statement. Record every AC in acResults with pass true/false and a one-line note (test count or key output). For each FAIL also emit a finding with the command output as evidence. If a Verify command cannot run on this machine (needs Accessibility, a second display, a human), mark pass=false with note "NOT RUNNABLE: <reason>" and do NOT emit a finding for it.
ACs:
${list}` })
})

// Lens: security-review
finders.push({ key: 'security', model: undefined, prompt: `${COMMON}
Lens: SECURITY. Invoke the \`security-review\` skill (Skill tool) over Sources/, App/, scripts/ and .github/. Then check by hand: no private API or SPI (grep -rn "_AX\\|@_spi\\|dlopen\\|dlsym\\|objc_msgSend\\|NSClassFromString" Sources App), no window titles or owner names read from CGWindowList (grep -rn "kCGWindowName\\|kCGWindowOwnerName" Sources App), no network (grep -rn "URLSession\\|Network\\|NWConnection" Sources App), entitlements (App/Zones.entitlements, App/Zones.Debug.entitlements: disable-library-validation must be Debug-only; read project.yml for which config uses which), scripts/release.sh and scripts/dev-cert.sh for unsafe shell (unquoted paths, rm -rf on variables, curl | sh), file writes outside Application Support (grep -rn "FileManager\\|URL(fileURLWithPath" Sources App | grep -v Tests), and the import/export path (LayoutsFlow / ImportExport: path traversal, oversize JSON, decoding of untrusted files). Every finding needs file:line evidence.` })

// Lens: accessibility
finders.push({ key: 'accessibility', model: undefined, prompt: `${COMMON}
Lens: ACCESSIBILITY (VoiceOver labels, keyboard-only). Static pass first: every control in App/Settings, App/Onboarding, App/Editor, App/Overlay, App/Composition (menu) must have an accessibility label/value where SwiftUI or AppKit does not infer one (images, KeyCapView, custom views, NSStatusItem button, NSMenu items with icons, CALayer overlay: the Overlay must expose Zone labels per AC in T26/T31 briefs). Check keyboard-only paths: Settings tab switching, Escape/Cmd-W close, the Layout editor keyboard commands (T35 brief AC list), the Shortcuts recorder (Tab focus, Escape cancels, Delete clears), onboarding Back/Next (dimmed-but-enabled is a defect). System Events is NOT available on this host (preflight), so do the dynamic pass IN-PROCESS: in a throwaway worktree (\`git worktree add --detach .build/review-worktrees/qa-a11y integration\`; \`xcodegen generate\`), add one scratch test file under AppTests/ that hosts each root view in an NSHostingView inside an offscreen NSWindow, then walks the NSAccessibility tree (\`accessibilityChildren()\`, \`accessibilityRole()\`, \`accessibilityLabel()\`, \`accessibilityTitle()\`, \`accessibilityValue()\`, \`isAccessibilityElement()\`) recursively and prints every element whose role is button/checkbox/popUpButton/textField/slider/image/menuItem with an empty label AND title; do the same for the status-item NSMenu built by App/Composition (MenuController/MenuModel) and for the overlay panel content view. Run with \`scripts/q.sh xcodebuild ... -only-testing:AppTests/<YourSuite> test\` with Q_LOG and grep the printed lines. Remove the worktree at the end.` })

// Lens: performance
finders.push({ key: 'performance', model: undefined, prompt: `${COMMON}
Lens: PERFORMANCE (drag at 120 Hz, 3 Displays). Run \`scripts/q.sh swift test --filter 'BudgetTests|SPK009|Perf|Budget'\` and read docs/spikes/SPK-009.md and docs/tickets/T37/ledger.md slices 10-11 for the measured numbers and the 8.33 ms/frame budget. Then trace the live drag hot path for per-event allocations and blocking: App/Composition/*.swift (the input loop that feeds DragSessionReducer and applies effects), Sources/ZonesWindowing/Adapters/EventTapInputSource.swift (tap thread, unbounded AsyncStream buffering: prove whether a slow consumer can lag the highlight), Sources/ZonesWindowing/Drag/*.swift (per-dragged work: HitTest, Span.rect, highlight diff), App/Overlay/*.swift (CALayer updates per highlight, implicit animations, one panel per Display), and the frame sampling cadence (requestSample per tick). Build a synthetic 3-Display ArmContext from Tests fixtures and time 10,000 dragged events across Display seams in a scratch @Suite under Tests/ZonesWindowingTests/ of a throwaway worktree (git worktree add --detach .build/review-worktrees/qa-perf integration; remove it after; never in the main checkout). Report measured p50/p99 per event and any path that blocks the tap thread or the main thread (sync AX calls, DispatchSemaphore, unbounded buffers).` })

// Lens: onboarding after TCC reset
finders.push({ key: 'onboarding', model: undefined, prompt: `${COMMON}
Lens: FIRST-RUN ONBOARDING after \`tccutil reset Accessibility com.dganesh.zones\` (authorized for this run; it clears only this app's grant). Steps: run the reset; launch the built app (\`open -n <Zones.app path from preflight>\`); within 5 s the Onboarding/Welcome window must appear. You cannot screenshot (no Screen Recording) and System Events is unavailable, so prove the window with a compiled swift tool (swiftc -o, never \`swift file.swift\`) that calls CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) and prints kCGWindowOwnerPID/kCGWindowBounds/kCGWindowLayer for windows owned by the Zones pid (names need Screen Recording; do not read them), and with \`/usr/bin/log show --process Zones --last 2m --info --debug --predicate 'subsystem == "Zones"'\` for the permission/app categories; (AC-004/AC-005 in docs/tickets/T33.md: grep -n "^### AC-" and sed the blocks), the status item must show the badge and a "Grant Accessibility" menu item (AC-012/AC-018 in T29.md). Screenshot it. Verify: the System Settings button opens the Accessibility pane (x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility) and the app keeps running; the window text matches the brief (no private NSAlert); Back/Next behavior; Cmd-W/Escape; the "Quit and Reopen" path must not terminate when relaunch fails (read App/Onboarding/OnboardingWindowController.swift relaunchApp). Check the launch log (per preflight) for the trust poll cadence (1 s) and no error spam. Also verify the login-launch path by reading App/Composition for launchedAtLogin handling against AC-012 (no window at login, badge + menu item instead) and the known issue in AppTests/AppLaunchTests.swift:47 (withKnownIssue): decide whether it is a real defect and report it as a finding if so, with the exact expectation text. Quit the app at the end. Do not grant Accessibility (you cannot; say so in coverage).` })

// Lens: ledger + reviewer non-blocker triage
finders.push({ key: 'triage', model: undefined, prompt: `${COMMON}
Lens: TRIAGE of recorded non-blockers. Read docs/STATUS.md section "Open items for Phase 4" and every docs/tickets/T*/ledger.md line containing "deviation", "GAP", "gap", "manual", "TODO", "not wired", "unwired", "pre-existing" (grep -rn -i over docs/tickets/*/ledger.md). For each candidate that describes behavior a user or an AC would see as wrong (not a style note), open the code at the named file and confirm it is still true on integration (grep/sed the lines). Emit one finding per confirmed real defect with file:line evidence and the AC/LI it touches. Skip anything already fixed (say so in coverage with the ledger line). Examples to check: Seams/WindowHandle.swift importing ApplicationServices vs AC-162 scope; Templates.generate(.grid, count:) silently building 2x2; span.zones keeping old-layout numbers after topologyChanged; EditorLauncher.start() not called; T29/T36 login-path badge expectation (AppLaunchTests known issue); SnapMode.positionOnly never carried; T33 relaunchApp terminating on failure; T33 show() activating on revocation; status item isTemplate ignored.` })

phase('Find')
const results = await parallel(finders.map(f => () =>
  agent(f.prompt, { label: `find:${f.key}`, phase: 'Find', schema: FINDINGS_SCHEMA, model: f.model })
    .then(r => ({ lens: f.key, ...r }))))
const lensResults = results.filter(Boolean)
log(`round ${R}: ${lensResults.length}/${finders.length} finders returned`)

const acResults = []
const screenshots = []
const coverage = {}
const fresh = []
for (const r of lensResults) {
  for (const a of (r.acResults || [])) acResults.push(a)
  for (const s of (r.screenshots || [])) screenshots.push(s)
  coverage[r.lens] = r.coverage
  for (const f of (r.findings || [])) fresh.push({ ...f, lens: r.lens })
}
log(`round ${R}: ${fresh.length} raw findings, ${acResults.length} AC results`)

// Dedup: code key first, then one agent pass for near-duplicates and matches against seen
const norm = s => (s || '').toLowerCase().replace(/[^a-z0-9 ]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 80)
const keyOf = f => `${f.area}|${norm(f.title)}`
const dropped = []
const seenKeys = new Set(SEEN.map(s => s.key))
let candidates = []
const byKey = new Map()
for (const f of fresh) {
  const k = keyOf(f)
  if (seenKeys.has(k)) { dropped.push({ ...f, key: k, reason: 'exact key already seen in an earlier round' }); continue }
  if (byKey.has(k)) { dropped.push({ ...f, key: k, reason: `exact key duplicate of "${byKey.get(k).title}" from lens ${byKey.get(k).lens}` }); continue }
  byKey.set(k, f); candidates.push({ ...f, key: k })
}
let canonical = candidates
if (candidates.length > 1) {
  phase('Dedup')
  const seenList = SEEN.map(s => `- ${s.key} :: ${s.title}`).join('\n') || '(none)'
  const freshList = candidates.map((f, i) => `[${i}] (${f.lens}, ${f.severity}, ${f.area}${f.file ? ', ' + f.file + (f.line ? ':' + f.line : '') : ''}) ${f.title} :: ${f.evidence.slice(0, 200)}`).join('\n')
  const d = await agent(`You deduplicate QA findings. Two findings are duplicates only when fixing one necessarily fixes the other (same root cause at the same place), not when they merely share an area. Group the FRESH list; for each group name the canonical index (the one with the best evidence) and its duplicates. If a group duplicates an already-SEEN finding (same root cause), set matchesSeenKey to that key. Every fresh index must appear exactly once across all groups (as canonical or duplicate).
SEEN (earlier rounds):
${seenList}
FRESH:
${freshList}`, { label: 'dedup', phase: 'Dedup', schema: DEDUP_SCHEMA })
  if (d && d.groups) {
    const keep = []
    const placed = new Set()
    for (const g of d.groups) {
      const c = candidates[g.canonical]
      if (!c || placed.has(g.canonical)) continue
      for (const di of (g.duplicates || [])) {
        const dup = candidates[di]
        if (dup && di !== g.canonical && !placed.has(di)) { placed.add(di); dropped.push({ ...dup, reason: `near-duplicate of "${c.title}" (${g.reason})` }) }
      }
      placed.add(g.canonical)
      if (g.matchesSeenKey) dropped.push({ ...c, reason: `duplicates seen finding ${g.matchesSeenKey} (${g.reason})` })
      else keep.push(c)
    }
    for (let i = 0; i < candidates.length; i++) if (!placed.has(i)) keep.push(candidates[i])
    canonical = keep
  }
}
log(`round ${R}: ${canonical.length} fresh findings after dedup, ${dropped.length} dropped`)

// Verify: three refuters per finding
phase('Verify')
const LENSES = ['correctness (trace the code path and run the repro yourself)', 'spec (is this actually required by the AC/LI/ticket brief it cites, or allowed behavior?)', 'reproduction (does the evidence hold on integration right now; re-run the exact command)']
const verified = await parallel(canonical.map(f => () =>
  parallel(LENSES.map((lens, li) => () =>
    agent(`${COMMON}
You are a skeptical verifier with the ${lens} lens. Try to REFUTE this QA finding. Default to refuted=true when you cannot confirm it with your own evidence within your lens.
FINDING: ${f.title}
severity: ${f.severity}; area: ${f.area}; ${f.file ? 'file: ' + f.file + (f.line ? ':' + f.line : '') : ''} ${f.ac ? 'cites: ' + f.ac : ''}
evidence: ${f.evidence}
repro: ${f.repro}
Return refuted (bool), confidence 0-1, your reason with what you ran/read, and the severity you would assign if it stands.`, { label: `verify:${f.key.slice(0, 40)}:${li}`, phase: 'Verify', schema: VERDICT_SCHEMA })))
    .then(vs => {
      const votes = vs.filter(Boolean)
      const stands = votes.filter(v => !v.refuted).length
      const sev = votes.map(v => v.severity).filter(Boolean)
      return { ...f, votes, confirmed: stands >= 2, standsVotes: stands, severityVoted: sev.length ? sev.sort()[0] : f.severity }
    })))
const vlist = verified.filter(Boolean)
const confirmed = vlist.filter(v => v.confirmed)
const refuted = vlist.filter(v => !v.confirmed)
for (const r of refuted) dropped.push({ ...r, reason: `outvoted: ${r.standsVotes}/3 verifiers kept it; ${r.votes.map(v => v.reason.slice(0, 160)).join(' | ')}` })
log(`round ${R}: ${confirmed.length} confirmed, ${refuted.length} refuted`)

return {
  round: R,
  finders: finders.map(f => f.key),
  coverage,
  acResults,
  screenshots,
  confirmed: confirmed.map(c => ({ key: c.key, title: c.title, severity: c.severityVoted, area: c.area, file: c.file, line: c.line, ac: c.ac, evidence: c.evidence, repro: c.repro, fix_hint: c.fix_hint, lens: c.lens, votes: c.votes.map(v => ({ refuted: v.refuted, confidence: v.confidence, reason: v.reason })) })),
  dropped: dropped.map(d => ({ key: d.key || keyOf(d), title: d.title, lens: d.lens, severity: d.severity, reason: d.reason })),
  rawCount: fresh.length,
}
