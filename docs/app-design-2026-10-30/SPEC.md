# Conduit redesign: implementation spec

## Ownership and context

- **Owner:** Kamran (product owner, sole user). Design and spec: Claude, 2026-10-30.
- **Status:** ready for engineering, phase by phase. Each phase ships to the S25 before the next starts.
- **Source of truth:** `DIRECTION.md` (tokens, sky, content, the one-card rules, owner decisions). Screens: `mockup.html` → `shots/r4/`, and `morph.html` → `shots/morph/` (m01–m14). When this spec and a mockup disagree, the mockup shows the look and this spec shows the behaviour; flag the conflict instead of picking one.
- **Branch:** `feat/manga-redesign` (the name predates the change of direction; the manga look is being retired).
- **References** (ideas, not looks): KaizenOS v2 and its Morphlet cards, Hark (living sky, visible agent window), CoWork OS at coworkosapp.com (visible, approvable runs; routines with scope).

## Problem and user need

Conduit is the owner's phone window onto six Hermes bots on his Umbrel, plus Open WebUI and direct models. Today the app is a Material list app with a manga skin on some tabs. Opening it does not answer the first question of the day: *what happened, and what needs me?* Starting a task takes several taps. And menus, dialogs and sheets pop up as separate layers, which the owner reads as broken (his KaizenOS rule).

The redesign makes the first screen answer that question in one sentence, keeps starting a task one tap away, shows a working bot as plain words and a picture instead of a terminal, and makes every menu, form and confirm a single card that grows out of what was pressed.

## Design approach

- **Constraints:** Flutter on Android (S25 Ultra, One UI, gesture navigation); Hermes APIs as they are today; the app must work on a slow or broken link to the Umbrel; the inline run UI and its type scale are fixed (14/600 line, 13.5/400 rows, 12 meta); bot faces and video avatars stay; A2UI/OpenUI surfaces keep their own structure.
- **Strategy:** build the foundations once (tokens, Geist, the one-card widget), then replace screens in the order the owner uses them: Today, the live window, Chats, then every remaining overlay.
- **Not done, on purpose:**
  - No Work tab (owner decision): its content lives on Today.
  - No terminal as the default live view: the raw log is one tap away.
  - No mono font in the interface.
  - No second accent colour.
  - No pop-up layered over a card.
  - No analytics service.
  - The You tab and settings are not redesigned in this pass. They take the tokens only.

## Ethical review

Checked against the Intent catalogue:
- **Destructive defaults, sneaking or confirmshaming:** none.
  - Sending email always goes through Review (m03).
  - Publishing and spending go through an approval card that states the consequence, the scope and the undo (m12).
  - "Approve once" never silently becomes "always".
- **Closing a card never acts:** dismissing is never consent.
- **Attention bait:** badges are real unread counts, cleared when read.
- **Opt-out burden:** new routines start paused (m14), so nothing new runs until the owner turns it on.
- **Privacy:**
  - The sky calls Open-Meteo with fixed Toronto coordinates, never the device's location.
  - No prompts, files or results leave the Umbrel except through the model providers the owner configured.
  - No telemetry is added.
- **Undisclosed AI decisions:** every bot action shows in its run, and approvals stay in the run as "Approved by you · 7:44" or "Denied by you · 7:44".

**Clearance:** the design was reviewed against the catalogue and uses no deceptive, coercive or manipulative patterns.

## Measurement

This is a one-person app, so measure by the owner's use, not analytics.
- **Primary signal:** time from opening the app to acting on the first "needs you" item. Checked by stopwatch on device at the end of phases 2 and 7, before and after.
- **Counter-signal:** no missed approvals. Every Needs you item must be reachable from Today without scrolling past the fold on the S25 (up to 3 items; more collapse to "3 of 7 · See all").
- **Instrumentation:** none shipped. `CONDUIT_DIAG` builds log morph timings and the one-card view stack for device proof only.

---

## Phases

Each phase lists its intent, its scope (existing code first), its acceptance criteria, **one regression test per real rule** (no more), and the device proof on the S25.

### Phase 0: Foundations

**Intent:** every later screen reads its colour, type and motion from one place, so the redesign cannot drift screen by screen.

