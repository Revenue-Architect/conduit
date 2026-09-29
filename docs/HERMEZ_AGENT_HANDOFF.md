# Hermez / Conduit: agent handoff

Updated 2026-09-28 (night), after the physical-motion rewrite, two device feedback passes, and a micro-motion pass (see the last section). This is the shortest safe entry point for a new coding session with no chat history. It describes the `Revenue-Architect/conduit` fork, not stock Conduit. Read code before changing behavior; this document is a map, not an override of current source.

## Start here

1. Read this file, then `docs/HERMEZ_MOTION_SYSTEM.md` (required before touching any Hermez motion), `docs/HERMEZ_VISUAL_SYSTEM.md`, and `docs/HERMEZ_INLINE_LIVE_STEEL_RUNBOOK.md`.
2. Run `git status --short` and `git log -8 --oneline` from `work/conduit`. Do not `git restore`, reset, or sync upstream. `origin/main` has one newer README-only commit (`105db9f6`) that this branch has not merged.
3. Phone package is `app.cogwheel.conduit.debug`. Wireless ADB (Samsung SM-S938W): serial `adb-R5CY13VFPEP-JAeGpv._adb-tls-connect._tcp`; if `adb devices` is empty after an adb restart, run `adb mdns services` and the phone reappears. `adb install -r` keeps the Hermes account. Toolchain: `../toolchain/flutter`, `../toolchain/android-sdk`, `../toolchain/jdk-17.0.20.1+1`.
4. Backups outside git: `work/backups/pre-motion-v2-20260928` (HEAD bundle, the pre-session uncommitted patch, copies of dirty files). Device frame captures and test logs: `work/diagnostics/hermez-motion-v2-20260928`.

**No fades.** The user's hard rule: nothing in Hermez animates opacity. Use the primitives in `lib/features/hermes/motion/` (`HermezMotionSurface`, `HermezMorph*`, `HermezRoute`/`pushHermezSheet`, `HermezEntrance`, `HermezPresence`, `HermezSize`, `HermezMotionGroup`, `HermezIconSwap`) and `showConduitDialog` for dialogs. Do not add `FadeTransition`, `AnimatedOpacity`, `AnimatedSwitcher` default transitions, `.fadeIn()`, or plain `showDialog`. `nib_motion` 0.3.1 is pinned and wrapped.

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
