# Conduit redesign: direction

## Brief

The owner answered the brief on 2026-10-24. The note on "grokbot" is my reading of their word.

- **The app:** Conduit, the owner's Android client for their own team of Hermes agents running on the Umbrel. The team is six bots: Chief, kai, ops, hermuse, architect and scout. It has one user: the owner, on a Samsung S25 Ultra.
- **The first ten seconds:** start a new task, then maybe check what Chief and the others did.
- **How it should feel:** useful; "grokbot"; making my life easier.
  - I read "grokbot" as a sidekick that gets you: direct, a bit cheeky, never corporate.
  - No outside references were given.
- **Fixed, never redesigned away:**
  - the bot faces and their idle/working video avatars
  - the current orange (`#FF5A26` light / `#FF6A36` dark) and its red-orange family
  - the A2UI/OpenUI surfaces
  - the recent inline chat run UI: the turn line, the plan unfolding in place, the type scale 14/600 > 13.5/400 > 12, and the Steel player
- **Scope:** the whole app (Home, Chats, a chat with a live run, Work, bot detail, You), as mockups.
  - This skill targets iPhone. Conduit is Android, so the frames are the S25 at 412 × 892 dp, with a punch-hole camera and a gesture bar.
  - The structure follows Material 3 navigation behaviour.
- **Imagery:** the owner's own bot art (anime chibi busts, already in the app). That is the richest source available, so no paid generation is used.

## Current app

Screenshots: `before/01-home.png` to `before/08a.png` and `shots/before-*.png`, taken on the S25 (build 232, dark mode).

**What it is now:**
- a dark Material list app
- `#111215` ground, Roboto, orange as the only colour
- every screen is a list of rows with chevrons
- the bot faces appear only as 40 dp row avatars, and at the top of a chat

**Slop tells it hits:**
- **Everything is a list, so the app reads as a settings panel.** Home is two lists (TEAM · 6, then WORK) of identical rows with chevrons. "You" is a settings page, which is right; Home and Work look the same as it.
- **ALL CAPS eyebrows** on every section: TEAM · 6, WORK, DECISIONS, HERMES, NEEDS YOU · 2, CHIEF 775.
- **Tinted-square icon chips** on every row of "You".
- **The core action is hidden.** Starting a task is a 24 dp "+" in the corner of Home. The first screen shows a roster and a link directory, not the thing you came to do.
- **"What did Chief do?" has no answer on Home.** The team rows say "Used just now" / "Used 4d ago". You learn the time and nothing about the work.
- **The richness is wasted.** Six characterful portraits are reduced to 40 dp circles. Three of them (Chief, kai, ops stills) sit on white squares that show as white discs in dark mode.
- **"Start chatting"** centred on an empty black screen in a new chat.
- **Uniform rhythm:** 66 dp rows, all evenly spaced, no rest.
- **The logo test fails.** Cover "Conduit" and this could be any Material agent client.

**Inventory: keep / lose / unknown.**

| Item | Verdict |
|---|---|
| Six bots with faces, idle and working clips | keep, and make central |
| Start a task to any bot, model chip, attach, mic, voice call button | keep |
| Chats grouped by bot, with counts | keep |
| Work: Needs you (failed run, review), running and recent runs | keep |
| Scheduled agents (10 active · 15 total), Kanban (7 tasks · 0 running · 7 done), Teams, Spaces, Artifacts | keep, but one level down from Home |
| Decisions: Needs you, Approvals | keep, and raise to Home when anything is waiting |
| Hermes settings, Appearance, Chat, Audio, Notifications, Hermes Agent, Direct Connections, Open WebUI, About, Support | keep, in You |
| Inline run UI: turn line, steps, plan in place, delegate branch, Steel player, Full run details | keep exactly; restyle only the surrounding chat |
| A2UI/OpenUI surfaces in chat | keep; frame them as objects |
| Header avatar with video, name under it, working dot | keep |
| "Used 11m ago" rows | lose; replace with what the bot did |
| Floating white pill tab bar with caps labels | unknown; a decision for the owner |

**Assets harvested:** `assets/chief.png`, `kai.png`, `ops.png`, `hermuse.png`, `architect.png`, `scout.png`, pulled from the phone. The accent and theme tokens come from `lib/shared/theme/tweakcn_themes.dart`.

**Decisions for the owner:** none are made silently. Each is listed under "Decisions" at the end.

