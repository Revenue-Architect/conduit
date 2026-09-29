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

