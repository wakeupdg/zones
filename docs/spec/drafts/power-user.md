# Zones — spec draft: power-user ergonomics (revised after round 3)

Persona: keyboard-and-mouse power user, years of FancyZones on Windows, now on a 3-Display Mac. Values speed, predictability, discoverability, zero surprise during a Drag Session, multi-Display and multi-window flows, shortcuts that never collide, and an editor faster than typing numbers.

## Problem Statement

I run three Displays and twenty windows. macOS gives me nothing between "drag it by hand" and full-screen. Every window I open lands somewhere random; every day I waste minutes nudging edges so two terminals and a browser line up. Third-party tools either tile everything (and fight me), or snap to halves and quarters only, or need me to memorize a dozen chords that collide with my editor's. On Windows I had FancyZones: hold a key while dragging, see the Layout, drop, done; one chord per Zone; a visual editor I could tweak in seconds. I want that on my Mac, with the same predictability: the same gesture always does the same thing, across every Display, for every well-behaved window, and it never moves a window I did not touch.

## Solution

Zones is a menu-bar app. Each Display gets a Layout: a set of rectangular Zones that tile it, from a Template or from my own editor. During a Drag Session I hold the Activation Modifier (default Shift): once the window actually moves, the Overlay appears, the Zone under my cursor highlights, and releasing the mouse Snaps the window into it. Holding the Span Modifier (default Control) too lets me sweep across several Zones and Snap to their union. Shortcuts send the focused window to Zone N, cycle it through Zones, or Restore its Original Frame. Nothing else moves. Windows I never want touched are excluded per app. Layouts live in plain JSON I can export, diff, and import on another Mac. What the Overlay draws is exactly where the window lands, to the pixel.

## User Stories

### Install, permission, shell
US-001. As a power user, I want Zones to live in the menu bar with no Dock icon, so that it never takes a Dock slot or a Command-Tab position.
US-002. As a first-time user, I want one onboarding window that explains why Accessibility is needed and a button that opens the exact System Settings pane, so that I am not hunting through Privacy settings.
US-003. As a first-time user, I want the onboarding window to notice the grant within a second of my flipping the toggle, with no relaunch, so that I can start dragging immediately.
US-004. As a user who revoked Accessibility by accident, I want the menu-bar icon to show a badge and the onboarding window to come back, so that I understand why nothing snaps instead of thinking the app is broken.
US-005. As a user, I want Zones to request only Accessibility and never Screen Recording or Input Monitoring, so that I am not asked for permissions that imply it reads my screen or keystrokes.
US-006. As a user, I want a launch-at-login toggle that reflects the real system state (including "turned off in Login Items" with a button to that pane), so that the toggle is never lying to me.
US-007. As a user, I want launch-at-login to be off by default and to be registered only when I turn it on, so that no app re-adds itself after I removed it.
US-008. As a user updating a Developer ID-signed release, I want the Accessibility grant to survive the update, the release script to warn loudly when it falls back to ad-hoc signing, and About and diagnostics to name the signing identity, so that a lost grant after an update explains itself.
US-009. As a user, I want the menu to list the Layouts for the Display under the cursor, with the active one checked, so that switching a Display's Layout is two clicks.
US-010. As a user, I want the menu to offer Edit Layouts, Settings, and Quit, so that every surface is reachable from the icon.
US-121. As a user who revoked and re-granted Accessibility, I want Zones to say plainly when the running process cannot pick the grant up and to offer one "Quit and Reopen" button only then, after repeated failed recoveries, so that I am never toggling a switch that appears dead and never shown a button that does nothing.
US-122. As a user launched at login without the grant, I want only the badge and a "Grant Accessibility" menu item, never a window, so that login does not steal focus.
US-123. As a power user, I want the menu to open instantly even while a target app is hung, so that Zones never looks frozen.
US-124. As a laptop user who docks lid-closed, I want the first modifier-drag after wake to work and the Display list and permission to be re-checked on wake, so that sleep never leaves a dead tap or stale geometry.
US-149. As a power user, I want a checkable "Exclude <App>" item in the menu for the frontmost app, checked when it is already excluded so the same click undoes it, so that a one-click exclusion is fast and a slip is one click back.
US-150. As a power user, I want Settings and the editor to open on the Space and Display my cursor is on and become key immediately, so that a menu-bar app behaves like a normal window when I ask for one.
US-152. As a user who revoked the grant while Zones sat idle, I want the badge within about five seconds, not at my next drag, so that the icon tells me before a failed gesture does (gated on the heartbeat spike; otherwise the badge appears at the next drag or tap signal and Settings says so).
US-153. As a user, I want Quit to tear down the event tap and panels and restore anything Zones changed in other apps, so that nothing lingers after I leave.

### Drag Session and Snap
US-011. As a power user, I want to hold the Activation Modifier while dragging any window and see the Overlay for every Display, so that I know exactly where a drop will land before I let go.
US-012. As a power user, I want the highlighted Zone to be the one under my cursor, not under the window's center, so that I can aim a large window precisely with a small motion.
US-013. As a power user, I want releasing the Activation Modifier mid-drag to hide the Overlay and cancel the Snap, so that I have a one-key escape hatch without touching the keyboard elsewhere.
US-014. As a power user, I want the Snap to depend only on whether the Activation Modifier is down at mouse-up, so that the rule is one sentence I can trust.
US-015. As a power user, I want to be able to press the Activation Modifier before the mouse-down or after the drag starts, so that both habits work.
US-016. As a power user, I want a plain drag with no modifier to do nothing at all (no Overlay, no Snap, no Restore), so that normal window handling is untouched.
US-017. As a power user, I want the Overlay to appear within one display refresh of the later of (modifier down, move confirmed) and the highlight to follow the cursor at display refresh rate, so that the gesture feels native.
US-018. As a power user, I want several windows to coexist in one Zone, so that I can stack two terminals in the same slot and alt-tab between them.
US-019. As a power user, I want a Snap to never move any window other than the one I am dragging, so that nothing on my other Displays shifts.
US-020. As a power user, I want the Overlay to draw its fills translucent above the dragged window so I can still read the window while aiming, so that neither occludes the other.
US-021. As a power user, I want the Overlay to never steal focus, never become key, and never intercept my clicks, so that the drag completes in the app I started it in.
US-022. As a power user, I want the Overlay to show on a Display whose active Space is a full-screen app when I drag a non-full-screen window there, if the overlay spike proves the panel is visible there, and the drop to use that Display's geometry, so that my setup works while a video plays full-screen on Display 3.
US-023. As a power user, I want Zones to do nothing, silently, when the window itself is full-screen, so that no half-applied resize wrecks a full-screen app.
US-024. As a power user dragging a window that an app refuses to resize, I want Zones to accept whatever size the app allowed and position the window inside the Zone (top-left aligned) rather than retry or fail, so that I still get a predictable placement.
US-025. As a power user, I want a Snap into a Zone smaller than the window's minimum size to leave the window at its minimum, aligned to the Zone's top-left, so that it never falls off the Display.
US-026. As a power user, I want a Snap to read back the frame the app accepted and treat that as truth, so that the "cycle" and "restore" paths work from reality, not from what Zones asked for.
US-027. As a power user, I want any resize gesture (size changing, from any edge or corner) to never be treated as a Drag Session, so that resizing with Shift held in a drawing app is not hijacked.
US-028. As a power user, I want Zones to give up on a hung app within a quarter of a second per call and keep my Overlay responsive, so that one frozen Electron app does not freeze my window manager.
US-029. As a power user, I want Chromium and Electron windows to move without the slow animated "enhanced UI" slide, so that a Snap in Chrome feels as crisp as in Terminal.
US-030. As a power user, I want Zones to fail closed (no Snap) when it cannot tell which window I am dragging, rather than snapping a guess, so that it never moves the wrong window.
US-125. As a power user, I want a Shift-click on a title bar with no movement to show no Overlay, Snap nothing, and record nothing, so that clicks stay clicks.
US-126. As a power user, I want a Drag Session on a background window to work exactly like one on the focused window, so that I never have to click first.
US-127. As a power user, I want a right or middle button press during a Drag Session to be ignored, so that a stray button never cancels or commits a Snap.
US-128. As a VoiceOver user, I want Enhanced UI restored after every write even when the write fails, and restored on next launch for apps a Zones crash left changed, with that bookkeeping never delaying a Snap, so that Zones never degrades VoiceOver elsewhere.
US-146. As a power user, I want the Overlay to appear only after Zones has confirmed the window is actually moving, so that nothing ever flashes on a click.
US-147. As a power user, I want the window to land exactly on the rectangle the Overlay drew, to the pixel, on 1x and 2x Displays alike, so that what I see is what I get with no one-pixel seams.
US-160. As a power user who grabs a title bar and pauses before moving, I want the pause to cost nothing: the Drag Session waits until I move or let go, so that a slow start never silently disarms Shift for that drag.
US-163. As a power user, I want a hung app to cost Zones one timeout, not eight, so that my next drag on a healthy app is never delayed by the last one.

