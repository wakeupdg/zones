# Acceptance matrix (Zones 0.1.0, 2026-10-24)

Source: QA round 1 (all auto ACs walked) and QA round 2 (11 re-walked after fixes). Auto: 139; pass 139; fail 0; fixed-after-fail or not walked 0. Manual: 30 (never marked pass by an agent). Human run 2026-10-24: 4 pass (AC-004, AC-010, AC-057, AC-066), 1 fail (AC-009), 1 blocked (AC-005); 24 still need a human run.

| AC | kind | title | tickets | result |
|---|---|---|---|---|
| AC-001 | auto | Menu-bar only | T01b | pass (QA round 1) |
| AC-002 | auto | Hardened runtime, no sandbox | T38 | pass (QA round 1) |
| AC-003 | auto | Only Accessibility, no private symbols | T38 | pass (QA round 1) |
| AC-004 | manual | Onboarding window | T33,T40 | pass (human run 2026-10-24, macOS 27.0.1) |
| AC-005 | manual | Grant noticed without relaunch | T33 | blocked by AC-009 (onboarding window never returned) |
| AC-006 | auto | Poll schedule per permission state | T20 | pass (QA round 1) |
| AC-007 | auto | Revocation via runtime signals | T20 | pass (QA round 1) |
| AC-008 | auto | Relaunch gate | T20 | pass (QA round 1) |
| AC-009 | manual | Revocation on a real Mac | T20 | FAIL (human run 2026-10-24: revocation not detected; heartbeat off, SPK-006) |
| AC-010 | manual | Re-grant recovery | T20,T40 | pass (human run 2026-10-24, macOS 27.0.1) |
| AC-011 | auto | Tap re-enable rate limit | T23 | pass (QA round 1) |
| AC-012 | auto | Launched-at-login path | T29,T41 | pass (QA round 2) |
| AC-013 | auto | Stable dev signing | T38 | pass (QA round 1) |
| AC-014 | auto | Ad-hoc release warning | T38 | pass (QA round 1) |
| AC-015 | auto | Signing identity in the report | T11 | pass (QA round 1) |
| AC-016 | auto | Menu model | T29 | pass (QA round 1) |
| AC-017 | auto | Menu never waits on the WindowActor | T29 | pass (QA round 1) |
| AC-018 | auto | Status item state | T29,T40 | pass (QA round 2) |
| AC-019 | auto | General status rows | T29 | pass (QA round 1) |
| AC-020 | manual | Cheat sheet and key caps | T33 | manual — needs a human run |
| AC-021 | auto | Re-run onboarding | T20,T47 | pass (QA round 1) |
| AC-022 | auto | Window placement | T32 | pass (QA round 1) |
| AC-023 | manual | Key status | T32 | manual — needs a human run |
| AC-024 | auto | Wake handling | T20 | pass (QA round 1) |
| AC-025 | manual | Wake on a docked Mac | T20 | manual — needs a human run |
| AC-026 | auto | Quit sequence | T29 | pass (QA round 1) |
| AC-027 | auto | Login toggle derivation | T32 | pass (QA round 1) |
| AC-028 | manual | Login item on a clean account | T32 | manual — needs a human run |
| AC-029 | auto | About model | T32 | pass (QA round 1) |
| AC-030 | manual | About pane on screen | T32 | manual — needs a human run |
| AC-031 | auto | Modifier first arms after confirmed move | T16 | pass (QA round 1) |
| AC-032 | auto | A click costs nothing | T16 | pass (QA round 1) |
| AC-033 | auto | Overlay only after move | T16 | pass (QA round 1) |
| AC-034 | auto | Highlight under cursor | T16 | pass (QA round 1) |
| AC-035 | auto | Modifier release cancels | T16 | pass (QA round 1) |
| AC-036 | auto | Snap keyed on mouse-up flags | T16,T45 | pass (QA round 2) |
| AC-037 | auto | Modifier late | T16 | pass (QA round 1) |
| AC-038 | auto | Plain drag records nothing | T16 | pass (QA round 1) |
| AC-039 | auto | Hot-path budgets | T37 | pass (QA round 2) |
| AC-040 | manual | 120 Hz pacing | T31,T50 | manual — needs a human run |
| AC-041 | auto | Snap touches one window | T15 | pass (QA round 1) |
| AC-042 | auto | Fill and highlight styles | T26 | pass (QA round 1) |
| AC-043 | auto | Panel configuration | T31 | pass (QA round 1) |
| AC-044 | manual | Drag uninterrupted | T31 | manual — needs a human run |
| AC-045 | auto | Displays outside the arm snapshot | T21 | pass (QA round 1) |
| AC-046 | manual | Full-screen Space Display | T31 | manual — needs a human run |
| AC-047 | auto | Full-screen and skipped windows never arm | T21 | pass (QA round 1) |
| AC-048 | auto | Resize is never a session | T16 | pass (QA round 1) |
| AC-049 | auto | Background window | T16 | pass (QA round 1) |
| AC-050 | auto | Stray buttons and presses ignored | T23 | pass (QA round 1) |
| AC-051 | auto | Modifier masking | T16 | pass (QA round 1) |
| AC-052 | auto | Cross-Display hit and drop | T21 | pass (QA round 1) |
| AC-053 | auto | Hide before write | T16 | pass (QA round 1) |
| AC-054 | auto | Window gone mid-drag | T16 | pass (QA round 1) |
| AC-055 | auto | Pause keeps the press | T16 | pass (QA round 1) |
| AC-056 | auto | Candidate resolution | T21 | pass (QA round 1) |
| AC-057 | manual | Four identical terminals | T21 | pass (human run 2026-10-24, macOS 27.0.1) |
| AC-058 | auto | Accessibility settings in the model | T31 | pass (QA round 1) |
| AC-059 | auto | Zones inside the visible frame | T26 | pass (QA round 1) |
| AC-060 | auto | Topology change mid-session | T21 | pass (QA round 1) |
| AC-061 | manual | Resolution change mid-drag | T31 | manual — needs a human run |
| AC-062 | auto | Space change re-asserts | T21 | pass (QA round 1) |
| AC-063 | auto | Label model | T26 | pass (QA round 1) |
| AC-064 | manual | Accessibility on screen | T31 | manual — needs a human run |
| AC-065 | auto | Listen-only tap configuration | T23 | pass (QA round 1) |
| AC-066 | manual | Modifier never consumed | T23 | pass (human run 2026-10-24, macOS 27.0.1) |
| AC-067 | auto | Excluded at phase 1 | T21 | pass (QA round 1) |
| AC-068 | auto | Overlay and Snap share one geometry | T09 | pass (QA round 1) |
| AC-069 | auto | Divider rounding | T09 | pass (QA round 1) |
| AC-070 | manual | Cross-scale Snap on screen | T36 | manual — needs a human run |
| AC-071 | auto | Clamped size placement | T15 | pass (QA round 1) |
| AC-072 | auto | Read-back is truth | T15 | pass (QA round 1) |
| AC-073 | auto | Write order | T15 | pass (QA round 1) |
| AC-074 | auto | Enhanced UI protocol | T19 | pass (QA round 1) |
| AC-075 | manual | Electron and VoiceOver | T19 | manual — needs a human run |
| AC-076 | auto | Recovery record | T19 | pass (QA round 1) |
| AC-077 | auto | Timeout protocol | T15 | pass (QA round 1) |
| AC-078 | manual | Hung app on a real Mac | T15 | manual — needs a human run |
| AC-079 | auto | Idempotent Snap | T15 | pass (QA round 1) |
| AC-080 | auto | Gap and Margin snap to nearest | T22 | pass (QA round 1) |
| AC-081 | auto | Span accumulation and union | T22 | pass (QA round 1) |
| AC-082 | auto | Highlight invariant | T37,T39,T45 | pass (QA round 2) |
| AC-083 | auto | Freeze, resume, clear | T22 | pass (QA round 1) |
| AC-084 | auto | Suspend across a seam | T22 | pass (QA round 1) |
| AC-085 | manual | Seam skim on three Displays | T22,T45 | manual — needs a human run |
| AC-086 | auto | Both modifiers first | T22 | pass (QA round 1) |
| AC-087 | auto | Modifier choice | T10 | pass (QA round 1) |
| AC-088 | auto | Focus Template | T12 | pass (QA round 1) |
| AC-089 | auto | First-Snap capture | T24 | pass (QA round 1) |
| AC-090 | auto | Restore command | T24 | pass (QA round 1) |
| AC-091 | auto | Mouse Restore and dim cue | T22 | pass (QA round 1) |
| AC-092 | auto | Restore no-ops | T24 | pass (QA round 1) |
| AC-093 | auto | Forget rules | T24 | pass (QA round 1) |
| AC-094 | auto | Restore after Span | T24 | pass (QA round 1) |
| AC-095 | auto | Off-Display clamp | T24 | pass (QA round 1) |
| AC-096 | manual | Restore returns to the pre-grab place | T24 | manual — needs a human run |
| AC-097 | auto | Defaults match ADR-0010 | T27 | pass (QA round 1) |
| AC-098 | auto | Send to Zone N | T28 | pass (QA round 1) |
| AC-099 | auto | Zone numbering property | T09 | pass (QA round 1) |
| AC-100 | auto | Cycle table | T28 | pass (QA round 1) |
| AC-101 | auto | Zone N beyond count | T28 | pass (QA round 1) |
| AC-102 | auto | Command or Control required | T27 | pass (QA round 1) |
| AC-103 | auto | Recorder states | T27,T42,T47 | pass (QA round 2) |
| AC-104 | auto | Registration failure keeps old chord | T27 | pass (QA round 1) |
| AC-105 | auto | Registration by permission state | T27 | pass (QA round 1) |
| AC-106 | manual | Shortcuts without the grant | T27 | manual — needs a human run |
| AC-107 | manual | Editor and Settings chords | T27 | manual — needs a human run |
| AC-108 | auto | Command path gates | T28 | pass (QA round 1) |
| AC-109 | auto | Cleared shortcut | T27 | pass (QA round 1) |
| AC-110 | auto | Dispatch during a Drag Session | T27 | pass (QA round 1) |
| AC-111 | auto | Preference change diff | T27 | pass (QA round 1) |
| AC-112 | auto | Template shapes | T12 | pass (QA round 1) |
| AC-113 | auto | Default Assignment | T17 | pass (QA round 1) |
| AC-114 | auto | Built-in identifiers and Duplicate | T12 | pass (QA round 1) |
| AC-115 | auto | Delete needs a replacement | T17 | pass (QA round 1) |
| AC-116 | auto | Tiling property | T09 | pass (QA round 1) |
| AC-117 | auto | Margin and Gap defaults | T17 | pass (QA round 1) |
| AC-118 | auto | Topology Assignment rules | T25 | pass (QA round 1) |
| AC-119 | manual | Dock Display replug | T25 | manual — needs a human run |
| AC-120 | auto | Layouts pane model | T25 | pass (QA round 1) |
| AC-121 | auto | Separate Spaces notice | T25 | pass (QA round 1) |
| AC-122 | auto | Mirror handling | T25 | pass (QA round 1) |
| AC-123 | auto | Unstable and nil identifiers | T25 | pass (QA round 1) |
| AC-124 | auto | Debounce and resize | T25 | pass (QA round 1) |
| AC-125 | auto | Disconnected Display editing | T30 | pass (QA round 1) |
| AC-126 | manual | Editor backdrop | T35 | manual — needs a human run |
| AC-127 | auto | Single-key split | T18 | pass (QA round 1) |
| AC-128 | auto | Divider snapping and nudging | T18 | pass (QA round 1) |
| AC-129 | auto | Merge rules | T18 | pass (QA round 1) |
| AC-130 | auto | Undo and redo | T18 | pass (QA round 1) |
| AC-131 | auto | Live Margin and Gap | T30 | pass (QA round 1) |
| AC-132 | auto | Editor labels equal Overlay labels | T30 | pass (QA round 1) |
| AC-133 | auto | Display switch | T30 | pass (QA round 1) |
| AC-134 | auto | Assign | T30,T48 | pass (QA round 1) |
| AC-135 | auto | Validator limits | T18 | pass (QA round 1) |
| AC-136 | auto | Save and Cancel | T30 | pass (QA round 1) |
| AC-137 | auto | Zone count edges | T18 | pass (QA round 1) |
| AC-138 | auto | Template picker | T18 | pass (QA round 1) |
| AC-139 | manual | Keyboard-only editor loop | T35,T43,T48,T49 | manual — needs a human run |
| AC-140 | auto | Appearance preferences | T10 | pass (QA round 1) |
| AC-141 | manual | Appearance applies live | T34 | manual — needs a human run |
| AC-142 | auto | Exclusions model | T14 | pass (QA round 1) |
| AC-143 | auto | Exclusion policy table | T14 | pass (QA round 1) |
| AC-144 | manual | Automatic skips on screen | T14,T46 | manual — needs a human run |
| AC-145 | auto | Export shape | T10 | pass (QA round 1) |
| AC-146 | auto | Merge and Replace | T17,T44 | pass (QA round 2) |
| AC-147 | auto | Newer versions | T10 | pass (QA round 1) |
| AC-148 | auto | Dormant Assignments | T17 | pass (QA round 1) |
| AC-149 | auto | Corrupt file | T10 | pass (QA round 1) |
| AC-150 | auto | Atomic writes | T10 | pass (QA round 1) |
| AC-151 | auto | Import validation | T17,T44 | pass (QA round 2) |
| AC-152 | auto | Migrations and golden fixtures | T10 | pass (QA round 1) |
| AC-153 | auto | Preferences coercion | T10 | pass (QA round 1) |
| AC-154 | auto | Diagnostics report | T11 | pass (QA round 1) |
| AC-155 | auto | Skip reasons logged | T11 | pass (QA round 1) |
| AC-156 | auto | Idle schedule | T37 | pass (QA round 1) |
| AC-157 | manual | Idle CPU | T36 | manual — needs a human run |
| AC-158 | auto | Heartbeat isolation | T20 | pass (QA round 1) |
| AC-159 | auto | Typed results and timeouts | T13 | pass (QA round 1) |
| AC-160 | auto | One command, CI | T01,T44,T52 | pass (QA round 2) |
| AC-161 | auto | Strict concurrency | T01b,T44 | pass (QA round 2) |
| AC-162 | auto | App-target hygiene gate | T38,T51 | pass (QA round 2) |
| AC-163 | auto | Fakes for every seam | T02 | pass (QA round 1) |
| AC-164 | auto | One coordinate conversion | T09 | pass (QA round 1) |
| AC-165 | auto | Seed in failure message | T02 | pass (QA round 1) |
| AC-166 | auto | Reducer invariants | T37 | pass (QA round 1) |
| AC-167 | auto | Ticket shape | T38 | pass (QA round 1) |
| AC-168 | manual | Release checklist | T38 | manual — needs a human run |
| AC-169 | auto | Logger facade | T11 | pass (QA round 1) |
