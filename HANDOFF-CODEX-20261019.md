# Handoff to Codex — 2026-10-19 (from Claude session)

Read this first, then the two agent briefs at the bottom. You have zero context; everything you need is here or linked.
Canonical docs live on the Umbrel at `/home/umbrel/.jarvis/docs/` (STATE.md, CHANGE-CHECKLIST.md, CHANGELOG-20261018.md, KAMRAN-TODO-20261018.md, RELIABILITY-AUDIT-20261018.md, CONDUIT-NOTIFICATIONS-SPEC-20261019.md, CONDUIT-NOTIFICATIONS-CONTRACT-CHANGES.md, CONDUIT-PAIRING.md). Follow CHANGE-CHECKLIST.md for every change and add a CHANGELOG entry.

## 1. Standing rules from Kamran (do not violate)

- Never print secrets in chat/logs/commits. Kamran authorises agents to *use* his credentials for requested tasks.
- Do NOT rotate: LiteLLM key, ntfy password, dashboard secret (Kamran will do it).
- Never restart the Docker daemon. Never `tailscale serve reset`; add/repoint single routes only. No Funnel.
- Preserve others' uncommitted work. Family Hub deploys are Kamran's call.
- Major changes need a plan/spec and his approval — **UnifiedPush cutover is already approved, to be finished today** (his answers: LAN then Tailscale; Play Store distributor install; upgrade ntfy; press-and-hold for approval actions; it may wake agents; do it all today).
- Keep chat replies short.

## 2. Access

- Umbrel: `ssh -i ~/.ssh/claude-umbrel -o BatchMode=yes umbrel@100.88.112.22` (no passwordless sudo). Over Tailscale.
- Laptop (Galaxy Book, Windows): `ssh laptop` (cmd). Long/interactive jobs: `schtasks /Create … /SC ONCE /ST 23:59 /F` then `/Run` (add `/IT` for GUI apps).
- Phone: wireless adb from the laptop, serial `adb-R5CY13VFPEP-JAeGpv._adb-tls-connect._tcp`, package `app.cogwheel.conduit.debug`. Flutter toolchain: `C:/Users/Kamran/Documents/Codex/2026-09-17/umbrel-ui-bootstrap/work/toolchain`.
- Conduit repo: `C:/Users/Kamran/Documents/Codex/2026-09-17/umbrel-ui-bootstrap/work/conduit`.

## 3. Primary open work: Conduit-native notifications via UnifiedPush

Design: `/home/umbrel/.jarvis/docs/CONDUIT-NOTIFICATIONS-SPEC-20261019.md` (decisions D1–D6). Summary:
- ntfy (self-hosted) is only the UnifiedPush distributor; Conduit is the UP client and renders notifications natively (Kotlin + Pigeon bridge). Payloads RFC 8291 encrypted.
- New container `hermes-notify` (notifyd): device registry, encryption, outbox, fallback to plain ntfy topic, phone gateway (Tailscale Serve **8450**), approvals + wake dispatch.
- V2 image `hermes-v2-next:0.6.0-notify` adds an operator key role (only notifyd can decide approvals).
- Decisions wake the originating session via `POST /v1/runs` (webhook route only as fallback).
- Cutover per category via mode file: `legacy → shadow → dual → conduit`; rollback = edit mode file.

**Consolidated status (final, from both agents):**
- Server: DONE and live. ntfy v2.32.0, `hermes-notify` (senders 18769, phone gateway 18768 → Serve 8450), V2 0.6.0 (operator/ingest keys, wake). 63 + 59 tests pass; fake-phone end-to-end passed. All 8 categories still in `legacy` mode. `approvals_loop`/`wake_loop` on, `hermes-v2-approvals.timer` disabled. Selftest 85 PASS / 3 WARN / 0 FAIL. Rollback: `/home/umbrel/.jarvis/backups/notify-20261019/`. Kuma NPM IP issue already fixed by the server agent.
- Conduit: CODE WRITTEN, NOT BUILT. Laptop worktree `…/work/conduit-unifiedpush`, branch `feat/conduit-unifiedpush` @ `333ac747` (64 files, unpushed). Kotlin never compiled; Dart tests need re-run (last 101/6, test fixes applied); tink duplicate-class check pending. Not implemented: `GET /inbox` catch-up, token rotation, `gateway_epoch`, QR scan.
- Blocker: phone wireless debugging was off — ask Kamran to re-enable it. Laptop scheduled jobs get Ctrl-C-killed; see the Conduit brief's workaround.

