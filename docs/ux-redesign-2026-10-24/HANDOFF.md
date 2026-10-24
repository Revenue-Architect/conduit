# Conduit UX redesign: handoff brief (2026-10-24, build 222)

This brief is for a fresh session with no context. It covers:
- what was built and why
- where it lives
- how to build, test and check it on the owner's phone
- what is verified and what is not
- what to do next

Read it fully before touching anything.

## 1. What this is

**Conduit** is the owner's Flutter chat app (Android, Samsung S25). It talks to **Hermes**, a self-hosted agent server in a Docker container on the owner's Umbrel box.

In October 2026 the owner asked for a UX redesign inspired by Muse and Grok Bot. They wanted:
- conversation first
- delegated work and every other inline element folded seamlessly into the chat, with no standalone cards
- a redesigned Home

They gave a ChatGPT-written package as reference, which is unpacked at `C:\Users\Kamran\AppData\Local\Temp\claude\C--Users-Kamran\85935346-96e1-4479-9733-5f15baf620d7\scratchpad\uxpkg\Conduit_Claude_UX_Implementation_Package\`. Their own judgment overrides it.

The rationale and every owner decision are in `docs/ux-redesign-2026-10-24/STRATEGY.md` (sections 8b and 8c in particular).

### The owner's standing design rules

The owner stated these in this session. They are saved in Claude memory as `conduit-inline-chat-ux.md`, `conduit-theme-modes.md` and `kaizenos-v2-design-language.md`.

**Inside a chat:**
- No cards. Every inline element (thinking, run activity, tools, delegation, approvals, questions, plan, files, errors, run details) uses the "thread branch" language: a thin rail, a turning chevron, and details that unfold in place.
- A2UI and OpenUI generated surfaces are the only exception. They keep their own rendering.
- No sheets pop up from inside a chat. The model picker is the one exception.
- When a run or its thinking ends, its line folds closed. It never disappears.
- Use the accent colour (signal orange `#FF5A26` / red variant) on inline elements, so the chat isn't all black, white and grey.
- A live browsing run shows the watch-only Steel browser automatically.
- A turn's plan (bars and steps) shows under the turn's line, not inside "Full run details".

**Theme:**
- Light mode is near-white `#FDFDFD`. A2UI and OpenUI panels sit on that canvas with only the border token around them.
- Charcoal is the dark mode's canvas only.
- The dock and navigation are drawn in the opposite theme ("reversed").
- Keep the Hermez identity: accent, anime bot avatars, technical uppercase labels, physical motion.
- Design rules may be bent when it is clearly better, but say which rule was bent and why.

**Navigation (phones):**
- Use only one navigation: the floating bottom dock (Home, Chats, Work, You). No drawer.
- **Home** is the hub (Team, Work, Decisions, Hermes). Its top bar is the masthead: "Conduit" with the construction-mark art, plus the working-bots stack and a **+** at the top right.
- **Work** holds Needs you, the conversation inbox, later today and the away digest.
- Back from a chat returns to the tab it was opened from.

**Design method:** Apple's design principle #1, Purpose (decide what not to build). Prefer unboxed, calm and alive.

## 2. Where the code is