### Span
US-031. As a power user, I want to hold the Span Modifier during an armed Drag Session and sweep the cursor over several Zones to Snap into their union, so that I can make a window two-thirds wide without editing the Layout.
US-032. As a power user, I want the Span result to be the bounding rectangle of every accumulated Zone, including diagonal picks (Zones 1 and 4 in a 2x2 give the whole Display), so that the result is always a rectangle.
US-033. As a power user, I want to see the accumulating Span highlighted as one rectangle while I sweep, and the highlight to always be exactly what a drop would give me, so that the Overlay never lies.
US-034. As a power user, I want releasing the Span Modifier to freeze the accumulated Span and re-pressing it to keep adding to the same set, with releasing the Activation Modifier as the one way to start over, so that a key bounce never throws away a sweep and a drop never needs three fingers.
US-035. As a power user, I want a Span scoped to one Display and suspended, not cleared, while my cursor is on another Display, resuming when I come back, so that skimming a seam never throws away my sweep; a drop on the other Display uses the Zone under the cursor there.
US-036. As a power user, I want the Activation Modifier and Span Modifier to be forced to differ in Settings, so that I cannot create an unusable combination.
US-037. As a power user, I want Caps Lock, Fn, and numeric-keypad state to be ignored when checking modifiers, so that a Snap is never refused because Caps Lock is on.
US-129. As a power user who holds both modifiers before the drag starts, I want the Overlay armed and the Span begun from the first Zone my cursor enters, so that key order never matters.
US-130. As a power user, I want the Span rectangle to include the Gaps between its members and re-sweeping a member to never remove it, so that a two-Zone Span looks like one wide Zone and a shaky hand cannot shrink it.
US-155. As a 3-Display user, I want a suspended Span to stay drawn on its Display in a dimmer style while the live highlight follows my cursor elsewhere, so that I can see what returning will resume.

### Multi-Display
US-038. As a 3-Display user, I want each Display to have its own Layout Assignment, so that my ultrawide gets three columns and my portrait Display gets rows.
US-039. As a 3-Display user, I want the Overlay to appear on every Display during an armed Drag Session, with the highlight only on the Display under the cursor, so that I can see targets before I cross.
US-040. As a 3-Display user, I want the highlight to jump cleanly when my cursor crosses a Display boundary and the Snap to land in the Zone of the Display under the cursor at mouse-up, even while the window still straddles two Displays, so that cross-Display drags are one motion.
US-041. As a 3-Display user, I want a Snap across Displays to land at the Zone's point size because the size is written again after the position, so that a window from a Retina Display never arrives clamped to its old Display.
US-042. As a 3-Display user with a Display arranged above and to the left of the primary (negative coordinates), I want every Zone to land exactly where the Overlay drew it, so that arrangement never shifts my windows.
US-043. As a 3-Display user, I want Display identity to be stable across unplug and replug, so that my dock-station Display gets its Layout back without re-assigning.
US-044. As a 3-Display user, I want Zones to never move windows when a Display disappears, so that unplugging my laptop is not followed by a cascade of resizes.
US-045. As a 3-Display user, I want a Display I have never seen to get the Priority Grid Layout, so that a new Display is usable immediately.
US-046. As a 3-Display user, I want the Layout picker in Settings to show each Display's name and resolution next to its Assignment, so that I can tell them apart.
US-047. As a 3-Display user with "Displays have separate Spaces" off, I want a one-time Settings note warning that windows may straddle Displays, so that I understand why a Snap near a seam behaves oddly.
US-048. As a 3-Display user, I want a mirrored set of Displays to be treated as one Display keyed by the mirror master, with nothing persisted while mirroring, so that a presentation mirror never creates a phantom Assignment.
US-131. As a 3-Display user with two identical Displays, I want each to keep its own Assignment when the hardware gives distinct identifiers, so that same hardware is never conflated.
US-132. As a 3-Display user whose Display briefly reports no identifier during reconfiguration, I want Zones to retry on a short timer rather than persist a bogus Assignment, so that my Assignments stay clean.
US-133. As a 3-Display user who changes resolution or scaling, I want Zones recomputed from fractions and the Overlay resized before my next drag, and a change mid-drag to redraw the Overlay rather than cancel my drag, so that the Layout still tiles the Display exactly.
US-154. As a 3-Display user whose two cheap panels report no stable identifier, I want to pick a Layout for each for this session anyway, with the Layouts pane saying it will not be saved, so that unstable hardware never locks me to Priority Grid.
US-165. As a 3-Display user whose one odd Display never reports a UUID but has a unique hardware identity, I want its Assignment persisted under that identity and labelled as such, so that one quirky panel does not need re-assigning every morning.

### Restore
US-049. As a power user, I want Zones to remember a window's Original Frame the first time it snaps that window and never overwrite it on later Snaps, so that Restore returns to where I started, not to the last Zone.
US-050. As a power user, I want a Restore shortcut (default Control+Option+R) that puts the focused window back to its Original Frame, so that I can undo a Snap from the keyboard.
US-051. As a power user, I want an Activation-Modifier drag that ends outside the Display's usable area (menu bar, Dock strip) to Restore the window, so that "drag it out" is a mouse-only Restore.
US-052. As a power user, I want Restore to do nothing when a window was never snapped, so that the shortcut never teleports a window somewhere unexpected.
US-053. As a power user, I want the Original Frame to be forgotten when the window closes or when I Restore it, so that memory does not grow and the next Snap after a Restore starts a fresh round.
US-054. As a power user, I want Restore to work after a Span exactly as after a Snap, so that the two gestures share one memory.
US-134. As a power user whose Original Frame is now off every Display, I want Restore to clamp the frame onto the Display the window is on, so that a window never vanishes off every Display or jumps to another one.
US-135. As a power user who places windows by chord only, I want the first "send to Zone N" to capture the Original Frame, so that Restore works for keyboard-only placement.
US-164. As a power user holding a window over the menu bar, I want the Overlay's fills to dim only when a drop would actually Restore (an Original Frame exists), and otherwise to show no highlight and no dim, so that the cue never promises a Restore that will not happen.

### Shortcuts
US-055. As a power user, I want Control+Option+1 through 9 to send the focused window to Zone N on the Display it is on, so that a window is placed with one chord, no mouse.
US-056. As a power user, I want Zone Numbers to read row by row from the top-left and be printed on the Overlay, so that I never have to guess which Zone is 3.
US-057. As a power user, I want Zone Numbers to be recomputed after every edit so the Overlay labels and the shortcuts always agree, so that a stale number never sends a window to the wrong place.
US-058. As a power user, I want Control+Option+Right and Left to cycle the focused window through the Zones of its Display with wrap, starting from the Zone whose rectangle best matches where the window really is, so that a hand-moved window still cycles sensibly.
US-059. As a power user, I want cycling a window that is in no Zone to start at Zone 1 (Right) or the last Zone (Left), so that the first press is always defined.
US-060. As a power user, I want a "send to Zone N" where N exceeds the Zone count to do nothing, silently, so that a muscle-memory chord for a bigger Layout is harmless.
US-061. As a power user, I want every shortcut to include Command or Control and never be Option-only, so that they work on macOS 15 and do not shadow typing.
US-062. As a power user, I want a recorder that shows each shortcut as a chord, lets me press a new one, and refuses duplicates within Zones, so that two Zones actions never share a key.
US-063. As a power user, I want the recorder to warn (not block) when my chord matches one of a short, best-effort list of system chords shipped as data (Mission Control, Spaces arrows, screenshots; at most six, not maintained per macOS release), so that the common collisions are caught without anyone pretending the list is complete.
US-064. As a power user, I want a shortcut registration failure (chord taken by another app) to be shown inline in Settings, so that a dead chord is diagnosable.
US-065. As a power user, I want the editor and Settings shortcuts to need no permission at all, and the window shortcuts to need only Accessibility (never the mouse tap), with the General pane saying which is missing, so that the keyboard path degrades predictably.
US-066. As a power user, I want Control+Option+E to open the editor on the Display the cursor is on and Control+Option+Comma to open Settings, so that both surfaces are one chord away.
US-067. As a power user, I want shortcuts to act on the focused window of the frontmost app and do nothing when that window is excluded, full-screen, or unmovable, so that the keyboard path obeys the same rules as the mouse path.
US-136. As a power user, I want clearing a shortcut in the recorder to leave that action unbound rather than reverting to the default, so that I can free a chord I need elsewhere.
US-137. As a user whose Accessibility grant is missing, I want the editor and Settings shortcuts to keep working and the window shortcuts to be unregistered until the grant returns, so that I can reach Settings to fix the grant and no chord is swallowed from other apps for nothing.
US-148. As a power user who re-records a shortcut while a Drag Session is in progress, I want the change applied after the session ends, so that re-registration never races my drag.
US-158. As a power user cycling a Spanned window, I want Right to go to the Zone after the Span's highest member and Left to the Zone before its lowest, so that the first press after a Span is predictable.
US-161. As a power user who presses a window shortcut while a Drag Session is in progress, I want it ignored with one log line, so that Zones never writes a frame while macOS is moving the same window under my mouse.

