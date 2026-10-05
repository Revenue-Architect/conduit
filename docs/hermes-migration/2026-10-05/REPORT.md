# Hermes stable migration preflight — 2026-10-05

## Outcome: production upgrade blocked, old runtime preserved

This is NOT a completed upgrade. No new production image/container/config was
deployed. Per the requested safety gate, production stays on 0.21.1 because
critical baseline checks and target compatibility prerequisites are not green.
Do not run `hermes update`, switch the image, clear failed queues, or change the
proactive router flag based on this report.

### Version report

| Item | Verified value |
|---|---|
| Production Hermes | 0.21.1 / v2026.9.7 / `2237be355906fbe6065ce1815711eee52b2d646e` |
| Latest stable target | 0.21.5 / v2026.9.24 / `f97608f178d1ffeca59860195ab7da295f7c8e5f` |
| Release published | 2026-09-24 10:09:38 UTC; non-draft, non-prerelease |
| Old image | `hermes-agent-umbrel-teams:v2026.9.7-kai1` |
| Old image ID | `sha256:47bdcb6d5a07757a1da3474bea993dca2d396616a0d074f2061ae0333a2ef59b` |
| New image | **Not built**; do not reuse/overwrite the old tag |
| Production container | `hermes-agent_web_1`, running; no restart by this task |
| Additional runtime | `kind_gates`, SSH-owned isolated Desktop serve sharing state; do not create another writer or stop it blindly |
| Umbrel config baseline | `feat/hermes-proactive-foundation`, `1aaea21` |
| Conduit baseline | `feat/hermez-motion-foundation`, `dc689da386a511ad2dd381b79ed101dbfba0ea89` |
| First client readiness patch | `3f21b5c7`; approval/reconnect fixtures, not a deployed APK |
| Final client safety follow-up | `5c936334`; expiry handling and cached-contract rollback regression |