| What | Where |
|---|---|
| Worktree | `C:\Users\Kamran\Documents\Codex\2026-09-17\umbrel-ui-bootstrap\work\conduit-push-recovery-20261020` |
| Branch | `fix/restore-unifiedpush-20261020`. Local only, never pushed, and the phone builds come from it. |
| Public repo | `https://github.com/Revenue-Architect/conduit`. Its `main` does not contain any of this work. |
| Toolchain | `C:\Users\Kamran\Documents\Codex\2026-09-17\umbrel-ui-bootstrap\work\toolchain\` (flutter, jdk-17.0.20.1+1, android-sdk, gradle-home, pub-cache) |
| Steel viewer define | `C:\Users\Kamran\Documents\Codex\2026-09-17\umbrel-ui-bootstrap\work\private-build-defines.txt` (the `HERMES_STEEL_VIEWER_URL=` line; not a secret, but keep it out of git) |

Commits from this session, oldest first. None are pushed.

| Commit | What it did |
|---|---|
| `9ee40ebf` | Profile-routed delegations shown cleanly |
| `ba422861` | Footer test harness seeds the open chat |
| `d85416f7` | Near-white canvas; A2UI/OpenUI panels on canvas (`hermezGenerativeTheme`) |
| `6db9915d` | One bottom dock, hub Home, Work inbox |
| `bacea16c` | Run activity folded into the conversation, no sheets |
| `285bf7db` | Strategy doc |
| `65b6d5e4` | QA fixes: auto browser, plan under the line, accent, open state per turn, avatar fix, composer padding |

Line endings: the repo has `core.autocrlf=true`, so working files are mostly CRLF while git stores LF. Two traps:
- Git Bash `grep`, `od` and `sed` can hide the `\r`.
- A perl edit must normalise first: `perl -0777 -pe 's/\r\n/\n/g' f | perl script | perl -0777 -pe 's/\n/\r\n/g'`.

The Edit tool handles CRLF fine. Never run `dart format` on a whole folder: it reformats unrelated files. Format only the files you touched.

## 3. Map of the redesign (key files)

All paths are relative to the worktree root.

### Chat: one activity line per answer

**`lib/features/hermes/widgets/hermes_run_activity_orb.dart`** is the heart of the inline UX.

`HermesMessageActivity` computes the whole turn with `hermesTurnSpanKey`:
- A turn runs from the owner's prompt to the next prompt, across Hermes' hidden `[ASYNC DELEGATION …]` user wake-ups.
- Later rows of the same turn render nothing (`leadsElsewhere`).
- The turn wraps its line in `HermezReveal`, so it rolls away rather than popping out.

It feeds:
- `thought`: `hermesThoughtLines`, from `reasoning` statuses
- `meta`: model · time · steps
- `browser`: the Steel section, while running and after a browser tool ran
- `plan`: `HermesInlinePlan`, when the turn used `todo` / `todo_list`; it reads `service.agenticStateFor`, with no fetch
- the provider-wait label (`hermesProviderWaitLabel`, "gpt-6-luna is slow to reply")

`HermesRunActivityOrb` draws:
- the face: `ThinkingOrb` + label, with `HermezShimmerText` while running, accent colour, and an `AnimatedSwitcher` rise
- the plan and browser under the face (always visible)
- the folded `_RunSteps`: meta, `_StepLine`s, then `_FullRunDetails`

Open state is kept per turn in the top-level sets `_hermesOpenRuns`, `_hermesOpenDetails` and `_hermesRanTurns`, keyed `sessionId:firstMessageId`. This is needed because the chat page remounts rows while a turn streams. A turn seen running is folded when it settles. Tests must call `resetHermesOpenRuns()` in `setUp`.

`_StepLine`:
- fades in once
- shimmers while running
- an inspectable tool step unfolds `HermesToolInspectorInline` in place

`_FullRunDetails` unfolds `HermesLiveRunPage(inline: true)` in place.

**`lib/features/hermes/views/hermes_live_run_page.dart`** is the run details. With `inline: true` it has:
- no chrome, headline or completion sheet
- the hero reduced to nothing (the plan moved under the line)
- the timeline without its thinking panel and without inspector sheets
- pending questions answered inline (`HermesAttentionResolutionInline`)

It also defines `HermesInlinePlan`, a preview that unfolds the full plan (`HermesPlanInline`). The sheet form still exists for routes outside chat.

### Sheets with inline modes

Each sheet still opens as a sheet elsewhere; the inline mode is what chat uses.

| File | Inline widget / mode |
|---|---|
| `lib/features/hermes/sheets/hermes_tool_inspector_sheet.dart` | `HermesToolInspectorInline`; `hermesReadableToolText` strips Hermes' untrusted-content notice and unpacks JSON |
| `lib/features/hermes/sheets/hermes_attention_resolution_sheet.dart` | `HermesAttentionResolutionInline` (answer controls only) |
| `lib/features/hermes/sheets/hermes_plan_sheet.dart` | `HermesPlanInline`, via a `_frame` helper |

### Other chat pieces

| File | What it does |
|---|---|
| `lib/features/hermes/widgets/hermes_chat_context_bar.dart` | Pills above the composer. Plan and delegates unfold a tray above the row; the pill inverts to ink while open. |
| `lib/features/hermes/widgets/hermes_inline_delegation.dart`, `hermes_delegated_worker_card.dart` | Delegation thread branch: accent rail, accent name, shimmering state |
| `lib/features/hermes/widgets/hermes_steel_live_view.dart` | `HermesRunBrowserSection(initiallyOpen:)`: "Watch the browser" line, player, full-screen button |
| `lib/features/hermes/widgets/hermez_live.dart` | `HermezShimmerText`; plan bar and todo glyph in accent |
| `lib/features/hermes/services/hermes_message_mapper.dart` | Maps saved `reasoning` into a `reasoning` status. The restored running placeholder carries Hermes transport metadata (fixes the Desktop avatar showing for "Chief"). |
| `lib/features/hermes/services/hermes_desktop_event_projection.dart`, `hermes_run_transport.dart`, `models/hermes_run_event.dart` | `thinking.delta` "⏳ waiting on …" becomes `HermesProviderWait`, then a hidden `hermes_provider_wait` status |
| `lib/features/chat/providers/chat_providers.dart` | Coalesces `reasoning` and `hermes_provider_wait` statuses in place |
| `lib/features/chat/views/chat_page.dart` | Back arrow on docked phones; Android composer bottom inset (gesture bar plus 8 dp) |

### Navigation and Home

| File | What it does |
|---|---|
| `lib/features/hermes/views/hermes_tab_shell.dart`, `widgets/hermes_tab_dock.dart` | Dock and tabs. `_lastHermesTab` remembers the last tab. |
| `lib/features/hermes/views/hermes_work_page.dart` | The hub. Titled "Conduit" with `brandHeader: true` when docked. |
| `lib/features/hermes/views/hermes_home_page.dart` | The inbox. Titled "Work" when docked; on tablets it's still the first page. |
| `lib/features/hermes/views/hermes_page_chrome.dart` | `brandHeader` masthead mode |
| `lib/features/navigation/widgets/drawer_shell_page.dart` | `hermesPhoneUsesDock` |
| `lib/core/router/app_router.dart` | `?tab=` |

### Theme

| File | What it does |
|---|---|
| `lib/shared/theme/tweakcn_themes.dart` | `lightCanvas` `#FDFDFD`; `lightSurface` `#F5F5F6` for other fills |
| `lib/features/hermes/widgets/hermez_visual_theme.dart` | `hermezGenerativeTheme` for A2UI/OpenUI |

