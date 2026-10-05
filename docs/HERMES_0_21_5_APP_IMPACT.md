# Updating Hermes 0.21.1 → 0.21.5: what it means for Conduit

Written 2026-10-05. It compares the running custom image `hermes-agent-umbrel-teams:v2026.9.7-kai1` (Hermes 0.21.1) with upstream stable v2026.9.24 (Hermes 0.21.5). The checks were done against the gateway source at both tags and the live container (read-only).

Codex's preflight covers the server side in depth: `docs/hermes-migration/2026-10-05/REPORT.md` and `CONDUIT_COMPATIBILITY.md`. That preflight blocked cutover on six items. This note summarises what the app needs and adds what I checked independently.

## Bottom line

Do not switch the image until two things are true:
- The installed APK speaks the new "server request" protocol. Codex's transport patch is in progress and is not in any APK yet.
- Codex's six cutover blockers are cleared.

With today's app on 0.21.5, Hermes would never show you an approval or a question. The agent would get "no answer", so risky commands would be refused and clarifying questions would time out. No error appears anywhere.

## What breaks in the app

1. **Approvals, questions, sudo, secrets and vault prompts become server→client requests.**
   - The app must send `client.capabilities {server_requests: true}` once per connection.
   - If it doesn't, Hermes logs "the attached client predates server→client requests (update the Hermes app)" and silently treats every prompt as unanswered.
   - `approval.request`, `clarify.request` and the other `*.request` events are no longer sent.
   - `clarify.respond` is removed. `approval.respond` remains only for queued room approvals.
   - The `*.expire` events are replaced by a single `request.cancel`.
   - Codex is patching this (`hermes_desktop_transport.dart` and its new test).
2. **Reconnect replay changes.** Unanswered prompts come back as `open_requests` on `session.resume`, `session.activate` and `session.events.since`, instead of `pending_approval` and `pending_clarify`.
3. **MCP and connector consent changes model.** `mcp.setup.*` becomes `connection.request`, `connection.update` and `connection.respond`, plus `pending_connection`. Codex lists this as an open blocker.

## What keeps working

Verified in the 0.21.5 source:
- **Every session method Conduit calls:** create, resume, history, list, `active_list`, steer, interrupt, close, title, branch.
  - Also `prompt.submit`, `model.options`, `config.get`/`config.set` and `subagent.steer`.
  - The only methods removed are `clarify.respond` and `session.foreign.*`. Conduit doesn't use `session.foreign.*`.
- **The model picker.** `config.set model … --session` is still parsed as session-only (`is_session`), so it still never changes a profile's model. 0.21.5 adds an optional reasoning-effort flag.
- **Live activity, plan, delegates and Active Work.** Every event they read is still emitted:
  - `message.*`, `tool.*`, `reasoning.delta`
  - `todo.updated`, `session.info`, `subagent.*`, `review.summary`
  - Resume still carries `todo_state`.
- **The transcript REST API used by the tool inspector and plan recovery.** `/api/sessions/{id}/messages` takes the same parameters (`order=oldest|latest`, `limit`, `offset`, `include_compacted`, `profile`). It now also returns `profile`, and new `/messages/around` and `/timeline` routes exist.
- **Kanban.** The plugin's HTTP API is identical: the same 46 routes.
- **Auth and other routes.** `/api/status`, `/api/auth/ws-ticket`, `/api/ws`, cron and files routes remain (per Codex). 0.21.3 also fixes remote sessions expiring on refresh bursts.

## Umbrel and custom-image traps

- **Never press "Update" on Hermes in the Umbrel app store.** The catalog offers a stock 2026.9.14 build, and Umbrel would swap in its own compose file. That drops:
  - the custom image and Teams runtime
  - the Kai memory, Kaizen skills and Bitwarden mounts
  - the Steel, graph and refinery private networks
  - `STEEL_BASE_URL`
- **The new image must reapply the custom layers.** From `docker history`:
  - the Microsoft Teams SDK packages
  - uid/gid 1000
  - `patch-umbrel-proxy-auth.py` and `patch-umbrel-update-message.py`
  - the `umbrel-runtime` plugin, the custom TUI entry and the Umbrel context init script

  The two patch scripts rewrite Hermes source text, so re-check each one against 0.21.5 before trusting the build. The original Dockerfile and scripts were not found (Codex blocker 6).
- **Live edits inside the running container die with it.**
  - `tui_gateway/prompt_turn.py` and `session_lifecycle.py` hold a backported room turn-slot release (#106847). 0.21.5 ships that fix, so drop them.
  - `hindsight.py` is a live edit too. Stable removes the bundled Hindsight provider, which is Codex blocker 4.
- **What survives in `/opt/data`:**
  - every profile config, including today's Steel blocks
  - `state.db`
  - the data plugins: `spaces`, `browser-steel`, `steel-live-view`, `hindsight`, `textbee-sms`

  `kanban` and `dashboard_auth` come with the image.
- **Config and database.** Config migrates from version 44 to 46: a Connections toolset, and MCP `disabled: true` becomes `enabled: false`. The state schema number stays 30, but the DB code changed a lot. Rolling back means restoring the backup, not just starting the old image. Take a fresh ZFS snapshot first (Codex blocker 5).
- **One gateway per host.** 0.21.4 adds a host-wide gateway singleton lock. The extra `kind_gates` Desktop serve that Codex found sharing state may refuse to start, or attach instead. Plan for it.
- **Fixed upstream.** 0.21.2's state.db fixes include profile gateways writing room state into the root database every 5 seconds. Teams rooms should be steadier.

## Order of operations

1. Finish Codex's transport patch plus the connector-consent adapter. Ship an APK with both and confirm approvals and questions still work on 0.21.1, where the old protocol must keep working.
2. Rebuild the custom image on 0.21.5 under a new tag; never overwrite `v2026.9.7-kai1`.
3. Stage it on a copy of `/opt/data`, then run the app checks below.
4. Cut over with the preflight backup (`~/.jarvis/backups/hermes-migration-20261005-preflight`) and a fresh snapshot ready.

## App checks after the switch

- Sign in, then reopen the app after an hour (refresh).
- Send a message with tools: live run, plan bar and sheet, tool inspector input and result.
- Switch the model from the pill, and confirm the profile's own model is unchanged.
- Ask for a risky command (approval card) and a question (clarify). Answer both; also let one time out, which should tear the card down via `request.cancel`.
- Kill the connection mid-run and reopen: the unanswered prompt should come back once, not twice.
- Run Steel on a profile that was local before (`kai`, `hermuse`, `autopilot`) and check the live view.
- In a Teams room, check the member live cards and that a second turn isn't blocked.
- Spaces: save, cause a conflict, save again. Kanban: board loads and a task moves.
- Cron: run-now and next run. Notification tap from a cold start opens the right chat.
