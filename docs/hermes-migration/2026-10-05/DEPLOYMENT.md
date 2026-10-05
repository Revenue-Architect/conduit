# Hermes 0.21.5 custom-image deployment — 2026-10-05

## Current outcome

Production is now on **Hermes 0.21.5**, custom image **v2026.9.24-kai3**.
The S25 Ultra received the fresh Conduit ARM64 debug APK with `adb install -r`
before this handoff was updated. App data was not cleared.

This supersedes the deployment status in the earlier [preflight report](REPORT.md).
After that preflight the user explicitly requested the minimum safe preparation,
then the upgrade, with unresolved problems recorded rather than a broad rebuild.
The runtime cutover is completed; **universal integration acceptance is not**.
The table below separates real passes, existing failures, and unperformed tests.

## Versions and provenance

| Item | Value |
|---|---|
| Previous Hermes | 0.21.1 / v2026.9.7 / `2237be355906fbe6065ce1815711eee52b2d646e` |
| Current Hermes | 0.21.5 / v2026.9.24 / `f97608f178d1ffeca59860195ab7da295f7c8e5f` |
| Official base | `nousresearch/hermes-agent@sha256:fca358f12efd65bfaaca05884166f15c0e2788375ca30d77061ac1ebc96452b7` |
| Retained old image | `hermes-agent-umbrel-teams:v2026.9.7-kai1` |
| Old image ID | `sha256:47bdcb6d5a07757a1da3474bea993dca2d396616a0d074f2061ae0333a2ef59b` |
| Current image | `hermes-agent-umbrel-teams:v2026.9.24-kai3` |
| Current image ID | `sha256:a7854c3635b65f3298e296ccb29519ccf38a24f177dddc1684b3ddd394800b09` |
| Container | `hermes-agent_web_1`, running, restart count 0 at final check |
| Runtime | Python 3.13.5; OpenAI SDK 2.24.0; Desktop contract 8 |
| Persistent config / state schema | Config migrated 44 → 46; state schema remains 30 |
| Conduit build source | `feat/hermez-motion-foundation`, `bb5521c9`; source compatibility patch `5c936334`, readiness patch `3f21b5c7` |
| Umbrel config starting point | `feat/hermes-proactive-foundation`, `b896a3b` before deployment commit |