Latest-release status was rechecked against the live GitHub release API, not the
old handoff. Releases crossed: v2026.9.11, v2026.9.14, v2026.9.21 and v2026.9.24.
Sources: [stable release](https://github.com/NousResearch/hermes-agent/releases/tag/v2026.9.24),
[exact target source](https://github.com/NousResearch/hermes-agent/tree/f97608f178d1ffeca59860195ab7da295f7c8e5f).

Config is version 44 on production, 46 in target defaults. Migration 45 can add
the Connections toolset to saved explicit platform toolsets; migration 46 turns
legacy MCP `disabled:true` into `enabled:false`. Inspect these changes on COPY
only. Both releases declare state schema 30, but extensive DB/FTS/lease/recovery
code changed: matching schema numbers do not prove downgrade compatibility.

## Work completed

- Inventoried production image, mounts, profiles, plugins, hot patches, proactive
  timers and repo state. Fetched/inspected the exact stable source; did not upgrade it.
- Created private recovery copies on Umbrel and copied the preflight directory
  to the Windows diagnostics area. No credentials/personal backup data go to Git.
- Compared hot patches against the old upstream source and target stable source.
  Hosted-room lease patch is superseded; Hindsight protection is not.
- Audited Conduit interfaces before code changes. Added backward-compatible
  capability negotiation, approval queue/frame ID normalization, unanswered
  request replay and decision recovery. No client redesign/dependency changes.
- Preserved unrelated dirty/staged work in both repos, frozen skills, model routing,
  other services, bindings and router ARMED state.

Detailed [customization audit](CUSTOMIZATION_AUDIT.md) and
[Conduit interface matrix](CONDUIT_COMPATIBILITY.md) accompany this report.

## Cutover blockers

1. **Existing proactive health failures.** Initial assurance: 13/15 healthy;
   oldest pending candidate ~4,610 minutes old and five failed mail items.
   Later saved baseline: 12/15 healthy, oldest pending ~4,705 minutes, the same
   five failed mail items, plus seven inbound SMS overdue >20 minutes.
   These were observed on the OLD image, not introduced by an upgrade.
2. **Assurance timer entry points are broken.** `--canary --dry-run` and
   `--reconcile --dry-run` fail with `ModuleNotFoundError: psycopg2`. Source then
   also uses unquoted `core-postgres`, database/user and result-key identifiers.
   Passing unit tests do not demonstrate runnable canary/reconciliation timers.
3. **Conduit target connector consent is unimplemented.** Contract 8 replaces
   `mcp.setup.*` with `connection.request/update/respond` and `pending_connection`.
   The new approval transport patch does not solve that separate operation model.
4. **Hindsight external-provider gate must be ported and tested.** Stable removes
   the bundled provider. Neither the pinned upstream external provider nor the
   dormant installed provider has the required system-prefix auto-retain exclusion.
5. **No fresh migration ZFS snapshot.** Pool is healthy; last observed snapshot
   is `pre-ssd-20261002`. No delegated snapshot permission is shown and `sudo -n`
   requires a password. Do not loosen sudo/ZFS permissions or expose a password.
6. **Custom image build inputs / staging validation are incomplete.** The original
   custom Dockerfile/build-time patches were not found in inspected locations.
   No target image, copied-state staging instance, real target auth/profile/chat
   E2E, browser smoke or rollback rehearsal exists yet.

## Baseline QA matrix

PASS below means the stated OLD-runtime check passed, not target E2E validation.
Every target integration is blocked/not run until a copied-state image exists.

| Surface | Old baseline | Target 0.21.5 |
|---|---|---|
| Gateway | PASS: production container and gateway/dashboard supervision up | NOT RUN |
| Profiles | PASS inventory: default, Kai, Fast, Strong, Local, Autopilot, Hermuse; model configs preserved | NOT RUN; A→B→A and actual prompts required |
| State DB | PASS backup: 45 discovered SQLite databases copied online; every copy `integrity_check=ok` | NOT RUN; restart/new session/FTS/lock checks required |
| Cron | PASS inventory: 11 jobs, 9 enabled; proactive-judge resolves by name | NOT RUN; successful controlled execution required |
| Judge | FAIL: stale pending candidate backlog | NOT RUN |
| Proactive suite | FAIL baseline: 201 tests, 3 failures, 4 skipped | NOT RUN |
| Hindsight | PASS health: assurance sees no new cron pollution; gate present in live bundled provider | NOT RUN; normal/system/manual retain tests required |
| AgentMail | FAIL: 3 failed items 1–24h old, 2 failed items >24h | NOT RUN; do not erase them |
| TextBee | Initially healthy; later FAIL: 7 overdue inbound messages | NOT RUN; OTP/security fixture coverage must be retained |
| Research | PASS: shared canonical predicate present; assurance sees no awaiting candidates | NOT RUN controlled flow |
| Router | PASS: fresh timer, ARMED=true, no stuck routable candidates; flag untouched | NOT RUN controlled flow |
| System Assurance | FAIL: normal check degraded; canary/reconcile entry points fail, despite 61 unit tests passing | NOT RUN |
| Qdrant | PASS health: all 5 collections green; documents 209, personal_notes 9, incidents 3, kaizen_knowledge 38, hermes_observations 11 points | NOT RUN |
| Postgres | PASS: required schemas, readable custom-format dump | NOT RUN; no DB migration attempted |
| Steel/browser | Container healthy, existing private provider/pane inventoried; browser action not exercised | NOT RUN |
| Bot Screen | NOT APPLICABLE to existing Conduit behavior | Optional; NOT RUN, not required to enable |
| Plugins | PASS inventory only; live custom providers/panes persisted | NOT RUN discovery/hooks/consent |
| Conduit | Focused transport/session tests pass; full-suite verification recorded below | Fixtures only, not target device E2E |

Doctor exited 0 but reported four issues: missing optional user-local CLI symlink
(Docker venv CLI works) and npm vulnerability findings in agent-browser, web and
ui-tui. No critical npm findings were reported. Do not blindly update npm packages
during this migration or treat exit 0 as a completely clean Doctor.

All three Assurance timers are loaded/enabled/active. Observed next triggers:
normal check 2026-10-05 19:13:26 UTC, canary 2026-10-06 06:00 UTC, reconcile
2026-10-06 06:30 UTC. `system_assurance.service` last exited 1. A scheduled timer
is not proof its command works.

Postgres read-only counts at inspection: candidates 62 (24 pending, 36 judged,
2 expired), events 379, activity 261, notifications 2, suppressions 1, goals 0,
goal_links 0; assurance check_state 15 / check_history 285. Counts are time-bound
baseline observations, not frozen expectations.

## Tests and evidence

Commands are run in the actual fork with its bundled Flutter 3.47.3 / Dart 3.13.3.
No dependency upgrade or code generation was required by this patch.

```powershell
../toolchain/flutter/bin/flutter.bat test --no-pub --reporter expanded --concurrency=1 `
  test/features/hermes/hermes_stable_upgrade_transport_test.dart `
  test/features/hermes/hermes_desktop_transport_test.dart `
  test/features/hermes/hermes_desktop_turn_state_test.dart
```

**48 passed**, including 9 new regressions (6 transport and 3 service recovery
tests). Covers old -32601 compatibility, new approval/cancel IDs, resume replay,
deduplication, unsupported host requests, legacy notifications, profile ownership,
v8 recovered batch answers, expired proxy/approval responses, and legacy replies
after cached newer-contract knowledge. Final focused run exited 0 in 10 seconds;
evidence: `work/diagnostics/hermes-upgrade-20261005-focused-final.log`.
The initial new-test run
was red; a later fixture failure (`thenReturn` on a Stream) was corrected and the
whole focused group rerun successfully.

Full `flutter analyze --no-pub` and `flutter test --no-pub` were attempted before
the patch. The first full test log reached +884 / -6 without a completion summary:
one FTS cold-start budget failure (585ms vs 400ms), one incompatible-server
expectation, and four suites disconnected while loading. The initial analyzer
log is empty; it is not a passing result. Post-patch full runs are recorded in
`work/diagnostics/hermes-upgrade-20261005-{analyze,tests}-postpatch.log`.
Post-patch full checks are **NOT PASSING**:

- Full test run reached **939 passed / 3 failures** before the Dart VM terminated
  with Windows exit `-1073740791`; no suite completion. Failures included FTS
  append budget (49.339ms vs 10ms), the existing incompatible-server expectation,
  and a router suite that could not load. The VM then failed to start a worker
  thread. This is not a completed all-tests count.
- Full analyzer's plugin VM terminated with **Out of memory**, the same Windows
  exit code. Therefore there is no reliable project-wide analyzer summary.
- The host has 16GB RAM and concurrent unrelated agent work. Do not call these
  infrastructure failures new migration-code defects or suppress them to claim
  a green build. Re-run full checks sequentially on an uncongested host before
  release. No target device/app acceptance test was performed.

A sequential retry (`flutter test --no-pub --reporter expanded --concurrency=1`)
ran for 19m20s and reached **3,446 passed / 10 failures**. It was deliberately
interrupted once the broad run was already red, to finish the focused patch check
promptly. This is an **incomplete** run, not a full-suite success or final total.
Evidence: `work/diagnostics/hermes-upgrade-20261005-tests-serial.log`.
Observed failures:

- FTS append budget: 19.412ms versus the 10ms limit.
- `server_incompatible_provider_test`: expected true, received false (also failed
  before the patch).
- `share_receiver_service_test`: Windows path separators differ from the fixture.
- Three `share_staging_cleanup_test` and three `clipboard_attachment_service_test`
  cases: Windows symlink creation refused with error 1314 (missing privilege).
- `direct_send_history_links_test`: the gated direct-attachment auth-epoch test
  timed out waiting for its condition.

These tests are outside the files changed by this patch. Do not silently relax
their expectations or grant Windows privileges to make this migration appear
green; diagnose them separately before a client release.

Final targeted Dart analysis of the changed transport, service entry point and tests
exited 0 with one pre-existing informational lint in
`hermes_desktop_api_service.dart:415` (curly braces); no new errors/warnings.
Evidence: `work/diagnostics/hermes-upgrade-20261005-analyze-final.log`.

Server commands:

```sh
cd /home/umbrel/umbrel-config
python3 -m unittest discover -s proactive/tests -v
python3 -m unittest proactive.system_assurance.tests.test_assurance -v
python3 -m proactive.system_assurance.assurance --dry-run
python3 -m proactive.system_assurance.assurance --canary --dry-run
python3 -m proactive.system_assurance.assurance --reconcile --dry-run
```

- Proactive: **201 run, 3 failures, 4 skipped** (therefore 194 passed).
  Failures: `test_existing_row_migration`, `test_reply_received`, `test_attention_shape`.
  Logs: `/tmp/hermes-migration-proactive-baseline.log`.
- Assurance modules: **61 passed**. Log: `/tmp/hermes-migration-assurance-tests.log`.
- Normal dry-run: exit 1, degraded; saved privately with the recovery assets.
- Canary and reconcile entry-point dry-runs: fail on missing `psycopg2`.
- Target upstream tests/device E2E: **not run**; no target image exists.

## Backup and rollback

Private server recovery directory:
`/home/umbrel/.jarvis/backups/hermes-migration-20261005-preflight/` (owner-only).
Windows copy:
`work/diagnostics/hermes-migration-private/hermes-migration-20261005-preflight/`.
Includes hot-patched Python, managed compose, private container inspection,
45 integrity-checked SQLite copies, Postgres custom dump/globals and persistent
files archive. `pg_restore --list` and `gzip -t` passed. `SHA256SUMS` covers the
data archive, Postgres dump and saved hot patches. No live database was overwritten.

The files archive was made while Hermes was running; tar warned that the live
directory changed and ignored runtime sockets. It is a recovery copy, **not an
atomic point-in-time snapshot**. SQLite copies are individually consistent, not a
cross-database transaction. Copied state must be used for staging, never mounted
writable alongside production. Fresh ZFS snapshot and rehearsal remain mandatory.

Backup coverage is deliberately explicit: the Postgres dump covers
`personal_platform` plus cluster globals. Hindsight's embedded Postgres lives in
the separate Docker volume `hindsight_data`, mounted at `/home/hindsight/.pg0`;
this task did not create a fresh backup of that volume. Qdrant collections were
inventoried, not snapshot-exported. These assets are therefore **not a complete
cross-service migration restore point**. Obtain verified service-specific recovery
copies and the fresh privileged snapshot before any cutover.

**Right now rollback requires no action: production never changed.** Keep the old
image ID/tag and its saved hot patches. For a later image-only rollback, after
coordinating the SSH-owned writer and confirming no incompatible state changes:

```sh
# These are a documented recovery sequence, NOT executed/rehearsed this time.
export APP_DATA_DIR=/home/umbrel/umbrel/app-data/hermes-agent
cd /opt/umbreld/source/modules/apps/legacy-compat
docker compose --project-name hermes-agent \
  -f docker-compose.common.yml \
  -f /home/umbrel/umbrel/app-data/hermes-agent/docker-compose.umbreld.yml stop web

# Restore the known old managed compose file (only after preserving the new one).
cp /home/umbrel/umbrel/app-data/hermes-agent/docker-compose.umbreld.yml \
  /home/umbrel/.jarvis/backups/hermes-migration-20261005-preflight/compose-before-rollback.private.yml
cp /home/umbrel/.jarvis/backups/hermes-migration-20261005-preflight/docker-compose.umbreld.yml \
  /home/umbrel/umbrel/app-data/hermes-agent/docker-compose.umbreld.yml

docker compose --project-name hermes-agent \
  -f docker-compose.common.yml \
  -f /home/umbrel/umbrel/app-data/hermes-agent/docker-compose.umbreld.yml \
  up --no-start --no-deps --force-recreate web

# Restore required LIVE hot patches before starting a recreated old image.
docker cp /home/umbrel/.jarvis/backups/hermes-migration-20261005-preflight/source/hindsight.py \
  hermes-agent_web_1:/opt/hermes/plugins/memory/hindsight/__init__.py
docker cp /home/umbrel/.jarvis/backups/hermes-migration-20261005-preflight/source/session_lifecycle.py \
  hermes-agent_web_1:/opt/hermes/tui_gateway/session_lifecycle.py
docker cp /home/umbrel/.jarvis/backups/hermes-migration-20261005-preflight/source/prompt_turn.py \
  hermes-agent_web_1:/opt/hermes/tui_gateway/prompt_turn.py
docker compose --project-name hermes-agent \
  -f docker-compose.common.yml \
  -f /home/umbrel/umbrel/app-data/hermes-agent/docker-compose.umbreld.yml start web
docker exec hermes-agent_web_1 /opt/hermes/.venv/bin/hermes --version
```

Do not run image-only rollback against changed incompatible state. Rehearse
selective config/SQLite restoration from the fresh cutover snapshot on a copy
first. Never roll back the whole shared ZFS dataset or restore the whole Postgres
dump just to change Hermes: that would also revert unrelated live services/data.
After rollback verify Doctor, gateway, profile routing, cron/judge, assurance,
Hindsight gate, Conduit auth/chat/approvals and the unchanged router flag.

The saved compose configuration was validated read-only with `config --images`
and the explicit `APP_DATA_DIR` above; it resolves to the old custom image.
Without this environment variable it looks for a nonexistent `/data/hermes`
env file. Do not omit it or substitute a generic `docker run` command.

## Continue safely

1. Repair/re-test actual Assurance entry points using the existing database
   access pattern, investigate pending judge/mail/SMS failures without erasing
   evidence, and obtain a fresh privileged snapshot immediately before cutover.
2. Recover original custom image inputs; build a NEW versioned tag pinned to
   stable source. Drop the superseded room patch, retain required integrations,
   port the Hindsight gate on the selected external provider. No skills edits.
3. Start a non-production instance with copied config/SQLite/cron state and
   isolated ports. Disable outbound effects in the COPY, not the live router.
4. Complete the typed connector-operation adapter and test every critical
   Conduit flow against that instance, including PKCE/cookies, approvals, restart,
   profile switching, foreground/cold-start notifications and Steel.
5. Rehearse rollback, compare baselines, then cut over only when critical items pass.

## Useful stable features (available after a validated upgrade, not enabled here)

- **Use after validation:** native hosted-room lease fix; reconnectable blocking
  prompts; profile isolation/lifecycle and state-file reliability fixes; scheduler
  manual-run fixes. These directly support the current multi-profile setup.
- **Consider later:** Bot Screen with server-enforced human control lease;
  richer Desktop SDK/SandboxedFrame extension points; reducing Steel provider glue;
  connector catalog; custom model entry and effort controls. No extra browser
  protocol or WebSocket is needed in Conduit.
- **Leave off/unchanged:** skill auto-loading or migrations, memory observations /
  auto consolidation, model strategy changes, unrelated service upgrades and a
  new browser stack. No evidence they are necessary for this migration.
- **Custom code removable from the future build:** hosted-room end-of-turn lease
  helper/call patch. Other customizations require evidence before removal.