**Scope:**
- **Colour tokens** in `lib/shared/theme/color_tokens.dart`, with matching ThemeData in `app_theme.dart` and `theme_extensions.dart`. The full table is in DIRECTION.md:
  - `ground` `#F7F7F7` / `#0B0C0E`
  - `raised` `#FFFFFF` / `#16181C`
  - `soft` `#F1F2F4` / `#22252B`
  - `ink` `#0E1116` / `#F2F3F5`
  - `ink-2` `#5A606B` / `#A3A8B2`
  - `ink-3` `#6B717B` / `#8F95A0`
  - `rule` `#E6E7EA` / `#272A30`
  - `live` `#FFB020`, with `live-text` `#8A5A00` / `#FFB020`
  - `neg` `#C2362B` / `#FF7A6E`
  - `dock`, reversed per theme
- **Remove orange** and any other accent from the Hermes surfaces.
- **Geist** bundled in `pubspec.yaml` with static weights 400/500/600/700 (OFL; licence file in `assets/fonts/`). Numbers use `FontFeature.tabularFigures()`.
- **Type steps:** 40/600 display, 30/600 title, 17 answer, 15 row title, 13/12 meta, 11 badges. The inline run scale stays as it is.
- **Motion:** add the one-card springs to `lib/features/hermes/motion/hermez_motion_tokens.dart`, authored at Morphlet × 0.885 so that, with `HermezMotion.appSpeed` (1.265), they land on KaizenOS's speed:

  | Spring | Response (s) | Damping |
  |---|---|---|
  | open | 0.44 | 0.86 |
  | close | 0.31 | 1.0 |
  | reshape | 0.40 | 0.86 |
  | content | 0.27 | 1.0 |
  | press-in | 0.14 | 1.0 |

  Convert with stiffness = (2π / response)² and damping = 4π · ratio / response, at mass 1.
- **App icon:** the adaptive icon (dawn sky, skyline in the safe zone) and the themed monochrome layer, from `shots/r4/09-icon.png` and `10-icon-themed.png`. The splash keeps white and black.

**Acceptance:**
- Light and dark themes build from the tokens alone.
- No orange remains in `lib/features/hermes`.
- Geist renders at 13 and 40 on the S25.

**Regression test (rule: text tokens are readable on their grounds):** `ink`, `ink-2` and `ink-3` on `ground`, `raised` and `soft`, and `live-text` on `raised`, are each ≥ 4.5:1 in both themes.

**Device proof:** screenshots of one Hermes screen in light, dark and the largest font size.

### Phase 1: Shell (three tabs)

**Intent:** the dock carries only places the owner goes daily. Work's job (what needs me, what is running) is Today's job now.

**Scope:**
- `lib/features/hermes/views/hermes_tab_shell.dart`: the pages become `TodayPage`, `ChatsPage` and `ProfilePage`.
  - `HermesWorkPage` and `HermesHomePage` content folds into Today.
  - `MangaPickTab` is retired when Chats lands (Phase 4). The `lib/features/hermes/manga/` code is removed in its own commit after Phase 4 is on the device.
- `lib/features/hermes/widgets/hermes_tab_dock.dart`: three items (Today, Chats, You).
  - It is reversed: ink on light, light on dark.
  - The selected tab gets the M3 active indicator, a 64×32 pill.
  - Labels are 12 sp. The Chats badge is the unread count.
  - The Today icon follows the sky: sun by day, moon by night.

**Acceptance:**
- Back on Chats or You returns to Today, then leaves the app (existing behaviour, kept).
- The `_lastHermesTab` memory still works.
- Deep links that opened Work land on Today, scrolled to Needs you.

**Regression test (rule: Back returns to Today before leaving):** from Chats, a system Back selects Today and does not pop the route.

**Device proof:** a recording of switching tabs and pressing Back on the S25.

### Phase 2: Today

**Intent:** answer "what happened, and what needs me?" in one sentence, keep the team visible, and keep starting a task one tap away.

**Scope and behaviour:**
- **The sky:**
  - `SkyState` is a pure function of (now, sunrise, sunset, dark mode, weather). It returns dawn, day, dusk or night, plus a weather modifier (clear, overcast, rain, snow), using the gradients in DIRECTION.md.
  - Dark mode always returns dusk or night, whichever is nearer.
  - The skyline is a vector path, lit windows only at dusk and night, with a 600 ms crossfade on state change.
  - The data comes from an Open-Meteo client: Toronto 43.65, −79.38, one request per hour cached on the device. It returns current weather code, temperature, sunrise and sunset. With no network, the sky follows the clock alone and the weather text is hidden.
