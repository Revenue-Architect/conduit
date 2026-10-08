# Hermez / Conduit: agent handoff

Updated 2026-09-28 (night), after the physical-motion rewrite, two device feedback passes, and a micro-motion pass (see the last section). This is the shortest safe entry point for a new coding session with no chat history. It describes the `Revenue-Architect/conduit` fork, not stock Conduit. Read code before changing behavior; this document is a map, not an override of current source.

## Start here

1. Read this file, then `docs/HERMEZ_MOTION_SYSTEM.md` (required before touching any Hermez motion), `docs/HERMEZ_VISUAL_SYSTEM.md`, and `docs/HERMEZ_INLINE_LIVE_STEEL_RUNBOOK.md`.
2. Run `git status --short` and `git log -8 --oneline` from `work/conduit`. Do not `git restore`, reset, or sync upstream. `origin/main` has one newer README-only commit (`105db9f6`) that this branch has not merged.
3. Phone package is `app.cogwheel.conduit.debug`. Wireless ADB (Samsung SM-S938W): serial `adb-R5CY13VFPEP-JAeGpv._adb-tls-connect._tcp`; if `adb devices` is empty after an adb restart, run `adb mdns services` and the phone reappears. `adb install -r` keeps the Hermes account. Toolchain: `../toolchain/flutter`, `../toolchain/android-sdk`, `../toolchain/jdk-17.0.20.1+1`.
4. Backups outside git: `work/backups/pre-motion-v2-20260928` (HEAD bundle, the pre-session uncommitted patch, copies of dirty files). Device frame captures and test logs: `work/diagnostics/hermez-motion-v2-20260928`.

**No fades.** The user's hard rule: nothing in Hermez animates opacity, apart from the four sanctioned exceptions listed at the top of `docs/HERMEZ_MOTION_SYSTEM.md` (sheet dim, side-navigation labels, the plus-to-panel morph, and the landing handoff inside a growing card). Use the primitives in `lib/features/hermes/motion/` (`HermezMotionSurface`, `HermezMorph*`, `HermezRoute`/`pushHermezSheet`, `HermezEntrance`, `HermezPresence`, `HermezSize`, `HermezMotionGroup`, `HermezIconSwap`) and `showConduitDialog` for dialogs. Do not add `FadeTransition`, `AnimatedOpacity`, `AnimatedSwitcher` default transitions, `.fadeIn()`, or plain `showDialog`. `nib_motion` 0.3.1 is pinned and wrapped.

## 2026-09-28 late pass (device feedback round 2)

- **One object, not parts.** Expanding routes (Home Schedule → Jobs, Board → Kanban, bot card → Bot Detail) and origin sheets (Kanban task, Today row, Bot Detail schedule row, artifacts, attention) now scale the whole destination inside the aperture (`_HermezSheetFrame._zoom`). Text, motifs, and decorations move with the container; nothing flies on its own timing. `HeroMode` is off inside expand routes; per-part `HermezMorph` flights remain only on `standard` routes. `HermezEntrance` stagger is off (`HermezEntrance.staggered = false`).
- **Exits faster than entries.** `springHeavy` is now 1 / 300 / 34 (~0.43 s). Expanding routes reverse on the medium spring.
- **Leaving for another destination.** Opening a chat from Bot Detail (or anywhere that calls `HermezRouteExits.leaveForAnotherDestination()` before `router.go`) slides the page out instead of contracting it back into a card that is about to disappear.
- **Headers span the full width.** `HermezPageHeader` backgrounds and technical marks reach the screen edge on every page, matching Kanban. The Jobs page no longer puts a second, clipped technical background behind New scheduled job.
- **Chat artifacts appear in Artifacts.** The Artifacts page merges `HermesArtifactProvenanceStore.allFor(identity)` (files seen in chats) with the listed directory, newest first, deduplicated by path.
- **Bot marks everywhere.** `HermesBotAvatar` (chat toolbar, drawer), the assistant message avatar, and the empty-chat greeting draw `HermezBotMark` for the conversation's bot instead of the synced backend image.
- **Empty chat greeting sits high.** In Hermez chat it is top-aligned with a 4 % spacer, so the keyboard does not squeeze it.
- **Steel browser preview.** The inline Watch browser block depends on a Steel viewer URL. Personal builds must pass `--dart-define=HERMES_STEEL_VIEWER_URL=<viewer url>`; the value lives only in `work/private-build-defines.txt` (outside git, never commit it). A blank saved preference now falls back to the build value. Hermes Settings can still override it.

Build command (from `work/conduit`, bash):

```
V=$(grep '^HERMES_STEEL_VIEWER_URL=' ../private-build-defines.txt | sed 's/^HERMES_STEEL_VIEWER_URL=//; s/ .*//')
flutter build apk --debug --target-platform android-arm64 --no-pub --dart-define=HERMES_STEEL_VIEWER_URL="$V"
```

Verified: focused suites (`test/features/{hermes,chat,navigation}`, `test/shared`) show only the 8 baseline failures. `test/features/hermes` all pass (713). Code commit `048e89aa`. ARM64 debug build with the Steel define installed on the S25 (SHA-256 `5e192531676fcaa9527e474077b9651bc32033d52084c35cbed39ba7f0a3cd09`). Device captures at 10x time dilation (`work/diagnostics/hermez-motion-v2-20260928/late*`): Today row → sheet and Back, Board card → Kanban, Kanban task → sheet (no exceptions), Bot Detail → new chat (slides in, greeting high above the keyboard, kai mark in toolbar and greeting), Jobs header full width.

Not verified on device this pass: bot marks inside an existing chat's message list, the Artifacts page listing chat artifacts, and the Steel preview during a live run (the inline Watch browser button only appears while a run is active; the URL is compiled in).

## What the 2026-09-28 motion rewrite changed

The earlier motion commit (`b5ac15c0`) faded routes and squeezed the detail header into the card mid-flight. It was replaced:

- Spring-derived curves (`HermezSpringCurve`) for routes, Hero, sizes, and dialogs; reverse uses the flipped spring.
- Expanding routes: Home bot card → Bot Detail, Schedule card → Jobs, Board card → Kanban grow out of the card through an aperture; each part (mark, BOT, name, description, status dot/text, motif) is its own Hero; secondary sections unroll. Expanding pages are non-opaque so Back starts on the first frame.
- Sheets (`pushHermezSheet`): Scheduled Agent (from Today and Bot Detail rows), Kanban task (from the task card), Artifact (from the tile, thumbnail travels), Attention (from the inline run surface), Run Complete. Drag down, tap outside, or Back closes. The sheet page stays full screen at the navigator origin (Hero measures against it); the future resolves after the sheet has contracted.
- Fade-free everywhere: Android `PageTransitionsTheme` uses `HermezPushPageTransitionsBuilder`; `ThemedDialogs`, adaptive dialogs, Hermes/MCP/settings/Kanban dialogs use `ConduitDialogRoute`; chat streaming content, message entrance, activity dot, greeting, scroll-to-bottom, composer icon swap, streaming status, image error/preview, loading states, drawer refresh no longer fade.
- UI: bot marks redrawn from the reference renders (Kai crest/gem, Strong armour, Fast fins, Local vents, Autopilot antenna); Bot Detail header mirrors the card; Scheduled Agent, Attention, Run Complete, and Artifact sheets rebuilt in the mockup grammar with real data only; Jobs page restyled (it keeps a `material_ui` Scaffold so its snackbars still show).
- Sidebar: chat rows press-scale on a spring (pressed tint stays instant); section disclosure chevrons rotate.
- Fixes found on device: Kanban task crash (FLIP measured positions during a build; now recorded after layout), TextStyle `inherit` mismatch in title flights, sheet title flying outside the sheet, collapse pause, inline Steel browser block restored exactly (no animated clip around the WebView).

Verified: `flutter test test/features/hermes/` all pass (plus `hermes_kanban_app_root_test.dart` under the real `material_ui` root). Across `test/features/{hermes,navigation,chat}` and `test/shared`, the only failures are 8 that fail identically on the pre-session baseline (clipboard symlink ×3, auth-epoch preflight, workspace tabs note rows, server-version card ×3). ARM64 debug build installed on the S25 (SHA-256 `bea9144a62f93ea3e29fa09ddbdef623cc9e6ad46ab4bfcbecebbb46bc0e1bb2`). Frame-by-frame device captures (8× slowed via `ext.flutter.timeDilation`) checked: bot open/Back, Schedule → Jobs and Back, Kanban open, task open/close, Today row → sheet.

Not verified on device: an active Hermes run (inline surface states, Steel inline and full-screen expand), artifact tile → preview with a real image, dialogs, sidebar feel. Watch those first.

## Product and boundaries

Hermez is an Android-first Flutter face of Conduit for the user's Hermes agent on Umbrel. Hermes is the system of record. The app uses Hermes Desktop Gateway for sessions, turns, decisions, and Bot Mode, and authenticated Dashboard REST for administration, cron, and files. Dashboard-cookie and native-PKCE authentication both exist. Do not add another backend, database, WebSocket, artifact server, or A2UI transport. Do not change Umbrel services, Tailscale, Gateway, auth, models, or Hermes core to solve a client presentation bug.

Recent Git milestones on `main` (verify `git log` before work): `90c63b2c` introduced the broader A2UI/Kanban integration; `4c24f7d3` added Home and workflow sheets; `3ed70f03` repaired inline activity and the Kanban profile picker; `e07d542b` linked Kanban attachments to Artifacts; `ede183fa` polished visuals and repaired live-activity navigation. This handoff's final polish makes Home's Scheduled agents card open the full Jobs page and makes the bot roster a responsive two-column gallery with a shared white-shell/dark-face bot mark. It does not change Hermes contracts.

## Entry points and ownership

| Concern | Source of truth / entry point |
| --- | --- |
| App routes and Hermes-only redirect | `lib/core/router/app_router.dart`, `lib/core/services/navigation_service.dart` |
| Hermes providers | `lib/features/hermes/providers/hermes_providers.dart` |
| Desktop facade and turns | `lib/features/hermes/services/hermes_desktop_api_service.dart` and `hermes_desktop_*` collaborators |
| Dashboard auth and REST | `hermes_dashboard_cookie_store.dart`, `hermes_dashboard_rest_bridge.dart`, `hermes_desktop_auth_rest.dart` |
| Bot profiles and sessions | `hermes_desktop_bots.dart`, `hermes_bot.dart`, `hermes_session.dart`, `hermes_session_tile.dart` |
| Home | `lib/features/hermes/views/hermes_home_page.dart` |
| Full scheduled agents | `hermes_jobs_page.dart`; route `RouteNames.hermesJobs` (`/profile/hermes/jobs`) |
| One scheduled job | `sheets/hermes_scheduled_agent_sheet.dart` |
| Kanban | `kanban/hermes_kanban_client.dart`, `hermes_kanban_page.dart` |
| MEDIA artifacts | `hermes_media_parser.dart`, `hermes_artifact_client.dart`, `hermes_artifact_view.dart`, `hermes_artifacts_page.dart` |
| A2UI | `hermes_rich_output_parser.dart`, `hermes_a2ui_layout_normalizer.dart`, `hermes_a2ui_surface.dart`, `hermes_visual_catalog.dart` |
| Inline run activity and actions | `chat_page.dart` → `ChatTimelineViewport.liveFooter` → `hermes_inline_run_surface.dart`; existing `hermes_live_activity.dart` / Desktop event stream |
| Steel watch viewer | `hermes_steel_viewer.dart` (URL validation/preference), `hermes_steel_live_view.dart` (lazy WebView/full screen), Hermes Settings |
| Pending decisions | `hermes_pending_decision_store.dart` → `hermes_live_run_providers.dart` (exact-session local read/change stream); existing resolution sheet and transcript cards |
| Visual system | `hermez_chat_palette.dart`, `hermez_visual_theme.dart`, `hermez_surfaces.dart`, `hermez_technical_background.dart`, `hermez_bot_mark.dart` |
| Physical motion | `lib/features/hermes/motion/`, `docs/HERMEZ_MOTION_SYSTEM.md`. `nib_motion` 0.3.1 is pinned and wrapped. Cross-route continuity uses `HermezMorph` (Flutter Hero). Do not add ad-hoc `AnimatedContainer`, `AnimatedSwitcher`, or page-route animations when a Hermez primitive applies. |

The `HermesHomePage` bot data comes from `hermesBotsProvider`; job aggregation is `hermesHomeProfileJobsProvider`, with each result tagged by the queried profile. The Home schedule summary **always** goes to the full Jobs route. Individual timed rows in Today may open one job sheet. A bot card goes to Bot Detail; the Bot Detail chat action creates a new profile-scoped conversation. Recent Home rows call `openHermesSession` on the exact stored session. Avoid replacing these with a generic sidebar transition or canonical Bot Chat.