### Layouts and Templates
US-068. As a power user, I want Templates for Columns and Rows (2 to 5), Grid (2x2, 3x3), Priority Grid, and Focus, so that the common cases take zero editing.
US-069. As a power user, I want Priority Grid to be the default for any unassigned Display, so that first launch matches what I had on Windows.
US-070. As a power user, I want to duplicate a Template into a custom Layout and tweak it, so that I start from something close rather than from blank.
US-071. As a power user, I want to rename Layouts and have names shown in the menu picker, so that "Code 3-col" is findable.
US-072. As a power user, I want every Layout to tile the Display with no gaps and no overlaps, and Margin and Gap to be applied afterward, so that there are never dead spots or double-covered areas.
US-073. As a power user, I want Margin and Gap in points, applied per Layout, so that 8-point gaps look the same on every Display.
US-074. As a power user, I want a Layout defined in Display fractions so that the same Layout fits a 4K and a 1080p Display, so that I design once.
US-075. As a power user, I want to delete a Layout that is assigned only after picking a replacement for those Displays, so that I am never left with a dangling Assignment.
US-138. As a 3-Display user on the road, I want to edit the Layout assigned to my disconnected desk Display at its last known size and scale, which Zones stored when it was last attached, so that I can prepare Layouts before I dock.
US-157. As a power user, I want Appearance to hold the default Margin and Gap used by Templates and new custom Layouts, with a custom Layout's own values overriding them in the editor, so that one slider sets my house style and one Layout can still differ.
US-159. As a power user, I want Focus to be exactly one Zone, Zone Number 1, with a drop anywhere on that Display landing in it, so that "Focus" means one place and one chord.

### Editor
US-076. As a power user, I want the editor to open on the Display being edited and draw its Zones at real scale over that Display, so that what I see is what the Overlay will show.
US-077. As a power user, I want to click a Zone and split it horizontally or vertically with a single key, so that a 3-column Layout takes three keystrokes.
US-078. As a power user, I want to drag a divider between Zones and have it snap to halves, thirds, quarters, and to other dividers, with a modifier to drag freely, so that alignment is instant.
US-079. As a power user, I want arrow keys to nudge the selected divider by one point (ten with a modifier), so that I can get exact results without a numeric field.
US-080. As a power user, I want to merge two sibling Zones back into one, so that I can undo a split without starting over.
US-081. As a power user, I want the editor to tell me why a merge is not possible and hint at the split order that produces the shape I want, rather than silently ignore my click, so that I learn the rules fast.
US-082. As a power user, I want unlimited undo and redo in the editor, so that experiments are free.
US-083. As a power user, I want to set Margin and Gap with sliders and see the result live on the Display, so that spacing is tuned by eye.
US-084. As a power user, I want Zone Numbers drawn in the editor as they will appear on the Overlay, updating as I split and merge, so that I can plan shortcuts while designing.
US-085. As a power user, I want to switch the Display being edited from inside the editor, so that I can fix all three Layouts without reopening it.
US-086. As a power user, I want the editor to assign the Layout I am editing to the current Display in one click, so that the edit-assign loop is tight.
US-087. As a power user, I want the editor to refuse ratios that leave a Zone under a minimum fraction of the Display on either axis and to warn when the resolved Zone on the current Display is under a usable point size, so that slivers are impossible and tiny Zones are visible before I save.
US-088. As a power user, I want to save with a shortcut and close with another, so that the editor never needs the mouse.
US-139. As a power user, I want Cancel in the editor to discard the draft and Save to be the only moment the live Layout changes, so that experiments can never leak into a drag.
US-162. As a power user, I want to merge two adjacent Zones that sit in the same row or column chain (columns 1 and 2 of Columns 3) even though they are not tree siblings, so that the most common merge is one gesture, not a rebuild.
US-166. As a power user building a 4x3, I want Zones beyond nine badged "no chord" in the editor and never refused, so that I know which Zones are mouse-only before I save.

### Appearance
US-089. As a power user, I want to pick the Zone fill color and opacity and see a live sample, so that the Overlay is visible on both light and dark wallpapers.
US-090. As a power user, I want the highlight to differ from idle Zones clearly even at low opacity, so that I can see the target on a bright Display.
US-091. As a power user, I want the Overlay to honor Reduce Motion and Reduce Transparency, so that my accessibility settings are respected.
US-092. As a power user, I want the Overlay to never draw Zones over the menu bar or Dock strip even though it covers the Display, so that Zones match where windows can actually go.
US-167. As a power user, I want Zone Number labels drawn with a contrasting outline independent of the fill opacity, so that the shortcut legend stays legible at any Appearance setting.

### Exclusions
US-093. As a power user, I want to exclude an app by picking it from a list of running apps or from a file picker, so that my floating note app never snaps.
US-094. As a power user, I want excluded apps to show no Overlay and ignore shortcuts, so that the exclusion is total and consistent.
US-095. As a power user, I want sheets, popovers, system dialogs, palettes, and Zones' own windows to be skipped automatically, so that a Save dialog never gets snapped.
US-096. As a power user, I want the Exclusions pane to show the bundle identifier next to each app name, so that I can tell two apps with the same name apart.

### Import, export, persistence
US-097. As a power user, I want to export all Layouts and Assignments, or one Layout, to a JSON file of one shape, so that I can keep them in my dotfiles.
US-098. As a power user, I want to import a JSON file and choose Merge (keep mine, rename theirs) or Replace (exactly the file), so that I can both combine and restore a backup.
US-099. As a power user, I want the export to carry a version field and the import to reject newer versions with a clear message, so that cross-version files fail loudly.
US-100. As a power user, I want Assignments exported with Display identifiers, and imported Assignments for Displays I do not have to stay dormant until that Display appears, so that moving between two desks is painless.
US-101. As a power user, I want a malformed JSON file on disk to be moved aside, not silently discarded, with a notice in Settings, so that I can recover my Layouts.
US-102. As a power user, I want an edit saved on one Display's Layout to be on disk before the editor closes, so that a crash never loses it.
US-140. As a power user, I want import to validate every Layout (ratios inside 0..1, tiling, minimum fraction), name the first offending Layout, and change nothing if any part fails, so that a bad file cannot corrupt my Layouts.
US-141. As a power user upgrading or downgrading, I want older documents migrated with a backup written first and newer documents left untouched and reported with both versions named, so that no version change loses Layouts.
US-142. As a power user, I want every data file write to be atomic, so that a crash mid-write never leaves a half file.
US-143. As a power user, I want preferences to carry a schema version, so that an upgrade never silently resets my modifiers or shortcuts.
US-151. As a power user whose hand-edited preferences hold one bad value, I want only that field coerced to its default with a one-time notice, so that one typo never wipes my shortcuts and exclusions.

### Awkward cases the persona insists on
US-103. As a power user, I want a drop on a Gap or Margin to Snap into the nearest Zone, not Restore, so that an 8-point miss never teleports my window across the Display.
US-104. As a power user, I want to Shift-drag a window from the Dock's edge of Display 1 straight onto Display 2 and have the Overlay already visible on Display 2 where macOS allows the drop, so that I do not stall at the seam.
US-105. As a power user, I want a title-bar drag begun with Shift already down to arm once the frame moves, and Zones to never consume the modifier, so that an app's own Shift semantics (Finder multi-select, constrained drags) still apply and a content drag never shows the Overlay.
US-106. As a power user, I want a Drag Session that began on a window that then disappears (app quit) to end quietly, so that nothing crashes or leaves a stuck Overlay.
US-107. As a power user, I want the Overlay to vanish on mouse-up before Zones talks to the app, so that a slow app never keeps a stale Overlay on screen.
US-108. As a power user, I want a second mouse-down during a Drag Session (trackpad glitch) to not start a second session, so that state never doubles.
US-109. As a power user, I want Zones to re-enable its event tap automatically when the system disables it under load and tell me if it cannot, so that drags do not silently stop working.
US-110. As a power user, I want to see in Settings whether the event tap is alive and whether Accessibility is granted, so that I can diagnose a dead drag in seconds.
US-111. As a power user with several same-size windows of one app stacked, I want the one I grabbed to be the one that moves, resolved by which candidate actually moved on the first frame sample, so that z-order ambiguity is settled by what I did and never by a guess; four identical terminals must work, not two.
US-112. As a power user, I want a Snap to be idempotent: snapping an already-snapped window to the same Zone changes nothing and does not overwrite its Original Frame, so that repeated chords are safe.