- **The top line:** date, Toronto, then "4° clear · sunrise 7:51". In the evening it reads "6° light rain · dark since 6:31".
- **The headline:** two sentences, from a pure function of counts. See the copy matrix.
- **The bots strip:** the six faces scroll horizontally.
  - A working bot becomes a wide live tile: its task in words, a step bar (done = ink, current = amber, rest = rule) and a ticking `m:ss` timer.
  - Quiet bots are dimmed.
  - The line under the strip names what the working bot is doing.
  - Tapping a live tile opens the live window (Phase 3). Tapping a face opens that bot's chat.
- **Ask the team:**
  - A solid pill: attach (+), text, a recipient chip ("Chief ▾", which opens the recipient card, m01–m02), and the mic.
  - Sending starts a chat with the chosen bot or model.
- **The sheet:**
  - **Needs you:** up to 3 rows (face, title, "bot · reason", one action: Review, Approve or Retry). With more than 3, a "See all" row shows the remaining count.
  - **Running:** one row per working bot, with the step bar.
  - **Overnight/Earlier:** a log of results with times.
  - **Tomorrow:** the first calendar item, if any.
  - **Quiet links:** "Scheduled · 10 on" (the routines card, m13) and "Kanban · 15 tasks".
- **Data:**
  - `hermes_unread_providers.dart` and existing session providers.
  - Needs you comes from runs awaiting review or approval, plus failed runs.
  - Running comes from active runs.

**States:**

| State | Headline | Strip | Sheet |
|---|---|---|---|
| Morning, busy (r4 01) | "11 done overnight. 3 need you." | ops live | Needs you, then Overnight |
| Evening, dark (r4 07) | "23 done today. 1 still needs you." | hermuse live | Needs you, Tomorrow, Umbrel line |
| Quiet (r4 08) | "Quiet night. Nothing needs you." | all quiet | Earlier, Tomorrow |
| Hermes unreachable | "Can't reach the Umbrel." / "Last seen 7:12." | faces greyed | the last known items, marked "as of 7:12", with Retry |
| First run, no bots | "No bots yet." / "Connect Hermes to start." | none | one action: Connect |

**Acceptance:**
- All five states render in light, dark, at 375 dp wide and at the largest font.
- Three Needs you items sit above the fold on the S25.
- The sky matches the time of day on the device.

**Regression test (rule: dark mode never shows a daytime sky):** for every hour of a day, `SkyState(dark: true)` returns dusk or night.

**Device proof:** screenshots at 7:40, 13:00, 18:50 and 02:00 (with the device clock set), plus one with the phone in airplane mode.

### Phase 3: The live window

**Intent:** show what a bot is doing in words and one picture, so watching it needs no reading of logs. The commands stay available for when the owner wants them.

**Scope:**
- **Opening:** a live tile or Running row opens the window as a growing route, using the existing `HermezRouteMotion.expand` with a `HermezMorphOrigin` from the tile. Back folds it into the tile.
- **Header:** a sky band with back, the face, "Working · 5:12", and Take over.
  - Take over opens the confirm card (m06).
  - Confirming grows the card into `HermesBotScreenView`, the existing noVNC Bot Screen with its control lease.
- **Body:**
  - A sentence about the outcome (30/600) and a line of context.
  - The window, with an amber frame while working.
  - The steps, in the inline run UI.
  - "Show the N commands ops ran ›", which opens the raw log as a nested view of the same route.
- **What fills the window, in order:**
  1. The bot's own A2UI surface for the task, rendered with the existing surface renderer (the alert path in r4 02 is an example).
  2. Its Bot Screen or Steel browser, when the bot is using one (`HermesBotScreenView` / `HermesSteelLiveView`, watch-only).
  3. Otherwise, the current `HermesActivityPresenter` row as the sentence, with the step bar.

  It is never the raw terminal by default.
- **Done state:** the frame turns from amber to `rule`, the sentence becomes the result ("Alerts are reaching your S25 again."), and an artifact card (Open) sits above a composer whose placeholder reads "Ask for a revision…".

**Acceptance:**
- All three content sources render.
- Take over and leaving it hand the lease back, as today.
- Back from the Bot Screen returns to the live window, then the tile.

