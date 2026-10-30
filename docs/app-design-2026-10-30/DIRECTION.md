# Conduit redesign (2026-10-30): direction

## Brief

The owner answered on 2026-10-30. This is a fresh redesign, unrelated to the Oct 24 manga direction.

- **The app:** Conduit, the owner's Android client (Samsung S25 Ultra) for his own team of Hermes agents on the Umbrel: Chief, kai, ops, hermuse, architect and scout. Also Open WebUI and direct model endpoints. One user.
- **The first ten seconds:** see what happened first (what the team did, what needs him), with starting a task one tap away.
- **Feel:** modern, premium, useful.
- **References:**
  - **KaizenOS v2 console** (`origin/main`, W4 visual system, 2026-10-29): neutral zinc grounds (`#f6f6f8` / `#09090b`), white and `#141416` surfaces, hairlines and no shadows, Hanken Grotesk 600 with tight negative tracking, mono figures, ink-solid KPI hero cards, a black dock rail with counts, 10–12 px radii, red only for "create" and "you are here", one-card spring morphs. Not the older navy / steel-ice v1 palette (owner's correction).
  - **Hark Pro** (Adcock, launched 2026-10-06): a full-screen homepage whose background imagery follows the local weather and time of day, chat in the centre, a proactive feed of suggested actions and "panels" (mini dashboards) below, and a small window that shows the agent working.
  - **CoWork OS** (coworkosapp.com, added 2026-10-30): an open-source AI desktop app built on "every action is visible and approvable". Taken: runs as plan steps with results, approvals that state consequence, scope and undo and stay in the record, routines with a trigger, a bot and a status, new routines start paused with an Observe / Propose / Act scope (m12 to m14). Not taken: its warm off-white, gradient headline and coloured status pills.
- **Fixed, kept as-is:** the bot faces and their idle/working video avatars; the inline run UI and its type scale (answer 17 > turn line 14/600 > rows 13.5/400 > meta 12, compact 13/600 pills); the A2UI/OpenUI surfaces.
- **Dropped:** the orange `#FF5A26`. The new direction uses another hue family.
- **Deliverable:** mockups first. No Flutter changes until a direction is approved.
- **Frame:** S25 Ultra at 412 × 892 dp (punch-hole camera, gesture bar, Android status bar) via `android.css` over the app-designer kit. Material 3 navigation behaviour.
- **Imagery:** the owner's bot art (`assets/*-cut.png`, transparent chibi busts). No image-generation tool is connected, so any other richness is drawn (SVG/CSS).

## Current app

Screenshots of build 268–270 on the S25 (2026-10-28): `before/01-home.png`, `before/02-work.png`, `before/03-chat.png`, `before/04-chat-dark.png`.

**What it is now:** a white Material list app. Roboto, near-black ink, orange as the only colour, a black floating pill dock with caps labels. The manga styling lives only in Pick/Today/Chats; Home, Work and chat are still the list app.

**Slop tells it hits:**
- **Everything is a list with chevrons.** Home is "TEAM · 6" then "WORK", rows of identical height. It reads as a settings panel.
- **ALL CAPS tracked eyebrows** on every section (TEAM · 6, WORK, NEEDS YOU · 2, DRAFT / NOT SENT, TO, SUBJECT, MESSAGE).
- **"Used today" / "Used 3d ago"** tells you when, not what.
- **The core question has no answer on the first screen.** "What did the team do overnight?" needs Work, and Work is a raw session list ("Diagnose initiative-reflection miss…" twice, "default / Chief", "# Kanban task t_7fe23841").
- **Raw machine strings in the UI:** `# Kanban task t_8e7184a8`, `Message from 🤖 hermes (@hermes)`.
- **Faces wasted** as 40 dp row avatars.
- **Chat header collision:** the folded bot name sits on top of the first user bubble (`03-chat.png`).
- **The logo test fails.** Cover "Conduit" and it is any Material agent client.

**Inventory (keep / lose / unknown):**

| Item | Verdict |
|---|---|
| Six bots with faces, idle and working clips | keep |
| Start a task to any bot; model chip; attach; mic; voice call | keep, one tap from the first screen |
| Needs you (reviews, approvals, failed runs) | keep, first screen |
| Running runs, with the Bot Screen / Steel live view | keep, first screen (Hark's "watch it work" window) |
| Recent runs and chats by bot, unread dot, Work count | keep |
| Scheduled agents, Kanban, Teams, Spaces, Artifacts | keep, one level down |
| Inline run UI, plan in place, Steel player, A2UI/OpenUI | keep exactly |
| Settings: Hermes, Appearance, Chat, Audio, Notifications, Direct connections, Open WebUI, About | keep, in You |
| "Used 3d ago" rows, raw task ids in previews, caps eyebrows | lose |
| Four tabs (Home, Chats, Work, You) | unknown: decision for the owner |

**History row for the current look:** `printed | light | grotesque | orange | illustration` (already in `~/.app-designer/history.md` as the Oct 24 row). The new direction must differ from it on at least 3 of 5 columns.

## Exploration (Step 2)

`explore.html`, shot to `shots/explore/` (sheet: `shots/explore/sheet.png`). Same core screen and content in all three: Thursday 30 Oct, 7:42, Toronto 4° clear; 11 done overnight, 2 need you, ops live.

| | A. Toronto sky | B. Control room | C. Desk radio |
|---|---|---|---|
| Concept | Conduit is the view from your window at 7:42, with the team's night written on it. | Conduit is a broadcast control room: six live feeds and a talkback key. | Conduit is a Braun desk radio: one dial, six stations. |
| Family | nature | place | object |
| Ground | image (drawn sky that follows Toronto's time and weather) | dark | light |
| Type | grotesque (Geist + Geist Mono figures) | condensed (Big Shoulders Display + IBM Plex Mono) | expanded (Unbounded + Instrument Sans) |
| Accent | neutral (ink pills; the sky is the colour) | yellow (amber tally = live) | green (power light = running) |
| Richness | colour-material (sky, skyline) | illustration (the bots as monitor feeds) | shape (dot grille) |

**Pick: A, Toronto sky.**
- It answers "what happened?" in one sentence before anything else, then hands over the two decisions and the night's log, with "Ask the team" one tap away. That is the brief's first ten seconds.
- It is Hark's living ground (sky by time and weather, the agent window you can see working), set over a calm working sheet that takes KaizenOS's sensibility (neutral surface, ink pills, a reversed black dock, soft counts) without copying its components.
- The colour means something: the ground is the actual sky, so the app looks different at 7am, at dusk and in snow, and no accent has to perform.

**Why the others lost:**
- **B** has the most character (the monitor wall is the best use of the bots' faces), but mono everywhere is a costume, it is dark-only, and the broadcast vocabulary ("cues", "segments") is a layer between the owner and his own words. **Taken into A:** the bots as live feeds. A running bot's face becomes a small live window (Hark's "watch it work"), and the Bot Screen grows out of it.
- **C** is the dashboard reflex in disguise: a giant number in a dial. The station row is good but the radio metaphor stops at Home.

**History check:** A = `nature | image | grotesque | neutral | colour-material`. Against Jarvis (`object | dark | expanded | orange | 3d-object`) it differs on 5 of 5; against Oct 24 Conduit (`printed | light | grotesque | orange | illustration`) on 4 of 5. Passes.

**Scan (explore):** no FAILs. Warns: A has 7 left edges in the left third (the overnight rows' time / face / text columns; will align in Step 4); B's gradients are the monitor lower-thirds; C's shadows are the dial's bevel. The app-wide size list is long because it spans three directions.

## Variants of A and B (owner asked, 2026-10-30)

The owner liked A and B and asked for two variants of each. `variants.html`, shot to `shots/variants/` (sheet: `shots/variants/sheet.png`). Each variant borrows from the other direction. All four use Geist + Geist Mono and one accent, amber `#FFB020`, for "live" only. Scan: no FAILs.

- **A1, sky + feeds:** the dawn sky. Under the headline, B's bots become a strip of feeds: ops' tile widens into a live window with an amber tally; quiet bots are dimmed. Then "Ask the team", then the white sheet (needs you, overnight).
- **A2, dusk + panels:** 18:52, light rain, city lights on. Most Hark-like: everything floats on the sky as glass. Two suggestions (Approve the theme, Open tomorrow's kickoff notes) and two panels (Umbrel health, Kaizen catalogue with a sparkline). The dock reverses to light because the ground is dark.
- **B1, control room, calm:** the 3 × 2 monitor wall kept from B, with Geist instead of all-mono; counts tucked into each tile's corner; "Ask the team / hold to talk" at the bottom.
- **B2, program monitor (light):** the live bot's screen is the hero (ops' terminal at 16:11, amber frame, "Take over"); the other five bots sit in a preview strip; then needs you. White canvas (owner's light-mode rule), black dock.

## Decision (owner, 2026-10-30)

**A1 is the default Today screen, A2 is how it looks in the evening.** The ground follows the real time and weather in Toronto; in dark mode it is always the evening or night version of the same sky. The bots stay visible as a strip of feeds. **B2's program monitor is what opens when you tap a live bot's tile.**

**Concept:** Conduit is the view from your window, with the team's day written on it.

## The category default refused

AI agent clients (ChatGPT, Claude, Open WebUI, Hermes Desktop) share a blank chat as the first screen, a left drawer of conversation titles, a model picker as the headline, grey bubbles, a purple or teal brand gradient, and sparkles next to anything automated. Conduit refuses all of them: the first screen is what happened, conversations are grouped by the bot that did the work, the model is a small chip in the composer, and nothing sparkles.

Also refused: the night-sky cliché (navy-violet gradient, moon and stars as decoration). The sky is Toronto's actual sky at that hour. Dawn is blue to pale gold, never violet, and stars appear only when it is really night and clear.

## Tokens

**Type.** Geist for everything (modern, technical, open counters that read at 13 on the S25). Times, counts and live timers use Geist's tabular figures, not a mono face: mono read as a terminal (owner, round 4). A mono face appears only inside code a bot writes in a chat. Tracking: display -0.045em, titles -0.03em, text 0.

| Role | Size / weight | Use |
|---|---|---|
| Display | 40 / 600, leading 1.04 | Today's one sentence |
| Screen title | 30 / 600 | Work, Chats, You; the live window's sentence |
| Answer body | 17 / 400, leading 1.45 | chat answers (fixed) |
| Row title | 15 / 600 | needs-you and inbox rows |
| Turn line | 14 / 600 | inline run line (fixed) |
| Run rows | 13.5 / 400, in progress 600 | plan and tool steps (fixed) |
| Meta | 13 / 400; 12 / 500 tabular | subtitles; times, live timers |
| Caption | 11 / 500 | badges |

**Colour roles.**

| Token | Light | Dark |
|---|---|---|
| `ground` (screens other than Today) | `#F7F7F7` | `#0B0C0E` |
| `raised` (sheet, rows, A2UI panels) | `#FFFFFF` | `#16181C` |
| `soft` (counts, quiet fills) | `#F1F2F4` | `#202328` |
| `ink` | `#0E1116` | `#F2F3F5` |
| `ink-2` | `#5A606B` | `#A3A8B2` |
| `ink-3` | `#6B717B` | `#8A909A` |
| `rule` | `#E6E7EA` | `#26292F` |
| `accent` = live | `#FFB020` fill; `#8A5A00` as text | `#FFB020` |
| `dock` (reversed) | `#0E1116` | `#F2F3F5` |

One accent, one role: **amber means a bot is working right now** (tally dot, live frame, live timer). Primary actions are ink pills, not the accent, and the system tint is ink. Semantic red is only for a failed run.

**The sky** (Today's ground) is a system, not decoration. Each state is a vertical gradient plus the Toronto skyline silhouette, crossfading as the hour changes:

| State | When | Top to horizon |
|---|---|---|
| Dawn | sunrise ± 60 min | `#0D2141` → `#2C4F80` → `#7E9DC2` → `#EFDDB2` |
| Day | after dawn until 2 h before sunset | `#2E6DB4` → `#6FA3D6` → `#CFE3F2` |
| Dusk | sunset ± 60 min | `#081224` → `#3B5A82` → `#B89474`, city lights on |
| Night | otherwise | `#05080F` → `#0E1A2E`, stars only when clear |
| Dark mode | always | dusk or night, whichever is closer |

Weather modifies it: overcast flattens the gradient toward grey `#8C96A3`, rain adds faint 1 px streaks, snow adds slow 2 px flakes. Text on the sky is white; the headline's second sentence is 62% white. The skyline is one flat silhouette (`#0F1E33` at dawn, `#0A1220` at dusk), with lit windows only at dusk and night.

**Layout.** Side margin 20. Radii: 999 for pills and the dock, 16 for bot tiles, 24 for the live window, 28 for the sheet's top corners. Spacing 4, 8, 12, 16, 20, 24, 32, 48. No cards inside the sheet; rows group by space. The dock is the only navigation: four items, 64 tall, reversed.

**Richness source.** Colour and material: the live sky and skyline, plus the bots' own faces as feeds. In the live window, a picture of the work (the alert path) drawn in the same hand. One hand: flat silhouettes and line icons, no gradient except the sky itself, no glow on UI.

## Signature: the window opens

Conduit is a window, and every live bot is a window you can open.

1. **Trigger:** tap a live bot's tile on Today, or the Running row on Work. The tile scales to 0.97 in 100 ms; light haptic on press.
2. **0–420 ms:** the tile's frame springs to full screen (shared-element morph, spring response 0.42, damping 0.86, no overshoot). The tile's step bar becomes the window's picture of the work; the amber frame stays on the window's edge; the bot's face slides from the tile's corner into the header. The sky pales to the page and folds up into the header band.
3. **300–520 ms:** the sentence and the run rows rise into place under the band, 40 ms apart (rows only).
4. **Land:** light haptic. The live timer keeps ticking.
5. **Back:** swipe down or the back gesture folds the window into its tile on the same spring. It is interruptible: let go halfway and it returns.
6. **Reduced motion:** a 150 ms cross-fade, no scale. The frame and timer still appear.

## One card (Morphlet): menus, modals and forms

Owner's rule (round 4): most menus, modals and forms are built like KaizenOS's Morphlet (`Downloads\morphlet-react-source.zip`, vendored in KaizenOS at `src/vendor/morphlet`), and every one is a **shared element**: the control you pressed *becomes* the card, and the card folds back into that control. Mockups: `morph.html`, shot to `shots/morph/` (small phone `shots/morph-small/`).

**The card.** One floating card, inset 16 from the sides and 16 above the gesture bar (Morphlet's own offsets), corner radius 32, `raised` fill, one soft shadow, a 30–34% ink scrim behind. Grabber on top; title 17/600 left, a 36 dp close in a 44 dp target right. Rows 56 tall with a 20-radius selection fill and an ink check. Fields are label-over-value rows on a hairline, the focused one on a 2 dp ink line, so nothing is a box inside the box. Actions are a full-width ink pill (primary) beside a soft pill. While a card is open the dock or composer steps down out of view: one surface at the bottom. Amber still only means "working now" (ops' ring and line in the pickers).

**The shared element.** At press the control gives to 0.94 (Morphlet press-in). Its frame, corner radius and fill spring from the control's rect to the card's rect as one object; the control's own label hands over to the card's content near the source (Conduit's existing handover), and nothing stretches: text and faces counter-scale. The trigger is hidden while its card is open, because it *is* the card.

**Nested steps reshape the same card** (Morphlet / KaizenOS `CardLayers`): the card narrows 20 dp a side and changes height on the same spring, the content slides 8 dp, the header gains ‹ back, × still closes everything. Typed input in the parent survives. Never a second card on top.

**Nothing opened from a card opens anything new** (owner's rule). Inside a card, every control that leads somewhere is itself a shared element:
- A row, field or button that opens a menu, picker, form or confirm **reshapes the card it is in**. The pressed row's label rises into the new view's header. There is no depth limit. On the phone, odd depths inset 20 dp a side and even depths return to full width, and the height always follows the content, so every step visibly changes shape (m10: New chat → Attach → Umbrel files → back with the file and the typed text intact).
- A control that leads to a full screen (Start chat, Take over, open an artifact) **grows the card itself into that screen**, then Back folds the screen into wherever its result now lives (m11: Start chat → the card becomes the chat → Back folds into Chief's row).
- ‹ pops one step, × or Back from the root folds the whole card into its original trigger, and dragging down does the same.
- **Never** from inside a card: a Material dialog, a `showModalBottomSheet`, a `PopupMenu`/`DropdownButton` overlay, a new route pushed over the card, or a snackbar standing in for a confirm.

**How the build enforces it:** the card owns a view stack (push, pop, replace), not the Navigator. One widget test opens New chat → Attach → Umbrel files, asserts exactly one card and no new route at every step, then pops and asserts the typed message is still in the field. Device proof on the S25: a frame-by-frame recording of the same chain, with one card throughout and its size springing at every step.

**Folding back carries the result.** The card returns to the control it came from, which now shows the new value: the recipient chip reads "Llama 3.3" and the input "Ask Llama 3.3 70B"; Review folds into its row, which reads "Sent 7:43" with a check. Send first turns into the check, then folds.

| Surface | Grows from | Lands as | Nested step | Folds back to |
|---|---|---|---|---|
| Recipient (m01, m02) | "Chief ▾" chip in Ask the team | Send to: six bots, Open WebUI models › | Open WebUI model list | the chip, showing the pick |
| Review a draft (m03, m04) | the row's Review pill | DraftReview, in its own structure; Edit, Send | Edit draft form | the row: "Sent 7:43" |
| Model (m05) | the model chip in a chat | Model for this chat; Reasoning; default switch | Reasoning levels | the chip, showing the model |
| Take over (m06) | Take over in the live window | Confirm: Keep watching / Take over | none | the Bot Screen grows on |
| New chat (m07) | the pencil on Chats | To (faces), Message, Model; Start chat | Model list | the new chat opens from the card |
| Also, not drawn | attach +, row long-press, Retry, Scheduled and Kanban forms, settings pickers | same card | same rule | the control |

**Motion.** Morphlet's SwiftUI-style springs at KaizenOS's speed (Morphlet × 0.7): open on the morph spring (response 0.35 s, damping 0.86), close on the dismiss spring (0.245 s, damping 1, so closing is quicker than opening), reshape on the layout spring, content on a 0.21 s critically damped spring. Conduit's global clock already runs 1.265× (`HermezMotion.appSpeed`), so author the Flutter springs at Morphlet × 0.885 to land on the same feel. Reduced motion: a 150 ms cross-fade, no scale or travel.

**Build on what exists.** Conduit already has `pushHermezSheet` with a `HermezMorphOrigin` (a sheet that grows out of the touched object and hands content over near the source). The work is to extend it, not replace it: the floating inset card shape, nested reshape inside one card, fold-back to a control that shows the new value, and routing the app's Material menus, dialogs and pickers through it.

## Content

All screens: Thursday 30 October 2026, Toronto. Bots: Chief (lead), kai (Kaizen commerce), ops (Umbrel and servers), scout (research), architect (system design), hermuse (writing).

**1. Today, morning** (light, 7:42, 4° clear, sunrise 7:51)
- Top: "Thu 30 Oct  Toronto" · "4° clear · sunrise 7:51".
- Display: "11 done overnight." / "2 need you."
- Feeds: ops (live tile: "Push server", step bar 3 of 5, 4:12), Chief, kai, architect, scout (quiet), hermuse (quiet). Caption: "ops is restarting the push server. Tap to watch."
- Composer: "Ask the team", mic.
- Sheet, "Needs you 2": Chief · "Reply to Jordan about Tuesday" · "draft ready, not sent" · Review; kai · "Publish the holiday theme" · "Maple & Pine storefront" · Approve.
- "Overnight": 6:05 kai synced 38 products to the catalogue · 5:40 scout read 14 Shopify changelog entries; 2 touch checkout · 3:12 ops restarted umbrel-serve after 2 failed checks · 1:20 architect drafted the push relay split, 3 pages.
- Dock: Today (on), Chats, Work (2), You.

**2. Live window: ops** (light, 7:43). The window shows the work, not the commands.
- Sky band header: back, ops face, "ops", "Working · 5:12", "Take over".
- Sentence (30/600): "A test alert is on its way to your S25." Sub: "Alerts stopped reaching your phone at 7:31. ops restarted the push relay at 7:42 and is checking that they arrive."
- Window (amber frame), "Alert path · 7:43": Umbrel ok → Push relay restarted → Firebase 0.4 s → Your S25 arriving (amber, with the alert travelling on the last link). Below a rule: "Alert delay 31.2 s → 0.4 s" (old value struck through), "Missed while down: 3 alerts".
- Turn line "Fixing the push server · 5m". Rows: done "Found Firebase timing out after 31.2 s"; done "Read the last 40 log lines"; done "Restarted the push relay"; in progress "Sending a test alert to your S25"; next "Watch alerts for 5 minutes, then resend the 3 missed".
- "Show the 6 commands ops ran ›" (the raw log, one tap away). Meta "Started 7:38 after 2 failed checks. ops pauses while you take over." Composer "Message ops".
- What fills the window, in order: the bot's own A2UI surface for the task when it sends one (this alert path is that); else its desktop or browser when it is using one (the existing noVNC Bot Screen and Steel views); else the current activity row from `HermesActivityPresenter` as the sentence, with the step bar. Never the raw terminal by default.

**3. Chat: Chief** (light, 7:44)
- Header: back, Chief face (video avatar), "Chief", new chat.
- You: "Draft a short note to Jordan confirming Tuesday's kickoff at 10 on Teams. Don't send it."
- Turn line (folded): "Read 4 emails and your calendar · 12s".
- Answer: "Here's the draft. Tuesday at 10:00 is clear, and Jordan's last email asked for the Teams link, so I put it in."
- A2UI DraftReview (kept component): "Kickoff confirmation" · Not sent · To jordan@mapleandpine.ca · Subject "Tuesday kickoff" · body "Hi Jordan, confirming our kickoff Tuesday at 10:00 on Teams. The link is below. See you then. Kamran" · Edit · Send.
- Composer: chip "gpt-6.1-terra · High", "Message Chief", mic, voice.

**4. Work** (light)
- Title "Work"; sub "2 need you · 1 running".
- Needs you: the same rows. Running: ops face in an amber ring · "Fixing the push server" · "ops · test alert arrived, watching" · 7:12 with a 5-step bar (step 5 in progress).
- Recent, unread first: Chief · "Plan for Thursday" · "3 meetings and a call at 2:30" · 6:58 · unread; kai · "Holiday theme QA" · "Checked on 3 phone sizes; fixed 1 overlap" · 6:12 · unread; scout · "Shopify changelog, 29 Oct" · "2 entries touch checkout extensions" · 5:40; architect · "Push relay split" · "3 pages, ready to read" · 1:20; ops · "umbrel-serve restart" · "Back up at 3:13 after 2 failed checks" · 3:12.
- Quiet links: "Scheduled · 10 active", "Kanban · 15 tasks".

**5. Chats** (light, 7:46)
- Sky band: "Chats", "6 bots · 3 unread", new chat (pencil). Search field "Search chats".
- Your team: Chief · "Plan for Thursday: 3 meetings" · 6:58 · 2; kai · "Theme QA: fixed 1 overlap" · 6:12 · 1; ops (amber ring) · "Test alert arrived. Watching for 5 min" · 8:12 live; scout · "Changelog digest for 29 Oct" · 5:40; architect · "Push relay split, 3 pages" · 1:20; hermuse · "Newsletter draft, issue 14" · Tue.
- Open WebUI and direct: "Scaling a bread recipe" · Llama 3.3 70B · Open WebUI · Mon; "Winter tires in Ontario" · Llama 3.3 70B · Open WebUI · Sun; "Regex for SKU codes" · gpt-6.1-terra · direct · 22 Oct. Open WebUI rows carry its logo (`assets/icons/open_webui.png`) small in a soft circle; direct rows carry a plug glyph.

**6. Signature storyboard** (4 frames): Today with ops' tile pressed → the frame springs out over a paling sky → the sky folds into the header, the sentence rises → landed, steps settled.

**6. Today, evening** (dark, 18:52, 6° light rain, dark at 6:31): "23 done today." / "1 still needs you." Composer. Suggestions: kai · "Publish the holiday theme?" · "kai checked it on 3 phone sizes" · Approve; Chief · "Tomorrow, 10:00 kickoff" · "Chief prepared notes from 4 emails" · Open. Panels: Umbrel "14 apps up" · "CPU 31% · ops restarted 1 at 3:12"; Kaizen catalogue "1,284 +38" with a 7-day line.

**7. Today, quiet night** (light mode at 2:14, clear): "Quiet night." / "Nothing needs you." Feeds all quiet. Line: "scout reads the changelog at 5:30." Composer. Sheet "Earlier": 1:20 architect drafted the push relay split; 12:48 Chief planned Thursday.

**8. App icon:** a black squircle holding one window: the dawn sky over the skyline, with an amber live dot in the window's corner.

**Not designed in this pass:** You and settings, the model picker, Scheduled, Kanban, Spaces, Artifacts, onboarding. They take the same tokens.

## Status (2026-10-30)

Final screens: `mockup.html`, shot to `shots/r4/` (sheet `shots/r4/sheet.png`; small phone `shots/r4-small/`). Round 3 is kept as `mockup-r3.html` and `shots/r3/`. Before/after: `shots/before-after/`. Scores and declined asks: `CRITIQUE.md`. History row appended to `~/.app-designer/history.md`.

Content changes made during critique: Needs you now has 3 items (the third is architect's failed diagram export, with Retry), so Today says "3 need you" and Work and Chats show 3. The live timer advances with the clock (4:12 at 7:42, 5:12 at 7:43, 7:12 at 7:45, 8:12 at 7:46), and ops' run moves through its five steps across the screens.

Round 4 also added the one-card system (`morph.html`: seven cards and four storyboards, including the nested chain m10 and card-to-screen m11; scan: no FAILs at both sizes). Built by `build_morph.py`, `build_morph_nested.py` and `build_morph_cowork.py` from `mockup.html`; m12 to m14 add the CoWork OS ideas (approval with scope, Scheduled routines, new routine paused). Implementation spec: `SPEC.md`.

Round 4 (owner: "02 and 05 too terminal like"): the live window became the work in words and one picture, light, with the raw commands one tap away; Geist Mono is gone from the interface; the live tile and Work's running row show a step bar instead of tiny terminal lines; Chats gained search, new chat, the Open WebUI logo and more rows.

**Keep list, checked against the mockups:**
- [x] Six bots with faces (strip on Today, rows on Chats); idle and working clips play in the strip and the chat header
- [x] Start a task to any bot: Today's input with attach, recipient chip, mic; each chat has the model chip, attach, mic and voice
- [x] Needs you: review, approval and a failed run, on Today and Work
- [x] Running runs with the live window (Bot Screen) and Take over
- [x] Recent chats by bot with unread counts; Work and Chats counts in the dock
- [x] Scheduled agents and Kanban one level down (Work)
- [x] Inline run UI at its fixed scale (02, 03)
- [x] A2UI DraftReview in its own structure (03)
- [x] Open WebUI and direct chats (Chats)
- [ ] Settings in You: not designed in this pass

**Decisions (owner, 2026-10-30):**
1. **Three tabs: Today, Chats, You.** Work folds into Today. Today's sheet carries Needs you, Running, then quiet links to Scheduled and Kanban; recent bot results live in Chats (by bot) and in Today's Overnight/Earlier log. The Work tab, its dock item and its badge go away; the mockups' four-item dock becomes three.
2. **Amber everywhere**, including the app icon (the sky icon, no orange).
3. **Geist bundled** as the app font (OFL), tabular figures for numbers.
4. **Sky data from Open-Meteo**, no key: called from the app for Toronto, cached for an hour, sunrise/sunset from the same call; offline, the sky follows the clock only.