### Discoverability and performance
US-113. As a new power user, I want the onboarding window to end with a one-page cheat sheet (hold Shift, add Control to Span, Control+Option+N), so that I can use Zones before opening Settings.
US-114. Removed in round 2 (first-use hint on the Overlay); see Out of Scope and the Response log. Id retired, never reused.
US-115. As a power user, I want Zones' own work between mouse-up and the first write to the app to be negligible (budget in Implementation Decisions) so that on a responsive app the window is in place as the button comes up; per-app wall time is recorded on the manual matrix.
US-116. As a power user, I want Zones to be invisible in Activity Monitor while I am not dragging, with the exact idle timers enumerated in Implementation Decisions (one 5 s health tick while granted, nothing else), so that it never costs battery for nothing.
US-117. As a power user, I want Zones to poll only the dragged window during a Drag Session and never poll windows while idle, so that battery life on my laptop is untouched.
US-118. As a power user, I want the Settings window and editor to open on the Display my cursor is on, so that I am never hunting for a window on another Display.
US-119. As a power user, I want changing a modifier or shortcut in Settings to take effect immediately without a relaunch, so that tuning is a tight loop.
US-120. As a power user, I want the menu-bar icon to be a template image that follows light and dark menu bars and to reflect state at a glance (plain when healthy, badged when permission or the event tap is lost), so that I never discover a problem by a failed drag.
US-144. As a power user filing a bug, I want a "Copy Diagnostics" button that shows the report before copying (version, build, signing identity, macOS, permission and tap state, Displays with identifiers and frames, Assignments, preferences, last 200 events, bundle identifiers grouped) with no window titles or document names, so that one paste is a complete report and I see what I share.
US-145. As a power user wondering why a window was ignored, I want every skipped window logged with its reason (exclusion, own window, sheet, full-screen, unmovable, unresponsive, ambiguous), so that "it did nothing" is diagnosable.

## Implementation Decisions

Modules follow ADR-0002: ZonesCore (types, persistence, preferences, diagnostics, Clock), ZonesLayout (split tree, templates, numbering, hit-testing, span math, grid rounding, editor command list), ZonesWindowing (window service, exclusion policy, event tap, hotkeys, topology, permission, behind protocols), and the app target (menu bar shell, Overlay panels, Settings, editor views, onboarding; wiring only).

### Layout model (ZonesLayout, per ADR-0003/0004)
- `Layout { id: LayoutID, name, root: SplitNode, margin: Points?, gap: Points?, origin: template(name, count) | custom }`. `SplitNode = leaf | split(axis: horizontal|vertical, ratio: 0<r<1, first, second)`. Nil `margin`/`gap` means "use the Appearance defaults"; Templates always do, custom Layouts may override.
- Built-in Layouts (every Template at every supported count) are generated at load with deterministic `LayoutID`s derived from Template name and count, are read-only, never written to layouts.json, and may be referenced from assignments.json. Duplicate creates a custom Layout with a fresh id named "<Template> copy".
- `resolve(layout, visibleFrame, margin, gap) -> [ZoneRect]` in exact CGFloat points: walk the tree into normalized 0..1 rectangles, scale to the visible frame, shrink by Margin at outer edges and half a Gap at internal edges. No rounding here; the tiling property test runs on this output.
- `grid(rects, scale) -> [ZoneRect]` is the single rounding step: every distinct edge coordinate is snapped once to the backing grid (1 divided by scale) so neighbours keep sharing the edge; no remainder, no order dependence. Both the Overlay model and the Snap target are produced from the same `grid` output, which is US-147.
- Zone Number: sort resolved Zones by top edge then left edge with an epsilon so sub-pixel differences never reorder visually aligned Zones. Numbers are never stored.
- Editor operations are pure functions on the tree: `split(leaf, axis, ratio)`, `setRatio(node, ratio)`, `merge(leafA, leafB)`. `merge` succeeds for siblings (ADR-0003) and for two adjacent leaves within one same-axis chain of splits: the chain is re-chained deterministically so the pair become siblings, then collapsed; the leaf set is otherwise unchanged and the result is a golden table row per Template (US-162). Any other pair returns `notMergeable` with the hint "split the parent the other way first". General re-treeing is a spike (Challenges C3). Every leaf keeps at least 1/12 of the Layout on each axis; violating operations return `tooSmall`. The editor additionally warns when a resolved Zone on the current Display is under 120x80 points after Margin and Gap, and badges Zones beyond nine with "no chord" (US-166).
- Templates generate trees: Columns and Rows as a right-leaning chain where the k-th of n-1 splits uses ratio 1/(n-k+1) so every Zone is equal; Grid as rows of columns; Priority Grid as a vertical split 25/50/25. Focus awaits the decision ticket in C4; this draft's recommendation is one leaf plus a Layout-level normalized surround fraction (0.2 per side) applied before Margin, so Focus is one Zone numbered 1 and the tree still tiles the Layout rectangle. Fallback if the amendment is refused: 20/60/20 columns.

### Hit-testing and Span (ZonesLayout facts, reducer policy)
- `hitTest(point, gridRects, visibleFrame) -> ZoneHit`, `ZoneHit = zone(n) | nearest(n) | none`. Inside a Zone is `zone`; inside the visible frame on a Gap or Margin is `nearest` (minimum edge distance, ties by lower Zone Number); outside the visible frame (menu bar, Dock strip, notch strip) is `none`. The hit tester states facts; the Drag Session reducer decides that `zone` and `nearest` Snap and `none` Restores (ADR-0009, C2). Hit testing always uses the Display under the cursor, never the Display the window overlaps most.
- `SpanState { displayKey, zones: Set<ZoneNumber>, frozen: Bool, suspended: Bool }`; `spanRect(set) = bounding rectangle of its members`, Gaps between members included (ADR-0008 union is rectangularized). Diagonal picks produce the enclosing rectangle by design.
- Single Span rule: while the Span Modifier is down every `zone` hit on `displayKey` is added and a member is never removed; releasing it freezes the set; re-pressing resumes adding to the same set; the cursor leaving `displayKey` suspends the set (nothing accumulates, the live highlight follows the cursor on the other Display, a drop there uses that Zone); returning resumes; releasing the Activation Modifier clears everything. Highlight = `spanRect` when the set is non-empty and the cursor is on `displayKey`, else the Zone under the cursor; a suspended set is drawn in the secondary style on its Display. On a `none` hit the highlight is empty and the fills dim only when the dragged window has an Original Frame (US-164). Invariant: the highlighted set equals what a mouse-up would snap to, and the dim cue appears only when a mouse-up would Restore.

### Display geometry (ZonesLayout + ZonesWindowing)
- `DisplayKey = uuid(String) | hardware(String) | unstable(String)`: the CGDisplay UUID when present. Nil UUID: retry three times one second apart on the Clock; then the vendor-model-serial key is used and persisted as `hardware` only when unique among attached Displays (US-165), else `unstable`. An `unstable` key accepts an in-session Assignment held in memory, is never persisted, and is labelled in the Layouts pane (US-154).
- `DisplaySnapshot { key, frame, visibleFrame, scale, isMain, mirrorOf?, separateSpaces }`. `TopologyService` observes both AppKit and CoreGraphics callbacks, debounces (named Clock-driven constant), and emits `topologyChanged(before, after)`; consumers never cache frames between events. Mirror sets collapse to the mirror master (the member that mirrors nothing); no Assignment is persisted while mirroring.
- One conversion function AppKit <-> AX/CG coordinates, flipping around the primary Display's top; `displayFor(frame)` by maximum intersection area is used by the keyboard path (no cursor) and by Restore clamping. Tested with negative-origin arrangements and mixed scales.
- `assignments.json` stores one map, per DisplayKey, of the Layout id plus presentation data: name, resolution, `lastFrame`, `lastVisibleFrame`, `lastScale`; dormancy is derived at read time (key absent from the current snapshot). These back US-138 and the disconnected-Display rows in the Layouts pane.
- ADR-0013 contingency: if the Space spike passes, the record gains an optional Space token and the document bumps to version 2 with a migration that leaves the token absent; lookups already take a record, so nothing else changes shape.

