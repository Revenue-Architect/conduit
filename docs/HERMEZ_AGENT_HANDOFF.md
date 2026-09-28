# Hermez / Conduit: agent handoff

Updated 2026-09-28. This is the shortest safe entry point for a new coding session. It describes the `Revenue-Architect/conduit` fork, not stock Conduit. Read code before changing behavior; this document is a map, not an override of current source.

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

The `HermesHomePage` bot data comes from `hermesBotsProvider`; job aggregation is `hermesHomeProfileJobsProvider`, with each result tagged by the queried profile. The Home schedule summary **always** goes to the full Jobs route. Individual timed rows in Today may open one job sheet. A bot card goes to Bot Detail; the Bot Detail chat action creates a new profile-scoped conversation. Recent Home rows call `openHermesSession` on the exact stored session. Avoid replacing these with a generic sidebar transition or canonical Bot Chat.

## Real behavior versus mockups

The user's images are a design-language reference, not sample data to hard-code. Use neutral white / very light gray canvas, white surfaces, thin gray borders, dark typography, sparse orange signals, and quiet technical geometry. See `docs/HERMEZ_VISUAL_SYSTEM.md` and `docs/HERMEZ_VISUAL_PASS_LOG.md`. The most recent bot references favor a dimensional white shell, dark face, orange eyes, and profile-specific small details. `HermezBotMark` draws this natively; it is a visual identity derived from the canonical profile name, not the bot's capabilities or backend avatar. Keep high-density lists quieter than hero areas and test at 320/412 logical pixels and 200% text. Never paint decorative imagery as a fake action.

Home, Bot Detail, Jobs, Kanban, Attention, and Artifacts are native Flutter. A2UI is only for agent-generated visual answers inside chat. A2UI uses explicit `a2ui` fences and the supported v0.9/GenUI catalog; ordinary JSON fences remain Markdown. `MEDIA:` paths are explicit Hermes attachment directives; binaries are fetched over the authenticated same-origin `/api/fs/download` path. Never put cookies or bearer tokens in a URL, message, log, or artifact record. Do not invent progress percentages, job summaries, artifact provenance, or bot availability when Hermes does not provide them.

## Current UX flow

Home → bot card → Bot Detail → new scoped chat. Home → recent conversation → that stored session. Home → Scheduled agents summary → full Jobs page; Today → individual scheduled job sheet. Home → Kanban summary → existing Kanban board. The chat timeline footer now holds the active Hermes run surface, alongside the original streaming footer; it appears only for the exact active Desktop session in running/reconnecting/synchronizing state or with a locally persisted pending decision. It disappears on completion/idle without pending input. Kanban task dependencies/files should navigate to the corresponding real task/artifact where supported. Attention resolution must never interpret sheet dismissal as approval or denial. Artifacts use authenticated bytes and offer large preview/open/share, not a tiny screenshot as the only interaction.

## Inline Live Activity + Steel viewer (implemented watch-only)

`ChatPage` no longer mounts a floating `Positioned` activity card or reserves its height above the composer. `ChatTimelineViewport.liveFooter` composes the original `StreamingTurnFooter` and one `HermesInlineRunSurface`, keyed to the active Hermes stored session ID. The inline surface shows bounded real activity, Steer, confirmed Stop, and exact-session pending requests; Review reuses `showHermesAttentionResolutionSheet`, and dismissing it does not deny anything. Pending reads use `pendingStoredDecisionsForSession()` against the existing local store (no Gateway resume merely to paint chat) and refresh via store mutation events, waiting-for-input, foreground resume, and successful resolution. `HermesLiveRunPage` remains optional larger details, not the only controls.

