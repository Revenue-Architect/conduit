# Handoff: Conduit ("Hermez") side of Conduit-native notifications (UnifiedPush)

> Codex completion, October 19: build 184 is installed and paired; all eight
> categories now use Conduit with ntfy fallback. See
> [the completion receipt](docs/hermes-push/CODEX-2026-10-19.md). The original
> agent brief below records the earlier, unbuilt state.

Written 2026-10-19 by Claude for Codex (zero context). No secrets in this file.

## 1. Goal

Build the Android app half of `~/.jarvis/docs/CONDUIT-NOTIFICATIONS-SPEC-20261019.md` (on the Umbrel; laptop copy
`C:/Users/Kamran/Documents/Codex/2026-10-07/your-umbrel-ssh-private-key-is/CONDUIT-NOTIFICATIONS-SPEC-20261019.md`), spec phase P4 plus the
phone half of P0/P7, then install it on Kamran's Samsung S25 Ultra and verify on device. Another agent builds the server
(`hermes-notify` container, V2 0.6.0, phone gateway on Tailscale Serve 8450, pairing). Keep every payload/API contract exactly as the spec;
re-read `~/.jarvis/docs/CONDUIT-NOTIFICATIONS-CONTRACT-CHANGES.md` (both NOW EXIST, read section 10) and `CONDUIT-PAIRING.md` before integrating and before the final build.

Kamran's decisions: ntfy Play Store app is the UnifiedPush distributor (LAN first, Tailscale second); in-app Approve = PRESS-AND-HOLD
(Deny = tap + confirm dialog); shade Approve/Deny need an unlocked phone; Critical must NOT bypass Do Not Disturb; no multi-day soak, finish today;
only device is the S25 Ultra; leave commits local (Kamran pushes via bundle). Build number must be 184 (increment if built again).

Extra scope added mid-task (also part of build 184): bare `/opt/data/...` server paths in replies must render as the existing file card (section 6).

## 2. Branch and commit

- Repo: `C:/Users/Kamran/Documents/Codex/2026-09-17/umbrel-ui-bootstrap/work/conduit` (main checkout; others have uncommitted files there, do not touch).
- Worktree (mine): `C:/Users/Kamran/Documents/Codex/2026-09-17/umbrel-ui-bootstrap/work/conduit-unifiedpush`, branch `feat/conduit-unifiedpush`, base `feat/hermes-open-threads-p2` (`ea66979f`).
- Commit: see `git log -1` on the branch (was `60f78e84` before a last amend with the live-contract fixes in section 10) "WIP: UnifiedPush native notifications, Approvals screen, bare /opt/data file cards" (64 files, +9769/-42). Not pushed (laptop cannot push).
- Untracked, intentionally not committed: `android/.kotlin/` (compiler session files), `third_party/mermaid`, `third_party/katex` (copied from the main checkout because worktrees do not populate submodules; their `.git` pointer files were removed).
- Sandbox mirror of the source I edited (Linux sandbox, may be gone): `.../scratchpad/cpush-work/src`. The laptop worktree is the source of truth; the commit matches it.
- Accident repaired: I once appended a stray line to the worktree's `.git` pointer file; it is restored to `gitdir: C:/Users/Kamran/Documents/Codex/2026-09-17/umbrel-ui-bootstrap/work/conduit/.git/worktrees/conduit-unifiedpush` and `git status` works. Its file attributes are now Normal (it was Hidden).

## 3. What was built (files)