**Regression test (rule: the terminal is never the default):** the content selector returns A2UI, then Screen, then Activity, by availability, and never the raw log.

**Device proof:** a recording of tile → window → Take over → back, on a real ops run.

### Phase 4: Chats

**Intent:** one list of every conversation, team first, with the working bot visible. It replaces the Manga Pick screen.

**Scope:**
- **Header:** a sky band with the title, "6 bots · N unread" and the new-chat pencil (opens the New chat card, m07).
- **Search:** "Search chats" filters bots and conversations by name and last message.
- **Your team:** one row per bot, unread first.
  - A working bot's face carries an amber ring, with its live timer on the right.
  - Unread rows have a weight-650 title and an ink count badge.
- **Open WebUI and direct:** conversations with the Open WebUI logo (`assets/icons/open_webui.png`) or a plug glyph for direct endpoints, and "Model · source" underneath.
- **Times** use tabular Geist. Today's show the time, this week's the day, older ones the date.

**Acceptance:**
- An unread count clears when the chat is opened.
- Search finds both kinds of row.
- The list scrolls under the dock with the fade.

**Regression test (rule: a search covers bots and Open WebUI chats alike):** a query matching one bot row and one Open WebUI row returns both.

**Device proof:** screenshots: list, search, new chat.

### Phase 5: The one card

**Intent:** every menu, form, picker and confirm is one card that grows out of the control that was pressed, reshapes in place for nested steps, and folds back carrying the result.

**Scope:**
- **`MorphCard`, built on `pushHermezSheet` and `HermezMorphOrigin`** (`lib/features/hermes/motion/`). Add:
  - **Shape:** a floating card inset 16 from the sides and 16 above the gesture area, radius 32, the `raised` fill, one shadow (0, 18, 48 at 24% ink) and a 34% scrim. It rides above the keyboard, and dragging down closes it.
  - **The trigger is the card:** the source control is hidden while open.
    - Open: frame, radius and fill spring from the source rect.
    - The source's face hands over to the card's content (the existing handover), and text never scales.
    - Press-in 0.94 with a light haptic.
  - **A view stack inside the card** (push, pop, replace), not the Navigator. Each push:
    - springs the card's size on the reshape spring, slides the content 8 dp and crossfades it on the content spring;
    - insets the card 20 dp a side at odd depths and returns it to full width at even depths, so every step changes shape;
    - shows ‹ in the header, while × closes the whole card.
  - **Parent views stay mounted:** typed input survives.
  - **Fold-back:** closing returns a result, and the source control rebuilds with the new value before the card lands in it.
  - **Grow to screen:** a view can turn the card into a full route (Start chat, Take over, open an artifact). The card's rect springs to the screen and the route's content takes over. Back folds the screen into wherever its result now lives.
  - **The dock or composer steps out of view** while a card is open.
  - **Reduced motion:** a 150 ms crossfade with no scale or travel.
- **Cards to ship in this phase:** recipient (m01–m02), review and edit draft (m03–m04), model and reasoning (m05), take over (m06), new chat with attach and Umbrel files (m07, m10), and start chat growing into a chat (m11).

**Acceptance:**
- At every step of the m10 chain there is exactly one card in the tree and no new route.
- Size visibly springs at each step.
- Typed text survives push and pop.
- × from depth 2 folds into the original trigger.

**Regression test (rule: nothing opened from a card opens anything new):** open New chat, type a message, push Attach, then Umbrel files. Assert one `MorphCard` and an unchanged route count at each step. Pop twice and assert the typed message is intact.

**Device proof:** a frame-by-frame recording (60 fps) of the m10 chain and the m08 round trip on the S25, with card count and size logged by `CONDUIT_DIAG`.

### Phase 6: Moving every overlay onto the card

**Intent:** no surface in the app still pops a separate layer.

**Inventory** (from `lib/`, 2026-10-30):

| Kind | Uses | Files |
|---|---|---|
| `AlertDialog` | 29 | 10 |
| `PopupMenuButton` | 26 | 14 |
| `showCupertino*` | 9 | 4 |
| `showDialog` | 6 | 4 |
| `showModalBottomSheet` | 6 | 3 |
| `DropdownButton` | 6 | 6 |
| `pushHermezSheet` (move to `MorphCard`) | 25 | 18 |

