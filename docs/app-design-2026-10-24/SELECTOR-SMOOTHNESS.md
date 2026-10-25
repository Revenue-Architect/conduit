# Character selector: smoothness and keyboard spec

The character selector is the Chats tab (`lib/features/hermes/manga/`). This is the 2026-10-25 work after the owner reported two problems: swiping between bots stutters, and with the keyboard open the bot tiles do nothing.

## What was measured

Build 251 is a diagnostic build (`CONDUIT_DIAG=true`) with a frame probe on the selector (`manga_frame_probe.dart`). It ran on the S25 at 120 Hz, which gives each frame 8.3 ms. The same scripted gestures were used for every scenario.

| Scenario | Frames late | Build p50 / p90 | Raster p50 / p90 / max |
|---|---|---|---|
| S1: 10 swipes | 213 of 394 | 1.6 / 3.3 ms | 1.6–81 / 53–186 / 216 ms |
| S2: 3 tile jumps | 17 of 19 | 0.9–2.1 / 3.7 ms | 11–59 / 111–119 / 197 ms |
| S3: keyboard open and close | 15 of 52 | 0.8–1.4 / 1.1–4.8 ms | 0.8–1.8 / 18–47 / 114 ms |
| S5: swipe with the keyboard up | 21 of 24 | 1.5 / 3.6 ms | 44 / 89 / 106 ms |

**The UI thread is fine; the GPU is the problem.** The causes:

1. **The figure's outline costs nine colour-filtered draws of a large image, each in its own layer.** On Android, Flutter renders with Impeller, which does not cache a repaint boundary as pixels. All nine draws repeat on every frame the page moves, for both pages on screen.
2. **Six tile portraits sample full-size images** (650–1424 px) into 60 dp tiles on every frame.
3. **Every swipe frame retargets a colour animation on all six tiles**, so each tile repaints with a colour that lags the swipe.

The tile bug is a hit-test problem. The tray is only *drawn* raised above the keyboard (a translation); its layout box stays at the bottom. Flutter tests taps against the layout box, so taps on the raised tiles land on nothing.

## Requirements

1. **Swipes and tile jumps stay within budget.** Raster p90 under 8.3 ms, and no more than a few late frames per swipe, with build times unchanged or better.
2. **The keyboard slide stays smooth,** under the same budget.
3. **With the keyboard open, tapping a tile switches to that bot.** The keyboard stays open and the typed text stays in the box.
4. **With the keyboard open, swiping the stage switches bot,** and the keyboard stays open.
5. **A tap on the stage closes the keyboard; so do Back and the keyboard's own hide button.** The typing pose reverses either way.
6. **No blinking** of figures during swipes, the pose, or tab switches.
7. **No visible change at rest.** The figure keeps its ink outline.
8. **The rest of the app is untouched.**

## Plan

| # | Change | Fixes |
|---|---|---|
| 1 | **Bake the outline.** Render the figure plus its outline once, into a single image at the displayed pixel size (`PictureRecorder` → `ui.Image`), keyed by file, colour, width and size, and cached. The page then draws one image per frame instead of nine filtered layers. | Raster on swipes, jumps, pose |
| 2 | **Decode tiles small.** Tile portraits decode at tile size (`ResizeImage`, about 3× the tile's logical width), not full resolution. | Raster on every frame |
| 3 | **No animation in tiles.** Tile colours come straight from the swipe's blended colour; drop `AnimatedContainer`. | Per-frame retargeting |
| 4 | **Build the pager once.** It's created once per bot list. Each page reads its own last words and working state, so a page change (mid-swipe) and each keystroke no longer rebuild the pages. | Mid-swipe rebuild |
| 5 | **Lay out the tray where it's drawn.** The body becomes a stack. The stage fills the space above the tray's resting height, measured once; the tray is positioned at `bottom = max(keyboard, rest)`. Only the tray re-lays out as the keyboard moves, and taps reach it where it is. | Tiles dead with the keyboard open |
| 6 | **Keep the keyboard on tile taps and swipes.** Tiles don't take focus. A stage tap closes the keyboard, a drag doesn't. | Requirements 3–5 |

## Test plan

**Measured:** the same probe scenarios run on a diagnostic build after the changes, compared with the table above.

**Checked on the phone (S25), with screenshots or keyboard state:**
- launch lands on the selector
- swipe forward and back through all bots
- tile jumps
- keyboard open, then a tile → the bot switches and the keyboard stays open
- keyboard open, then a swipe on the stage → the bot switches and the keyboard stays open
- a tap on the stage, Back, and the keyboard's hide button all close the keyboard and reverse the pose
- typed text survives a bot switch
- sending a task opens the new chat
- switching tabs away and back
- dark mode

**Automated:** the analyzer, plus the Hermes and router test suites.

## Result (builds 254 and 255)

Measured with the same probe scenarios as before:

| Scenario | Frames late | Raster p50 / p90 / max |
|---|---|---|
| S1: 10 swipes | 3 of 1,176 | 1.2 / 1.5 / 21 ms |
| S2: tile jumps | 0 of 150 | 1.2 / 1.7 / 5 ms |
| S3: keyboard open and close | 0 of 58 | 0.7–1.7 / 2.7 / 4 ms |
| S4: a tile with the keyboard up | 2 of 104 | 0.5–1.1 / 2.4 / 35 ms |
| S5: a swipe with the keyboard up | 0 of 119 | 1.1 / 1.3 / 2.5 ms |
| S6: a tap on the stage closes the keyboard | 0 of 45 | 1.1 / 4.6 / 6.5 ms |

**Checked on the phone:**
- With the keyboard up, a tile switches bot, the keyboard stays open and the typed text stays.
- A swipe with the keyboard up does the same.
- Back and a tap on the stage close the keyboard.
- A cold start lands on the selector.
- Sending a task opened the new chat, and Chief replied.

**Two further causes found while testing:**
- **The keyboard closed on a swipe** because of the app-wide "dismiss the keyboard on any scroll" listener in `main.dart`. Android's IME history showed Conduit itself asking to hide the keyboard. The pager now keeps its scroll notifications to itself.
- **The tray stopped above the floating dock,** leaving a band of the field colour around it. The tray now reaches the bottom edge, so the dock sits on the tray's colour.

**Also changed:**
- The bots have a fixed order: Chief first, then the rest by name. Hermes lists the most recently active first, which made them trade places.
- Bubbles skip a reply that opens with a system notice.

**Not checked on the phone:** dark mode (the selector draws its own colours, so only the dock differs) and 200% text.