## Real behavior versus mockups

The user's images are a design-language reference, not sample data to hard-code. Use neutral white / very light gray canvas, white surfaces, thin gray borders, dark typography, sparse orange signals, and quiet technical geometry. See `docs/HERMEZ_VISUAL_SYSTEM.md` and `docs/HERMEZ_VISUAL_PASS_LOG.md`. The most recent bot references favor a dimensional white shell, dark face, orange eyes, and profile-specific small details. `HermezBotMark` draws this natively; it is a visual identity derived from the canonical profile name, not the bot's capabilities or backend avatar. Keep high-density lists quieter than hero areas and test at 320/412 logical pixels and 200% text. Never paint decorative imagery as a fake action.

Home, Bot Detail, Jobs, Kanban, Attention, and Artifacts are native Flutter. A2UI is only for agent-generated visual answers inside chat. A2UI uses explicit `a2ui` fences and the supported v0.9/GenUI catalog; ordinary JSON fences remain Markdown. `MEDIA:` paths are explicit Hermes attachment directives; binaries are fetched over the authenticated same-origin `/api/fs/download` path. Never put cookies or bearer tokens in a URL, message, log, or artifact record. Do not invent progress percentages, job summaries, artifact provenance, or bot availability when Hermes does not provide them.

## Current UX flow

Home → bot card → Bot Detail → new scoped chat. Home → recent conversation → that stored session. Home → Scheduled agents summary → full Jobs page; Today → individual scheduled job sheet. Home → Kanban summary → existing Kanban board. The chat timeline footer now holds the active Hermes run surface, alongside the original streaming footer; it appears only for the exact active Desktop session in running/reconnecting/synchronizing state or with a locally persisted pending decision. It disappears on completion/idle without pending input. Kanban task dependencies/files should navigate to the corresponding real task/artifact where supported. Attention resolution must never interpret sheet dismissal as approval or denial. Artifacts use authenticated bytes and offer large preview/open/share, not a tiny screenshot as the only interaction.

## Inline Live Activity + Steel viewer (implemented watch-only)

`ChatPage` no longer mounts a floating `Positioned` activity card or reserves its height above the composer. `ChatTimelineViewport.liveFooter` composes the original `StreamingTurnFooter` and one `HermesInlineRunSurface`, keyed to the active Hermes stored session ID. The inline surface shows bounded real activity, Steer, confirmed Stop, and exact-session pending requests; Review reuses `showHermesAttentionResolutionSheet`, and dismissing it does not deny anything. Pending reads use `pendingStoredDecisionsForSession()` against the existing local store (no Gateway resume merely to paint chat) and refresh via store mutation events, waiting-for-input, foreground resume, and successful resolution. `HermesLiveRunPage` remains optional larger details, not the only controls.

Hermes Settings has an optional Steel viewer URL. Its default comes from the `HERMES_STEEL_VIEWER_URL` dart-define (blank when not passed; the private tailnet address is kept in `work/private-build-defines.txt`, never in git). During an active turn, expanded inline activity offers Watch browser and a session-scoped full-screen viewer. The embedded `flutter_inappwebview` is created only when opened, uses `interactive=false`, and leaves Steel in charge of its streaming implementation. The full-screen page hides the viewer if that exact run ceases to be active. The installed Steel endpoint answered HTTP 200 from the S25; embedded playback during an actual Steel run remains unverified because the phone locked during QA.

**Takeover remains intentionally unavailable.** `service.steer()` returns true for a **queued** steer, not proof Hermes has paused browser clicks/typing. Hermes source indicates a steer may be appended after a tool result. There is no verified exact-browser handoff acknowledgement in this client contract. Do not switch the viewer to `interactive=true` merely on queued Steer; implement takeover/resume only after an authoritative control-transfer signal exists. See `docs/HERMEZ_INLINE_LIVE_STEEL_RUNBOOK.md` for evidence, acceptance checks, and next steps.

## Verification and release

Start with `git status --short`, `git log -5 --oneline`, and the focused test nearest the changed feature. Important suites live in `test/features/hermes/`, notably `hermes_destinations_smoke_test.dart`, `hermes_live_activity_disclosure_test.dart`, `hermes_kanban_*`, `hermes_artifact_*`, `hermes_a2ui_*`, `hermez_chat_visuals_test.dart`, and `hermez_visual_theme_test.dart`. Run targeted `dart analyze`, focused Flutter tests, and an Android ARM64 debug build. Existing full-project analyzer/test noise may be unrelated; record it separately, but do not declare a changed flow tested if its focused suite fails.

The Android toolchain is in the parent `work/toolchain` directory. Build from this repo with `../toolchain/flutter/bin/flutter.bat build apk --debug --target-platform android-arm64 --no-pub`, setting `ANDROID_HOME` to `../toolchain/android-sdk` and `JAVA_HOME` to `../toolchain/jdk-17.0.20.1+1` if needed. APK output is `build/app/outputs/flutter-apk/app-debug.apk`; install with `adb install -r` to preserve app data. Check `adb devices` first. Wireless ADB may require the user to enable and authorize it again. On-device QA should explicitly open Home, expand a bot, enter a real existing chat, open the full Jobs list, and inspect for Flutter errors/overflow. Do not claim on-device paths passed if only widget tests ran.

For remote delivery, the Hermes Dashboard on the Umbrel tailnet has previously served APKs placed in its artifacts directory via `/api/fs/download?path=<encoded /opt/data/artifacts/filename.apk>` on HTTPS port 8444. Verify the reachable host, auth, exact path, and SHA-256 before sharing a new link. The Desktop Gateway port is not the file-download endpoint. Do not put credentials in the link. Commit and push only after checking that the worktree contains no unrelated changes and that local `main` can fast-forward/push without overwriting other work.

The preceding 2026-09-27 Home pass had a focused Home smoke suite (8 tests), wider bot/session/job/visual suites (61 tests), targeted analyzer, and ARM64 debug APK build pass. On-device inspection then confirmed the responsive six-bot Home roster, Scheduled agents → full Jobs page, and Home bot card → correct Bot Detail. Its APK checksum was `1fc20b13223d52dd1bebc1991e20a864b6bf0e5aa177afa360fb88bcfdc491e1` (`hermez-2026-09-27-home-bots-schedules-arm64-debug.apk`).

The 2026-09-28 inline-run/Steel pass: focused Hermes/decision/chat ownership suite **49 passed**; new inline/Steel and pending-store suite **18 passed**; chat timeline/render/turn-state regression suite **84 passed**. Targeted analysis of new/touched Hermes UI and store files found no issues; a wider single analyzer invocation including the very large `chat_page.dart`/Desktop facade stalled and was stopped, but the ARM64 debug build compiled both. `adb install -r` succeeded on the S25 Ultra, preserving app data. The final APK was also pushed to the phone's Downloads folder as `Hermez-inline-live-2026-09-28-arm64-debug.apk`; local and on-phone SHA-256 both equal `6e2d623ea47a5d968a5f9b75ea29576f6df8ab0f3022f26a4eeb1f13cd227793`. The app launched to Home without a visible Flutter error and the phone reached the Steel debug viewer with HTTP 200. **A real active Hermes turn, embedded Steel playback, inline Steer/Stop/approval, and completion were not accepted on-device**: the phone entered Samsung accidental-touch protection and then keyguard lock before those interactions. Do not upgrade those checks to “passed” from widget tests.

## Known limitations / next investigation

- The phone has the motion-rewrite debug APK (SHA-256 `bea9144a62f93ea3e29fa09ddbdef623cc9e6ad46ab4bfcbecebbb46bc0e1bb2`).
- Device acceptance for an active-to-completed Hermes turn and the embedded Steel WebView is still outstanding; leave the phone unlocked, face-up, and awake for that run. Use a disposable task, verify exact-session decisions/Steer/Stop, browser watch/expand, profile switching, and no scroll jump/Flutter error.
- Next motion work: watch a real Hermes run (inline surface collapse/expand, attention, Stop → Stopping, Steel inline → full screen), artifact → preview with a real image, then Kanban lane reflow when a task changes status. Sidebar section content still appears/disappears without a size animation (slivers); only the chevron turns.
- Hermes screens import Flutter's `material` while the app root is `material_ui`; the compatibility bridge supplies theme and localizations but not a Flutter `ScaffoldMessenger`, so existing `ScaffoldMessenger.of` error paths in Hermes screens likely throw. New code uses `maybeOf`; a follow-up task was suggested.
- Human browser takeover/resume is explicitly deferred pending an authoritative Hermes browser-control handoff acknowledgement; a queued steer is not one. The viewer must stay watch-only until then.
- Recent visual polish has not been exhaustively compared on every screen at the phone's largest text scale. Keep accessibility and dark-mode checks in new UI work.
- Hermes contract versions can change; inspect the connected Desktop contract before changing blocking-decision handling. Do not silently assume newer upstream Hermes behavior matches the installed Umbrel version.
- Home's scheduled-agent summary aggregates the bot profiles (five jobs were visible during this QA), but the existing full Jobs page currently lists the configured/default profile (one job in this QA). Navigation now reaches the requested full page; making that page an all-profile manager would require profile-aware reads **and mutations** on every row. Do not silently apply a control to the wrong profile. This is a follow-up product/data-scope decision, not part of the Home tap fix.
- This repository contains project-specific work and may be ahead of/behind upstream Conduit. Do not sync or reset upstream during a focused UX fix.

## Safe continuation checklist

1. Confirm current branch, dirty state, phone connection, and Hermes version/contract only if relevant to the task.
2. Trace a visible UI action to its existing provider/service and real Hermes profile/session ID before changing it.
3. Add a regression test using a populated state (an empty state can hide the wrong branch).
4. Inspect at narrow width and large text; preserve the Hermez visual grammar and backend behavior.
5. Build/install/verify if wireless ADB is available; otherwise report the unverified device step honestly.
6. Commit/push only scoped changes, then provide the APK provenance and a direct authenticated tailnet download URL if requested.

## 2026-09-28 night pass: micro-motion, Steer, profile builds

Commits: `f8fbfea3` (end-of-motion holds, Steer, fades) and `22bf016a` (card landing), then this handoff.

- **Root cause of the "jump or stutter at the end".** The medium spring overshot by 0.5 %; clamped to [0, 1] that became a dead hold for the second half of every medium animation, then a snap when the controller ended. Medium is now critically damped (1 / 385 / 39.3) and every spring curve is rescaled so its settle point is exactly 1. A test (`every Hermez spring keeps moving until it settles`) guards it. Do not add a bouncy spring to a duration-driven animation.
- **Remounts mid-motion.** Route, cover, and dialog transitions now return the same widget structure on every frame and at rest (neutral scale/offset/`Clip.none` instead of swapping wrappers). Route and dialog curves come from `hermezCurved`, which shares one `CurvedAnimation` per parent instead of creating one per frame (each leaked a status listener).
- **Mirrored reverse curves.** Ease-out reverse curves slammed into the last frame (Kanban lanes, several switchers). Reverse now uses the flipped spring or an ease-in.
- **Sections collapse as one piece.** `HermezUnroll` slides under its top edge (a drawer) instead of being sliced by a sweeping clip. Kanban lanes use the spring; "Show empty stages" unrolls and its chevron turns. The inline run surface lost its outer `HermezSize`, which trailed behind its own reveals.
- **Card content no longer pops in when a screen shrinks.** A `HermezMotionSurface` with `onOpen` captures its face (`HermezMorphOrigin.snapshot`, `toImageSync` of a `RepaintBoundary`) before it opens. `_HermezSheetFrame._landing` slides the destination up inside the aperture near the source and uncovers that image, which lands on the real card. Same widgets at every progress value. Applies to Home Schedule/Board/bot cards, Today rows, and Kanban tasks.
- **Steer is not a dialog.** `HermesRunActions` (`hermes_run_actions.dart`): the Steer pill stretches across its row into a text field. Icon and label stay put, the send control grows in at the moving edge (close while empty, send when there is text), and the field contracts when Hermes accepts. A rejected steer keeps the text and shows the snackbar. Used by the inline run surface and the Live Run page; `promptHermesSteer` was removed.
- **Remaining fades gone.** Code-block copy/collapse icons, streaming footer, banners, selection checks, voice pill, note recorder route, and text swaps. New `HermezSwitch` (`glyph`, `unroll`, `column`) for `AnimatedSwitcher`s; an `AnimatedSwitcher` with no `transitionBuilder` fades, so always pass one.
- **Profile builds.** `android/app/build.gradle.kts` gives the `profile` build type the `.debug` application id, so an AOT build installs over the debug app and keeps the sign-in. It is much closer to real frame rate than a debug build. **The profile build shows the stock Conduit name and icon** (the Hermez label and icon live in `src/debug`); the user chose to leave that as is. A first profile build takes about 13 minutes, later ones about 3.5.
- **APK:** `build/app/outputs/flutter-apk/app-profile.apk`, SHA-256 `3d9e0bdd3eb6f2709e878635b8ec84567ddd8be73a877a69a676a53082ba5230`, built with the Steel define (`HERMES_STEEL_VIEWER_URL`, value in `work/private-build-defines.txt`, never committed). Installed on the S25.
- **Tests:** `test/features/hermes` all pass (717). Across hermes/chat/navigation/shared the failures are the same 8 baseline ones. `test/features/notes/services/note_audio_upload_service_test.dart` also fails here (13 tests, Windows path-length errors in a service this work did not touch; not part of the earlier baseline). The server-version card tests now wait for the banner to unroll before tapping.

