# Hermes customization audit — 2026-10-05

## Final disposition after deployment

Read [DEPLOYMENT.md](DEPLOYMENT.md) for the current runtime and evidence.
Production now uses custom 0.21.5 `v2026.9.24-kai3`. The old bundled Hindsight
provider was deliberately carried as a compatibility bridge: discovery proves
that exact provider is loaded, its system-session gate is applied during build,
and its SDK loader uses pinned hindsight-client 0.6.1 / aiohttp-retry 2.9.1.
External 1.1 remains dormant; no provider relocation was performed. Real recall
passes; retain paths were tested with writes mocked, not new memory facts.

Umbrel/Teams/context assets are preserved from the retained old image; hosted-room
lease patches were not ported because upstream implements them. Frozen skills
remain untouched and native sync uses a nonexistent bundle override. Actual
model/memory/provider configuration, cron cadence/enable states and armed router
were checked against the fresh recovery checkpoint. The deployment report lists
remaining baseline and client issues explicitly.

## Historical preflight audit (before custom image build)

Status: preflight only. Production remains on 0.21.1. No patch was removed from
the live server, no skill was changed, and no router state was changed.

Compared production image `hermes-agent-umbrel-teams:v2026.9.7-kai1`
(`2237be355906fbe6065ce1815711eee52b2d646e`) with stable tag `v2026.9.24`
(`f97608f178d1ffeca59860195ab7da295f7c8e5f`, Hermes 0.21.5).

| Customization | Why it exists | Stable upstream support | Migration disposition | Risk / evidence |
|---|---|---|---|---|
| Hindsight automatic-retain session-prefix gate | Keep cron/system/internal/scheduler/webhook traffic out of personal memory | **No equivalent exclusion** in the stable catalog's pinned external provider | **Modify and keep** on the provider actually loaded by the new image | High: stable removes the bundled provider. Patching the old path would protect nothing. Preserve human auto-retain and manual retain; test both independently. |
| Hosted-room end-of-turn lease release in `session_lifecycle.py` | Prevent one bot-room member from holding its profile slot indefinitely | **Yes**: `_release_hosted_room_turn_slot` exists in target and is called from `prompt_turn.py` | **Delete the local patch from the future build**, use upstream implementation | Actual diff of the live files against 0.21.1 contained the helper and the end-of-turn call; target implements both. This deletion has NOT been applied to production. |
| Teams dependency pins / Kai routing | Working Teams adapter and correct destination profile | Upstream has Teams and profile multiplexing; exact installed dependency compatibility still needs staging | **Keep routing; re-evaluate pins** against the target's requirements | Do not reroute Teams, change models, or install unrelated dependency updates. Original custom Dockerfile was not located in inspected paths. |
| Umbrel runtime-context plugin | Inject NAS context using `pre_llm_call` | Generic hook infrastructure remains; installation-specific context is not upstream content | **Keep**, verify plugin discovery/hook invocation in staging | Native hook support does not make the custom context redundant. |
| Umbrel bootstrap, setup wrapper, TUI bundle, proxy-auth and update-message patches | Umbrel container onboarding/authentication/lifecycle UX | Dashboard auth and PKCE exist upstream; this does not prove Umbrel proxy compatibility | **Audit build inputs before porting** | Image history proves these assets were copied/patched. Build source and removed build-time patch scripts are not recovered yet; do not fabricate a Dockerfile from guessed behavior. |
| `browser-steel` provider and Steel live-view pane | Use existing tailnet/private Steel browser and debug player | Browser-provider interfaces and Desktop `SandboxedFrame` exist upstream | **Keep pending staging validation**; consider reducing glue later | Bot Screen's RFB/control lease is not a Steel debug-player lease. Do not claim it automatically makes Steel takeover safe. |
| `spaces` plugin and Kanban data | Native Conduit spaces/pages and task management | Generic plugin routing remains; installation-specific plugin/data still needed | **Keep** persistent plugin assets/data | Verify `/api/plugins/*` routes against copied state, not names alone. |
| TextBee platform plugin, OTP defense, pre-judge DROP | SMS ingress without OTP noise; preserve real security alerts | No proof that upstream replaces these installation-specific protections | **Keep** | Frozen skills are unrelated to these adapters and must remain untouched. |
| Proactive poller/applier/router/scouts/judge/research/caretaker | Existing operational pipeline and central judgment boundary | Not a Hermes framework replacement | **Keep unchanged** | Router was ARMED before and after inspection. Never clear actual pending candidates to pass health checks. |
| AgentMail filename/retry/failure handling | Handle SES-style underscore filenames and visible failures | Installation-owned spool pipeline, not replaced by Hermes | **Keep unchanged** | Five failed items are present. Preserve their failure reasons for review. |
| System Assurance | Deterministic reliability/invariant checks | Not replaced by Hermes | **Keep; prerequisite repairs are needed** | Canary/reconcile CLI paths fail on missing `psycopg2`; source also contains unquoted identifiers. 61 module tests pass but do not cover those live timer entry points. |
| Model aliases and per-profile configuration | Default/Codex, Fast, Strong, Local/Qwen, Kai, Autopilot, Hermuse | Upstream supports profile/model configuration | **Keep unchanged** | No model strategy change or credential migration was attempted. Profile A→B→A tests remain required. |
| Frozen skill trees | User-owned workflows/content | No mandatory skill-schema migration established | **Do not modify** | Read-only checksum captured for `/srv/kaizen/kaizen-skills/skills`: `7a18305cca985b062b221539b030fd97497b0052c946b381c2147ff4662d9baa`. |

## Hindsight relocation evidence

Target `plugin-catalog/hindsight.yaml` pins:

- Repository: `vectorize-io/hindsight`
- Commit: `176f8c2de1369f569c489b831d143b78128b5535`
- Subdirectory: `hindsight-integrations/hermes`
- Catalog version: 1.0.1; requires Hermes >=0.21.4

Its `sync_turn` has no equivalent system-session prefix gate. Production currently
loads bundled 1.0.0; `/opt/data/plugins/hindsight` 1.1.0 is dormant. The newer
loader can make an external provider active, so installation/version/precedence
must be intentional. Preserve the configured memory defense, concise mission,
disabled observations and disabled consolidation; do not reset bank policy.

Current reapply assets are `/opt/data/hindsight-cron-gate/`, tracked in the Umbrel
config repo at `ff50a41`. They target the OLD bundled path and are not a valid
0.21.5 migration by themselves.

## Recovery assets

Private preflight recovery directory on Umbrel:
`/home/umbrel/.jarvis/backups/hermes-migration-20261005-preflight/`.
Contains the three hot-patched source files, the managed compose file, private
container inspection metadata, SQLite backups and a Postgres dump. Never add its
contents to Git: it includes credentials/personal data. This is not a fresh ZFS
snapshot or an atomic cross-service recovery point.