Hermes Settings has an optional Steel viewer URL (blank by default; the user's private tailnet address is not tracked). During an active turn, expanded inline activity offers Watch browser and a session-scoped full-screen viewer. The embedded `flutter_inappwebview` is created only when opened, uses `interactive=false`, and leaves Steel in charge of its streaming implementation. The full-screen page hides the viewer if that exact run ceases to be active. The installed Steel endpoint answered HTTP 200 from the S25; embedded playback during an actual Steel run remains unverified because the phone locked during QA.

**Takeover remains intentionally unavailable.** `service.steer()` returns true for a **queued** steer, not proof Hermes has paused browser clicks/typing. Hermes source indicates a steer may be appended after a tool result. There is no verified exact-browser handoff acknowledgement in this client contract. Do not switch the viewer to `interactive=true` merely on queued Steer; implement takeover/resume only after an authoritative control-transfer signal exists. See `docs/HERMEZ_INLINE_LIVE_STEEL_RUNBOOK.md` for evidence, acceptance checks, and next steps.

## Verification and release

Start with `git status --short`, `git log -5 --oneline`, and the focused test nearest the changed feature. Important suites live in `test/features/hermes/`, notably `hermes_destinations_smoke_test.dart`, `hermes_live_activity_disclosure_test.dart`, `hermes_kanban_*`, `hermes_artifact_*`, `hermes_a2ui_*`, `hermez_chat_visuals_test.dart`, and `hermez_visual_theme_test.dart`. Run targeted `dart analyze`, focused Flutter tests, and an Android ARM64 debug build. Existing full-project analyzer/test noise may be unrelated; record it separately, but do not declare a changed flow tested if its focused suite fails.

The Android toolchain is in the parent `work/toolchain` directory. Build from this repo with `../toolchain/flutter/bin/flutter.bat build apk --debug --target-platform android-arm64 --no-pub`, setting `ANDROID_HOME` to `../toolchain/android-sdk` and `JAVA_HOME` to `../toolchain/jdk-17.0.20.1+1` if needed. APK output is `build/app/outputs/flutter-apk/app-debug.apk`; install with `adb install -r` to preserve app data. Check `adb devices` first. Wireless ADB may require the user to enable and authorize it again. On-device QA should explicitly open Home, expand a bot, enter a real existing chat, open the full Jobs list, and inspect for Flutter errors/overflow. Do not claim on-device paths passed if only widget tests ran.

For remote delivery, the Hermes Dashboard on the Umbrel tailnet has previously served APKs placed in its artifacts directory via `/api/fs/download?path=<encoded /opt/data/artifacts/filename.apk>` on HTTPS port 8444. Verify the reachable host, auth, exact path, and SHA-256 before sharing a new link. The Desktop Gateway port is not the file-download endpoint. Do not put credentials in the link. Commit and push only after checking that the worktree contains no unrelated changes and that local `main` can fast-forward/push without overwriting other work.

The preceding 2026-09-27 Home pass had a focused Home smoke suite (8 tests), wider bot/session/job/visual suites (61 tests), targeted analyzer, and ARM64 debug APK build pass. On-device inspection then confirmed the responsive six-bot Home roster, Scheduled agents → full Jobs page, and Home bot card → correct Bot Detail. Its APK checksum was `1fc20b13223d52dd1bebc1991e20a864b6bf0e5aa177afa360fb88bcfdc491e1` (`hermez-2026-09-27-home-bots-schedules-arm64-debug.apk`).

The 2026-09-28 inline-run/Steel pass: focused Hermes/decision/chat ownership suite **49 passed**; new inline/Steel and pending-store suite **18 passed**; chat timeline/render/turn-state regression suite **84 passed**. Targeted analysis of new/touched Hermes UI and store files found no issues; a wider single analyzer invocation including the very large `chat_page.dart`/Desktop facade stalled and was stopped, but the ARM64 debug build compiled both. `adb install -r` succeeded on the S25 Ultra, preserving app data. The final APK was also pushed to the phone's Downloads folder as `Hermez-inline-live-2026-09-28-arm64-debug.apk`; local and on-phone SHA-256 both equal `6e2d623ea47a5d968a5f9b75ea29576f6df8ab0f3022f26a4eeb1f13cd227793`. The app launched to Home without a visible Flutter error and the phone reached the Steel debug viewer with HTTP 200. **A real active Hermes turn, embedded Steel playback, inline Steer/Stop/approval, and completion were not accepted on-device**: the phone entered Samsung accidental-touch protection and then keyguard lock before those interactions. Do not upgrade those checks to “passed” from widget tests.

## Known limitations / next investigation

- Device acceptance for an active-to-completed Hermes turn and the embedded Steel WebView is still outstanding; leave the phone unlocked, face-up, and awake for that run. Use a disposable task, verify exact-session decisions/Steer/Stop, browser watch/expand, profile switching, and no scroll jump/Flutter error. The current debug APK is already installed and in Downloads.
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