### Exclusion policy (ZonesWindowing, pure)
- `ExclusionPolicy -> allow | skip(reason)`, `reason = userExclusion(bundleID) | ownWindow | systemBundle | unresponsive | ambiguousMatch | nonStandardSubrole | sheetOrPopover | fullScreen | positionNotSettable`. Two phases. Phase 1 at mouse-down from CG facts only (pid, layer, bundle identifier, candidate count, `AppHealth`): no AX call is made for a bare click. Phase 2 on the first frame sample from AX facts (role, subrole, full-screen, settable flags), which already costs one AX read. Size-not-settable is not a skip; it yields a position-only plan. Both phases run before any Overlay effect, on the mouse and the keyboard path; every skip is logged and counted (US-145); one table test per reason per phase.

### Drag Session state machine (ZonesWindowing reducer, effects as values)
States: `idle -> pressed(candidates, frame0) -> moving(window) <-> armed(window, hit, span) -> idle`. Events: mouseDown, frameSample, dragged, flagsChanged, mouseUp, windowGone, tapLost, appUnresponsive, topologyChanged, wake, hotkey. Effects: `showOverlay(model)`, `updateHighlight(set | dimAll | clear)`, `hideOverlay`, `snap(plan)`, `restore(handle)`, `log`.
- `pressed`: on mouse-down resolve the candidate set from the event's window number, else a front-to-back CGWindowList hit test, else the element at position; map to AX elements by pid + frame within 1 point. Phase-1 policy drops excluded, own, system and unresponsive candidates (fail closed when none remain). The held set is capped at four by z-order (US-111); more than four is `ambiguousMatch` before any sampling. Frame samples read all held candidates in one batched actor call per tick. One candidate becomes `moving` on the first sample whose origin changed with size unchanged and phase 2 passes; several candidates are held and the one whose frame changed wins; a sample where none moved keeps `pressed` until mouse-up (US-160); two or more moved after three returned samples, a phase-2 failure on the mover, or a first `timedOut` sample, ends in `idle` with a logged reason and polling stopped. Any size change beyond tolerance (from any edge or corner) is a resize and ends in `idle`. Mouse-up records nothing.
- `moving`: modifier state latched from flagsChanged and each event's flags, masked to Shift, Control, Option, Command; the check is containment. Activation Modifier down enters `armed`; the Overlay is shown only on that transition (US-146).
- `armed`: Overlay on every Display, highlight per the Span rule, target recomputed on every dragged event from `hitTest` on the Display under the cursor. Both modifiers held before `moving` arm at once and start the Span from the first Zone entered. Right and middle buttons are filtered at the input source and never reach the reducer; a mouse-down outside `idle` is ignored. A `hotkey(windowCommand)` in any state but `idle` is dropped with one log line (US-161); editor and Settings hotkeys always run. Activation Modifier release returns to `moving`, hides the Overlay and clears the Span.
- `topologyChanged` while `armed` re-arms from the new snapshot (new Overlay model, new hit) so Overlay and Snap always share one geometry; the drop never re-reads `visibleFrame` on its own. `windowGone`, `tapLost`, `appUnresponsive` and `wake` in any state go to `idle` and hide the Overlay.
- Mouse-up in `armed`: `hideOverlay` is emitted first, in the same reducer step, then `snap(plan)` for a non-empty Span on the cursor's Display or a `zone`/`nearest` hit, or `restore` for `none` when an Original Frame exists (else nothing). Mouse-up in `moving` or `pressed` does nothing. Cancel is modifier release only; there is no Escape path because key events are not tapped (ADR-0020).

### Window service (ZonesWindowing, per ADR-0015/0018/0022)
- `WindowActor` serializes all AX traffic with a 250 ms per-app messaging timeout and a 1 s process-wide one. Protocol: `frame(of:)`, `frames(of:)` (batched), `setFrame(_, to:) -> WriteResult`, `isMovable`, `isResizable`, `isFullScreen`, `roleAndSubrole`, `observe(destroyed)`, `heartbeat()`. AX observers live on one dedicated thread with a running CFRunLoop and forward value-type notifications to the actor; the actor never owns a run loop source.
- `WriteResult = applied(actual) | clamped(actual) | refused(code) | timedOut | elementGone`. The write protocol is up to eight round trips: read Enhanced UI (skip the pair when absent or already off), set off, size, position, size, read position, read size, restore in a defer. The first `timedOut` aborts the sequence: no further calls except the Enhanced UI restore, the pid is marked unresponsive at once, and the result is `timedOut` (US-163); worst case on a hung app is 0.5 s on the WindowActor, never on the main thread. On `clamped` where the accepted size exceeds the Zone, exactly one follow-up position write aligns the top-left inside the visible frame; never loop. A target equal to the current frame within tolerance is a no-op that records nothing (US-112).
- Governed by `EnhancedUIPolicy = toggle | leave | auto` (default `toggle`, ADR-0022; `auto` toggles only when the attribute reads on, no bundle lists). Size-not-settable yields a position-only plan aligned to the Zone's top-left (C1); position-not-settable is a skip.
- `AppHealth` per pid: `timedOut` -> `unresponsive(until)` for a named Clock-driven cooldown during which that app's windows are `skip(unresponsive)`; one retry after the cooldown. Heartbeat results feed only the permission machine, never `AppHealth`. Frame polling at about 60 Hz keeps one in-flight sample; a tick while one is outstanding is dropped.
- Enhanced UI safety: pids whose Enhanced UI Zones turned off are kept in memory and drained by the defer, on Quit and on entering `revoked`. A small recovery record (pid, bundle identifier, process launch date) is written only on the transition of that set from empty to non-empty, as the tail of the same actor task after the frame write completes, never between mouse-up and the first AX write; it is removed on clean quit; on launch only entries whose process still matches all three fields are restored (US-128).

### Window registry (ZonesCore types, ZonesWindowing owner)
- `WindowHandle` is an opaque Hashable, Sendable value in ZonesCore; only the Windowing adapter knows it wraps an AX element and compares with CFEqual. It is the one documented unchecked-Sendable box.
- `OriginalFrameRegistry: [WindowHandle: Rect]`, in memory only. Written only when absent, on `applied` or `clamped`, by both the mouse and keyboard paths. Removed on a successful Restore, on `destroyed`, on `elementGone` at next touch, and on the app-terminated notification for that pid. No periodic sweep, no stored placement. The reducer receives `hasOriginalFrame` for the dragged window at arm (US-164).
- Cycle: read the frame back; the current Zone is the one with the largest intersection area, ties by lowest Zone Number; when several Zones tie within epsilon (the window covers them, a Span or a hand-made equivalent), Right goes after the highest tied Zone and Left before the lowest (US-158); no intersection means Right starts at 1 and Left at the last Zone. Restore writes the Original Frame through the same write protocol; a frame outside every Display is clamped into the visible frame of the Display the window currently occupies (US-134).

### Input (ZonesWindowing, per ADR-0006/0011)
- One listen-only session tap for left mouse down/dragged/up and flagsChanged on a dedicated thread; other buttons are filtered at the source; `dragged` is coalesced to the newest sample, down, up and flagsChanged are never dropped; snapshots hop to the main actor as values. One 5 s health tick while granted checks `CGEventTapIsEnabled` (and carries the spike-gated heartbeat); re-enable is rate-limited to about five per minute with backoff; beyond that `tapState = dead`, shown in General and as the badge, with an automatic retry every 30 s. A nil tap means no permission. Acceptance criterion on the InputSource ticket: the production tap is created listen-only (US-105).
- Hotkeys are Carbon-registered; `ShortcutStore` enforces uniqueness within Zones, requires Command or Control in every chord, warns from a data fixture of at most six system chords (best effort, not maintained per OS release, US-063), and surfaces registration failure per row leaving the previous chord active. On a preference change only chords whose value changed are re-registered; a change during a Drag Session is queued until `idle`; a cleared chord stays unbound. Editor and Settings hotkeys are registered in every `PermissionState`; window hotkeys are registered only in `granted` and unregistered on leaving it (US-137), so no chord is swallowed for nothing.

### Overlay (app, per ADR-0023)
- One reusable panel per Display at screenSaver level, click-through, never key, created at launch and rebuilt only on `topologyChanged`. Zone layers and label layers persist; an arm sets frames, colors and label text from the cached `grid` output inside one CATransaction with actions disabled, so arming allocates nothing after warm-up; layers are rebuilt only on `topologyChanged`, an Assignment change or an Appearance change. Three highlight states: active, suspended-Span (dimmer; an outline under Reduce Transparency), and dim-all for a `none` hit with an Original Frame. Reduce Transparency uses solid fills; Reduce Motion disables fades. Labels show Zone Numbers with a contrasting outline independent of fill opacity and the correct `contentsScale` per Display (US-167). Panels and layers are hidden from VoiceOver.