Spike S2 result (partial): connector `org.unifiedpush.android:connector:3.3.5` (Maven Central) resolves fine with AGP 9.2.1 / Kotlin 2.4 / Gradle 9.4.1.
It pulls `com.google.crypto.tink:tink` (jar) while another library already brings `tink-android` at the same 1.23.0, so the build has
`configurations.configureEach { exclude(group = "com.google.crypto.tink", module = "tink") }` in `android/app/build.gradle.kts`.
NOT yet confirmed: `checkProfileDuplicateClasses`, Kotlin compile of my code, R8 (release only, not needed for the profile APK). The connector's AAR already declares the
`<queries>` for distributor discovery. 3.x API: `MessagingReceiver` is deprecated in favour of `PushService`, but still supported; I used `MessagingReceiver` (synchronous in the broadcast). Fallback if the build hits a wall: spec's `unifiedpush` pub package.

Android native, package `app.cogwheel.conduit.push` under `android/app/src/main/kotlin/app/cogwheel/conduit/push/`:
`PushReceiver` (UP entry), `PushIntake` (expiry, dedup of last 500 ids, ack queue, foreground-to-Dart vs shade), `PushEnvelope` + `PushPolicy` (pure, JUnit-tested),
`PushRenderer` (NotificationCompat, group summaries, public lock-screen version for approvals/critical/alerts, Approve with `setAuthenticationRequired(true)`, Review fallback below Android 12),
`PushChannels` (8 channels `hermez_<cat>_v1` + shadow; never sets bypassDnd; plain notification sound usage), `ApprovalActionReceiver` + `PushWorkers` (`ActionWorker`: GET approval, check pending + digest, POST decision with `Idempotency-Key: dec-<id>-<decision>-<deviceId>`, rewrite the notification; relay-URL POST for `relay` actions; `PushSyncWorker`: endpoint upload `PUT /devices/me/push`, `POST /push/verify`, batched `POST /push/ack`, `DELETE /devices/me/push`),
`PushVault` (Keystore AES-GCM), `PushStore`, `PushGatewayClient` (HttpURLConnection), `PushWork`, `PushRuntime`, `PushHostApiImpl` + `ConduitPushApi.g.kt` (Pigeon), `DebugPushReceiver` (debug/profile manifests only, `android:permission="android.permission.DUMP"` so only adb can call it).
Edits to existing files: `MainActivity.kt` (attach/detach bridge, 2 spots), `ConduitApplication.kt` (install runtime, create channels), `AndroidManifest.xml` (receivers, extra deep-link filters for `approvals`, `conversations`, `home`), `src/debug` and `src/profile` manifests, new drawable `ic_stat_hermez.xml`.
Pigeon: new `pigeons/conduit_push_api.dart`; `tool/pigeon_codegen/bin/generate.dart` now generates both Pigeon files. `lib/features/push/platform/conduit_push_api.g.dart` is committed (`.gitignore` negation added, same as the existing platform file).

Dart (`lib/features/push/`): `models/` (push_envelope, approval, push_health, push_route), `services/` (push_gateway_client, push_registration_service, push_dispatcher), `providers/` (push_providers, push_runtime), `views/` (approvals_page, approval_detail_page, approval_widgets, approval_formatting, hold_to_confirm_button, push_pairing_page, push_settings_section).
Changed: `notification_router.dart` (push kinds ignore the default-off master toggle; they are gated natively), `app_notification.dart` (7 push kinds, `isPush`), `notification_center.dart` (banner + tap routing, `safePushRoute`), `notification_settings_page.dart` (adds `PushSettingsSection`), `navigation_service.dart` + `app_router.dart` (routes `/profile/hermes/approvals`, `/approvals/:approvalId`, `/profile/hermes/push/pair`), `secure_credential_storage.dart` (push device keys), `hermes_home_page.dart` (Approvals tile), `main.dart` (reads `pushRuntimeProvider`). Strings are English literals like the other Hermes pages (no l10n).
Docs: `docs/hermes-push/README.md`. Media parser: `lib/features/hermes/services/hermes_media_parser.dart` + its test.

Deviations from the spec worth knowing: deep links are `hermez://hermes/profile/hermes/approvals/<id>` (matches the existing `.../live/` pattern, Flutter passes the path to go_router), not `hermez://hermes/approvals`; no QR scanning (no scanner package in the app); no token rotation call; push switches live natively (Pigeon `getPrefs/setPrefs`), approvals/critical ignore per-category switches; `url`/`view` actions open in the external browser, not an in-app browser.