**History row for the current look:** `– | dark | grotesque | orange | none`. The bot art is used too small to count as richness.

## Exploration

The accent hue is fixed to orange by the brief. So instead of varying hue as the skill normally asks, the three directions vary ground, type, source family and richness. Ruling: the owner's fixed accent outranks the skill's rule. Cost if wrong: all three share a colour story.

The three concepts:
1. **Conduit is the character-select screen of a fighting game.** (play) Choosing who takes the task is choosing a fighter.
   - Colour-field ground, set per bot from their art.
   - Archivo Expanded Black Italic.
   - Richness: the portraits, huge.
2. **Conduit is a weekly manga chapter.** (printed; the one printed form allowed)
   - White page, black ink, orange as the spot colour.
   - Bricolage Grotesque.
   - Richness: panels holding the portraits; each bot's report is a panel.
3. **Conduit is a night-time dispatch board in a transit depot.** (place) Each bot is a line, tasks are departures.
   - Dark ground.
   - Barlow Condensed.
   - Richness: a shape language of route lines and stops.

Rendered in `explore.html`; the shots are in `shots/explore/`.

**The winner: B (the manga chapter), with two pieces from A.** The owner made the same pick, unprompted, on 2026-10-24.
- **B is the only direction that answers both first-ten-seconds jobs on one screen.** Its task box starts a task, and its panels show what each bot is doing or did. It also turns the six portraits into a cast, which no other agent client has.
- **From A, the roster strip:** six faces above the task box, choosing who gets the task.
- **From A, the pick-your-fighter screen:** it becomes the new-task screen and the signature (owner's call).

**Why the other two lost:**
- **A (character select)** is the most fun, but it shows one bot at a time. "What did the others do?" costs a swipe per bot. A full orange screen every day also turns the accent into wallpaper.
- **C (dispatch board)** is the most legible, but it is the current app with better type. The portraits shrink back to 34 dp icons, and the logo test still fails.

**History check:**

| Row | Source family | Ground | Type | Accent hue | Richness | Columns that differ |
|---|---|---|---|---|---|---|
| Jarvis (2026-10-05) | object | dark | expanded | orange | 3d-object | |
| Conduit, current look | – | dark | grotesque | orange | none | |
| **Conduit, chosen** | **printed** | **light** | **grotesque** | **orange** | **illustration** | 4 of 5 vs Jarvis; 3 of 5 vs current |

**The rollback is the owner's condition.**
- The new look ships behind a switch, "Classic layout", in You → Appearance. It defaults off while the new look is tested.
- Today's widgets stay in the tree untouched: the redesign adds new screens and does not edit the old ones.
- One switch flips back.

## The category default refused

AI chat clients (ChatGPT, Claude, Open WebUI, and Conduit today) share:
- a list of chat titles as the home screen
- a centred "How can I help?" / "Start chatting" on an empty canvas
- grey bubbles
- a model dropdown with a sparkle icon
- sidebars of history
- violet or teal for "AI"

Refused here:
- Home is the team's day, not a list of titles.
- An empty chat shows the bot and what it last did.
- No sparkle icons. The model chip is plain text.
- Chat titles live one tab down, under each bot.

## Tokens

The page is printed matter: square panels, ink borders, one spot colour.

| Role | Light | Dark | Notes |
|---|---|---|---|
| ground | `#FFFFFF` | `#0B0B0D` | the page |
| raised | `#F2F2F4` | `#18181B` | screentone panels, fields |
| ink | `#0E0E10` | `#F4F3EF` | text and panel borders |
| ink-2 | `#4A4A50` | `#B4B3AE` | secondary text, 8.6:1 / 9.4:1 |
| ink-3 | `#6C6C73` | `#8E8D88` | tertiary, 5.1:1 / 5.9:1 |
| rule | `#DCDCE0` | `#2C2C30` | hairlines inside lists |
| accent | `#FF5A26` | `#FF6A36` | fills only: the send button, the live stamp, the needs-you count |
| accent-text | `#C23A0B` | `#FF8A5E` | orange as text, 5.0:1 / 7.3:1 |
| on-accent | `#0E0E10` | `#0E0E10` | ink on orange, 6.0:1 |

**The accent's role:** "happening now or needs you": the live stamp, the send button, the needs-you count, and the live turn line. The system tint is ink: selected tab, switches and links. The orange never marks selection.

**Type:** Bricolage Grotesque, one family. It has an optical-size axis and a width axis (75 to 100).
- The display moments are 800 weight at 75% width, which is the manga lettering register.
- The text is 400 to 600 at 100% width.
- On Android it is bundled as a variable font (OFL).

| Step | Use | Size and weight | Tracking |
|---|---|---|---|
| Display | screen titles | 44 / 800, width 75 | -3% |
| Hero | the needs-you numeral, an empty-state name | 28 / 800, width 75 | -2% |
| Panel | bot names in panels | 19 / 800, width 75 | -1% |
| Body | chat answer, task box | 17 / 400 | 0 |
| Line | panel speech, turn line | 14 / 600 (speech: 500) | 0 |
| Meta | times, counts | 13 / 500 | 0 |
| Label | tab labels, stamps | 12 / 600–800 | +4% on stamps |

The inline run UI keeps its own scale inside a turn (14/600 > 13.5/400 > 12, from `conduit-inline-type-scale`). The two scales agree on 14 and 12.

**Layout:**
- page margin 14
- panel gutter 7
- spacing 4 · 7 · 12 · 16 · 24 · 40
- panels: square corners, 2.5 dp ink border (2 dp in dark)
- capsules for the task box and buttons
- avatars round, as now
- the live panel may have one slanted edge, and only that one

## Richness

The bots are the art. Six chibi portraits in one consistent hand, the owner's own assets.
- Each portrait is cut from its white square, so there are no more white discs in dark mode.
- Portraits stand in panels at bust height, cropped by the panel edge like manga figures.
- **Screentone carries meaning.** Radiating speed lines behind a bot mean it is working right now. A plain panel means it is idle. Nothing else gets tone.
- **Speech bubbles carry meaning too.** A bubble is the bot's own latest words, from its last reply or its live step. System copy never sits in a bubble.
- **Video:** the idle and working clips play inside the round header avatar and in the live panel, exactly as today. The speed lines are the still-frame fallback and the reduced-motion state.

## The signature: "pick your fighter"

On 2026-10-24 the owner sharpened the merge: from A they want the whole pick-your-fighter screen, where "the bot you pick fills the screen in a bold colour, and you give it a task from the bottom". So starting a task is A, full screen, and Today stays B.

**Where it lives:** new task (the "+" on Today and in Chats, or a tap on any face in Today's roster strip) opens **Pick**: a full-screen fighter select.
- Today's small task box stays as the **fast path**. It sends to the last bot with no extra screen.

**Pick, frame by frame:**

| Time | Frame |
|---|---|
| 0 ms | The tapped face's tile grows from its position in the roster strip into the whole screen (shared-element transition, 380 ms smooth spring). The bot's field colour floods out from the tile. |
| 380 ms | The name lands, 76 / 900 italic expanded, at the top left. The portrait sits huge, cropped by the right edge. The idle clip plays in the portrait. Light impact haptic. |
| swipe or tap another face | The field colour wipes across on a 105° diagonal (the slash), and the portraits slide past each other. Selection haptic per bot. 300 ms. |
| send | The portrait's clip switches from idle to working. The screen shrinks back into that bot's panel on Today, which now has speed lines. Medium impact haptic. |

**Reduced motion:** cross-fades replace the grow, wipe and shrink. Haptics stay.

**Pick has its own type and colour.** It is the one screen that leaves the page:
- **Type:** Archivo Black Italic at 125% width, for the name only. Everything else on Pick is Bricolage. Two families, and the second has one job.
- **Field colours:** one per bot, taken from its art. They are grounds that mean "who", not accents (color.md §7).

| Bot | Field | Deep (slash, dark mode) | Ink on field |
|---|---|---|---|
| Chief | `#E8531C` flame | `#B83A0E` | `#120B08` |
| kai | `#2F6FE4` cobalt | `#1D4BA8` | `#FFFFFF` |
| ops | `#E9E7E2` bone | `#BDB9B0` | `#0E0E10` |
| hermuse | `#C21E33` crimson | `#8A1222` | `#FFFFFF` |
| architect | `#F2A3B6` pink | `#D9798F` | `#1A0C10` |
| scout | `#5B2FA6` violet | `#3E1D7A` | `#FFFFFF` |

- The send button on Pick is ink on the light fields and white on the dark ones, never orange. Orange stays the app's "now" colour on Today, and Chief's field is already flame.
- Scout's violet is the bot's own hair, used flat, so it is not the AI-violet tell.

## Decisions for the owner

1. **Tab names.** "Home" becomes "Today". Chats, Work and You stay.
2. **Moved one level down.** Team, Scheduled agents, Kanban, Teams, Spaces and Artifacts leave Home: Team becomes the roster strip and Pick, the rest move into Work.
3. **The floating white pill tab bar becomes a flat bar on the page,** ink on paper with a hairline above. It matches the print direction.
4. **The type changes from Roboto to Bricolage Grotesque.** It adds about 190 KB to the APK.
5. **Light ground by default.** A real dark mode is designed too, and it follows the system setting.
6. **Rollback:** the "Classic layout" switch, described above.
7. **Bot colours.** Each bot gets a field colour for Pick (table above). These would become editable per bot, next to the idle and working clips.

## Content

Content is taken from the owner's real data on 2026-10-24 (the screenshots in `before/`). The clock is 20:36, Friday.

**State:**
- Chief is mid-run on `initiative-engine` (4 min, step 3 of 5, and it has delegated to scout).
- One run failed today. One note waits for review.
- ops, hermuse and architect are idle.

**Today**
- Title "Today"; meta "Fri 24 Oct · 11 runs".
- **Live panel:** Chief; stamp "ON IT · 4 MIN"; bubble "Writing next week's plan from the open threads."; caption "initiative-engine · step 3 of 5".
- **Smaller panels:**
  - kai: "Built the OpenUI greeting card." (20:08)
  - scout: "Checking the DonorPerfect API docs for Chief." (live, delegated)
- **Needs-you strip:** "2". "open-threads-research failed. The DonorPerfect note for Georgia is ready to review."
- **Roster:** Chief (selected), kai, ops, herm, arch, scout. Chief and scout have working dots.
- **Fast task box:** Chief's face, "Tell Chief what to do", send.
- **Tabs:** Today, Chats, Work, You.

**Pick (Chief)**
- Close (×) on the left; "Working · 4 min" on the right.
- Name "CHIEF"; role "Runs the team. Plans, delegates, checks the work."
- **Last done · 13m:** "Checked Umbrel health. 47 containers up, Kuma and Beszel green." Below it: "+3 more today".
- **Roster tiles:** the six bots.
- **Task box:** "Give Chief a task", with attach (+), mic and send.
- **Below the box:** "gpt-6-luna · High".

**Chat, live run (Chief)**
- **Header:** the round video avatar, with "Chief" and a working dot under it.
- **You:** "Plan next week from the open threads, then have scout check the DonorPerfect docs."
- **Turn line (live):** "Delegated and 4 more · 3m 12s".
- **Plan, unfolded in place:** "PLAN · 2 OF 4".
  - ✓ Read the 9 open threads
  - ✓ Sorted them by who they wait on
  - ◉ Drafting the week
  - ○ Review it with you
- **Branch:** scout, "Checking DonorPerfect API docs".
- **Answer so far:** "So far: 9 open threads, 3 of them waiting on you. I'm putting the DonorPerfect key first, because Georgia's import is blocked on it."
- **A2UI panel "Next week, draft":**
  - Mon: replace the DonorPerfect key
  - Tue: Georgia's import
  - Wed: close 4 stale threads
  - Buttons: "Looks right" / "Change it"
- **Task box:** "Reply to Chief"; stop.

**Chats**
- Title "Chats". A face filter with "All" selected.
- **Chief · 775:**
  - initiative-engine · Oct 24 20:23 (Working now · 16 messages)
  - Hermez client capability description (13m · 2)
  - Umbrel health · Oct 24 (13m · 8)
- **kai · 86:**
  - Begin conversation (11m · 2)
  - Hermez openui greeting (28m · 45)
- **ops · 31:**
  - Restart core-litellm after config change (4d · 6)

**Work**
- Title "Work".
- **Needs you · 2:**
  - open-threads-research: Chief · failed at step 3 of 5 · 19:41. Buttons: "Retry", "Open".
  - DonorPerfect key replacement note for Georgia: Chief · ready for review · 20:02. Button: "Review".
- **Running now:** Chief, initiative-engine, 4 min; scout, DonorPerfect API docs, 1 min.
- **Rows:**
  - Scheduled agents: 10 active · 15 total · next kai inbox sweep at 21:00
  - Kanban: 7 tasks · 7 done
  - Spaces
  - Artifacts
  - Teams