Not verified on device this pass: the card landing, the Steer field, and the profile build's feel. The phone was in use, so nothing was driven on screen after the install. Check these first: Kanban/Scheduled agents close, a Kanban task close, Steer during a live run (needs an active turn), and the collapse of Kanban lanes.

Product analysis against Muse and Grok Bot: `docs/HERMEZ_COMPETITIVE_GAP_ANALYSIS.md`. Top gaps: the app never notifies you when a bot needs approval, voice and wake word through Hermes, memory and skills are invisible, session search/pin/export unused, bots cannot be created from the phone.

## 2026-09-28 late night: run summaries, bots reach you, what each bot knows

Commit `746084ff`. Profile APK SHA-256 `fc103e0d27a61e50a3c668386c30d78ff4adfc4698abd32cdd5ca89201f0b179` (Steel define included), installed on the S25. Not driven on device; the user tests next.

- **Run surface stays after a run.** `shouldShowHermesLiveActivity(hasRecentActivity:)` keeps the inline surface for the open session when this app has activity for it. When a run ends it collapses to a summary: Done or Run failed, time, steps, top tools. Expanded, it shows `_RunStats` and only that run's timeline (`HermesRunSummary.latest`). While running, the header shows the current step, the step count, and a ticking elapsed time. Steer and Stop only while working. Activity is in memory, so after an app restart the summary is gone until the next run.
- **Bots reach the user.** New `NotificationKind.hermesAttention` / `hermesRun` go through the existing `NotificationRouter`: master toggle (off by default), dedup, and no alert for the Hermes chat being viewed (`ActiveView.hermesSessionId`). Attention ignores the chat-responses toggle. A tap opens the Live Run page for that session. `HermesRunNotifier` (`hermes_run_notifications.dart`, started in `main.dart` so Hermes-only mode gets it) listens to the new `HermesDesktopApiService.activityEvents`. It announces a finish or failure only for sessions it saw start (a replayed completion never notifies twice), and dedups attention by request id. While a run works it holds a `hermes-run` lease on the existing background streaming service. Android shows the same silent "Conduit · Background service active" notification Open WebUI streams do, capped at 45 minutes.
- **Limits:** only runs on this app's Desktop connection are seen. Cron runs and chats started from Telegram or WhatsApp are not. There is no push server, so if Android kills the app anyway, nothing arrives until it is opened. Notification actions (approve or deny from the shade) are deliberately not offered.
- **Home.** "Since you were away" (`HermesAwayDigest`): after 10+ minutes away (`hermesLastActiveAt`, written on pause), it lists waiting requests, conversations with new activity, and scheduled agents that ran. It is hidden when nothing changed and can be dismissed. The one-time "Let your bots reach you" prompt sits beside Attention at the bottom of Home. Placed at the top, it pushed the bots off a 320 px screen.
- **What each bot knows** (Bot Detail, read-only): About you (USER.md cards), Notes (MEMORY.md cards), and Learned skills (agent-written or used), from `GET /api/learning/graph?profile=` on Hermes v2026.9.14 (checked in the tagged source). Each row grows into a sheet. The Skills stat falls back to `GET /api/skills?profile=` (enabled only) when `skills.manage` returns nothing, which is why it showed 0.
- **Tests:** new `hermes_run_summary_test.dart`, a finished-surface test, visibility, and Hermes router cases. The wide suites show the 8 known baseline failures. `test/core` has 5 more that fail identically without these changes (share and server-version tests), plus an fts timing budget that flakes.

Next (after the user tests): "5" as numbered in the chat summary, which is creating a bot from the phone plus a team view of bots handing work to each other. These are gaps 4 and 6 in `HERMEZ_COMPETITIVE_GAP_ANALYSIS.md`; the document's gap 5 is session search, pin, and export. Confirm which one the user means.

## 2026-09-29: Teams (bots working together)

Commit `5ee28ec3`. Profile APK SHA-256 `2928cb3a8fb8581f605c123d2a86f4a11926ab7638815e12b58d7943a7f42158` (Steel define included), installed on the S25. Not driven on device.

- **What it is.** Teams use Hermes' own Group Chat (hosted rooms, `groups.*`), which ships in the installed 2026.9.14. The methods are registered on the Desktop connection through `methods_bot_relay.register`; this was checked in the tagged source (`tui_gateway/methods_groups.py`, `contracts/groups_bot_relay.py`, `gateway/hosted_room_discussion.py`). A room has 2 to 6 local bot profiles. The user posts (`groups.send`, payload `{text}`); the discussion driver gives up to 3 rounds and 10 replies, bots may pass, and @mentions direct a bot. The app never schedules bot turns.
- **Where.** Home has a TEAMS section after Recent; it is hidden when `groups.list` errors, which means the server lacks Group Chat or its worker is down. `/profile/hermes/teams` lists all teams and has New team. `/profile/hermes/teams/:roomId` is the room. Both routes are in the Hermes-only allowlist.
- **Room page** (`hermes_teams_page.dart`, pure logic in `models/hermes_team_timeline.dart`):
  - Shows user and bot messages, passes, failures, "The team is done" or "reply limit" milestones, and who is thinking now (`turn.started` with no terminal event).
  - Shows approvals from `driver_status.pending_actions`. Answers are Allow once or Deny only, which is what the room driver accepts.
  - Offers Retry for an unfinished reply, @mention chips, and a send button that becomes Stop while the team works.
  - Delete team (`groups.disband`) asks for confirmation. It is permanent on Hermes and does not affect the bots.