### Persistence (ZonesCore, per ADR-0017)
- One document shape for disk and export: `{ version, layouts?: [Layout], assignments?: [DisplayKey: AssignmentRecord] }`, both arrays optional and validated as a whole; "export one Layout" is this document with one Layout. Import offers Merge (keep mine, rename incoming collisions with a numeric suffix, fresh ids for colliding ids) or Replace (timestamped backup of both documents written and named first, then both swapped in one transaction). Assignments for unknown Displays are kept in the same map and apply when the Display appears. Import runs the editor's validator and changes nothing on disk if any Layout fails, naming the first offender.
- Writes are synchronous and atomic (temp file, then rename) on Save, Assignment change and import; nothing is pending at quit; no debounce. Decoding dispatches on `version`: older runs an ordered migration chain after a timestamped backup; newer is left untouched and reported with both versions named; a file that fails to decode is renamed aside with a timestamp and defaults load with a one-line notice in Settings.
- Preferences in UserDefaults under one namespace with a `schemaVersion`, decoded field by field with per-field defaults: modifiers, shortcuts, appearance (color, opacity, default Margin and Gap), exclusions (bundle identifiers), `enhancedUIPolicy`, one-time-notice flags. Launch-at-login is read live from the system and never stored.

### Settings, menu and editor (app)
- Settings panes: General (permission and tap status rows, launch at login, modifiers as key caps, Reset and re-onboard), Layouts (attached Displays with name, resolution, Assignment picker, open editor; disconnected Displays with their Assignments and Copy Assignment to / Forget; `hardware` and `unstable` keys labelled), Shortcuts (recorder table), Appearance (color, opacity, default Margin and Gap with a live preview saying which Layouts use them), Exclusions (running-apps picker plus file picker, bundle identifiers shown), About (version, build, signing identity, license, the inspired-by line, Copy Diagnostics with preview).
- Menu, built on open from cached state only (never waits on the WindowActor): Display name and active Layout for the Display under the cursor (ADR-0019); Layout picker (Templates with Zone counts, then custom Layouts, active one checked); a checkable Exclude <App> for the app frontmost when the menu opened, checked when excluded (US-149); Edit Layouts; Settings; Grant Accessibility (only when not granted); Quit. Picking a Layout writes the Assignment immediately and rebuilds that Display's Overlay layers.
- Editor: ZonesLayout owns the draft Layout and a command list (split, merge, setRatio, setMargin, setGap, rename) with undo and redo as a stack; the validator runs after each command and a failing command leaves the draft unchanged with a reason. Selection, dirty flag and the Display being edited live in the app view model. Keys: H and V split the selection at one half; M merges with the sibling or same-chain neighbour chosen by the next click; arrows nudge a selected divider one point (ten with Shift); Command-Z and Shift-Command-Z; Command-S saves; Escape clears selection; Command-W prompts when dirty; Assign (US-086) has its own shortcut. Divider drag snaps to halves, thirds, quarters of the parent and to collinear dividers within 6 points; Option disables snapping; ratios are stored as fractions. The editor is a full-Display window on the Display being edited with a Display switcher (prompting when dirty); a disconnected Display is edited at its stored `lastVisibleFrame` and `lastScale` in a window on the current Display. Save validates, writes, then replaces the live Layout; Cancel discards; nothing reaches a Drag Session before Save. Deleting an assigned Layout requires choosing a replacement.

### Performance targets and idle budget (app + ZonesWindowing)
- Idle timers, exhaustively: trust poll at 1 s only in `notGranted` and `revoked`; one health tick at 5 s while granted (tap enabled check plus the heartbeat, gated on the spike and removed if it fails); nothing else. No AX reads while idle except the heartbeat; no window polling while idle.
- Drag Session: one CGWindowList lookup for the dragged window per dragged event (no full enumeration), one `hitTest`, one highlight update. Full enumeration happens once at mouse-down.
- Targets (manual Instruments checklist, not CI): Overlay visible on the next display refresh after arm; highlight update per dragged event under one frame at 120 Hz; under one percent CPU idle; Zones' own work from mouse-up to the first AX write under 2 ms on the reducer side.

### Permission and shell state machine (app, per ADR-0019/0020/0021)
- `PermissionState = unknown | notGranted | granted | suspect | revoked | needsRelaunch`. Launch: read trust without prompting; `granted` starts the tap, registers window hotkeys and starts the health tick; `notGranted` shows onboarding (at login: badge and a Grant Accessibility menu item only) and polls trust once per second. The poll is never used to detect revocation. A nil tap, a tap that cannot be re-enabled, or an API-disabled error from any AX call or the heartbeat moves to `suspect`; `suspect` returns to `granted` when the tap is recreated and a trivial AX read succeeds, else after a 3 s Clock window becomes `revoked` (badge, onboarding with Open System Settings, Drag Session and window shortcuts off and unregistered, editor and Settings shortcuts on, no relaunch button, trust poll at 1 s, tap recreation retried every 3 s). `revoked` becomes `needsRelaunch` only after three failed tap recreations over 10 s on the Clock with trust reading true; `needsRelaunch` shows one "Quit and Reopen" button (US-121). A successful recreation from either state returns to `granted`. Wake re-validates the tap, re-polls trust once, forces a topology snapshot and orders panels out.
- Launch sequence: AX timeouts; load documents (migrate with backup, quarantine corrupt, leave newer alone); Preferences field by field; repair Enhanced UI from the recovery record; register editor and Settings hotkeys; first topology snapshot and hidden panels; permission check (window hotkeys registered only when granted); status item last so the menu never shows before state exists. Launched-at-login is detected from the launched-as-login-item flag on the open-application event, read only inside the did-finish-launching callback; no window appears on that path in any state. Quit disables and invalidates the tap, orders panels out, drains the Enhanced UI set and removes the recovery record.

### Shortcut recorder (app)
- `RecorderState = idle | recording | conflict(reason) | warning(reason) | failed(reason)`. Chords without Command or Control are `conflict(needsModifier)`; chords bound in Zones are `conflict(duplicate(action))`; the fixture warning list yields `warning` that can be accepted. Registration happens on commit; a Carbon failure shows `failed(inUse)` inline and leaves the previous chord active.
- `Shortcut { key: KeyCode, modifiers: Set<Modifier> }`; `ShortcutAction = sendToZone(1...9) | cycleNext | cyclePrevious | restore | openEditor | openSettings`. Every action is optional (unbound allowed); defaults per ADR-0010.

### Diagnostics (ZonesCore + app)
- One logger facade with a per-module category; the production sink is the unified log, the test sink an array. A bounded ring of the last 200 events (permission and tap transitions, Snap results with pid, bundle identifier, Zone and write result, every skip reason with counts, topology events) feeds Copy Diagnostics with version, build, signing identity, macOS, Displays, Assignments and preferences, shown in a window before copying with bundle identifiers grouped. Window titles are never read anywhere. A `Clock` protocol drives every cooldown and debounce.

## Testing Decisions

A good test here is deterministic, runs headless on the build machine, and encodes an invariant a power user would notice when broken: the Overlay and the Snap disagree, a number changes under them, a window lands off-Display, a sweep is lost at a seam, a chord goes dead.

Property tests (ZonesTestSupport seeded generator, ADR-0016, failing seed and Layout printed):
- Split tree: for random trees, unrounded `resolve` output tiles the frame with no gaps and no overlaps at Margin and Gap 0; with Margin and Gap, every pair is separated by exactly Gap and the outer edge by exactly Margin when both lie on the grid, within half a backing pixel otherwise; after `grid`, every edge lies on the backing grid for scales 1, 2 and 3 and neighbours still share edges.
- Split then merge of the new siblings yields the original tree; same-chain merge yields a tree whose leaf set is the union and whose other leaves are unchanged; `setRatio` keeps the leaf count; random edit sequences never produce an invalid tree; every Template at every supported count tiles, has the expected Zone count, and Columns and Rows Zones are equal within epsilon.
- Zone numbering is a bijection onto 1..N, row-major, invariant under frame scaling, Margin and Gap changes, and sub-epsilon edge differences.
- Hit-test: every point in the visible frame maps to exactly one `zone` or `nearest`; every point outside maps to `none`; `nearest` is the Zone with minimum edge distance, ties by lower Zone Number.
- Span: the bounding rectangle contains every member and is the smallest such rectangle.
- Coordinate conversion round-trips on arrangements with Displays above and left of the primary, mixed scale factors, and a mirror set.
- Documents: JSON round-trip; Merge and Replace rules; version rejection; a Preferences blob with one unknown value loses only that value; golden fixtures per version each migrate to a document that validates; a fixture-hash test fails when a golden changes without a version bump; every Template name matches CONTEXT exactly; built-in Layout ids are stable across runs.
- Reducer invariants: the Overlay is shown only in `armed` and only on the transition into it; every path to `idle` hides it if shown; `hideOverlay` precedes `snap` and `restore` in the same step as mouse-up; Snap is emitted only with the Activation Modifier down at mouse-up; Restore is never emitted from `moving`; the highlighted set always equals the set a mouse-up would snap to; dim-all appears only when `hasOriginalFrame` and the hit is `none`; Span release then re-press preserves the set; leaving the Span's Display suspends and returning resumes; a mouse-down outside `idle` changes nothing; a window hotkey outside `idle` emits only `log`; no AX effect is emitted from `pressed` before the first frame sample.

