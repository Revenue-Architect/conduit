# Conduit redesign (2026-10-30): critique

One fresh critic (a separate agent, briefed with the concept, the colour roles, the refused defaults, the keep list and `references/critique.md`) scored every round from the rendered 3x PNGs. Screens: `shots/r1`, `shots/r2`, `shots/r3` (and `-small` at 375 × 667).

## Scores

| # | Line | R1 | R2 |
|---|---|---|---|
| 1 | Concept on the pixel | 3 | 4 |
| 2 | Not the category average | 4 | 4 |
| 3 | Not this skill's average | 3 | 4 |
| 4 | Hierarchy | 3 | 4 |
| 5 | Typography | 4 | 4 |
| 6 | Colour | 3 | 4 |
| 7 | Richness | 4 | 4 |
| 8 | Rhythm and space | 3 | 3 |
| 9 | Craft details | 2 | 3 |
| 10 | Native fluency | 2 | 4 |
| 11 | Signature | 3 | 3 |
| 12 | Feature test | 3 | 4 |
| 13 | Fidelity (redesign) | 3 | 4 |

Round 2 verdict: **done by the stop rule** (nothing below 3; 9 of 12 at 4 or above). The critic listed concrete defects to fix; round 3 fixed them and was not rescored (see below).

## Round 1 → 2 (what changed)

- **Craft:** the "Ask the team" bar is solid (`#FFFFFF` / `#16181C`) with the city base behind it on solid ground; the spire clears all text on Today; the skyline path is closed (no wedges); stars sit at least 16 dp from text; "dark since 6:31".
- **Native fluency:** One UI status bar (time and notification icons left; wifi, signal, battery % right); Material `arrow_back` in a 48 dp target; the M3 active indicator (64 × 32 pill) in the dock with 12 sp labels.
- **Colour:** amber only means "working now"; the icon has no amber sun; lit windows are warm white `#F3E6C8` at 70%.
- **Icon:** full-bleed adaptive icon (dawn sky, skyline centred in the safe zone) plus a themed monochrome layer.
- **Hierarchy (evening):** stat tiles became one sentence; same structure as morning (strip, input, sheet with Needs you, Tomorrow, Umbrel sentence).
- **Fidelity:** six faces with a scrolling peek; a failed run with Retry; attach on the Today input; a new Chats screen including Open WebUI; Work, Chats and Chat carry a sky band; DraftReview restored to its own structure.

## Round 2 → 3 (defects fixed, not rescored)

- 02: the terminal fills the window down to the steps; the steps sit 24 dp above the input; the log shows the follow-up `curl` and the test push.
- 04 / 05: the subtitle sits under the title (15/400), clear of the spire.
- The live timer advances with the clock: 4:12 at 7:42, 5:12 at 7:43, 7:12 at 7:45; the step header says 5m.
- 03: subtitle is "gpt-6.1-terra" only.
- Today: the fade sits behind the dock only (24 dp ramp), never over a pill; "Overnight" starts below the fold.
- 08: the sheet gains a "Tomorrow" row (11:00 weekly ops review).
- 06: at 0 ms the ops tile is at 0.94 with a 3 dp amber frame and the other tiles dimmed to 60%; at 360 ms the rows are legible.
- Icon: the 1 px nub at the right edge is gone.

## Round 3 → 4 (owner feedback, not rescored)

The owner did not like 02 (live window) or 05 (Chats): "too terminal like". Changes:
- **02:** the black terminal is gone. The screen is light, with the sky band header like the other inner screens. The hero is one sentence about the outcome ("A test alert is on its way to your S25."), then the window: an amber-framed picture of the alert path (Umbrel → push relay → Firebase → your S25) with the alert travelling on the last link, and the before/after delay. The steps stay in the fixed inline run UI. The commands are one tap away ("Show the 6 commands ops ran").
- **05:** times and the live timer use Geist tabular figures instead of Geist Mono; the mono "OW" monogram is replaced by the Open WebUI logo from the repo; ops' face carries the amber ring; search and new chat added; two more Open WebUI/direct rows so the list scrolls under the dock.
- **Everywhere:** Geist Mono removed from the interface (it was the terminal signal). Today's live tile and Work's running row show a step bar instead of tiny terminal lines. The storyboard (06) now morphs the tile into the new window: the sky pales and folds into the header instead of dimming to charcoal.
- **Continuity:** ops' run moves through five steps across the screens (restarting at 7:42, test alert at 7:43, watching at 7:45 and 7:46).

Scan (r4): no FAILs at 412 × 892 or 375 × 667. One small-phone FAIL on the way (Chief's long preview overlapping its badge, the known ellipsis false positive) was cleared by shortening two previews. New warns, answered:
- 02 "7 elements cast shadows": they are 2 px rings (the amber window frame, the check badges' cut-outs, the travelling alert), not depth.
- 02 "3 gradients": the sky band, the dashed live link, and the fade behind the composer.
- App-wide type scale (40, 30, 17, 16, 15, 14, 13.5, 13, 12, 11): the window's sentence reuses the 30 title step; the fixed inline run scale still sits inside the app scale.

## Declined asks

- **Model chip on Today's input:** declined. On Today you address the team and the model belongs to the bot you pick, so the input carries a recipient chip ("Chief ▾"). The model chip stays in each bot's chat. The critic accepted this.
- **Evening identical to morning's solid sheet:** done structurally, but 07 keeps the dusk sky and light dock the owner chose (variant A2). The critic accepted this.

## Scan

Every round ends with no FAILs (r1 to r4) at 412 × 892 and at 375 × 667. Remaining warns, answered:
- "Text inside the system's safe areas" on 02/03/04: the scan uses iPhone safe areas (62 dp); the Android frame's status bar is 40 dp, and the text sits below it.
- "No element owns the screen" on 02 and 03: 02's hero is the live window (a frame, not text); 03 is a chat, where the answer is the content.
- "Distinct left edges": the time column in logs, the face column in rows, and the 20 dp margin; three real verticals plus the dock.
- "Type scale this long": the fixed inline run scale (17, 14, 13.5, 12) sits inside the app scale (40, 30, 15, 13, 11) by the owner's rule.

## Not verified

Real-device feel and motion timing (the storyboard is static), Geist rendering on Android, live sky crossfades and weather modifiers, and Dynamic Type at the largest sizes.
