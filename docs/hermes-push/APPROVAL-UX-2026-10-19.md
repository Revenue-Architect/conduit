# Approval navigation and continuation — October 19, 2026

## Scope

The button-only fix is isolated in commit `56423851`. The following changes
reuse the existing chat opener and approval decision controls. No approval
sheet, new approval backend, or automatic continuation message was added.

| Entry | New behavior |
|---|---|
| Single approval detail | Successful Approve/Deny opens its originating conversation, with explicit profile metadata. |
| Queue | Remains in the queue after deciding; the result offers Open chat. Detail is fetched only when that action is selected. |
| Completed shade notification | Tapping the result resolves the approval and opens its chat when approved/denied. Expired/cancelled requests retain their receipt. |
| Missing or invalid origin | Remains on the approval receipt with an explanation. It never guesses the active bot. |

An optional, dismissible notice above the chat composer shows the server's
continuation state. It is bound to that conversation, session, profile and
service instance. It does not appear in another chat or an OpenWebUI
conversation. It distinguishes waiting, dispatched, unavailable and failed
continuation; dispatch is not presented as a completed assistant response.
Requests with `wake_mode=none` are labelled accordingly.

## Server contract

Phone approval detail now exposes `origin: {session_id, profile}`. The gateway
already receives the profile from V2 and formerly removed it. It continues
stripping session keys and other origin fields. Missing/empty profile and the
`chief` alias normalize to `default`, exactly as the existing wake dispatcher
does. Other profiles must match `[a-z0-9][a-z0-9_-]{0,63}` before exposure.

Existing `wake_mode` and `wake_state` fields are parsed by Conduit. Active
detail refreshes on app resume/native approval activity. A visible, resolved
request awaiting continuation refreshes every three seconds for up to two
minutes after resolution; no background polling or duplicate wake is added.

The deployed notification image is `hermes-notify:1.0.1-approval-ux`, a small
derivative of the retained `hermes-notify:1.0.0`. Canonical source:
`/home/umbrel/.jarvis/hermes-notify/src/notifyd/gateway.py`. Recipe, original
source, compose and mode backups, verified SQLite backup, and logs:
`/home/umbrel/.jarvis/codex-approval-ux-20261019/`. The image has a keeper and
verified saved image. No database schema or notification mode was changed.

## Wake delay and specialist limitation

The 30-second delay is a constant, `WAKE_DELAY_SECONDS`, in V2 approvals code.
It deliberately lets the requesting turn finish. It was inspected and retained;
this release does not lower the guard without a supported turn-idle signal.

Read-only probes against the running service returned:

| Profile | Session-list route | GET run-create route |
|---|---:|---:|
| default | 200 | 405 (POST route exists) |
| kai | 401 | 404 |
| scout | 401 | 404 |

These are route probes, not successful specialist wake tests. Specialist
continuation remains unvalidated/unsupported on this configured path. The
origin profile can still identify the right conversation in Conduit; a failed
wake must remain visible. It is never silently retried through the default bot.

## Validation and delivery

- Server before change: 86 PASS, 3 existing WARN, 0 FAIL.
- Server after change/image protection: 87 PASS, 3 existing WARN, 0 FAIL.
- Phone's installed build-184 APK was backed up before replacement at
  `approval-ux-20261019/rollback-installed-184.apk` in the private laptop evidence
  folder. No uninstall, app data clearing, profile reset or credential change.
- App analysis/build/install results are recorded in the final delivery receipt.
  No new automated tests were added or run for this implementation request.

## Rollback

Restore the saved compose image reference to `hermes-notify:1.0.0`, restore the
gateway source from its beside-file `.bak-20261019-approval-ux` after checking
for concurrent changes, then recreate only the notify service:

```sh
docker compose -f /home/umbrel/.jarvis/hermes-notify/compose.yaml up -d --no-build notify
```

Keep the live database and mode file; rolling this additive response field
back does not require restoring old notification data. To roll back the phone,
install the backed-up APK in place with the matching signer and supported
version downgrade flag. Never clear app storage. Installed Desktop, its theme,
plugins and host patches are outside this change.