Each becomes a `MorphCard`: confirms become a confirm view, popup menus a menu view anchored to their button, and dropdowns a select view that grows from its field and folds back with the value.

**Order:**
1. Hermes surfaces first: the Needs you actions, chat menus, the attach menu, scheduled and Kanban forms, artifact actions.
2. Then shared and settings surfaces.

**Acceptance:** the inventory reaches zero outside an allowlist (system share sheets, OS permission prompts, file pickers, all of them platform-owned).

**Regression test (rule: no new pop-up layers):** a test fails when `showDialog`, `showModalBottomSheet`, `PopupMenuButton`, `DropdownButton` or `AlertDialog` appears under `lib/` outside the allowlist file.

**Device proof:** a pass through every migrated surface on the S25, with a written list of each surface checked.

### Phase 7: Approvals and routines (from CoWork OS)

**Intent:** an approval says what will happen, where, and how to undo it, and stays in the record. Scheduled work is a list of routines the owner can read at a glance, and nothing new runs until he turns it on.

**Scope:**
- **Approval card (m12):**
  - It grows from the Approve pill.
  - It shows a plain sentence of the consequence, then label and value pairs (Store, Replaces, Checked, Undo).
  - The buttons are Deny and Approve once.
  - The run records "Approved by you · 7:44" or "Denied by you · 7:44" as a step.
- **Scheduled (m13):**
  - It grows from Today's "Scheduled" link and shows "10 on · 1 needs you · 1 paused".
  - Each row shows face, name, "trigger · bot", and a status: Running (amber), Needs you (ink pill), On (soft pill) or Paused (outline).
  - "Schedule something" pushes the New routine view.
- **New routine (m14):**
  - Fields: What, Who (select), When (select), and "What [bot] may do": Observe / Propose / Act, defaulting to Propose.
  - The button reads "Save, paused".
- **Data:** the existing scheduled-agent code (`lib/features/hermes/sheets/hermes_scheduled_agent_sheet.dart`, `hermes_jobs_page.dart`).

**Acceptance:**
- An approval shows its scope before it acts.
- The record shows who approved and when.
- A new routine is saved paused.

**Regression test (rule: a new routine never starts running on save):** saving the New routine form produces a routine whose enabled flag is false.

**Device proof:** approve a real kai theme publish on a test store, or a dry-run equivalent, then show the run record.

---

## Use cases

1. **7:42, three things need him.** He opens Conduit and reads "11 done overnight. 3 need you." He taps Review on the Jordan draft. The pill becomes the draft card, he presses Send, and the card turns into a check, folds into the row ("Sent 7:43") and the headline drops to 2.
2. **ops is fixing the push server.** He taps the live tile and the window grows from it. The sentence says a test alert is on its way. He watches the alert path finish, presses Back, and the window folds into the tile, now showing step 5 of 5.
3. **He wants to take over.** In the live window he taps Take over. The button becomes the confirm card, which says ops stops where it is. He confirms, the card grows into ops' desktop, and leaving hands it back.
4. **A file from the Umbrel.** In New chat he types, taps +, and the card narrows into Attach, then widens into Umbrel files. He picks `sourdough.pdf` and pops back with the file attached and the text still there. Start chat grows the card into the chat.
5. **Offline on the subway.** Today shows "Can't reach the Umbrel. Last seen 7:12." The sky follows the clock, and the items shown are marked "as of 7:12" with Retry.
6. **Seven things need him.** Three rows show, then "4 more · See all", which opens the full list as a card.
7. **A routine asks for something.** "Support reply drafts" shows Needs you. The approval card says what Chief would send and to whom. He picks Deny, and the run records it.

## Copy matrix

