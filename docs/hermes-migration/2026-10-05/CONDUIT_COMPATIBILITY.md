# Conduit / Hermes stable compatibility — 2026-10-05

Audit baseline: `Revenue-Architect/conduit`, `feat/hermez-motion-foundation`,
`dc689da386a511ad2dd381b79ed101dbfba0ea89` (also the fetched origin/main at start).
Do not reset to the old handoff's `90c63b2c`. Concurrent unrelated work exists in
chat providers, Home, Active Work and their tests; it is not part of this patch.

Server baseline: custom 0.21.1; target 0.21.5, Desktop contract **8**.
The old contract generation is 6, confirmed from source; a live authenticated
handshake was not performed during this preflight.

**Static compatibility is not target-server E2E proof.** No target container or
development APK was deployed. Target MCP/connection operations remain a cutover
blocker; the transport changes below are only part of migration readiness.

| Interface | Client expectation | Old server | Target stable source | Breaking? / action |
|---|---|---|---|---|
| Auth/status | Dashboard cookies or native bearer, `/api/status` | Supported | Native authorize/token/refresh and status remain | No route break identified; real old/new sign-in/expiry tests required. |
| WS authentication | Same-origin `/api/auth/ws-ticket`, `/api/ws` or legacy token | Supported | Ticket and WS routes remain | Preserve no-redirect transport and same-origin credential boundaries. |
| Capability negotiation | Previously none | Not required | `client.capabilities {server_requests:true}` is required for questions | **Patch:** advertise once per socket; tolerate old -32601. |
| Human approval | `approval.request` notification; `approval.respond` queue ID | Notification path | Server request `approval`, frame `srq-*`, distinct queue `params.request_id`; `approval.respond` still exists | **Patch:** normalize to existing UI preserving QUEUE ID; cancellation translates frame ID back to queue ID. |
| Clarify/sudo/secret | Notification or server request; legacy paired respond fallback | Paired respond methods | Server requests; paired methods removed; `request.answer` proxy exists | **Patch:** retain existing direct replies, retry after resume, use proxy for `srq-*` IDs with explicit owning profile on contract >=7; reject expired status rather than show success. Cached newer-contract knowledge must not break legacy notification IDs after rollback. |
| Decision reconnect | Legacy `pending_approval` / `pending_clarify` | Legacy snapshots | `open_requests` on resume/activate/events.since | **Patch:** replay unanswered frames before returning result, deduplicate frame IDs. Existing persisted decision model remains. |
| MCP/connector consent | `mcp.setup.request` / `mcp.setup.respond`, single-server actions | Supported | `connection.request/update`, `pending_connection`, target list and `connection.respond` | **Unresolved break / BLOCK CUTOVER.** Needs a small typed adapter, not a second approval system. Include multi-target state, deadlines, required env, OAuth return and reconnect. Do not flatten an arbitrary operation into the old single-server model. |
| MCP settings | Existing MCP REST/config management | Supported | REST MCP management remains | Inspect actual lifecycle responses in staging; do not equate settings compatibility with new consent compatibility. |
| Sessions/transcript | `session.create/resume/history/list/title/close`, stored/runtime binding; REST message pagination | Supported | Methods remain; resume includes optional `open_requests`, `pending_connection`, todo and live info | Keep optional-field parsing and explicit profile ownership. Test reconnect, title/branch/close and stored→runtime aliases. |
| Prompt/tools/activity | `prompt.submit`, message/tool/subagent events | Supported | Methods/event families remain | Source matches core projection; actual multi-step streamed run still required. |
| Steer/stop/queue | Exact bound session; `session.steer/interrupt` | Supported | Methods remain | Preserve exact stored/runtime scope and service-owned run state. |
| Profiles/multiplexer | Explicit `profile` overrides connection fallback; cross-profile sessions | Already multiplexed in production | Routing and profile/session APIs remain; lifecycle/isolation changes | No one-gateway=one-profile assumption should be introduced. Test A→B→A on every configured profile. |
| Models/options/uploads | `model.options`, `config.get/set`, optional provider; file/pdf/image attachment RPCs | Supported | Methods remain; custom model entries and richer capabilities added | Keep existing strategy and optional parsing. No dependency/model changes. |
| Cron | Dashboard `/api/cron/jobs` CRUD, pause/resume/trigger/runs | Supported | All corresponding routes remain | Preserve name→job-ID resolution for proactive-judge and execution DB authority. Test cadence/manual trigger semantics against copied state. |
| Artifacts | Authenticated `/api/fs/list/download`, `MEDIA:` refs | Supported | Routes remain | Preserve sensitive-path, same-origin and redirect restrictions. Test file/image access under PKCE and cookies. |
| Kanban/Spaces | Installation plugin `/api/plugins/*` routes and data | Custom installed plugins | Generic plugin machinery remains | No proof without carrying plugins into staging. Do not drop persistent assets. |
| Notification center/deep links | App-shell-owned NotificationCenter; service activity feeds run notifications | Current native architecture | No new native mobile notification transport required | Leave architecture unchanged; replay must not produce duplicate notifications. Test foreground/cold-start taps and owning profile. |
| Steel viewer | Configured viewer in existing WebView; browser provider/plugin on server | Custom installed setup | Browser-provider interfaces and SandboxedFrame exist | Keep setup; test installed viewer/CDP path. New Bot Screen is optional, not a drop-in replacement. |
| Bot Screen | Not surfaced by Conduit | Not relied upon | Authenticated RFB display bridge and server-side control lease | Optional follow-up; no new Conduit screen/streaming stack in this migration. |

## Source anchors

Target source is the exact release checkout, not upstream main:

- `tui_gateway/server.py`: contract 8; resume snapshot.
- `tui_gateway/server_requests.py`: capability gate, `srq-*`, cancellation and replay.
- `apps/shared/src/json-rpc-channel.ts`: upstream capability/replay pattern.
- `tui_gateway/contracts/prompt_voice.py`: proxy answer and approval contracts.
- `tui_gateway/contracts/connectors_operation.py`: replacement MCP operation contract.
- `hermes_cli/dashboard_auth/routes.py`: native auth and ticket routes.
- `hermes_cli/web_routers/{cron,files,display}.py`: scheduler/files/display routes.

Client patch scope: Desktop transport, connection negotiation and decision reply
recovery only. No theme, skills, profiles, model routing, notifications architecture,
new transport, schema, database, or app dependency changes.

An expired `approval.respond` result with `resolved:0` is rejected rather than
clearing the pending record and presenting false success. Approval frame IDs and
queue IDs remain distinct throughout reconnect/replay and cancellation.

## Deployment gate

Passing socket fixtures does **not** authorize upgrading production. Remaining
required evidence: copied-state staging image, new connector consent adapter,
normal/cron/manual Hindsight retain tests, profile isolation, old/new auth,
notification/deep-link device QA, Steel smoke, proactive end-to-end flow and fresh
privileged ZFS snapshot. See `REPORT.md` for baseline failures and exact test runs.