### Tests added or changed

- `test/features/hermes/hermes_run_inline_details_test.dart`
- `hermes_unified_run_activity_test.dart`
- home, work and dock tests

## 4. Build, install, test

**Memory is tight on this PC.** Builds and test runs crash with "Out of memory" below about 3.4 GB free.
- Before a build, kill stale Gradle daemons, and kill them again after.
- Never run tests and a build at the same time.

Kill stale Gradle daemons (PowerShell):
```powershell
Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'java.exe' -and $_.CommandLine -match 'umbrel-ui-bootstrap' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
```

Build (Git Bash, from the worktree). Increase the build number each time; the last one was **222**:
```bash
T=$(cygpath -w ../toolchain) && export PUB_CACHE="$T\\pub-cache" JAVA_HOME="$T\\jdk-17.0.20.1+1" ANDROID_HOME="$T\\android-sdk" ANDROID_SDK_ROOT="$T\\android-sdk" GRADLE_USER_HOME="$T\\gradle-home" && def=$(grep -o "HERMES_STEEL_VIEWER_URL=[^ ]*" ../private-build-defines.txt | head -1) && ../toolchain/flutter/bin/flutter.bat build apk --profile --build-number 223 --target-platform android-arm64 "--dart-define=$def"
```
The APK lands at `build\app\outputs\flutter-apk\app-profile.apk`. Always build `--profile`: debug APKs lag badly.