| Element | Primary | Edge cases |
|---|---|---|
| Today headline, morning | "11 done overnight." / "3 need you." | 1: "1 needs you." · 0: "Nothing needs you." · 0 done: "Quiet night." |
| Today headline, day/evening | "23 done today." / "1 still needs you." | 0 needs: "Nothing needs you." |
| Unreachable | "Can't reach the Umbrel." / "Last seen 7:12." | never seen: "Connect Hermes to start." |
| Live tile caption | "ops is restarting the push server. Tap to watch." | finished: "ops fixed the push server at 7:48." |
| Live window sentence | the bot's current outcome, in words | none: the current activity row ("Searching the web for Flutter springs") |
| Commands link | "Show the 6 commands ops ran" | 1: "Show the command ops ran" · 0: hidden |
| Take over confirm | "Take over ops' screen?" / "ops stops where it is: it was [step]. Your taps and typing go to its desktop until you hand it back." | Keep watching · Take over |
| Approval | "[Action]?" / a consequence sentence / Store, Replaces, Checked, Undo | no undo: "Undo: not possible" (shown, never hidden) |
| Approval record | "Approved by you · 7:44" | "Denied by you · 7:44" |
| Needs you overflow | "4 more · See all" | none |
| New routine note | "Propose: [bot] reports and drafts; you approve before anything changes. It starts paused." | Observe: "[bot] only reports." · Act: "[bot] acts within this routine and tells you after." |
| Chats subtitle | "6 bots · 3 unread" | 0 unread: "6 bots" |
| Search empty | "No chats match "regex"." | none |

## Backend validation (2026-10-30, read from hermes-agent source)

- **Ask/Do switch: not built.** Hermes has no per-message "answer only" mode. `prompt.submit` takes no toolsets or mode; `approvals.mode` (manual, smart, off) and `write_approval` are per bot; session `yolo` only loosens; `/plan` is a prompt, not enforced. An unenforced "Ask" would be false comfort. The You tab shows the real controls instead. Revisit if Hermes adds a per-turn tool restriction.
- **Bot Screen: confirmed.**
  - Each bot has its own headless Xfce desktop plus Chromium on Linux hosts (`display.start`, `display.observe` → `/api/display/ws`, `display.lease.acquire` and `.release`).
  - The lease fences only the bot's screen and browser tools; its terminal keeps running. The Take over copy says so (m06).
  - Conduit must call `display.status` (`supported`, `installed`, `running`) before offering the screen.
  - noVNC is loaded from a CDN today. Bundle it so the screen works offline on the LAN.
- **Routines: confirmed, with a different scope model.**
  - Endpoints: `/api/cron/jobs` (create with `paused: true`), plus pause, resume, trigger and runs.
  - Scope is an `enabled_toolsets` allowlist per job, plus `approvals.cron_mode` (deny by default), which blocks risky commands in routines. There is no Observe / Propose / Act, so m14 shows "Tools [bot] may use" instead.
  - Statuses come from `enabled`, `state` and `last_status`: Running, On, Paused, Failed.
  - Conduit must start sending `profile`, `paused` and `enabled_toolsets`.
- **Kanban: card (owner).**
  - Lanes are triage, todo, scheduled, ready, running, blocked, review, done. The card groups them: Needs you = review and blocked; Running; Up next = triage, todo, scheduled and ready; Done.
  - There are no due dates. Rows show status and age.
- **You tab (y01).** Every row maps to Hermes:
  - the `USER.md` and `MEMORY.md` built-in memory (`/api/memory` returns sizes, so reading the text needs a file read);
  - `/api/analytics/usage`;
  - approvals settings;
  - gateway channels;
  - `/api/profiles` for the bots.

## Pending questions

**Design (owner):**
- Settings beyond the You tab (y01) are not designed.
- Reading `USER.md` text over the API: confirm which endpoint serves memory file content.

**Engineering:**
- Does Hermes emit an A2UI surface for run progress (the alert path), or is that new bot-side work? Until then, the window uses sources 2 and 3.
- Does Hermes store a per-routine autonomy (Observe, Propose, Act) and an enabled flag? Phase 7 needs both.
- Geist: static weights versus the variable font. Static is simpler and enough.
- The live timer's source of truth: the run's start time from Hermes, not a local counter, so it survives app restarts.

## Assets

- **Screens:**
  - `shots/r4/` (01–08, icon 09–10);
  - `shots/morph/` (m01–m14 and the storyboards);
  - `shots/before-after/`.
- **Sources:** `mockup.html`, `morph.html` (built by `build_morph.py`, then `build_morph_nested.py`, then `build_morph_cowork.py`) and `DIRECTION.md`.
- **Faces:** `assets/*-cut.png` here. The app already ships its own bot images.
- **Logos and fonts:**
  - The Open WebUI logo comes from the app's `assets/icons/open_webui.png`.
  - Geist comes from vercel/geist-font (OFL) and goes into `assets/fonts/`.