Scenario tests with fakes (headless): the Drag Session reducer driven by scripted event streams and a fake window service covering arm-before-press, arm-after-move, modifier release cancel, Span accumulate, freeze, resume and suspend, Display crossing with a straddling window, resize from each edge (no session), window destroyed mid-session, second mouse-down, `nearest` drop, `none` drop with and without Original Frame (dim only with), pause then move still arms, two stacked candidates resolved by the first moved sample, four candidates sampled in one batched call, five candidates fail closed before sampling, two movers after three samples (fail closed), phase-2 failure on the mover ends the session, first sample `timedOut` (fail closed at once), window hotkey mid-session dropped, `topologyChanged` while armed re-arms; ExclusionPolicy table with one row per reason per phase; the registry's first-Snap-only rule and removal on Restore (Snap, Restore, hand-move, Snap, Restore returns the hand-placed frame) and on app termination; cycle from each placement including a Span (Right after the highest tied Zone), a clamped window and a hand-moved window; the topology debounce, nil-UUID Clock retry then `hardware` when unique else `unstable`, unstable never persisted but assignable in session, mirror master key; the shortcut store's uniqueness, chord and fixture-warning rules, registration diffing, deferral during a session, failure keeping the old chord, window hotkeys absent outside `granted`; the write protocol's `clamped` (one follow-up write), `refused`, `timedOut` (sequence aborted, call count asserted, cooldown set), `elementGone` (eviction), EUI pair skipped when absent, EUI restored on every path, recovery record written once per empty-to-non-empty transition and never before the frame write; heartbeat `timedOut` never touching `AppHealth`; permission `suspect` to `granted`, to `revoked` (no relaunch button, poll resumed), probe-stuck-true staying in `revoked` until three failed recreations over 10 s, then `needsRelaunch`; keyboard Snap capturing the Original Frame; Restore clamping onto the Display the window occupies; editor command stack undo and redo, rejected command leaves the draft unchanged, chain merge accepted and cross-chain merge refused with a hint, Save writes once, Cancel writes nothing, Assign writes the Assignment, delete of an assigned Layout requires a replacement.

Budget tests (headless, deterministic): `hitTest`, `spanRect`, `resolve` and `grid` allocate nothing after warm-up on a 9-Zone Layout; arming the Overlay model allocates nothing after warm-up; the Drag Session reducer processes 10,000 synthetic dragged events under a generous bound that catches only order-of-magnitude regressions. Absolute timings live on the manual checklist.

CI gates: logic suite green from one root command; app build green with strict concurrency and zero warnings; the fixture-hash and glossary tests above; a grep gate limited to `try!`, `as!` and `fatalError(` in the app target with a per-line allow marker.

Fakes contract: every fake in ZonesTestSupport is scriptable (a queue of responses per call, a recorded call log, latency driven by the fake Clock) and is the only kind of test double. Each production adapter also has a manual contract test that runs the same scripted scenario against the real OS when a human invokes it, so fake and production cannot drift silently.

Needs a human or a second machine: AX behavior against Chrome, Safari, Terminal, Finder, Calculator (position-only), VS Code, Slack, IntelliJ, a SIGSTOP'd app, with wall time per Snap; Overlay over a full-screen Space, Split View, a Space created after launch, Stage Manager, menu bar auto-hidden; 120 Hz highlight latency; TCC grant, revoke mid-session (badge within seconds while idle, what the probe reads afterwards), re-grant and relaunch on a clean user account; launch-at-login transitions and a DMG-mounted quarantined copy; stable signature across three rebuilds; a 3-Display drag across seams with mixed scale factors and a suspended Span; four identical Terminal windows stacked; two identical Displays of one model; Reduce Motion and Reduce Transparency rendering; label legibility at 10 percent fill opacity; the fixture warning list against the current macOS.

Per-module placement:
- ZonesLayout: all property tests above, template generation, grid rounding, editor command list including chain merge. No system dependencies, runs in `swift test`.
- ZonesCore: persistence round-trips, Merge and Replace, version rejection, corrupt-file quarantine, migrations, preferences coercion, built-in ids, diagnostics ring.
- ZonesWindowing: Drag Session reducer, ExclusionPolicy, registry, cycle rule, shortcut store, permission machine and topology against protocol fakes; a thin AX adapter covered only by the manual matrix and its contract test.
- App target: SwiftUI views are smoke-built by the CI `xcodebuild` step; no logic beyond wiring.

Fixtures worth keeping: a 3-Display arrangement with the primary in the middle, a 2x Display on the left and a 1x portrait Display above; a hung-app fake that times out every call; an app fake that clamps to a 400x300 minimum; a window fake whose size is not settable; four same-size windows of one pid; two identical Displays with serial 0; a six-chord warning fixture.

Acceptance walk-through for a human tester (one page, run per release): grant permission from a clean account; Shift-drag across all three Displays and drop on a Zone, on a Gap, and on the menu bar (once with and once without an Original Frame); grab a title bar, pause, then drag; Control-sweep a diagonal Span, release Control before the button, skim a seam and come back; send a window to each Zone by chord; press a chord mid-drag; cycle with wrap from a Span; Restore, hand-move, Snap, Restore; revoke permission mid-drag and while idle; unplug a Display mid-session; change resolution mid-drag; import a document from another Mac with Merge and with Replace.

## Out of Scope

- Tiling or evicting other windows; a Snap never moves an unrelated window.
- Re-snapping windows after Display topology changes.
- Per-Space Assignments unless the ADR-0013 spike passes.
- Shortcuts for "move to next Display", "swap windows between Zones", or per-app default Zones.
- Overlapping or non-rectangular Zones; FancyZones canvas-style free rectangles; general re-treeing merge in v1 (spike first; same-chain merge ships).
- Escape key to cancel an armed Drag Session (requires key tapping).
- Text or hints drawn on the Overlay beyond Zone Numbers (the former US-114 first-use hint).
- Special handling of Stage Manager beyond working on the current stage (manual checklist row).
- Window titles in matching or in the UI; Screen Recording and Input Monitoring permissions.
- Auto-update, cloud sync, iCloud, localization beyond English, App Store distribution, telemetry.
- Snapping during a resize gesture; snapping on window creation.
- Remembering which Zone a window was in across app relaunches; storing a window's "current Zone" at all.
- A complete or per-OS-maintained list of system shortcuts; the fixture is six chords, best effort.

## Further Notes

### Challenges to ADRs
- C1 (ADR-0018, automatic exclusions): the ADR skips windows whose "size or position is not settable". Research (ax-window-moves, implications 2 and 3) recommends still writing position when only size is locked. Proposed: skip only when position is not settable; when size is not settable, place without resizing, top-left aligned. All three drafts agree; the ADR text should drop "size".
- C2 (ADR-0009, Restore when a modifier drag "ends outside every zone"): with a Layout that tiles the Display, "outside every Zone" means the Gap, the Margin, or the strip outside the visible frame; a default Gap makes accidental Restore likely. Proposed wording: "ends outside the Display's visible frame"; Gap and Margin hits Snap to the nearest Zone (US-103). All three drafts agree; the policy sits in the reducer so a reversal is one line.
- C3 (ADR-0003, merge collapses a node): sibling-only merge cannot join two adjacent columns of Columns 3 in one gesture. Refinement adopted with the maintainer draft: two adjacent leaves within one same-axis chain are re-chained deterministically into siblings and then collapsed, which is still "collapse a node" and preserves every other leaf; a golden table per Template lists accepted and refused pairs. General re-treeing (a wide center from a Grid) remains a spike.
- C4 (ADR-0005 versus ADR-0003 and CONTEXT, Focus): "one center zone at 60 percent" cannot be a split tree whose every leaf is a Zone. Options: (a) 20/60/20 columns, Focus becomes three Zones and the named Zone is number 2; (b) a Layout-level normalized surround fraction applied before Margin, the tree tiles the Layout rectangle, Focus is one Zone numbered 1, drops in the surround go to the nearest Zone (one-line amendment to ADR-0003 and CONTEXT: "tiles the Layout rectangle"). This persona votes (b): a Template named for one Zone must be one Zone and one chord. A decision ticket picks before the Templates ticket. All three drafts now recommend (b).
- C5 (ADR-0009, Original Frame kept until the window closes): after a Restore the user positions by hand, Snaps again and Restores; they expect the hand-placed frame. Proposed and adopted here with the other drafts: a successful Restore removes the record; "first Snap captures" and "forget on close" stay.
- C6 (ADR-0021, poll AXIsProcessTrusted to detect revocation): research shows the probe does not reflect revocation of a running process. This draft keeps the poll for the first grant and in `revoked`, derives revocation from runtime signals plus a 5 s heartbeat (gated on a spike), confirms through `suspect`, and offers "Quit and Reopen" only in `needsRelaunch`, entered after three failed tap recreations over 10 s with the probe true. All three drafts agree on the signals; the platform draft folds the relaunch button into `revoked`, which this persona rejects (a button that sometimes does nothing).
- C7 (ADR-0008, Span accumulation is silent on release): decision proposed here and shared with the maintainer draft: release freezes, re-press resumes, Activation Modifier release clears; a Span is scoped to one Display and suspended, not cleared, when the cursor leaves it. The platform draft's FancyZones hysteresis rule (keep inside the union, replace outside) is rejected: the drop target would change with no key pressed, which US-033 forbids.