Stable release was reverified against the official
[v2026.9.24 release](https://github.com/NousResearch/hermes-agent/releases/tag/v2026.9.24).
No upstream merge, in-place `hermes update`, or other service upgrade was done.

## What changed and what did not

The custom Dockerfile derives from the pinned official image and copies only the
old Umbrel wrappers/context assets and required plugins. It pins the existing
Teams packages (2.0.13.4), dependency-injector 4.49.1, pydantic-settings 2.15.0,
Hindsight SDK 0.6.1 and aiohttp-retry 2.9.1. UID/GID remain 1000.

The Hindsight bundled 1.0 compatibility bridge is intentional. New upstream
removed that bundled provider. The first new kai1 candidate exposed a removed
lazy-dependency entry and then a missing aiohttp-retry dependency. Both were
fixed; real SDK construction and real recall pass in final kai3. Do not use the
new-release kai1 candidate. Kai3 applies the existing gate from a tracked build
script rather than copying a mutable live hotpatch. External Hindsight 1.1 was
not activated or migrated in this upgrade.

| Custom behavior | Final disposition |
|---|---|
| Hosted-room turn/lease release hotpatch | Not carried into new core; upstream implements it. Old rollback still needs its three saved hotpatched files. |
| Hindsight system-session auto-retain exclusion | Retained and build-reproducible; cron/system/internal/scheduler/webhook prefixes excluded. Manual retain remains available. |
| Hindsight SDK loader | Changed to use the image-pinned SDK; no removed lazy feature name. |
| Umbrel context/bootstrap/TUI/Teams | Retained; no profile or delivery rerouting. |
| Explicit Umbrel proxy auth opt-in | Retained; deployed auth still reports required, Basic provider. No public exposure or gate removal. |
| Frozen skills | No content changes; native `HERMES_BUNDLED_SKILLS=/app/skills-sync-disabled` points to a **nonexistent** path, so synchronization exits without writes. Never create this empty directory. |
| Steel, Kanban, Spaces and persistent plugins | Carried through existing mounts/config; no second transport or backend. |
| Models, fallback/memory/provider/auxiliary settings | Compared against fresh checkpoint, unchanged for all seven configured profiles. |
| Cron and proactive/router | Eleven root job IDs/cadences/enable state retained against fresh checkpoint; router remains ARMED. Local has four existing jobs. No queue clearing. |

Only Hermes runtime image references changed in managed compose, root compose and
Umbrel pre/post-start regeneration hooks. All now use kai3, including restart
regeneration. Mounts, credentials, bindings and gateway command remain.
Postgres, Qdrant, Hindsight service, Steel, n8n, LiteLLM and Conduit dependencies
were not upgraded. The old SSH-owned shared-state container `kind_gates` was
stopped before checkpoint and automatically removed by its existing `--rm`.
Do not revive an old-image Desktop writer against current shared state; reconnect
SSH Desktop clients using the new image. The isolated staging container is stopped.

## Recovery coverage and limitations

Before changing the image, shared Hermes writers were stopped. A fresh checkpoint
contains **45 SQLite backup-API copies**, all integrity-checked, plus a verified
24 MB private archive of root/profile config, auth/env, cron, plugins/hooks/skills
and small root files; original compose and regeneration hooks are included.

Remote private checkpoint:
`/home/umbrel/.jarvis/hermes-upgrade-20261005/cutover-checkpoint/`

Packed recovery file:
`/home/umbrel/.jarvis/hermes-upgrade-20261005/cutover-checkpoint.private.tar.gz`

Verified off-box copy on Windows:
`work/diagnostics/hermes-migration-private/cutover-checkpoint.private.tar.gz`
(relative to the umbrella workspace, **not this Conduit repo**).

Both archive hashes match:
`a4ca934c7d0f81b8977082d457939e791da22a99bb736fc503803998326790ec`.

Older private preflight recovery is at
`/home/umbrel/.jarvis/backups/hermes-migration-20261005-preflight/` and includes a
Postgres personal_platform dump/globals and the three old live hotpatched files.

No fresh privileged ZFS snapshot was taken: noninteractive sudo was unavailable,
and no privileged Docker workaround was used. These copies are **not an atomic
cross-service snapshot**, a complete artifact/log/request-dump backup, or a fresh
backup of Hindsight's separate embedded Postgres volume and Qdrant. The initial
broad config archive hit an old unreadable request dump before cutover; the
targeted recovery archive was completed and verified before proceeding. Keep all
private assets and the old image. Never put private recovery contents into Git.

## Hermes QA matrix

PASS means the explicitly stated check passed, not every possible workflow.

| Surface | Result | Evidence / limit |
|---|---|---|
| Gateway | PASS | Live status 0.21.5, multiplex, running/not busy; authenticated WS capabilities, ping and profile/session reads. No restart loop. |
| Hermes Doctor | WARN / exit 1 | Actual live `python -m hermes_cli.main doctor` finishes with four issues: missing ~/.local/bin/hermes symlink, agent-browser 1 npm vulnerability, web 5, ui-tui 4. Gateway/profile diagnostics run. No blind doctor --fix/npm audit fix applied; review advisories in a separate pinned rebuild. |
| Profiles | PARTIAL | Seven profile REST/WS lists pass. Real harmless inference passes Default, Kai, Fast, Strong, Autopilot, Hermuse without fallback. Local fails the existing 32K config versus Hermes 64K minimum, also present in old source. No model strategy changed. |
| state.db | PASS | 45 checkpoint DB copies intact; eleven live root/profile session DB integrity checks pass. Existing sessions remain visible. Restart/recreation retained session data. |
| Cron | PASS | Eleven root IDs/cadences/enable states retained, four Local jobs readable; scheduler remains enabled. Manual judge execution completed in authoritative executions.db. |
| Judge / candidate flow | FAIL (baseline remains) | Trigger receipt timed out at 60s; did not retry. DB shows completed 16:43:49 → 16:44:58 Toronto. Zero newly updated candidate judgments proved by this probe; stale eligible backlog remains. Not a proved candidate→record_judgment E2E. |
| Proactive overall | PARTIAL | Existing processes/config preserved; focused adapter/research/wiring tests pass. No synthetic notifications or candidate deletion to obtain green health. |
| Hindsight | PASS within checked scope | Actual loaded provider, pinned SDK/client construction and configured recall pass (96 results, contents not printed). Five excluded prefixes plus human/manual callbacks pass with writes mocked. Real human/manual durable write not performed. |
| AgentMail | FAIL (baseline remains) | Existing spool handling/underscore filename regressions pass; same five failed items remain visible. No harmless external test email sent. |
| TextBee | PASS within checked scope | Standalone poller healthy, overdue SMS count returned to 0, OTP/security fixture tests pass. Hermes platform-adapter creation failure was already present Sep 29 and remains a separate issue. |
| Research | PASS within checked scope | Health/dry-run and focused canonical predicate/wiring tests pass; no new outbound research campaign. |
| Router | PASS | Armed flag preserved; dry-run invariant healthy, zero events created by assurance. |
| System Assurance | PARTIAL | Latest dry-run 13/15 healthy: judge freshness and failed mail remain red. Timers enabled/active. Canary/reconcile entrypoints still have baseline missing psycopg2/unquoted-identifier errors; timer scheduling is not execution proof. |
| Qdrant | PASS health | All five collections healthy; no service upgrade or snapshot export this turn. |
| Postgres | PASS health | Existing health/invariants pass; preflight backup retained, no DB/service upgrade. |
| Steel/browser | PASS backend smoke | Native provider create → CDP attach → about:blank navigation → DOM snapshot → debug viewer HTTP 200 → release only our disposable session. Phone rendering/human takeover not retested. |
| Bot Screen | NOT RUN | Optional new feature; not enabled in Conduit for this migration. |
| Plugins/Teams | PARTIAL | Kanban boards/current, artifacts list, MCP settings, 30 toolsets and Umbrel plugin discovery work. Default Teams connected/no error. Duplicate credentials on other profiles are refused by the new runtime's safety guard; no credentials changed. |

Configured profile session totals at final read: Default 325, Kai 31, Fast 18,
Strong 6, Local 8, Autopilot 0, Hermuse 3. Natural cron execution can change these.
Home displays eleven bot rows because pre-existing state-only `*skills` profile
directories also appear in upstream profile enumeration; only seven have configs.
Do not delete those directories or assert they are new working bots.

## Conduit / APK acceptance

The [compatibility matrix](CONDUIT_COMPATIBILITY.md) retains the full interface
audit. Existing source patches advertise `server_requests`, preserve approval
queue/frame IDs, replay `open_requests`, recover v7+ replies and reject expired
decisions while preserving legacy rollback behavior.

**Unimplemented contract-8 mobile surface:** `connection.request/update/respond`
and `pending_connection` still need a typed adapter for multi-target consent,
required env, OAuth and deadlines. MCP settings working does not prove this new
blocking connector flow works. Do not silently map it to old single-server setup.

Fresh focused tests (48 passed):

```powershell
../toolchain/flutter/bin/flutter.bat test --no-pub --reporter expanded --concurrency=1 test/features/hermes/hermes_stable_upgrade_transport_test.dart test/features/hermes/hermes_desktop_transport_test.dart test/features/hermes/hermes_desktop_turn_state_test.dart
```

Nine of these are new transport/service regressions. Earlier targeted Dart analysis
exited 0 with one pre-existing info. Full analysis exhausted Windows memory; a
serial broad test run was stopped at 3,446 passes / 10 failures. A redundant
targeted analysis retry was stopped to free memory for the APK, not counted as a
pass. The full suite is **not green or completed**.

Fresh build and install:

```powershell
$env:ANDROID_HOME=(Resolve-Path '../toolchain/android-sdk').Path
$env:JAVA_HOME=(Resolve-Path '../toolchain/jdk-17.0.20.1+1').Path
../toolchain/flutter/bin/flutter.bat build apk --debug --target-platform android-arm64 --no-pub
../toolchain/android-sdk/platform-tools/adb.exe -s 'adb-R5CY13VFPEP-JAeGpv._adb-tls-connect._tcp' install -r build/app/outputs/flutter-apk/app-debug.apk
```

Build passed in 699.2 seconds. Install returned Success; version 4.1.7/code 148,
lastUpdateTime 2026-10-05 17:00:46 Toronto. Device serial is session-dependent;
use `adb devices -l` rather than assuming it remains constant.

Build warns about future Flutter built-in Kotlin compatibility for
flutter_callkit_incoming, flutter_image_compress_common and home_widget. The
current build succeeds; no dependency upgrade was bundled into this migration.

APK size 219,870,934 bytes; SHA256
`4ac4d317d512b7ea31b0e45f7bd7beae3368fa5d1cee32830537bb0e5c0c33cd`.
Only `app.cogwheel.conduit.debug` appears for Android user 0. Before/after app
data folders include databases/files/shared_prefs/app_flutter; no uninstall,
`pm clear`, sign-out or app-data reset occurred. Normal relaunch succeeded.
Post-install screenshot shows real Home bot data without error UI. App-PID
filtered logs contained no matching Flutter exception/No-Material/Hermes-error
lines at this check. Neither fact proves all app flows.

Still NOT RUN on the phone: fresh PKCE/cookie sign-in and expiry, real streaming
approval/clarification/sudo/secret resolution, steer/stop/queue, reconnect during
an active turn, notification/cold-start deep links, profile A→B→A prompts, Steel
takeover and 200% accessibility pass. Read-only server diagnostics used a
short-lived administrator-local bearer, **not proof of fresh mobile PKCE login**.

Other automated checks:

```bash
cd /home/umbrel/umbrel-config
python3 -m unittest proactive.tests.test_textbee proactive.tests.test_drain_mail_spool proactive.tests.test_research proactive.tests.test_wiring
```

36 passed in 11.458s. Earlier Assurance module tests: 61 passed. Earlier full
proactive run: 201 tests, 194 passed / 3 failed / 4 skipped. Private diagnostic
logs reside in `/home/umbrel/.jarvis/hermes-upgrade-20261005/`; only sanitized
counts/results belong in Git.

## Rollback — image only first, not a blind data restore

Rollback helper is tracked with the Umbrel migration assets and also available
privately at `/home/umbrel/.jarvis/hermes-upgrade-20261005/rollback_image.py`.
It validates recovery inputs before stopping production. It restores old image
references in compose/hooks, recreates the stopped old container, reapplies the
three required old hotpatched files, then starts it. **Not rehearsed live.**

```bash
ssh umbrel 'python3 /home/umbrel/umbrel-config/hermes/migrations/2026-10-05/rollback_image.py --confirm-image-only'
```

This retains current state/config/conversations; matching schema 30 does not
guarantee downgrade safety. Review config 46→44 compatibility first and stop any
other shared-state writer. Current compose/hooks are preserved in a private
`before-rollback-*` directory. Do not restore entire ZFS/Postgres/shared data.
If a specific config migration is incompatible, preserve current credentials
and selectively recover the affected config from checkpoint. Restore DB copies
only after proving incompatibility, stopping all writers and accepting loss of
post-checkpoint changes. Recheck auth, gateway, profile sessions, DB integrity,
cron, memory gate and phone after rollback. Do not merely switch the old tag and
forget its required source hotpatches.

For ordinary current-image restart, use Umbrel's managed lifecycle. Diagnostic
compose invocation requires the existing common file and APP_DATA_DIR:

```bash
export APP_DATA_DIR=/home/umbrel/umbrel/app-data/hermes-agent
cd /opt/umbreld/source/modules/apps/legacy-compat
docker compose --project-name hermes-agent -f docker-compose.common.yml -f "$APP_DATA_DIR/docker-compose.umbreld.yml" ps
```

Rebuild on the same host (retained old image required as an asset source):

```bash
cd /home/umbrel/umbrel-config/hermes/migrations/2026-10-05
docker build -t hermes-agent-umbrel-teams:v2026.9.24-kai3 .
```

The official base is digest-pinned; Python packages are version-pinned, not a
fully vendored/hash-locked dependency archive. Preserve the already tested image
ID rather than rebuilding it casually. No private config is in the build context.

## Useful stable capabilities / next work

- **Use now:** upstream hosted-room slot release; stable state/session fixes;
  multiplex profile routing; request capability negotiation/recovery already
  patched into Conduit; native browser-provider interface with existing Steel.
- **Consider later:** typed mobile connector-consent adapter first; Bot Screen
  and native take-over UI as a separate feature; external Hindsight provider
  migration with the same exclusion gate and actual retain tests; model options,
  reasoning controls, plugin hot-loading and richer Desktop extension surfaces.
- **Leave off for this migration:** changed model routing, blanket skill
  auto-loading/migration, new credential manager, new Steel streaming stack,
  service/dependency upgrades or mass personal-memory writes.
- **Custom code not carried:** hosted-room lease/end-of-turn patches now supplied
  by upstream. Hindsight gate and Umbrel-specific context are still necessary.

Highest-value follow-ups are mobile connector consent and full device critical
workflow acceptance, Local context compatibility without lying about capacity,
stale judge/candidate flow, failed AgentMail review and Assurance timer entrypoint
repairs. The new image is usable for the verified core paths; those outstanding
items prevent calling every integration fully accepted.
