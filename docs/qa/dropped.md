# QA — dropped findings
One line per deduped, outvoted, or skipped finding: `round | finding | reason`.
## Round 1 (2026-10-24)
- [accessibility/minor] Onboarding Back (page 1) and Next (page 2) are dimmed to 40% opacity yet enabled and inert: dimmed-but-enabled affordance — near-duplicate of "Onboarding Back/Next buttons are drawn dimmed (opacity 0.4) while still enabled" (Both report the same code: OnboardingView.swift:21-26 Back/Next dimmed to 0.4 opacity while still enabled. Removing the opacity hack / disabling the buttons fixes both. [1] has code plus rendered screenshots.)
- [acs5/minor] AC-151 Verify filter DocumentTests.importValidatesWholeFile runs 0 tests (test lives in ImportExportTests) — near-duplicate of "AC-146 Verify filter DocumentTests.mergeAndReplace runs 0 tests (test lives in ImportExportTests)" (Both AC-146 and AC-151 verify filters reference a DocumentTests suite that does not exist; the tests live in ImportExportTests. One fix (rename the suite or correct the catalog's suite name) resolves both.)
- [triage/minor] 'Quit and Reopen' terminates Zones even when the relaunch failed to open a new instance — near-duplicate of ""Quit and Reopen" terminates the running app even when the relaunch fails (completion ignores the error)" (Same file and line (OnboardingWindowController.swift:104-110): relaunchApp completion ignores the error and always terminates. One fix resolves both.)
- [triage/minor] Status item image is forced non-template, ignoring StatusItemModel.isTemplate (AC-018 says the image is a template image) — near-duplicate of "Status item NSImage is explicitly non-template (image.isTemplate = false) while AC-018 states the image is a template image" (Same file and line (StatusItemController.swift:94): image.isTemplate = false hard-coded, ignoring the template requirement/model flag. One fix resolves both; [14] has in-process runtime verification.)
- [screens/major] Onboarding window did not appear within 20 s on one not-trusted launch (0 of 4 windows at layer 0), but appeared at 8 s on the next launch — outvoted: 0/3 verifiers kept it; Could not reproduce and the finding's mechanism is contradicted by the logs of the failed launch itself.

1. Repro (5 launches, 05:07-05:09 AM PT, `open -n .bui | What I ran/read:
1. Spec: docs/LOCKED-SPEC.md:227-230 (AC-004) requires "first launch shows exactly one window" on a clean account; it states no time bound (the | Re-ran the exact repro on integration (52
- [accessibility/major] Editor canvas (the Zones, selection and dividers) is invisible to VoiceOver: not an accessibility element, no role, no children — outvoted: 1/3 verifiers kept it; Technical observation CONFIRMED independently, but the defect claim against AC-139 is refuted: no spec clause makes the observed behavior wrong.

What I ran (ow | Observation is factual but the requirement is not. (1) Observation confirmed: a11y-run3.log:357 `A11Y[editor.canvas] elem=false role=AXUnknown label='' children | CONFIRMED on integration @ 523b079 with m
- [accessibility/major] Escape does not close the Settings window (or the onboarding window) through the key-event path; only Cmd-W does — outvoted: 0/3 verifiers kept it; Ran my own repro; the finding does not hold.

1. Code read
- App/Settings/SettingsWindow.swift overrides `cancelOperation(_:)` to call `performClose`.
- The onb | 1) Spec lens: AC-023 (LOCKED-SPEC.md:303-306, also T32.md:20-23) only covers key status: the window becomes key from the menu and orders front from the hotkey.  | The finding's closes=0 comes from the tes
- [triage/minor] element(at:) keeps issuing AX calls to a hung app after a timeout, up to ~6 s on the WindowActor per mouse-down — outvoted: 1/3 verifiers kept it; I read the code myself and checked who calls it. Four points knock out the finding:

1. The "up to ~6 s, 25 calls" figure is wrong.
   - AXRaw.copy (AXWindowSys | I refuted it on four separate points:
1. Wrong citation. AC-039 (LOCKED-SPEC.md:369-372) is about hot-path budgets: zero allocations in hitTest/spanRect/resolve | The core finding holds. The ~6 s / 25-cal