- **Polling, not push.** Hermes does not push room events. The page reads `groups.log` from its cursor only while it is open and the app is in front: every 1.5 s while working or within 20 s of a send, every 6 s otherwise, and every 8 s after an error. Notifications do not cover team replies yet.
- **Service:** team calls live in `hermes_desktop_teams.dart`, a new part file; no existing calls changed. Ids come from `newHermesTeamId` (Hermes' identifier alphabet with a secure random suffix). Roster rows are `{member_id: m-<profile>, profile, handle: <profile>, display_name}`.
- **Tests:** `hermes_teams_test.dart` covers parsing, the timeline rules, merging, and the room page against a fake gateway answering `groups.state`, `groups.log`, and `groups.send`. The wide suites show only the 8 known baseline failures.

Check first on device: does Home show TEAMS (if not, the Group Chat worker is not running on the Umbrel), create a team with two bots, send a message, and watch replies and the thinking row.

## 2026-09-29: contraction landing fix (verified on device)

Profile APK SHA-256 `86627682d3cb150c0690c0eb4f8d80f29614e8444c63f5be426f4268fb103711`, installed on the S25.

- **Symptom:** closing Kanban from Home, or a Kanban task sheet, clipped or stuttered at the end.
- **Cause:** frame captures at 10x time dilation (`diagnostics/hermez-motion-v2-20260928/kanban-close`, `task-close`) showed the problem. Near the card, `_landing` slid the destination up by the aperture's height to uncover the card's face. The scaled page is far taller than the card, so more of the page (lanes, sheet sections) scrolled through the card outline instead. The card's face was only uncovered on the last frame.
- **Fix:** `_HermezSheetFrame._landing` now slides the destination down and out through the aperture's bottom, clipped by `_LeavingEdge`, a top edge that travels with it. No new page content enters the outline, and the face, anchored at the top, is uncovered from the top while it shrinks onto the real card.
- **Verified:** captures after the fix (`kanban-close3`, `task-close2`) show the face uncovered mid-contraction and landing exactly on the card, with no swap.
- **Test:** the motion test for sheet contraction now checks that the title never jumps above its path and that the card's face (`RawImage`) is drawn before the route ends. It no longer checks that the title stays between its start and end positions, since the title now leaves downward. All 729 tests in `test/features/hermes` pass.
- **Time dilation:** reset to 1 on the device after capture.

## 2026-09-29: sheets push the screen they grew out of

Commits `af6ad0c2` (first lift), `418950f5` (contact push), and the weight tuning after them. Profile APK SHA-256 `4511e2b86adb99feb166fa5d00bbc5a7592789b9734f08856d3fc07f92c3a110`, installed on the S25. The user asked for no on-device test this round.

- **Goal (the user's words):** "a physical interconnected object." A card that grows into a sheet should push the screen above it up while it grows, and pull it down while it shrinks. It should have some weight or resistance, and not snap.
- **How:** `hermezSheetAperture(card, end, t)` is the single geometry. The card widens to full width first (t 0 to 0.3), then its top edge rises (ease-in-out cubic). The covered Hermez screen (`HermezCoverKind.lift`) is translated up by `_pushAt(t)`, which is exactly how far that edge has risen above the card, less any drag. Both sides evaluate the same function on the same controller and curve (`curvePush`, 1.3 / 240 / 35.3, critically damped, about 0.6 s), so edge and screen stay in contact. The reverse takes as long as the forward, and the pushed screen does not recede.
- **Limits:** only Hermez screens move. The chat screen (a no-transition page) stays still under its sheets. Sheets that did not grow from a card keep a gentle 32 to 64 dp lift.
- **Tests:** the screen rises monotonically while the sheet grows, ends up pushed by exactly the edge's rise, follows a drag down and back, and returns exactly on close. The aperture phases and the push spring's settling are also covered. All 731 tests in `test/features/hermes` pass. Wide suites: only the 8 known baseline failures, re-run after the contact-push change.
- **Device:** a slowed capture of the first lift (`lift-open`, `lift-close`) confirmed the screen moving with the sheet and the outline following the card. The contact push and weight tuning were not captured on device, at the user's request.

## 2026-09-29: physical mobile side navigation, heavier sheet push

Commits `ac8b54a0` (push weight) and `f461fd67` (side navigation). Profile APK SHA-256 `490d4535810fc7b832621c7811e1a6f2163a645ba305b893adc141614f812e64`, installed on the S25. The user asked for no on-device test this round.

- **Push weight:** `springPush` is now 1.7 / 210 / 37.8 (critically damped), about 0.6 s to 99 % and 0.75 s to rest, both ways. The user had said "still a bit too snappy" at 1.3 / 240 / 35.3.
- **Side navigation goal:** replicate Calendar-Master's mobile navigation. The chat is a physical sheet that slides off to the right, not a drawer laid over it. A narrow CHAT rail stays on the right edge, and the navigation lives underneath.
- **Where:** `lib/features/navigation/widgets/physical_side_nav.dart` holds the geometry (`sideNavGeometryFor`), the stagger (`sideNavItemProgress`), `SideNavItem`, and the `PhysicalSideNav` shell. `ResponsiveDrawerLayout._buildMobileLayout` now renders `PhysicalSideNav` instead of the scrim and the panel over the content. `SidebarPage` wraps its app bar leading, actions, content, and bottom tabs in `SideNavItem` (indices 0, 1 to 3, 4, 5). `DrawerShellPage` sets the rail to CHAT / "Return to chat".
- **Behaviour:**
  - The controller value is the progress. Settles use `animateTo` over `520 ms * distance` on the curve, from the current value, so a toggle mid-flight reverses without a jump.
  - `toggle()` follows `_navTarget` (direction), not `isOpen`.
  - Android Back goes through a `BackButtonListener` on the router's back dispatcher, which runs before route `PopScope`s. It closes the navigation and consumes the event.
  - Reduced motion sets the value directly.
- **Preserved:** the edge-swipe and drag-to-close gesture arenas, drag haptics, `SidebarDrawerController` / `closeSidebarDrawerIfOverlay`, native drawer chrome composition, and the tablet persistent sidebar. The chat child stays mounted at full width. A frame changes only its transform, its clip (none at rest), and `IgnorePointer`.
- **Known limits:**
  - A drag release now settles on the curve and ignores fling velocity.
  - The label opacity stagger is the only fade in the app; the spec asked for it.
  - The iOS 26 native sidebar chrome has no stagger.
  - `scrimColor` is unused on mobile.
  - The hamburger has no expanded-state semantics. While open, the chat is excluded from semantics and the rail carries "Return to chat".
- **Tests:** `test/features/navigation/widgets/physical_side_nav_test.dart` (16 tests) covers:
  - geometry closed, halfway, and open at 390 px, plus the 2 px rail threshold and the stagger
  - closed and open states, and halfway timing
  - reversal both ways
  - rail and destination close
  - chat state (same State, composer text, and scroll offset)
  - Back under GoRouter
  - viewport change
  - reduced motion and the label stagger

  All 50 existing drawer tests pass. Wide suites show only the 8 known baseline failures.

## 2026-09-29: team send fixed, bigger team composer

Profile APK SHA-256 `f88ba2b8f8606ed919863cdf6dda98b48e49920c2ea113dd2660e5705cdbe103`, installed on the S25.

- **Symptom:** in a team room, Send did nothing.
- **Cause:** `groups.send` was rejected with "user payload is missing fields: thread_id". Hermes' `validate_user_payload` (`gateway/hosted_room_discussion.py`) requires exactly `{text, thread_id}`. Temporary `debugPrint`s in the profile build showed the tap working and the RPC failing. The error snackbar was not noticed on device.
- **Fix:** `_sendToTeam` sends `thread_id: roomId`, so the room is one discussion thread. The room test's fake gateway now asserts the exact payload keys.
- **Verified on device:** a message sent to OP Team, strong replied, and the button turned to Stop while the team worked.
- **Composer:**
  - 2 to 8 lines, 16 pt text, and a 44 dp send button
  - theme focus borders switched off inside the pill
  - bottom gap of at least 14 dp over the gesture bar; this S25 reports `viewPadding.bottom == 0` while drawing the bar over the app

  The extra bottom gap was not re-checked on device: the phone was rotated and in use.
- **Side navigation, for reference:** Hermez Home is outside the drawer `ShellRoute`, so it has no side navigation. It opens from a chat (hamburger, or a swipe from the left edge). Home's Recent "See all" has always pushed the Conversations page.

## 2026-09-29: side navigation from Hermes Home

Profile APK SHA-256 `c759fba2cec12309d58254b296881f0ca773b697b8f30cac3f64a248e5bedc21`, installed on the S25. It was not checked on device because the phone was in use.

- **Ask:** a way to open the side navigation from Home. The user chose a menu button in Home's top bar.
- **How:**
  - On phones (`!usesPersistentTabletSidebar`), the `hermesHome` route builds `DrawerShellPage(mobileRailLabel: HOME, mobileRailSemanticLabel: 'Return to Home', child: HermesHomePage())`. Home is then the physical sheet over the same `SidebarPage` the chat uses.
  - `HermesPageChrome` gained `leading`. Home puts a menu `IconButton` there (`hermes-home-navigation-toggle`) that toggles `SidebarDrawerControllerScope`.
  - The left-edge swipe, the HOME rail, and Back work as they do in the chat.
- **Notes:**
  - This is a second `DrawerShellPage` instance, separate from the chat `ShellRoute`'s. Home and the chat do not normally coexist, because a session opens with `go(Routes.chat)`. The sidebar's Hermes Home entry pushes Home over the chat shell, so two sidebars can be mounted then. From Home's own sidebar, that entry now just closes the navigation.
  - Tablets are unchanged.
- **Tests:** `hermes_destinations_smoke_test.dart` checks that the button slides Home to x = W with the "Return to Home" rail, and that the rail brings it back. Wide suites show only the 8 known baseline failures.

## 2026-09-29: inverted side navigation, stutter removed (measured on device)

Profile APK SHA-256 `85818e109b686e2341e94e269d62b07f8b976201577c42bafaf74e63eefb0ac9`, installed on the S25.

- **Theme:** `ResponsiveDrawerLayout.mobileNavigationTheme`. `DrawerShellPage` passes the opposite app theme on phones, and the stage takes its background.
- **Stutter causes:** found with VM-service frame timings and timelines, plus a temporary runtime probe that has since been removed.
  1. `HermezBotMark` blurred glows were re-rendered offscreen every frame. Marks are now cached as images (`_CachedBotMarkPainter`, LRU of 32).
  2. Label opacity fades are gone; the stagger is motion only.
  3. System bar style is held while the navigation rests open or closes back (`_RestingOverlayStyle`), never switched part-way.
  4. Moving offsets are snapped to device pixels (`snapToDevicePixels`) so the glyph atlas is reused.

  The rounded clip was also replaced with a scissor and painted corners.
- **Result over 3 open/close cycles:** dropped frames went from 13 to 0, and max raster from 35 ms to 12 ms.
- **Rejected:** snapshotting the sheet (`SnapshotWidget`) stalled the raster thread for about 70 ms on the first frame.

## 2026-09-29: bot artwork, and sensory feedback phase 1 (runbook "Not Boring Hermes")

Profile APK SHA-256 `6116d9a0a9e26f166a742354a73b512fc469b69228ac860dd2c81577078ebcfa`, installed on the S25.

- **Bot artwork:** `HermezBotMark` now draws the PNGs in `assets/icons` (Defaultbot, KaiBot, StrongBot, autopilotbot, "fast bot", locabot). Each is fitted (contain) in the same square, so layouts do not move. Pushed to `main` as a fast-forward.
- **Sensory foundation:** see `HERMEZ_MOTION_SYSTEM.md`, "Sensory feedback". It covers `flutter_soloud` 5.1.4, 12 original cues, `HermezFeedback`, the "Interface sounds" setting, and the run coordinator.
- **Wired so far:**
  - the side-nav latch
  - Home bot, Scheduled and Kanban cards (`objectOpen`)
  - Bot Detail "Chat with" (`botEngage`, plus failure)
  - live run engage, attention, complete and fail for the visible session
  - approval and decision answers
- **Device check:** the engine initializes, and AudioFlinger shows a 48 kHz track at each side-nav settle.
- **Tooling:** VS 2022 Build Tools (C++ workload) were installed on this PC, because the soloud build hook compiles for the host during `flutter test`.
- **Tests:** feedback fail-open and suppression, the coordinator transition rules, and exactly-once for a cue surface and for a decision. Wide suites show only the 8 known baseline failures.
- **Deviations from the runbook:**
  - The nav latch is sound only; the existing no-settle-haptic tests stay unchanged.
  - Bot presence must animate the PNG physically (lift, compression), because the eyes are no longer painted.
- **Not done yet:** sheet dismiss detent, `objectClose` on returning from Detail, `HermezBotPresence`, `HermezTouchLight`, and the listening QA on the phone speaker (levels).

## 2026-09-29: sensory runbook completed (detents, presence, touch light, action cues)

Profile APK SHA-256 `cf6c01722423730c73ff235058c32a72ea87635e7db8ab853046bf9303894c49`, installed on the S25.

- **Added:**
  - the sheet dismiss detent
  - the close latch on returning into a card
  - Run now, Steer and Stop result cues
  - `HermezBotPresence` (Detail, Home cards, greeting)
  - `HermezTouchLight` (Home bot cards)

  Details are in `HERMEZ_MOTION_SYSTEM.md`, "Sensory feedback".
- **Device:** the touch light shows as a faint warm reflection on the kai card while held.
  - The first version was invisible, because a white sheen on a white card cannot show; it is now warm-tinted.
  - Presence was seen on Bot Detail. Running, waiting and completion motion were not exercised on device (no live run was started).
- **Tests:** presence state mapping, float without opacity, small marks still, reduced motion, and a lit card still taps once and still scrolls. Wide suites: 2654 pass, plus the 8 known baseline failures.
- **Open:** listening QA of cue levels on the phone speaker; exercising a real run on device for the engage, attention, complete and fail cues and presence.

## 2026-09-29: physical compartments (spec "Physical animation prompt")

Profile APK SHA-256 `c429b68cad64dea277aaf408f3a4793365a7282fa044e1f210e32aa098b0e1c0`, installed on the S25.

- **Built:**
  - the `HermezExpandableSection` primitive, with 9 tests: layout displacement, rapid reverse, parent control, feedback once per tap and silence otherwise, semantics, inert while closed, reduced motion, and no business imports
  - Bot Detail Systems (replacing the `ExpansionTile`)
  - Home TODAY
  - scheduled agent run history
  - inline run header alignment

  Details are in `HERMEZ_MOTION_SYSTEM.md`.
- **Device (wireless debug):**
  - Home TODAY opens in place, pushing Schedule, Kanban and Recent down (about 150 dp). Two open/close cycles plus a rapid double tap ran 193 frames, 0 dropped, max raster 10.6 ms.
  - Bot Detail SYSTEMS / 120 opens and pushes Knowledge down. Over 714 frames there was 1 dropped frame: mounting 120 rows on the open's first frame, 8.7 ms build.
  - A scheduled sheet with no runs shows the empty state unchanged; the drag-to-close and the close button were both exercised.
  - Run history with data was not seen on device, because no job has runs and Run now was not pressed (it starts a real job).
- **Not done:** Phase 6 (Knowledge is not dense, so it stays), Phase 7 (Kanban task activity already has its own show-all toggle), Phase 8 (artifact context).

## 2026-09-29: clarify answers fixed; artifact context; clearer attention cards; live device QA

Profile APK SHA-256 `393b13910cdf05aabfd6227c4fd2ff6ca3bbb7b3bbe8fdcdd2ce4b87bf886e84`, installed on the S25.

- **Clarify bug (pre-existing, found on device).** Every clarify answer reached Hermes empty. The installed Hermes sends `clarify.request` in the batch form `{request_id, questions:[{qid, question, choices}]}`, even for one question, and `_respond` treats a `clarify.respond` without `question_id` as cancel-all.
  - The app read only a top-level `question`, so the prompt was blank, and it answered without `question_id`.
  - Fix, in `services/hermes_clarify_form.dart`: the batch is parsed for prompt, choices and qids (`_clarifyQids` per request id), and the answer is sent with one `clarify.respond` per qid. With several questions, the numbered prompt maps one line per question.
  - Newer Hermes (server requests, per the `tui_gateway/server_requests.py` contract) sends `clarify`/`sudo`/`secret` as server requests. They are now kept open by the transport, surfaced as `<kind>.request`, and answered with the response frame (`{answer}`, `{answers}` or `{value}`); `request.cancel` becomes `<kind>.expire`. Previously every server request was declined with -32601.
  - Verified on device: "Which color do you prefer?" shows, and answering "blue" gives "You chose blue."
- **Attention.** The sheet names the bot, the conversation ("In '…'") and the labelled QUESTION or COMMAND. It says plainly when the question text was not sent. Rows lead with the question, then bot and conversation.
- **Artifact context.** A FILE CONTEXT compartment appears in the artifact preview when this app recorded provenance. It shows source bot, conversation, type, first seen and path, from existing data only; there are no new requests. Verified on device with a file kai created.
- **Live device QA:**
  - run engage, complete and attention cues each fire once (AudioFlinger timestamps)
  - the inline run compartment opens mid-run and after completion
  - Run now is accepted, with send and success cues
- **Run history with data could not be shown.** Hermes skips every scheduled job with `drift_skip:silent` (the global model changed from deepseek to custom after the jobs were created), so no run sessions exist and "No runs yet" is truthful. Re-pinning the jobs on the server (`hermes cron edit … --provider … --model …`) is the user's call.


## 2026-09-29: a2UI visual-first chat, with six structure components

Profile APK SHA-256 `f79bcb843a13c5fa94085f1964fa8e59c1cc73fbb383e4fa33703acedfeee6ed`, installed on the S25.

- **Components** (`widgets/hermes_visual_structure.dart`, registered in the Hermes catalog): InfoRow, StepRail, ActionCallout, ArtifactTile, BotBadge and ExpandableSection.
  - They are data-only: no I/O, no URLs, no `dispatchEvent`.
  - Unknown props and out-of-range values are rejected, either by the normalizer's schema check or by a "Visual unavailable" notice.
  - ExpandableSection wraps `HermezExpandableSection`, with compartment cues and state held locally.
- **Interaction lock** (`widgets/hermes_a2ui_interaction_lock.dart`) replaces the surface-wide `IgnorePointer`.
  - When a surface is read-only, busy or has a tap in flight, it is still inert, except for a compartment header, which can open because that reveals content already in the reply and sends nothing.
  - Anything inside the compartment keeps the lock.
  - `_forwardInteractions` still drops submissions under the same conditions.
- **Normalizer:** an unweighted Button-only row (for example Approve / Hold) gets `weight: 1` per button. At 200% text on 300 px it overflowed by 154 px.
- **Validator** (`a2ui_check.py`): knows the six types, their required props, enums, per-prop lengths, StepRail steps, and `actionChild` references. It caught all 14 negative cases.
  - Two older fixtures, `metric-row-ranged-unweighted` and `synthetic-22`, still fail by design; they are normalizer repair inputs, and they failed the old validator too.
- **Fixtures:** 8 new ones in `test/fixtures/hermes/a2ui/`, all passing the validator. The tests are `hermes_visual_structure_test.dart` (31), additions to the normalizer tests, and one chat E2E in which expanding sends no turn and a Button sends one.
  - In `test/features/hermes` and `test/features/chat`, 1927 pass. The 4 failures are the known baseline ones.
- **Authoring skill:** SKILL.md 0.9.0 adds "Choose the presentation before writing" (plain vs structured categories, a trigger table, table avoidance, no duplicated prose, no visual spam) and the difference between conversational and presentation-only interaction.
  - `component-guide.md` has the schemas; `patterns.md` has 8 new patterns (7–14), all valid.
- **Device QA:** a surface Hermes echoed in a temporary chat rendered all six components, in portrait and landscape.
  - EVIDENCE / 2 opened in place and pushed the content below down, with no turn sent.
  - Hold sent exactly one turn ("Qa · Hold"), and Hermes received the interaction.
- **Not done:** the updated skill is **not deployed** to the Hermes server (`/opt/data/…`); deploying it is the user's call. Until it is, Hermes doesn't know the new components, and prompt QA (spec §42) can't run.

### Deployed to the Hermes server (same day)

- **Why the first reply after Hold failed:** the fast profile had no `a2ui-mobile` skill; only the default profile did. The model replied with a bare `updateComponents` patch for the old surface, with no `createSurface`. Conduit correctly declines that ("could not be displayed safely").
- **Server SKILL.md had drifted:** the Hermes skill curator had reworded it and cut the description to "Compose A2UI phone surfaces: checklists, pickers, cards."
  - 0.9.0 was merged on top of the curated text, and the full description was restored.
  - A new rule was added: after an interaction, reply in plain text or with a complete new surface (new `surfaceId`), never a fragment of an old one.
  - The repo SKILL.md now equals the deployed file.
- **Deployed** through the Umbrel MCP (file route plus rename/copy/trash; no SSH):
  - `data/hermes/skills/software-development/a2ui-mobile/{SKILL.md, references/component-guide.md, references/patterns.md}` and `data/hermes/scripts/a2ui_check.py`.
  - The originals are kept beside them as `*.bak-20260929`, with a local copy in `work/backups/hermes-server-20260929/`. Uploads were verified byte for byte.
  - The skill was copied into `profiles/{fast,kai,strong,local}/skills/software-development/`. autopilot was left out on purpose.
- **Restarted hermes-agent:** the skill index is cached in memory per profile (`.skills_prompt_snapshot.json`), so new skills only appear after a restart. The restart made one user message fail with a 502; it was retried and succeeded.
- **Rollback:** rename the `.bak-20260929` files back, trash the profile copies, and restart.
- **Prompt QA (§42) is still to do after the restart.** Before the restart, fast answered a rollout plan in Markdown because the skill was not in its index. That test also led fast to do extensive read-only recon (LAN/port probes) about an NVR that does not exist; the NVR in the test data was invented.

### Getting Hermes to actually use the skill (same evening)

- **Where Conduit chats run:** the main Hermes profile (session source `mobile`, model `deepseek-flash`). The system prompt says `Platform: tui`; the word Conduit never appears. The skill index shows only about 60 characters of each description.
- **The skill alone was not enough.** Even with the trigger at the front of the description ("Platform tui = Conduit app: load before any status, plan…"), `deepseek-flash` answered a rollout plan in Markdown without opening the skill.
- **The fix:** a five-line section in the server `SOUL.md`, "Conduit replies (Platform: tui)". It says to load `a2ui-mobile` before any structured answer, keep one-liners as text, and never emit A2UI on other platforms. The original is kept as `SOUL.md.bak-20260929`.
  - The skill body now also says: Conduit = `Platform: tui`; no A2UI on WhatsApp, Teams, webhook, cron or cli.
- **Verified on the S25 after the change:**
  - A dashboard request used InfoRow, ExpandableSection and ActionCallout; it rendered, and the compartment opened locally.
  - "Plan a 4-stage rollout for a website launch." gave a StepRail, a STAGE GATES compartment and a Next-step ActionCallout, with one intro sentence.
  - The same payloads render cleanly in widget tests.
- **Known side effect:** the Hermes desktop/TUI also reports `Platform: tui`, so it may receive A2UI blocks, which it shows as code.
- **Not yet run:** the §42 plain-text check ("What is 2 + 2?") and the remaining prompts.

## 2026-09-30: Steel preview regression fixed; Kanban compartments (spec Phase 7)

- **Steel "Watch browser" had disappeared.** Its cause was the build, not the code.
  - `private-build-defines.txt` holds `HERMES_STEEL_VIEWER_URL=<url>  # private; …`, and the build passed the whole line.
  - The app received `<url>  # private…`. `#` parses as a fragment, so `parseSteelViewerUrl` returned null and `browserAvailable` was false.
- **Two fixes:**
  - The build strips the comment: `sed -E 's/[[:space:]]+#.*$//'`, with a guard that fails if `#` or a space remains.
  - The app keeps only the first token of the define (`sanitizeSteelViewerDefine`), with a test.
  - Verified on the S25: mid-run, the live view shows the Steel browser with Close browser / Expand.
  - **Use the stripped define for every future build.**
- **Kanban task sheet (Phase 7, previously skipped):** "Dependencies & files" now holds DEPENDENCIES / n (parents and child tasks), FILES / n and DIAGNOSTICS / n (only when present), all on `HermezExpandableSection`.
  - The parent owns each open state; data, tap targets and navigation are unchanged, with no new requests.
  - Board lanes keep their `ExpansionTile` on purpose (§37: do not collapse lanes).
  - Compartment content has its own transparent Material, so tile press ink shows above the frame.
- **Phase 6 (Bot Knowledge)** is still intentionally not wrapped. The spec makes it conditional ("only if dense"), and it is three navigation rows.
- **Tests:** hermes and chat suites give 1928 passing and the 4 known baseline failures.

## 2026-09-30: Hermez Red accent palette

- **New option:** Appearance → Accent palette → **Hermez Red** (`id: hermez_red`, signal `#E3192B`). It is the Hermez theme with only the signal roles swapped (`primary`, `ring`, `sidebarPrimary`, `sidebarRing`; dark `accent` tint `#4B2327`). Canvas, ink, borders and status colours are identical. Orange Hermez stays the default.
- **White text on red:** graphite on `#E3192B` would be about 3.7:1, below 4.5:1; white is 4.8:1. Both are enforced by tests.
- **Hermes-only mode** used to force the orange theme. It now allows either Hermez theme (`TweakcnThemes.isHermez`).
- **`HermezChatPalette`** follows the active theme via `HermezChatPalette.useThemeId(...)`, set where the light/dark themes are built. Every caller reads the palette through `Theme.of(context)`, so switching palettes rebuilds them.
- **Stray oranges** now use the palette: Kanban header dot, Kanban task dot, home "LIVE WORK" label, touch-light tint. The PDF file-type red is a file-kind colour and was left alone.
- **Not recoloured:** the bot artwork PNGs (`assets/icons/*bot.png`) have orange eyes baked in. They need red-eyed artwork if wanted.
- **Verified on the S25:** the picker shows Hermez Red; the home screen, drawer strip, bot detail and away card turn red. The phone was left on Hermez Red.
- **Tests:** `hermez_red_palette_test.dart`. The wide suites have 13 failures; all were checked against the stashed baseline code and fail identically there (symlink, timing, server-version and share tests).

## 2026-09-30: New task — the button becomes the panel; OPTIONS compartment

- **Plus-to-panel morph** (the user's Transitions.dev reference, rebuilt in Hermez terms). New primitive `motion/hermez_panel_morph.dart`: `pushHermezPanel` / `HermezPanelRoute` / `HermezPanelMorph`.
  - The tapped button's rectangle and corner radius grow into a content-sized panel: top-anchored, centred, above the keyboard.
  - Opening uses a spring with a light bounce (about 3 %, ~0.39 s). Closing uses the critically damped medium spring (~0.32 s) and goes home into the button.
  - The button's face (plus and label) rides the growing surface. The plus turns into a × and shrinks away while the panel content wipes across from the button's side.
  - **No opacity and no blur anywhere** (Hermez rule), unlike the CSS reference, which cross-fades and blurs.
  - Input unlocks when the panel is at rest; tapping outside or Cancel closes it. The panel follows its own content height every frame (compartments, errors).
  - The real button stays in place but is not drawn while the panel stands in for it, and reappears only after the panel has contracted. The origin rectangle is captured once, because the keyboard lifts the button.
- **Kanban:** the floating "New task" button and the Triage / Ready lane "+" buttons both use it. The dialog is gone.
- **OPTIONS compartment** in the new-task form (`_NewTaskOptions`, on `HermezExpandableSection`).
  - Status, bot and priority sit one tap away, and their real values are on the header ("Triage · No bot · Priority 0").
  - Title, details, the agent-work warning, errors and Create stay visible.
  - Opening the compartment closes the keyboard.
  - At 200 % text, Cancel / Create stack (`OverflowBar`) and the priority dropdown takes the full width.
- **The created task is unchanged:** same client call and fields. No new requests.
- **Tests:** `hermez_panel_morph_test.dart` (13) and `hermes_kanban_new_task_test.dart` (15); existing Kanban tests updated to open OPTIONS. The wide suites fail only the 13 known pre-existing tests.
- **Device:** installed on the S25; the user is testing it themselves.

### New task, second pass: Transitions.dev "Dropdown menu morph", replicated faithfully

- **User feedback on the first pass:** it did not match the reference, and the New task button rode up alone when the keyboard opened.
- **Source:** the reference was read from its public repo (`Jakubantalik/transitions.dev`, `transitions/dropdown-menu-morph`). The `npx` installer was not run.
- **One object:** the button's own surface expands in place into the panel.
  - It is anchored to the button's nearest corner and grows toward the screen: a bottom button grows up, a top one grows down. The corner radius relaxes to 20.
  - This follows the user's rule: "the object expands as one shared element geometry into the menu".
- **Tokens (`HermezPanelMotion`), exactly as in the CSS:**
  - Open 350 ms, `cubic-bezier(.34,1.25,.64,1)` (overshoot); close 250 ms, `cubic-bezier(.22,1,.36,1)`.
  - Fades 200 ms, slide 40 px, scale 0.97, blur 2 px, plus rotates 45°.
  - Each property keeps its own duration and easing, derived per frame (`HermezMorphFrame`).
- **This control deliberately cross-fades and blurs,** at the user's request: the one exception to the Hermez no-fade rule.
- **Keyboard:**
  - The Kanban Scaffold no longer resizes for the keyboard, so the floating button never moves.
  - The title no longer autofocuses.
  - When the keyboard shows, the whole panel's anchored edge moves above it.
- **Tests:** morph tests are rewritten around the reference; there is a Kanban test that the keyboard does not move the button. The wide suites show only the 13 known pre-existing failures.

## 2026-09-30: Physical interaction, navigation, approvals and notifications spec (phases A–G)

Source: the user's "Hermez Physical Interaction + Navigation + Approval + Notifications Implementation Spec" (baseline `49d733c2`). One commit per phase.

- **A (`924b2032`), Home destinations:**
  - Recent's See all and All teams grow their whole block, header plus list, into Conversations and Teams. It works through the existing expand route by passing a `HermezMorphOrigin`.
  - Attention and Artifacts are compact Hermez objects that open with an origin. Attention shows the real pending count (`hermesHomePendingDecisionsProvider`, which was the private away-digest provider); Artifacts has no count because only a network listing backs it.
  - `HermesConversationsPage` is a real page: a bot filter, and conversations grouped by bot, using the same providers and rows. It carries no side-navigation entries.
- **B (`d3026d8e`), creation and editing:**
  - The scheduled-agent editor is one Hermez sheet, grown from the New button or from the agent's own card. Fields, validation and mutations are unchanged.
  - The scheduled-agent delete guard expands inside the card.
  - New Chat: the + grows into a Hermez bot picker; creation is unchanged. New Task was done earlier.
- **C (`95407bde`), Kanban:**
  - Title, priority, assignee and comment are edited inline under their control.
  - Assignee is a physical profile list (also in New task OPTIONS), with the same roster and the same Unassign semantics.
  - Status moves use a Keep current / Move guard under the chips; running is never offered.
  - The Kanban dialog helpers are removed.
- **D (`9558aba1`), guarded actions:**
  - Stop (inline card and Live Run page) expands a STOP THIS RUN? guard. Stop interrupts exactly once.
  - Team options is a tray under the room header, with a guarded Delete team.
- **E (`e569527a`), inline decisions:**
  - The approval card uses the Hermez frame (`hermez_decision_frame.dart`). The action shows as a command line, primary options are physical rows, and any other policies Hermes sent go in a More options compartment. One answer per pending request.
  - The clarify, sudo, secret and MCP cards use the same frame, with radio or checkbox choices. Submit values and secure fields are unchanged.
  - Attention rows and Live Run pending rows grow into the resolution sheet.
- **F (`7e69503b`), admin:**
  - Toolset details open in place.
  - MCP: Add and Catalog grow sheets. Server actions are a tray under the row, Set API key is a secure sheet grown from the row, and Remove is guarded in the tray. The service calls are the same.
- **G (`eb02187d`), notifications:**
  - `LocalNotificationService` gains `areNotificationsAllowed`, `androidHealth` and `sendDiagnosticNotification`.
  - Settings gains a NOTIFICATION HEALTH section, Send test notification, and an explanation of foreground versus background delivery.
  - `HermesRunNotifier` prints one `hermes/notifications …` trace line per relevant event (not in release). The `_armed` logic is unchanged.
  - The router already covered its cases; the new notifier tests cover arming and routing.
- **Recurring real bug (fixed three times):** `material_ui` fields and buttons placed inside a Hermez sheet or frame need `material_ui`'s own `Material`, because the Hermez one is Flutter's. It showed up in the job editor, the decision card and the MCP sheets. Wrap them in `Material(type: MaterialType.transparency)` from `material_ui`.
- **Not done:**
  - **Phase H** (moving notification tap and init ownership out of the Open WebUI listener): the spec gates it on notifications being proven on device first.
  - **Killed-app delivery:** needs a server-to-device push transport; out of scope by design.
  - **Device QA** of each flow, and the §34 notification tests, are pending on the S25.

## 2026-09-30: Device QA round (motion and interaction polish)

This round covers the user's reports and a QA pass on the S25 (profile build, 120 Hz).
- **Frame timing method:**
  - Run `dumpsys SurfaceFlinger --latency '<SurfaceView layer>'` around an `input tap` (script kept in the session scratchpad).
  - Every measured transition held 8.3 ms frames: See all, New task, the + menu, Options, the drawer, Home, and Jobs warm.
  - Jobs cold open drops about 7 frames on first build.
- **Fixes from user reports:**
  - **New Chat +:** now the plus-to-menu panel morph (`pushHermezPanel`) instead of a bottom sheet. With a tiny top-right origin, the sheet aperture's widen-then-rise path stalled mid-flight. No origin falls back to the sheet.
  - **See all / All teams close:**
    - The block is a `RepaintBoundary`, and its drawing is passed as the origin snapshot via `HermezMorphOrigin.capture`.
    - Contracting now lands on the block's own face. Before, a shrunken, clipped Conversations page showed and then swapped.
  - **New task Options clipped:**
    - `RenderHermezPanelMorph` used to cap the content at the room between the anchor and the screen edge.
    - Now the content may use the whole clear height, and the panel slides off its anchor before anything scrolls.
  - **Notifications missing in Hermes-only mode:**
    - `/profile/notifications` is added to the accountless allowlist.
    - The Profile entry is no longer gated on an Open WebUI account.
    - Hermes settings links to it.
    - The Channels toggle shows only when an Open WebUI API is present.
- **Found in QA and fixed:**
  - **Back swallowed on every page opened from the side navigation.**
    - `ResponsiveDrawerLayout._handleBackButton` claimed Back while the covered drawer was "open".
    - Its tickers are off while covered, so it could never close, and every Back was eaten. This affected Kanban, bot detail, the New task panel and others.
    - Now it returns false unless its own route is current.
  - **Hermez sheets with scrolling content could not be dragged down.**
    - The scroll view won the drag.
    - `_HermezSheetPlacement` now turns overscroll past the content's top into sheet drag, and ScrollEnd into the dismiss/settle decision. The stretch indicator is suppressed while the sheet moves.
  - Assignee rows (Kanban) are Hermez physical rows instead of stock ListTiles, and the label is shortened to "Assign a bot".
  - Bot detail Capabilities (a second data pass) grows in on `HermezSize` instead of jumping the page.
  - Long scheduled-job errors are two lines with Show full error (`HermesJobError`).
  - Live activity labels are sentence case.
  - The Notification health settings link shows only when the permission or channel is off.
- **Open, not motion:**
  - Scheduled-agent counts disagree. Home shows 4 active / 5 total across profiles, while the side navigation and the Jobs page show the main profile only (0 active / 1).

## 2026-09-30: Notification device tests, richer notifications, phase H

Commits `88744f03` and `94128ed7`, plus a round of visible-view fixes.
- **Device results (S25, Hermes-only, fast bot):**

  | Test | Result |
  | --- | --- |
  | 1. Health | Passed. |
  | 2. Test notification in the background | Passed. |
  | 3. App open on another page | Initially suppressed, because the stale active chat counted as "viewing". Fixed by `visibleActiveView` (router location plus `ResponsiveDrawerLayoutState.mobileDrawerShowing`). The banner now appears over Kanban. |
  | 4. Background finish | Passed, with the bot named. |
  | 5. Clarify ("needs you") in the background | Passed, and shows the question. |
  | 6. Failed run | Unit tests only; a server failure can't safely be forced. |
  | 7. Restart and reopen finished chats | No replays. |

- **Taps:**
  - Warm taps now deep-link.
  - "finished" opens the conversation, via the live page with `?open=chat`.
  - "needs you" opens the live page.
  - The cold-launch drain was added in `main.dart`, but its device check was blocked. Force-stop wipes an app's notifications, so use `am kill`.
- **Phase H:**
  - `NotificationCenter` (`providers/notification_center.dart`) owns the plugin, taps, the launch tap (once), `notificationRouterProvider`, the banner and deep links. It is started in `main.dart _initializeAppState`.
  - Before this, the tap subscription existed only after an Open WebUI sign-in (`_runPostAuthenticationStartup`), so Hermes-only taps were never routed.
  - `notification_socket_listener.dart` is Open WebUI socket only and re-exports `notificationRouterProvider` and `visibleActiveView`.
- **Banner:** `HermezInAppBanner` sits in the root overlay (spring slide, swipe up, one at a time) for Hermes kinds. A `ScaffoldMessenger` snackbar only reached the chat's Scaffold, under the covering page.
- **Content:**
  - Finished: the answer's opening, skipping narration, headings and "(Saved to …)" asides, after the stream settles. Then conversation · "Used tools" · time.
  - Needs you: from `pendingStoredDecisionsForSession`.
  - Android `BigTextStyle`.
- **Also fixed:** a chat opened from a list resolves its bot from the session profile (it showed "Hermes Agent" before).
- **Gotcha:** `build_runner --delete-conflicting-outputs --build-filter` deleted unrelated `.g.dart` files. Run a full `build_runner build` after any filtered run.
- **Open:**
  - The same pending request shows twice in chat (inline "Input needed" plus the composer clarification card).
  - "Watch browser" shows on any working run when Steel is configured; left as is to avoid regressing the preview.
  - Opening an old chat may pop the keyboard; unconfirmed.
  - `hermes_decision_card_test` "wall-clock expiry" fails regardless of these changes: its 50 ms lifetime is shorter than the first frame on this machine.
  - Device QA of Teams, Attention, MCP and live run is still to do.

## 2026-09-30: Open items closed

- **Cold-launch tap:** `HermesLiveRunPage(openChat: true)` waits up to about 6s for `hermesSessionsProvider` and about 10s for the Desktop service, then calls `openHermesSession`. If that fails it falls back to the live page. Verified on the S25: `am kill`, then tap, opens the chat named for its bot. (Force-stop wipes notifications, so use `am kill`.)
- **No keyboard on existing chats:** `chat_page` skips its startup composer focus for a native Hermes conversation that has messages.
- **Duplicate request:** `HermesInlineRunSurface.requestShownBelow` is set when `findPendingHermesComposerPrompt` finds the composer card. The inline surface then shows only "Input needed".
- **Watch browser:** needs Steel configured **and** a run tool whose name matches `browser|steel` (`hermesRunUsedBrowser`).
- **Schedules:**
  - `hermesHomeProfileJobsProvider` now lives in `hermes_providers.dart`.
  - The Jobs page header and the side-nav `_ScheduledAgentsTile` count all bots.
  - The Jobs page lists the other bots under "OTHER BOTS", opening `showHermesScheduledAgentSheet`.
- **Device pass:**
  - Teams: list, room, options tray, and the delete guard (cancelled).
  - Attention: failed runs open Scheduled agents.
  - Artifacts: grid.
  - MCP: actions tray, and the Add sheet (cancelled).
  - Toolset compartment.
  - No data was changed.

## 2026-09-30: A2UI catalog expansion and visual-language cleanup

Spec: `docs/HERMEZ_A2UI_CATALOG_EXPANSION_SPEC.md`. Phases 1–5 are in commits `6dd8973e`, `5410a5d9`, `98c1d778` and `b0f467e1`. The notification path was not touched.

- **Visual language:**
  - `ActionCallout` has no 4px edge. Tone recolors the complete outline, eyebrow and icon; body copy is unchanged.
  - Shared helpers in `hermes_visual_structure.dart`: `hermezOutline(palette, semantic)` (neutral border 1.0, semantic 1.4) and `hermezStatusColorsOf(context)`. Success, warning and danger are never the accent.
  - `Card` is a zero-elevation Material with a full outline. It stays a Material so ListTile ink inside forms keeps working.
- **Button:**
  - GenUI's own builder still runs, so actions, `checks` and function calls behave exactly as before, one dispatch per press.
  - Hermez owns the look through a Theme scoped to the one button: primary is the accent fill with `onAccent` (white on Red); default is a surface with a full border; borderless is bare. Minimum 48dp, no elevation, labels wrap.
  - The old test that pinned default to the accent fill was updated to the spec.
- **New components** (bounded schemas, data-only, invalid input shows a fallback):
  - `hermes_visual_personal.dart`: ProgressMeter, ActivityFeed, ScheduleTile, MessagePreview.
  - `hermes_visual_technical.dart`: CommandBlock, TaskTile, KeyValueGrid, ComparisonCard.
  - CommandBlock's Copy is a `HermesA2uiLocalControl`: clipboard only, no event, and it works on a locked surface.
- **Normalizer:**
  - The eight new types are in `_stackInRowComponentTypes` and also in `_alwaysStackComponentTypes`: a Row holding any of them becomes a Column even when weighted. MetricTile and Button rows are unchanged.
  - The graph walk treats `content` as a reference only for non-CommandBlock types, i.e. Modal.
- **Authoring:**
  - SKILL.md: mapping, telling similar components apart, usage rules, compositions.
  - Component guide: props plus the visual-language rule.
  - patterns.md: patterns 15–24.
  - `a2ui_check.py`: new props, bounds and enums, and an error when a new object is a direct Row child.
  - All 24 patterns validate, and the smoke test renders every one at 320px and 200% text.
- **Tests:** `hermes_a2ui_visual_language_test`, `hermes_visual_personal_test`, `hermes_visual_technical_test` and `hermes_a2ui_catalog_smoke_test`. They cover Orange and Red in light and dark.
- **Not done:**
  - **Server deployment of the updated skill:** 4 files into `data/hermes/skills/software-development/a2ui-mobile/` plus the four profile copies, then a hermes-agent restart. It needs the user's go-ahead; follow the procedure above and keep `.bak` copies.
  - **Real-Hermes prompt QA (spec §66):** waits on that deployment.

### Deployed a2ui-mobile 0.10.0 to Hermes (2026-09-30, approved)

- **Access:** key-based SSH as `umbrel` (the `~/.ssh/config` host `umbrel`). App data is at `~/umbrel/app-data/hermes-agent/data/hermes`.
- **Pre-check:** all 4 server files were byte-identical to the previous repo versions (no curator drift). All four profile copies matched main.
- **Backups:**
  - `*.bak-20260930` beside every replaced file, covering main, the fast/kai/strong/local profiles and `scripts/a2ui_check.py`.
  - A local copy is in `work/backups/hermes-server-20260930/srv/`.
  - autopilot is still excluded.
- **Deployed:** SKILL.md (version 0.10.0; description triggers now include progress, schedule, messages, tasks, command), `references/component-guide.md`, `references/patterns.md` and the checker. SHA-256 was verified on all copies. Then `docker restart hermes-agent_web_1`.
- **Rollback:** restore the `.bak-20260930` files, then restart.
- **Real-Hermes check:**
  - The default bot, asked for a restart command, loaded the skill and answered with a CommandBlock (Copy), an InfoRow with state Unknown, and a full-outline ActionCallout. No edge stripe.
  - The remaining §66 prompts were not run (the user took the phone).
- **Log note:** after the restart the gateway warns "Skipping secondary profile fast/local/strong: port-binding platforms with multiplex_profiles on". This is profile `config.yaml` state and was not changed here. Chats are served through the default listener's `/p/<profile>/` prefix.

## 2026-10-03: card closes land on the card; panel, Kanban, chat and drawer polish

User report (screen recording): cards slid their content down fast while shrinking home, then popped into the card; New task and lane + blinked at the end of the close; the Kanban New task button flipped in; bot detail → new chat flashed the side navigation; the clarify card vanished when answered; everything felt slow. Earlier the same day `f964d2dd` turned off `HeroMode` on Hermez pages and `143da7e3` removed `HermezSize` under closing bot cards and schedule sheets; neither had a section here.

- **Landing (`_HermezSheetFrame._landing`).**
  - The destination no longer slides out through the aperture. It and the source's face cross-dissolve while both ride the moving aperture: destination 1 to 0 over t 0.48 to 0.16, face 0 to 1 over t 0.36 to 0.06.
  - This is a deliberate exception to "no opacity", listed at the top of `HERMEZ_MOTION_SYSTEM.md`. Without a face the destination stays as it is (the live browser aperture cannot be drawn).
- **Faces everywhere.**
  - `HermezMorphOrigin.of` now draws the face itself from the first same-size `RepaintBoundary` at the top of the source's subtree, and `didPop` calls `refreshFace()` so a close lands on the card as it is now.
  - Boundaries were added for the Jobs page job card (Edit), the New scheduled job button, the attention rows, the live-run pending rows, the MCP rows, catalog button and FAB, and the inline run surface (key moved onto the boundary).
  - The Jobs OTHER BOTS rows now use `onOpen`.
- **Sheet aperture.** It widens over t 0 to 0.34, and the top edge rises over t 0.12 to 1 on ease-in-out (was ease-in-out cubic over t 0.3 to 1). The peak edge speed is about half, so a close no longer throws the content down in its first 200 ms.
- **Lifted page backdrop.** `HermezCoveredTransition.backdrop` paints the strip a pushed page uncovers in the canvas colour (pages only, never hit-tested), so the side navigation no longer shows under a rising sheet.
- **Spring tails.** `HermezSpringCurve` settles at 0.8 % and under 0.15 travel/s (was 0.2 % and 0.1).
  - Settle times: light 265 ms, medium 353 ms, heavy 382 ms, push 622 ms (was 302, 433, 463, 763).
  - The New scheduled job sheet closes 18 % faster.
- **Panel morph (Home +, New task, lane +).**
  - Open is 320 ms on `Cubic(0.22, 1, 0.36, 1)` with no overshoot. Close is 320 ms on `Cubic(0.4, 0, 0.2, 1)`. The fade is 180 ms on `Cubic(0.2, 0, 0, 1)`.
  - Only the plus blurs now; the content panel no longer does.
  - The mapping keeps the direction it started in until it lands, so a tap outside mid-open never jumps.
  - `pushHermezPanel` returns on the frame the panel lands, not after route disposal. That disposal came one frame later, and a caller-hidden button blinked out for that frame (the end-of-close glitch).
- **Kanban.** The New task button is present from the first frame (inert until the boards load) with `FloatingActionButtonAnimator.noAnimation`. Before, it appeared after the boards request and Material's FAB entrance spun it in.
- **Bot detail → chat flash.**
  - Home is pushed over the chat shell from the open drawer, so the drawer stayed open underneath. Leaving for Chat revealed it, then slid it shut.
  - `DrawerShellPage` now calls `ResponsiveDrawerLayoutState.closeUnseen()` when Chat becomes the destination while its route is covered: instant, silent, no latch.
- **Bot detail open stutter.**
  - `_botDataProvider` was auto-disposed, so every open refetched and swapped spinner → details mid-flight in one long frame.
  - It is now kept for 5 minutes. The page shows what it opened with until its route settles, then refreshes in the background. `.value` keeps the old details visible during refresh and pull-to-refresh.
- **Clarify / approval card above the composer.** `_ComposerAttachedOverlay` in `modern_chat_input.dart` rises out of the composer and sinks back into it (SizeTransition riding the top edge, no fade). A leaving card is drawn from a snapshot, because the live card rebuilds to nothing once answered.
- **Tests:**
  - New: `contracting home, a sheet dissolves into its card's own face…` and `the caller hears back on the frame the panel lands…`.
  - Updated: the panel tokens, timing, blur and aperture tests.
  - `test/features/{hermes,navigation,chat}`: 2193 pass. The 5 failures are the known baseline: the auth epoch test, 3× clipboard symlink, and the timezone-dependent sidebar note row.
  - `hermes_decision_card_test` "wall-clock expiry" also fails on a loaded machine (its 50 ms wall-clock budget lapses during setup). It is pre-existing and unrelated.

## 2026-10-04: Hermes Spaces & Pages (plugin + Conduit feature)

Persistent Markdown working documents shared by the user and Hermes. The design follows the implementation plan given by the user:

- One Hermes user plugin plus a native Conduit feature.
- No new service, database server, agent runtime or Hermes core change.
- Steel, Hindsight, the proactive system and skills are untouched.

- **Hermes plugin:** `hermes-plugins/spaces/`. Its README covers contracts, install, backup and rollback.
  - The store (`spaces_store.py`) is SQLite at `/opt/data/spaces/spaces.db`:
    - WAL, foreign keys, `BEGIN IMMEDIATE`;
    - an expected-revision check on every mutation, so a stale writer gets `409 revision_conflict`;
    - one shared DB for all profiles.
  - Five tools in the `spaces` toolset, with no delete tool.
  - A `pre_llm_call` hook that injects Page metadata only (never the body) for a session bound to a Page.
  - REST at `/api/plugins/spaces/` behind dashboard auth.
  - Tests: 30 stdlib `unittest` tests, all passing in the Hermes venv.
- **Deployed 2026-10-04 (user-requested):**
  - Backups: `config.yaml.bak-20261004-spaces` for root and the kai, fast, strong and local profiles.
  - `hermes plugins doctor spaces` is clean.
  - Enabled for root (CLI, no tool-override grant).
  - Profiles: under a profile Hermes loads bundled plugins and `<profile>/plugins/` only, not root user plugins. The first live test showed Kai using the browser instead of the Page for this reason. Each profile with a config (autopilot, fast, hermuse, kai, local, strong) now has `plugins/spaces` symlinked to the root copy and `spaces` in its `plugins.enabled`. `hermes --profile kai tools list` shows the toolset.
  - Verified live: in a Page-bound kai session, Hermes finds `spaces_read_page` and reads the Page.
  - `docker restart hermes-agent_web_1`. The log shows `Mounted plugin API routes: /api/plugins/spaces/`, and unauthenticated health returns 401.
  - Rollback: remove `spaces` from `plugins.enabled` and restart; keep the DB.
- **Conduit (`lib/features/spaces/`):**
  - Models and `HermesSpacesClient`. It uses native PKCE via `HermesDesktopApiService.requestSpacesJson` (prefix-locked to `/api/plugins/spaces/`), or the Dashboard cookie bridge. Ids are validated. `SpacesRevisionConflict` is its own type.
  - Providers, including `spacesAvailableProvider`: the health probe that hides the feature on an older Hermes.
  - `PageDraftController`: 800 ms autosave; states saved, dirty, saving, error and conflict. A conflict keeps the draft, stops retries and loads the remote copy. Keep mine and Use latest both require confirmation.
  - Routes `/spaces`, `/spaces/:spaceId` and `/spaces/:spaceId/pages/:pageId`, not under `/workspace`. They are on the Hermes-only allowlist.
  - Side-nav entry "Spaces" under Kanban, shown only when health is ok.
  - Editor: the Fleather visual editor using the Notes codec and toolbar restrictions, with Markdown canonical. Source mode is forced for HTML, images, footnotes, front matter, directives, display math, tables, nested lists, reference links and setext headings (`page_document_codec.dart`).
  - "Ask Hermes" (`page_chat_launcher.dart`, `page_chat_picker_sheet.dart`):
    - flushes the draft first;
    - offers every Hermes profile, those with a conversation for this Page first ("CONTINUE"), then kai, then the rest (`GET /pages/{id}/chats`);
    - each profile has its own conversation per Page and reuses it;
    - re-creates and re-binds when the gateway refuses a never-prompted session (Hermes persists sessions lazily).
  - Assistant replies get "Save as Page" in the overflow menu. It records `source_session_id` and offers "Open Page" afterwards.
  - In a Page's own conversation, a "PAGE · title · Open" chip sits in the composer's attached slot. Prompts and approvals take the slot first.
- **Not done in v1:**
  - ~~Inline "Page created" cards~~: done in the agentic activity rows (below).
  - Phase 2 items (Artifact references, reviewed drafts, slash commands, Page links, FTS5, profile picker, proactive Page upkeep).

## 2026-10-04: Agentic chat: plan, activity, inspector, delegates, model picker, Active Work, Teams live

Follows the user's "Conduit Agentic Chat UX" spec, scoped to what the live Hermes 0.21.1 exposes. There is no new service, store, planner or Hermes core change: everything is a projection of Hermes sessions, and nothing is invented (no percentages, no guessed durations).

- **What Hermes 0.21.1 sends (verified on the Umbrel):**
  - Plan: `todo.updated {todos, revision}`; resume and create return `todo_state` (Hermes rebuilds it from the transcript when needed). `todo_list` is a deferred core tool but still emits.
  - Tools: `tool.start {tool_id, name, context, args}` and `tool.complete {tool_id, name, args, duration_s, result, summary?}`. Deferred plugin tools run through the bridge `tool_call {name, arguments}`; Conduit names the tool that actually ran.
  - Delegates: `subagent.*` events; RPC `subagent.steer` (returns `queued`, which is not "delivered") and `subagent.interrupt`. 0.21.1 has no `subagent.list` or `tail`.
  - Model: `model.options {profile, session_id?, explicit_only}` per profile. `config.set {session_id, key: model, value: "<model> --provider <p> --session"}`, `key: reasoning` (no scope) and `key: fast` are session-scoped, so a profile's saved default is never rewritten. A switch during a turn is deferred by Hermes to the next turn.
  - Teams: each member's turn runs in a hidden session titled `Group: <room_id>` (source `bot_room`), one per room and profile. Conduit reads it with `session.list {profile, title, include_hidden}`, `session.active_list` and `session.events.since`. It never resumes, steers or interrupts a room session.
- **Data layer:**
  - `HermesAgenticStateStore` (`services/hermes_agentic_state.dart`), per session: the plan (revision-monotonic), delegates (terminal states are sticky; a completion without a known status fails closed) and live model info from `session.info`. It is fed by the Desktop event stream and by resume and create results. Read it through `hermesAgenticStateProvider`.
  - Models: `HermesTodoSnapshot` (`models/hermes_todo.dart`) drops bad steps, roots dangling parents and flattens cycles. `HermesSubagentState` (`models/hermes_subagent.dart`).
  - `HermesTodoUpdated` run event.
  - `HermesLiveActivityEvent` gains the tool id, a preview, Hermes' summary and duration, failure, the delegate id and a Page reference.
  - `HermesActivityPresenter` (pure): verbs ("Searched web" / "Searching web"); start and finish paired into one row; adjacent identical successes folded (never failures, waits, plan updates, delegates or Pages); "+N earlier"; previews redacted.
- **Chat:**
  - Inline run surface:
    - the present-tense line ("Searching web · …"), and a plan bar under the header;
    - the plan preview (current step first), a delegates row and semantic activity, where any row opens the inspector;
    - "Plan paused · 3 of 7" when a run stops with steps left.
  - Context bar above the composer in every Hermes chat: [Page] [Plan n/m] [Delegates] [Model · Effort]. Pending prompts still take the slot first.
  - Sheets:
    - **Plan:** comment, add after, change, cancel a step, replan, continue. Each is a steer while the run is live, or a draft in the composer when idle.
    - **Tool inspector:** reads the transcript by `tool_call_id`; bounded, redacted, with copy.
    - **Delegates:** steer and stop each worker.
    - **Model:** Model and Effort tabs. Applies to this chat only, and a new chat keeps its pick until it is created.
    - **Active Work.**
  - A Page the agent creates or edits shows as "Created Page · title" with an Open button.
- **Elsewhere:**
  - Home: the Active Work card from `session.active_list` covers every client, profile and schedule, needs-you first, and opens a sheet that opens the chat.
  - Live Run: an honest hero (state, elapsed time, the current step) instead of the indeterminate ring.
  - Teams: a live card per working member: current step, recent steps, plan, latest reasoning and the reply as it is written. It is polled every 1.2 s only while the team is busy, and tapping it shows every step.
- **Spaces fixes found in device QA:**
  - Conflicts showed "Spaces request failed (409)". The Desktop Dio drops error bodies (`receiveDataWhenStatusError: false`); Spaces requests now opt in (`receiveErrorBody`) and decode under the client's own cap. A regression test reproduces the phone symptom when the fix is removed.
  - The Ask Hermes picker put a `ListView` inside the sheet's own scroll view (unbounded height). It is now a column, covered by a widget test.
  - Tool search defers every plugin tool; only `tools.tool_search.enabled: off` keeps them eager. The Page hook names `spaces_read_page` and Kai reaches it through the bridge. Documented, not changed.
- **Motion and visual:** see "Live work" in `docs/HERMEZ_MOTION_SYSTEM.md`. Live state moves scale and position only (a breathing dot, rolling text, a travelling band on the live plan step). Large titles collapse into a compact title that travels up from under the bar. The mechanical motif appears on the Live Run hero only while it runs.
- **Device QA (2026-10-05) and what it changed:**
  - The model switch is session-scoped and holds at send time. In the QA turn, OpenCode's free tier answered HTTP 400 and Hermes' fallback chain served the turn on `mimo-v2.6-pro` (Xiaomi).
    - `session.info` reports the model that really served, so Conduit shows it as is.
    - When it differs from the chat's own pick, the pill adds an accent "Fallback" tag and the Model sheet says what happened.
  - The transcript REST endpoint accepts `order=oldest|latest` only. `latest` pages are in time order. An earlier `newest` silently 400'd.
  - Profile chats load history over the socket (`session.history`), which drops tool-call ids. The inspector reads the REST transcript instead (`toolCallMessages`), newest pages first.
  - With a compute host, a resume carries no `todo_state`. A chat on screen restores its plan once from the latest stored `todo_list` result (`restorePlanIfMissing`, triggered by `hermesAgenticStateProvider`). Sends never make that extra request.
  - `tool.generating` (no id, raw bridge name) no longer opens activity rows. A row a finished run never closed shows as finished.
  - Teams: a room's first turn creates the member session, so discovery re-checks every 2 s while the team is busy. Reasoning that repeats the reply preview shows once.
  - The Spaces plugin tests now delete their temp databases. About 90 leftovers from the 2026-10-04 runs were removed from the container's `/tmp` (test artifacts only).
- **Motion polish after QA:**
  - Every "say something to Hermes" control is now a pill that stretches into its field with the Steer morph (`HermezActionPills`): plan step Comment, Add after and Change; Replan; a delegate's Steer.
  - Every agent sheet grows out of what was tapped.
  - Text that changes in place changes instantly, per the motion rules.
  - The Model sheet's panel swaps instantly under its travelling tab indicator.
  - The pill field draws no border of its own (the theme's focused outline showed inside the pill).
- **Second device pass (2026-10-05) and what it changed:**
  - Direction drafted from an open field (Replan with nothing typed while no run is live) now closes the Plan sheet. The field's fold-first Back handling swallowed `maybePop`, so the sheet uses a plain `pop`. The draft waits in the composer beside the send button, keyboard down.
  - Hermes' background self-review emits `review.summary` after `message.complete`. "Finished recently" now skips review events when it looks for the run's last event, so a reviewed run still counts as finished.
  - A finished run's card names its work ("Ran command, Searched files"), not its housekeeping (finding tools, opening skills, keeping the plan), unless that was all it did (`HermesActivityPresenter.headline`).
  - Active Work (Home card and sheet) shows only chats that are running or need the user, per the user; nothing finished. `session.active_list` also lists open idle sessions, so only `working`/`starting`/`waiting` count.
  - Verified on device: the tool inspector grows from its row and shows INPUT and RESULT from the REST transcript; Active Work lists a live run with its model; plan recovery after restart; Replan and Comment morphs.
  - Reopening a native chat in the same app session after a run no longer shows its last reply twice. `session.history` rows carry no `hermesResponseId`/`hermesRunId`, so the finished run's projection was never matched and was appended. A finished, settled projection is now retired when the native transcript ends with the same session's reply with the same visible text (`hermesNativeTranscriptEndsWithReply`, used in the projection overlay on load).
  - Steel: profiles `kai`, `hermuse` and `autopilot` had no `browser:` section and ran a local browser; they now carry the root's Steel block (backups `config.yaml.bak-20261005-steel`). `fast`, `local`, `strong` and the root already had it.
- **Open:** profile sessions use a local browser, not Steel (root config only); enabling Steel for profiles is a permission change awaiting the user.

## 2026-10-05 — Hermes 0.21.5 migration preflight (BLOCKED)

See [migration report](hermes-migration/2026-10-05/REPORT.md),
[customization audit](hermes-migration/2026-10-05/CUSTOMIZATION_AUDIT.md), and
[client compatibility matrix](hermes-migration/2026-10-05/CONDUIT_COMPATIBILITY.md)
before upgrading Hermes. Production remains on custom 0.21.1; stable target is
0.21.5 (`v2026.9.24`, `f97608f1`). No runtime cutover or APK update was performed.
The separately authored [app-impact notes](HERMES_0_21_5_APP_IMPACT.md) complement
the preflight; they do not supersede its deployment gates.

The client patch adds per-socket server-request capability advertisement,
approval queue/frame ID mapping, `open_requests` replay and v7+ decision reply
recovery. It preserves old-server notifications/fallbacks and rejects expired
approvals rather than reporting false success. 48 focused tests pass, including
9 new regressions. Full checks are not green: the serial run was stopped after
3,446 passes / 10 failures, and full analysis exhausted memory. Details and logs
belong in the migration report; these are not full-suite completion counts.
This does NOT make contract 8 fully supported: `connection.request/update/respond`
and `pending_connection` still need the typed MCP/connector adapter before cutover.

Other gates: stale judge backlog, five failed mail items, later seven overdue SMS,
broken Assurance canary/reconcile entry points, a fresh privileged ZFS snapshot,
recovering custom image inputs, and copied-state staging/E2E. Do not clear queues,
change the router's ARMED flag or edit frozen skills to get green checks. Private
recovery copies include 45 integrity-checked SQLite DBs, Postgres dump/globals and
hot-patched source; they are not an atomic cross-service snapshot and never go to Git.
Hindsight's separate embedded-Postgres volume and Qdrant snapshot exports are
not covered by those recovery copies; verify their recovery path before cutover.

Upstream supersedes the hosted-room lease patch. It does NOT supersede the
Hindsight cron/system auto-retain gate: stable removes the bundled provider and
the exclusion must move to the selected external provider. No provider patch,
model/profile changes or unrelated infrastructure changes were deployed.

## 2026-10-05 — Production custom Hermes 0.21.5 deployed; APK updated

This append supersedes the preceding **preflight BLOCKED** runtime status, not
the listed unresolved defects. User subsequently requested minimum safe prep,
then upgrade, recording future breakage. Primary reference:
[deployment and rollback report](hermes-migration/2026-10-05/DEPLOYMENT.md).

- **Production:** `hermes-agent_web_1` now runs
  `hermes-agent-umbrel-teams:v2026.9.24-kai3`, image ID
  `sha256:a7854c3635b65f3298e296ccb29519ccf38a24f177dddc1684b3ddd394800b09`,
  Hermes 0.21.5/f97608f1, config 46, state schema 30, contract 8. Managed/root
  compose and Umbrel regeneration hooks reference kai3. Old stable image retained.
- **Custom image:** pinned official base; old Umbrel wrappers/context/Teams;
  bundled Hindsight bridge + tracked system-prefix gate; pinned SDK and retry
  dependency; nonexistent native skill-bundle override. Upstream supplies the
  former hosted-room lease patch. Do not enable the dormant external Hindsight
  provider blindly or use the failed new-release kai1 candidate.
- **Recovery:** stopped-writer checkpoint at
  `/home/umbrel/.jarvis/hermes-upgrade-20261005/cutover-checkpoint/`, 45 checked
  SQLite copies and targeted private config archive, verified off-box. No fresh
  privileged ZFS snapshot; not full cross-service recovery. The old `kind_gates`
  SSH-owned writer was stopped/auto-removed; do not relaunch it on the old image
  against upgraded shared state. Use new-image Desktop sessions.
- **APK first, then handoff:** bb5521c9 build (source fixes 5c936334/3f21b5c7),
  ARM64 debug build passed, installed `-r` at 17:00:46 Toronto on S25 Ultra.
  App data folders preserved, Home loads real bots, no matching Flutter exception
  in final PID-filtered log. APK hash is in the deployment report. No app reset.
- **Verified:** 48 focused Flutter tests; 36 focused proactive tests; real
  authenticated REST/WS seven-profile reads; six harmless model probes; real
  Hindsight recall/SDK construction; native Steel create/CDP/blank-page/snapshot/
  viewer/release; eleven session DB integrity checks. Model/memory strategy,
  cron IDs/cadences/enable states and armed router compared against checkpoint.
- **Incomplete, do not call all green:** contract-8 mobile connection consent;
  Local 32K-versus-64K context mismatch already present before upgrade; stale
  judge backlog (manual execution completed but no new judgment proved); five
  failed mail items; Assurance canary/reconcile dependencies/SQL; duplicate Teams
  credentials; pre-existing Hermes TextBee adapter failure. Standalone SMS poller
  is healthy and overdue count returned to zero. Home bot count includes existing
  state-only `*skills` directories; do not delete them to fix the count.
- **QA boundaries:** broad Flutter analysis/tests not green/completed; full
  real-device streamed decisions/notifications/deep links/Steer/Stop/Steel takeover
  not performed. SDK memory writes were mocked; no test facts injected. No other
  service upgraded. Rollback helper is prepared but not live-rehearsed.

Build/rollback/smoke assets are tracked in Umbrel config at
`hermes/migrations/2026-10-05/`. Private credentials/logs/DB backups are never Git
inputs. A future agent should start with DEPLOYMENT.md, recheck live versions and
scope, and tackle the typed connector adapter/device acceptance or baseline
proactive repairs as distinct work, not redesign Conduit or change model strategy.
Existing unrelated `graphify-out/` in Conduit and the pre-staged n8n workflow in
Umbrel config were deliberately preserved outside migration commits.

## 2026-10-08 — LiteLLM choices in the chat model picker

- **Scope:** surgical fix on `feat/hermez-motion-foundation`, based on
  `7b1fa73b`. No selector redesign, new transport, model-default change or image
  upgrade. `hermes_desktop_agentic.dart` now sends `refresh: true` with the existing
  profile/session-scoped `model.options` request. The existing provider retains
  its one-minute cache; this is not per-frame discovery or polling.
- **Root cause:** cache-only catalog reads could omit proxy models. The bare
  custom-endpoint discovery also lacked the credential needed to enumerate this
  authenticated LiteLLM endpoint. User explicitly approved adding the minimal
  named provider entry in Hermes.
- **Runtime configuration, not Git:** added `providers.litellm` to the root and
  `autopilot`, `fast`, `hermuse`, `kai`, `local`, `strong` configs, using the
  existing `http://core-litellm:4000/v1` endpoint and existing scoped credentials.
  Each already-proxied profile retains its own key; root/autopilot reuse the
  existing Fast-scoped key, never the master key. Parsed config comparisons
  verified every other setting unchanged. No restart was needed. Private,
  adjacent originals are named `config.yaml.before-litellm-<UTC stamp>`;
  credentials and backups must not enter Git. If keys are rotated later, update
  this named provider too. Rollback can remove only this new provider entry
  without restoring an entire stale config.
- **Live checks:** real `model.options` RPC and runtime-provider resolution
  passed for all seven profiles. Kai/Hermuse expose their permitted
  `spark-contributor`; the other profiles expose `deepseek-flash`,
  `mimo-v2.6-pro`, `mimo-v2.6-flash`, `qwen3-30b-a3b`, `glm-flash`. Defaults and
  fallback chains remain unchanged. No test inference or default-model mutation.
- **Client QA:** 41 focused agentic-service/transport tests pass, including new
  discovery and live-session ownership regressions. Targeted Dart analysis and
  `git diff --check` pass. The device picker showed Strong's LiteLLM group before
  the APK update. The fresh app launches with an active Hermes chat; final
  post-update picker inspection was interrupted by concurrent phone use.
- **APK:** ARM64 debug build passed; installed with `adb install -r` on S25 Ultra
  at 01:17:44 Toronto, 2026-10-08. Version 4.1.7/148; one Conduit debug package,
  existing preferences/database/app folders preserved. SHA256:
  `0cf8e896dff85313ae6ee6e34c9e0dc85fae266b3ae4ac8323cfe6546886e6e0`.
- **Build caveat:** Windows memory pressure caused failed native/JVM builds.
  The successful invocation used task-local Gradle options: heap 1536m,
  metaspace 512m, code cache 192m, `ActiveProcessorCount=2`, one worker,
  no parallelism, Kotlin in-process, and
  `-Dorg.gradle.project.android.jetifier.ignorelist=arm64_v8a_debug.*`.
  The ignored engine archive contains only two native `.so` files, no Java to
  rewrite. No project/toolchain properties were edited. Existing KGP-plugin
  future-compatibility warnings remain. Fresh app logs also contain
  `capability-negotiation-failed`; no matching Flutter/fatal exception was found
  in the scoped launch check. This is not full-suite or broad device acceptance.