## 4. Verified vs not verified

Verified (laptop, Flutter 3.47 toolchain):
- `flutter pub get`, `build_runner`, Pigeon generation OK. `flutter analyze` on the touched Dart: no errors; a few infos (one fixed after).
- Dart tests run at 10:03 (push + media parser + notifications + Hermes home smoke): 101 pass, 6 fail. The failures were test-side and are FIXED but NOT re-run: (a) hold-button tests needed one `pump()` after `startGesture` because the ticker starts on the first frame; (b) approvals test double-overrode `pushPairingProvider`; (c) `Override` import (`package:flutter_riverpod/misc.dart`); (d) `tester.semantics.longPress(find.semantics.byLabel(...))`; (e) two old media-parser tests used `/opt/data/report.pdf` as "ordinary prose" and now use `/home/user/report.pdf` (intended behaviour change); (f) envelope ids containing `..` now rejected in Dart and Kotlin.
- The Hermes destinations smoke test (Home with the new Approvals tile) and all existing notification tests passed.

NOT verified:
- Any Kotlin compile of the push code, the Kotlin unit tests (`PushEnvelopeTest`, `PushPolicyTest`), `checkProfileDuplicateClasses`.
- The re-run of the Dart tests after the fixes, and the newest media-parser lint fix (regexes rebuilt with interpolation; run the media tests).
- Any APK build. Build 184 has NOT been built or installed. No on-device check was done.

## 5. How to build, install, test

Toolchain on the laptop: `$tc = C:/Users/Kamran/Documents/Codex/2026-09-17/umbrel-ui-bootstrap/work/toolchain` (flutter `$tc/flutter/bin/flutter.bat`, JDK `$tc/jdk-17.0.20.1+1`, `ANDROID_HOME=ANDROID_SDK_ROOT=$tc/android-sdk`, `PUB_CACHE=$tc/pub-cache`, adb `$tc/android-sdk/platform-tools/adb.exe`).
Private build define: `C:/Users/Kamran/Documents/Codex/2026-09-17/umbrel-ui-bootstrap/work/private-build-defines.txt` (one `NAME=value` line; pass it as `--dart-define=<contents>`; never print it). Example script: `.../scratchpad/genui-build183.ps1`.

In the worktree: `flutter pub get` (already done), then
`flutter test test/features/push test/features/hermes/hermes_media_parser_test.dart test/features/notifications` and
`cd android; ./gradlew.bat :app:testDebugUnitTest --tests "app.cogwheel.conduit.push.*" -x :app:compileFlutterBuildDebug` (the `-x` skips a slow Dart kernel step; drop it if the unit-test task complains).
Generated files (`*.g.dart`, `*.freezed.dart`) are git-ignored; if missing run `dart run build_runner build --delete-conflicting-outputs` (about 5 min) and `dart tool/pigeon_codegen/bin/generate.dart` (then `git checkout` the three regenerated committed platform files if they only differ in line endings).
Build: `flutter build apk --profile --target-platform android-arm64 --build-number=184 --dart-define=<defines>` (about 12+ minutes). Output `build/app/outputs/flutter-apk/app-profile.apk`.
Install: `adb -s adb-R5CY13VFPEP-JAeGpv._adb-tls-connect._tcp install -r <apk>` for package `app.cogwheel.conduit.debug`. NEVER uninstall or clear data.
Rollback: before installing, pull the installed 183 split APK(s): `adb -s <serial> shell pm path app.cogwheel.conduit.debug` then `adb pull` each into `C:/Users/Kamran/Documents/Codex/2026-10-07/your-umbrel-ssh-private-key-is/claude-qa-20261019-push/rollback/`. NOT DONE YET (phone unreachable, see 7). A copy of build 183 may also exist under `.../claude-qa-20261018-genui/`; check.
Screenshots go to `.../claude-qa-20261019-push/`.