**Next steps, in order:** (1) re-run Dart tests + compile Kotlin, fix; (2) build 184, pull build-183 rollback APK, install via adb; (3) pair phone per CONDUIT-PAIRING.md; (4) `notifyctl cutover` per category (dual → conduit), verify each; (5) supervised approvals test (shade Approve/Deny + in-app, session wake), then `cutover --approvals`; (6) on-device check of file cards incl. session `20261018_231313_e7c11b`; (7) push branch, update STATE.md/CHANGELOG/KAMRAN-TODO.

State at handoff (as observed by Claude at ~14:20 UTC):
- Running on Umbrel: `hermes-notify` (healthy), `hermes-v2-shadow` on `hermes-v2-next:0.6.0-notify` (healthy), keep-image containers for both.
- Selftest approvals checks all PASS (dispatcher timer every 10 s, 0 pending).
- Server agent brief: `/home/umbrel/.jarvis/docs/HANDOFF-UNIFIEDPUSH-SERVER-20261019.md` (exact deployed state, remaining steps).
- Conduit agent brief: `C:/…/work/conduit/HANDOFF-CONDUIT-UNIFIEDPUSH-20261019.md` (+ copy in the Umbrel docs folder). Branch `feat/conduit-unifiedpush`; push it when done (earlier pushes used a git bundle from the laptop).
- Remaining to finish (verify against the briefs): build + install the Conduit APK with UP (build 184), pair the phone (CONDUIT-PAIRING.md), end-to-end test each category in `dual`, approval Approve/Deny from shade and in-app screen, session wake, then flip categories to `conduit`, keeping ntfy fallback. Update STATE.md, CHANGELOG, KAMRAN-TODO.

## 4. Secondary open work

1. **File delivery to phone.** Hermes was giving raw file paths. Done: all 6 profiles' SOUL.md have a `<!-- hermes-file-delivery-v1 -->` block (attach files as a `MEDIA:<path>` line); `/opt/data/skills-chief/ask-specialist/SKILL.md` line 42 updated. Conduit renders `MEDIA:` lines as downloadable cards via `/api/fs/download`. Open: Conduit fix so *bare paths* in replies also become file cards (assigned to the Conduit agent), and on-device check of default-profile session `20261018_231313_e7c11b`.
2. **Nginx Proxy Manager (Umbrel app).** Containers vanished 13:44 UTC (app files rewritten; likely a Stop/Restart in Umbrel UI). Restarted with:
   `cd /opt/umbreld/source/modules/apps/legacy-compat && APP_DATA_ROOT=/home/umbrel/umbrel/app-data/nginx-proxy-manager/data DEVICE_DOMAIN_NAME=umbrel.local docker compose --project-name nginx-proxy-manager --file docker-compose.common.yml --file /home/umbrel/umbrel/app-data/nginx-proxy-manager/docker-compose.umbreld.yml up --detach`
   Verified: site 200, Teams ingress via NPM 401 (expected), `/data/nginx/custom/server_proxy.conf` intact. Open: Uptime Kuma "Nginx Proxy Manager" monitor targets old IP `10.21.0.27:81` (now `.28`) — change it to hostname `nginx-proxy-manager_web_1:81`. If Umbrel dashboard shows NPM stopped, press Start (never uninstall; Teams + duckdns site depend on it).
3. Selftest: `bash ~/.jarvis/selftest/runtime-selftest.sh` (last run 76 PASS / 3 WARN / 1 FAIL — the Kuma IP above). WARN zfs snapshot age = Kamran's `zfs allow` todo.

## 5. Done in this session (for reference, no action needed)

- KaizenSite (GitHub Kaizen-Commerce/KaizenSite, `main` at f49c28b): Lucian UX/UI + Taste polish, mobile scroll pins restored. Notes `docs/ui-polish-2026-10-18.md`.
- Hermes Desktop: Steel live-view fix in Agent Computer plugin; generated-image host patch (asar C4D4E4F7…, rollback folder `release/win-unpacked-before-imgfix-20261019`); OpenUI/A2UI styling QA. Laptop `RECOVERY.md` §13–15.
- Conduit build 183 installed (rollback APK `claude-qa-20261018-genui/rollback-build182-installed.apk`).
- V1 proactive API retired; approvals moved to Hermes V2. Reliability audit + fixes; profile hygiene (backups `/opt/data/backups/profile-hygiene-20261019/`); ops scripts fixed.
- n8n fixes, gateway fallback leak, Tailscale Serve routes repointed, duplicate n8n credential deleted.

## 6. Kamran-owned todos (don't do)

Rotate LiteLLM key, ntfy password, dashboard secret; `zfs allow` for snapshot automation; optional healthchecks.io. See KAMRAN-TODO-20261018.md.