### Discoverability notes
- Zone Numbers on the Overlay are the only in-situ teaching surface; they double as the shortcut legend, so they carry a contrasting outline (US-167) and stay legible at any fill opacity.
- Settings General shows the two modifiers as key caps, mirroring the cheat sheet, so a user who changes them sees the new gesture spelled out.
- The menu-bar picker lists Templates with their Zone counts in the name (for example "Columns 3") so the chord range is obvious without opening the editor; the editor badges Zones beyond nine with "no chord".

### Open questions the spike tickets must answer
- Does the CGEvent window-number field reliably identify the dragged window on macOS 14 and 15, does `windowNumber` equal the CGWindowList id, and for four identical stacked windows does the first frame sample move exactly one AX candidate?
- Do AX moved notifications fire during a live drag on any common app, and at what cadence?
- Does the listen-only tap with mouse and flagsChanged events work with Accessibility alone on a clean VM for macOS 14, 15, and the current release, and what is its latency at 120 Hz?
- Does a trivial AX read return API-disabled promptly after revocation of a running process, making the 5 s heartbeat a valid signal (US-152), and what does the trust probe read afterwards?
- Does the Overlay panel appear on a Space created after launch, over a Split View Space and over a full-screen Space (US-022), and what does `visibleFrame` report with the menu bar auto-hidden?
- Does the "Zones Dev" self-signed identity keep the Accessibility grant across three rebuilds?
- Per-Space witness-window method (ADR-0013): does `isOnActiveSpace` on a hidden managed window identify the Space on each Display, and what happens when a Space is deleted?
- Highlight latency at 120 Hz: is a CALayer frame update per dragged event under one frame, or does the Overlay need a display link?
- Re-treeing (C3): what fraction of merge requests on Template-derived Layouts does the same-chain rule already accept, and is a general algorithm worth a later ticket?
- Do two identical Displays of one model report distinct UUIDs on the current release, and what does the hardware fallback look like when serials are zero?
- Carbon hotkey registration failure modes: which `inUse` cases are reported synchronously, and which system chords register successfully yet never fire? The six-chord fixture is seeded from the answer.
- On which thread do AXObserver callbacks arrive when the run loop source lives on a dedicated thread, and do they survive that thread idling between drags?

### Response log
Round 1 (18 platform, 16 maintainer critiques): all accepted except maintainer 3 (rounding placement, accepted in part: one shared `grid` step) and maintainer 10 (US-105 kept as a user-observable story plus the listen-only acceptance criterion); details in the round-2 revision of this file.

Round 2, from platform (round2-platform.md, attacks 1-16 on power-user):
1. ACCEPTED in part: the recovery record is written once per empty-to-non-empty transition, after the frame write, keyed by pid, bundle identifier and launch date (US-128, Window service). REBUTTED dropping the record to a v2 note: a VoiceOver user whose Chrome is left with Enhanced UI off after a Zones crash has no way to know why.
2. ACCEPTED (already applied in the round-2 revision): US-017 reads "the later of (modifier down, move confirmed)".
3. ACCEPTED (already applied): Span suspended on another Display (US-035, US-155).
4. ACCEPTED (already applied): opaque `WindowHandle` in ZonesCore, CFEqual in the adapter.
5. ACCEPTED (already applied, different mechanism): no observer, no stored placement; cycle base is maximum intersection with a tie rule that covers Spans (US-158).
6. ACCEPTED: US-104 says "where macOS allows the drop"; US-022 was already gated on the overlay spike.
7. ACCEPTED (already applied): one `grid` step on the backing grid shared by Overlay and Snap (US-147).
8. ACCEPTED (already applied): US-061 says Command or Control.
9. ACCEPTED (already applied): any size change ends the session (US-027).
10. ACCEPTED (already applied): idle timers enumerated; badge timing gated on the heartbeat spike (US-116, US-152).
11. ACCEPTED: panels and layers persist; arm sets frames, colors and labels in one CATransaction; rebuild only on topology, Assignment or Appearance change (Overlay section, budget test).
12. ACCEPTED (already applied): Preferences decoded field by field.
13. ACCEPTED: re-enable rate limit about five per minute with backoff, then `dead` with badge and a 30 s automatic retry; the 2 s watchdog is folded into the single 5 s health tick (Input, idle budget).
14. ACCEPTED: two-phase ExclusionPolicy; no AX call for a bare click (Exclusion policy section, reducer, invariant).
15. ACCEPTED: window hotkeys fired outside `idle` are dropped with one log line (US-161, reducer).
16. ACCEPTED: "Display under the cursor" per ADR-0019 (US-009, menu).

Round 2, from maintainer (round2-maintainer.md, attacks 1-17 on power-user):
1. ACCEPTED (already applied): inert leaves withdrawn; surround fraction recommended in C4.
2. ACCEPTED (already applied): placement and the 1 Hz resync removed; cycle by maximum intersection.
3. ACCEPTED (already applied): freeze, resume, clear (US-034); the hysteresis rule is rejected in C7.
4. ACCEPTED (already applied): `WindowHandle` opaque in Core; registry in Windowing named for Original Frames.
5. ACCEPTED: same-axis chain merge ships; general re-treeing is a spike (US-162, Layout model, C3).
6. ACCEPTED (already applied): US-115 budgets Zones' own work; per-app wall time on the manual matrix.
7. ACCEPTED (already applied): resync deleted; idle wake-ups enumerated (US-116).
8. ACCEPTED: poll schedule per state (notGranted and revoked); `needsRelaunch` only after three failed recreations over 10 s with the probe true; probe-stuck-true test (Permission machine, US-121, C6).
9. ACCEPTED (already applied): any size change ends the session.
10. ACCEPTED (already applied): US-041 reworded to the clamp hazard.
11. ACCEPTED in part: the warning list ships as a data fixture of at most six chords, labelled best effort and not maintained per OS release (US-063, Out of Scope). REBUTTED dropping it: Carbon registration of a system chord can succeed while the system swallows it, so the inline result alone leaves a silently dead chord.
12. ACCEPTED: as platform 11; budget is zero allocations on arm plus a manual Instruments row.
13. ACCEPTED (already applied): assignments.json carries name, last frames and scale per DisplayKey; now stated as one map with derived dormancy.
14. ACCEPTED (already applied): CI budgets are allocation counts and an order-of-magnitude bound.
15. ACCEPTED: US-008 scoped to Developer ID-signed releases; release script warns when ad-hoc; signing identity in About and diagnostics (US-144).
16. ACCEPTED (already applied): Copy Diagnostics shows the report before copying.
17. ACCEPTED: one pure `ExclusionPolicy -> allow | skip(reason)` with enumerated reasons and two phases, evaluated before any Overlay effect, one table test per reason.

Steal list adopted this round (see round3-power-user.md): two-phase ExclusionPolicy, hotkey-mid-drag rule, label outline, "no chord" badge, single 5 s health tick, observers on a run-loop thread, `hardware` DisplayKey tier, ADR-0013 contingency, rate limiter (platform); chain merge, checkable Exclude item, window hotkeys registered only while granted, abort at first timeout, `needsRelaunch` K-rule, signing identity, recovery record write-once rule, buttons filtered at the source, manual contract tests (maintainer).