Device test steps (after the server side is ready): pair via Settings > Notifications > Push from Hermes (gateway default `https://umbrel.tail4c9e01.ts.net:8450`, code from `docker exec hermes-notify notifyctl pair`);
install/open ntfy once; set Hermez and ntfy to Unrestricted battery, remove from Samsung sleeping apps. Without the server you can still test rendering with the debug receiver:
`adb shell am broadcast -n app.cogwheel.conduit.debug/app.cogwheel.conduit.push.DebugPushReceiver --es envelope '<json>'` (envelope examples in `PushEnvelopeTest.kt` and spec 5.1; `ts` must be current epoch seconds), check with `adb shell dumpsys notification --noredact | grep -A20 app.cogwheel.conduit`, and kill the process with `adb shell am kill app.cogwheel.conduit.debug`.
Required checks: an alert push renders as a Hermez notification on the right channel; an approval push shows Approve/Deny; press-and-hold Approve in the Approvals screen works; the shade Approve works only when unlocked; taps open the right screen (`approvals/<id>`, live session); behaviour when the Conduit endpoint is unhealthy (health card warnings, server falls back to plain ntfy); Critical does not break through DND.

## 6. Bare-path file card (extra scope) 

Request from the coordinator/Kamran: replies sometimes give a bare path like `/opt/data/specialist-handoffs/2026-10-18/kai-20261018_231519_20db93.md` (session `20261018_231313_e7c11b`, message 9747) instead of a `MEDIA:` line; make it render as the existing file card (Open/Share via `HermesArtifactClient.download` -> `/api/fs/download` with the session id).
Done in `hermes_media_parser.dart` (`parseHermesMedia`): bare absolute paths under `/opt/data/` ending in an existing `_mediaDeliveryExtensions` extension become artifacts; masked code fences, inline code and blockquotes stay text, except an inline-code span that is exactly the path; the path in the text is replaced by the file name; paths with `..`, `.secrets`, `.env*`, `auth.json`, `config.yaml` are ignored; no other roots, schemes or relative paths; a path already given by `MEDIA:` yields no second card; `MEDIA:` mid-sentence already worked (test added). 14 new tests in `test/features/hermes/hermes_media_parser_test.dart` (message 9747 style text, backticked, fenced, secrets, mixed with MEDIA line). Those tests passed at 10:03 except two old tests that were updated as noted; the final lint-only rewrite of the regexes has not been re-run.
Not done: on-device check that session `20261018_231313_e7c11b` shows the handoff as a card that opens (needs the phone and build 184). If the card does not open, check `HermesArtifactClient.download` handling of the path in `hermes_artifact_client.dart` and the server `/api/fs/download` authorisation; do not widen what can be downloaded.

## 7. Known issues and environment traps