Tests. Always run sequentially (`--concurrency=1`), in two batches:
```bash
export PUB_CACHE=$(cygpath -w ../toolchain/pub-cache) && ../toolchain/flutter/bin/flutter.bat test --concurrency=1 test/features/hermes test/features/chat
```
These failures already existed before this work; leave them alone:
- `hermes_activity_presenter_test`: "store a new turn drops finished delegates…"
- `hermes_inline_run_surface_test` ×2 (that widget isn't used in chat any more)
- `direct_send_history_links_test` (OpenWebUI)
- in `test/core`: `fts_perf_test` (timing), `share_receiver_service_test` (Windows path separators), `server_incompatible_provider_test`
- `sidebar_workspace_tabs` note-date test (timezone)

The latest run: Hermes and chat had only the first four of those failing.

Analyze: `../toolchain/flutter/bin/flutter.bat analyze lib/features/hermes lib/features/chat`. It is clean apart from long-standing info lints.

## 5. The phone (wireless adb)

The owner allows driving the phone (Samsung S25) over adb even while they use it. The details are in memory as `phone-wireless-debug-allowed.md`.

| Item | Value |
|---|---|
| adb | `C:\Users\Kamran\Documents\Codex\2026-09-17\umbrel-ui-bootstrap\work\toolchain\android-sdk\platform-tools\adb.exe` |
| Serial | `adb-R5CY13VFPEP-JAeGpv._adb-tls-connect._tcp`. It can change; find it with `adb mdns services`. |
| Package | `app.cogwheel.conduit.debug`. Launch with `adb shell monkey -p app.cogwheel.conduit.debug -c android.intent.category.LAUNCHER 1`. |
| Screen | 1440×3120. Screenshot coordinates displayed at 923 px wide × **1.56** = device pixels. |

Helper script, adapted from this session (its scratchpad dies with it):
```bash
A=/c/Users/Kamran/Documents/Codex/2026-09-17/umbrel-ui-bootstrap/work/toolchain/android-sdk/platform-tools/adb.exe
S=adb-R5CY13VFPEP-JAeGpv._adb-tls-connect._tcp
a() { "$A" -s "$S" "$@"; }
focus() { a shell dumpsys window | grep -m1 mCurrentFocus; }
kb() { a shell dumpsys input_method | grep -m1 -o "mInputShown=[a-z]*"; }
shot() { a exec-out screencap -p > "$1"; }
guard() { focus | grep -q -i conduit || { echo "ABORT: focus not Conduit"; return 1; }; kb | grep -q "mInputShown=false" || { echo "ABORT: keyboard up"; return 1; }; }
```

Hard rules:
- Run `guard` before every tap or swipe. Only type while Conduit has focus.
- Never send `keyevent 4` (Back) or `keyevent 67` (Delete).
- Never swipe while the keyboard is up.
- When the owner is in another app, only install and screenshot.

Typing works with `a shell input text "Use%sthe%sbrowser..."` (`%s` is a space). With the keyboard up, Send is at about device (1267, 1630); the composer field is at about (780, 2978).

Good QA prompts:
- "Use the browser: open example.com, wait 45 seconds on the page, then open iana.org and tell me both page titles." Exercises Steel auto-show, the live line, and folding.
- "QA test: make a 3-step plan with your todo tool, then delegate to Scout asking it to reply PONG, then mark the plan done." Exercises the plan under the line, the plan tray, the delegate branch, and the async continuation.

These are QA turns, not owner decisions. Never act on real owner decisions just for QA.

## 6. Verified vs not

**Verified on the phone (builds 218–221):**
- Home masthead with art and **+**
- Work tab
- back arrow; back returns to the previous tab
- "Thought" line kept after a reload
- inline steps
- tool input and result inline (no sheet)
- full run details inline (no sheet)
- Steel browser auto-opens live and folds when the run ends
- tapping a live line unfolds it (fixed in 221)
- plan tray above the composer, pill inverts to ink
- delegate branch with accent
- accent on the working line, rail and marks
- composer clears the gesture bar
- finished label leads with the real work ("Browsed and 1 more")

**Not yet seen on the phone** (in build 222, installed but not looked at):
1. The plan (bars and steps) under the turn's line instead of in full details. Check how fast it appears after the `todo` call.
2. The "Chief" waiting row no longer showing the Hermes Desktop avatar (restored running placeholder now has Hermes metadata).
3. A turn folding when it settles, even if its row was remounted.
4. Accent on plan bars, todo checks, plan rail and timeline tool tiles.
5. Readable tool text (no untrusted notice, JSON unpacked); inline inspector without the ACTION repeat.
6. Streamed thoughts split ("**A****B**" becomes two lines); Hermes notes keep a notes icon, thoughts get a bulb.
7. Meta step count on saved turns.

**Never checked:**
- dark mode
- 200% text
- a tablet layout
- an approval or clarify question answered inline on the device (only covered by widget tests)
- the plan tray's step actions (Comment, Add after, Change, Cancel)

## 7. Known issues and open items

1. **A line opened by itself once.** During the plan+delegate QA turn, it was open after the turn finished without anyone tapping it. The cause was not found; `_hermesRanTurns` now folds any turn seen running when it settles. Watch for it, and check for pending decisions (`attention`) during async delegation.
2. **Big blank gap** under an earlier turn's line ("Browsed and 1 more") once a later turn was running. Seen once and not investigated. Suspects:
   - the Steel section's space while it detaches
   - a collapsed `HermezReveal` in that row
3. **Full run details rows are visually heavier** (bold verb plus icon tile) than the light step lines. Consider a dense or light variant of `HermesActivityRowView` for inline use.
4. **The "Hi took 5 minutes" stall** was upstream: the `openai-codex` provider kept its stream open with no output for 300 s; Hermes' watchdog killed and retried the call. Conduit now shows "gpt-6-luna is slow to reply".
   - Open owner decision: `HERMES_CODEX_TTFB_STRICT=1` (keeps the 120 s cutoff). Check which watchdog fired before changing anything.
   - A bare "Hi" is about 31k tokens of context; worth a context audit.
   - Logged in `C:\Users\Kamran\umbrel-worker-rebuild\FINDINGS-BACKLOG.md`.
5. **The near-white handoff from Hermes** asked for:
   - a fresh clone of GitHub `main`
   - a PR
   - a `v*` tag, which triggers a release build

   The colour change itself is done on this branch (`d85416f7`). Pushing, the PR and the tag were **not** done. This branch isn't on GitHub, and a tag starts a release. That needs the owner's explicit go-ahead and a decision on how this local branch reaches `main`.
6. **Scheduled task** `hermes-selftest-fixes-20261025` runs on 2026-10-25 at 09:00. It fixes the stale SOUL OpenUI self-test check and the wrapper unit tests.
7. **Reminder for the owner:** rotate the webhook route secrets that appeared in a subagent's tool output during the Hermes audit.

## 8. Hermes server (only if needed)

| Item | Detail |
|---|---|
| SSH | `ssh -o BatchMode=yes umbrel-lan "<cmd>"` (192.168.2.107). The tailnet name is `umbrel`. |
| Container | Always `docker exec -u hermes hermes-agent_web_1 …`. Never as root. |
| Data | `/opt/data` (`state.db`, `logs/agent.log`, `logs/errors.log`, `logs/gui.log`, `config.yaml`). Hermes source is in `/opt/hermes`. |
| Version | 0.22.5 with advanced delegation |
| Profiles | Chief (`default`), kai, ops, hermuse, architect, scout. Default model gpt-6-luna via `openai-codex`. |

Plugin edits load in two processes. The dashboard on `:18789` needs `kill -USR1 <pid>`, which is a restart: pick the pid by `hermes_cli.main` + `dashboard`, and get the owner's OK first. Details in memory `hermes-plugin-two-processes.md`.

Rules:
- never restart the Docker daemon
- never pause crons `ed0460e33a6a` / `24220086aad7`
- never set `approvals.cron_mode` to approve
- don't touch frozen skills
- back up before editing (`*.bak-YYYYMMDD-*`)

## 9. Working rules (owner's)

- **Subagents:** use model Sonnet 5.5 and ask for extra-high effort in the prompt.
- **Deliverables:** Markdown files, not published Artifacts, unless asked. Always give full absolute paths.
- **Findings:** log anything not right in `C:\Users\Kamran\umbrel-worker-rebuild\FINDINGS-BACKLOG.md`.
- **Clean up after work:** stop servers and background jobs, kill Gradle daemons, delete QA temp files and screenshots.
- **Approval first** for pushes, PRs, tags, releases, external messages, purchases, permission changes and production restarts. Never expose or commit credentials.
- **UI work:** the owner has UI skills (`emil-design-eng`, `apple-design`, `journey`, and `npx ui-skills`); use them. Agent-chat component libraries (for example Vercel AI Elements: Reasoning, Tool, Task, Plan, Queue) are fair references.

## 10. Suggested next steps

1. When the owner's phone is free, open build 222 and check the seven items in §6, "Not yet seen on the phone". Use the two QA prompts in §5.
2. Investigate the blank gap (§7.2) and the self-opening line (§7.1) if either recurs.
3. Run a dark mode pass (accent contrast on charcoal, reversed dock) and a 200% text pass.
4. Lighten the full-details timeline rows to match the step lines (§7.3).
5. Ask the owner how this branch should reach GitHub (§7.5) before any push.