- PHONE UNREACHABLE: at 09:41 the laptop's adb mDNS listed only a different device (`adb-57301HFAG13HX9`, 192.168.2.70), not the S25 (`adb-R5CY13VFPEP-JAeGpv`). Kamran probably has to re-enable Developer options > Wireless debugging (and keep the screen on). The laptop's adb server dies when an ssh session ends, so start it inside a scheduled task or the same command (`adb start-server`, wait ~20 s, `adb mdns services`, `adb devices -l`). Tailscale name of the phone: `kamrans-s25-ultra` (100.112.6.103).
- Server side was not ready at 10:20 but IS live by 10:30 (gateway on 8450, ntfy upgraded, CONTRACT-CHANGES and PAIRING docs written). Section 10 lists how I adapted.
- Long laptop jobs: run them as scheduled tasks (`schtasks /Create /TN x /TR <cmd file> /SC ONCE /ST 23:59 /F` then `/Run`; "Interactive only"). Several of my tasks ended with exit `-1073741510` (Ctrl-C) for no clear reason, including one that died instantly; something on the laptop (another agent's cleanup, or console events) kills console-attached jobs. What worked: `Start-Process cmd.exe /c <bat> -WindowStyle Hidden -Wait` so each tool runs in its own console, writing output to a file, and reading that file with `scp` (never `type`/`Get-Content` on a file being written, and never wrap reads in `timeout`, they hung). Helper scripts live in `.../scratchpad/cpush-*.sh|ps1` in the sandbox, not on the laptop; the laptop has copies under `C:/Users/Kamran/cpush/`.
- A stale lock `.dart_tool/hooks_runner/shared/flutter_soloud/.lock` made `compileFlutterBuildDebug` fail after 5 minutes (a killed run left it). Delete `.dart_tool/hooks_runner/**/.lock` when no dart process runs.
- `flutter analyze lib/core` alone takes about 7 minutes; analyze only the touched folders.
- CRLF: the laptop checkout has `core.autocrlf=true`; I edit LF files and git normalizes. Do not rewrite whole files with CRLF changes.
- Risky spots I could not compile-check: `NotificationCompat.Action.Builder.setAuthenticationRequired` (needs androidx.core >= 1.8; resolved versions in the Gradle cache go up to 1.18), `PushDeepLinks` smart casts, nested access to `RetryAction.KIND`, generated Pigeon names (`PushNativeStatus` named arguments in `PushHostApiImpl.status()`), `ForegroundInfo` for expedited work.
- Env: `notificationsEnabled` (master toggle) defaults to false in this app; push deliberately does not depend on it.

## 8. Server contract relied on (from the spec, section 5; no secrets)

Gateway base `https://umbrel.tail4c9e01.ts.net:8450/phone/v1`, `Authorization: Bearer hpd_<token>` except pair; JSON; errors `{ "error": "<code>" }`; `Cache-Control: no-store`.
- `POST /pair` `{code, device_name, platform:"android", app_version}` -> `{device_id, token, expires_at, scopes[], gateway_epoch}` (expires_at parsed as epoch seconds or ISO string).
- `GET /devices/me` -> device info, endpoint health, fallback flags (parsed leniently: `endpoint.state` or `endpoint_state`; `fallback`/`fallback_flags` map of category -> bool). Unknown shape means "unknown", not healthy.
- `PUT /devices/me/push` `{generation, distributor, endpoint, p256dh, auth, instance}` (instance is `"default"`, p256dh/auth base64url unpadded from the connector); `DELETE /devices/me/push`; `POST /push/verify {nonce}` (nonce read from top-level `nonce` of the `verify` envelope); `POST /push/ack {ids:[...], rcv_ts}`.
- `GET /approvals?status=pending|approved|denied|expired|cancelled|all&limit=&before=` -> `{items:[...], next_before}` (also accepts `approvals`); rows have `id, action_type, description, status, created_at, expires_at, requested_by, resolved_at, resolved_by, decided_via, payload_digest, wake_state`.
- `GET /approvals/{uuid}` -> `{item:{... payload, origin{session_id}, events[{type,created_at,actor,details}], payload_digest}}` (a bare object is accepted too).
- `POST /approvals/{uuid}/decision` `{decision:"approve"|"deny", digest, notes?}` + `Idempotency-Key`; 200 `{id,status}` (replay 200 `replayed:true`); 409 `{error, status}` for already decided or `digest_mismatch`; 404/410 gone; 401/403 re-pair.
- Push envelope v1 (spec 5.1), cleartext JSON inside the RFC 8291 encrypted message: `v,t(notify|dismiss|update|probe|verify),id,dedupe,tag,ts,ttl,cat,pri,title,body,open{k,id|url},actions[{id,label,kind(decide|relay|view),approval,digest,auth,url,method}],group,ack,shadow,nonce`. Categories: approvals, critical, alerts, proactive, briefs, agent, watch, status. Relay/view URLs must start with `https://umbrel.tail4c9e01.ts.net:8447/`. Undecrypted messages render only as a generic "Hermes has an update".
- V2 itself returns `{"items":[...]}` for lists and `{"item":{...}}` for detail (read from `approvals.py` 0.5.0), which the client accepts.

## 9. Next steps for Codex, in order

1. Get the phone back on wireless adb (ask Kamran); pull the installed 183 APK into `.../claude-qa-20261019-push/rollback/`.
2. Delete stale hook locks; run the Dart tests and the Kotlin compile/unit tests; fix whatever the first Kotlin compile reports (expect a few small errors); run `checkProfileDuplicateClasses` (profile build does it) to close spike S2.
3. Re-read the server docs (CONTRACT-CHANGES, PAIRING); adjust Dart/Kotlin if shapes changed.
4. Build 184 profile APK, install with `-r`, run the on-device checks in section 5 and the session `20261018_231313_e7c11b` file-card check in section 6; save screenshots.
5. Update `docs/hermes-push/README.md` if behaviour changed, commit on `feat/conduit-unifiedpush`, report branch + commit for Kamran's bundle push.

## 10. Live server contract (read after the code was written) and what I changed

Read `~/.jarvis/docs/CONDUIT-NOTIFICATIONS-CONTRACT-CHANGES.md` and `CONDUIT-PAIRING.md` first; they win over section 8. Applied in the final commit:
- `PUT /devices/me/push`: body must contain exactly `generation, endpoint, p256dh, auth` plus optional `distributor, instance`; the endpoint is sent exactly as the distributor gave it (it already ends in `?up=1`). `distributor` is now omitted when empty. A lower generation answers 200 `{ignored:true, generation}`: the worker now raises its counter past the server's and retries. 400/409 (`topic_in_use`, `topic_retired`, `topic_key_mismatch`, `generation_conflict`) are recorded as `endpoint_rejected_<code>` (shown by the health card), not hidden.
- `GET /devices/me`: live shape is `{device, endpoint:{state,...}|null, categories:{<cat>:{mode,fallback_active}}, gateway_epoch, ...}`; `DeviceHealth.fromJson` reads `categories[*].fallback_active` (test added).
- Pair errors are 403 `invalid_code`, 429 `rate_limited|pairing_locked`; the pairing page maps 400/401/403 to the "code not accepted" text. The code prints as `XXXXX-XXXXX`; normalisation drops dashes/spaces.
- `update` envelopes: same `tag` `approval:<uuid>`, no actions, no sound (handled by `showUpdate`, `setOnlyAlertOnce`). `verify`: `cat:"status"`, empty title/body, top-level `nonce`, show nothing, answer `POST /push/verify {nonce}`. `probe`: `ack:true`, show nothing, ack at once. Ack EVERY envelope with `ack:true`.
- Times: device/push API in epoch seconds, approvals API ISO 8601 with offset; `before` cursor is `next_before` passed back unchanged.
Still TO DO against the live contract:
- `GET /inbox?since=<last next ULID>&limit=100` catch-up on app start/resume is NOT implemented (store the last `next`, replay missed envelopes through `PushIntake`, which already dedups).
- Token rotation (`POST /devices/me/token/rotate`) and handling a changed `gateway_epoch` (treat as "re-pair") are not implemented.
- ntfy on the phone must be signed in as `kamran` and have its default server set (tailnet `https://umbrel.tail4c9e01.ts.net:8446` preferred); pairing flow in `CONDUIT-PAIRING.md` (`docker exec hermes-notify notifyctl pair --minutes 30`, then `notifyctl test --category <cat>` and `notifyctl cutover`; approvals last, supervised). Do not run `notifyctl cutover` without Kamran's say-so for production categories; `notifyctl test` is Conduit-only and safe.
