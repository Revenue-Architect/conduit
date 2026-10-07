# Hermes 0.21.5 admin capability probe (U21)

- **Probed:** 2026-10-06, read-only, over `ssh umbrel-lan` -> `docker exec -u hermes hermes-agent_web_1`.
- **Installed version:** `hermes-agent 0.21.5` (`importlib.metadata`; `/opt/hermes/pyproject.toml:5`). Source checkout at `/opt/hermes` (venv `/opt/hermes/.venv`).
- **Live dashboard:** port 18789 inside the container. Public `GET /api/status` reports `version 0.21.5`, `config_version 46`, `auth_required: true`, `auth_providers: ["basic"]`, `auth_flows: ["cookie", "native_pkce"]`. No other HTTP calls were made except one GET to an unknown `/api/` path (answered 401 before routing) and GETs of `/`, `/login` and a missing `/assets/` file.
- **Method:** grep and read the installed source. Nothing was written, restarted or revealed. Paths below are relative to `/opt/hermes`.

Verdicts: **present** = exists and matches what the plan assumes; **changed** = exists but differs from the plan's 0.21.2 expectation in a way a unit must handle; **missing** = not on this server.

## Gateway JSON-RPC methods

Every method registers through `@method` and has a contract in `tui_gateway/contracts/`. An unknown method answers JSON-RPC error `-32601` with message `unknown method: <name> — ...` (`tui_gateway/rpc_dispatch.py:22-24`).

| Capability | 0.21.2 expectation | 0.21.5 verdict | Evidence |
|---|---|---|---|
| `profiles.list` | present | present | `tui_gateway/methods_profiles.py:266`; contract `contracts/profiles_vault_complete_foreign_subagents.py:179` |
| `profiles.describe` | present | present. `toolsets_pinned` now reflects `platform_toolsets.cli` (its docstring still says `tools.enabled_toolsets`) | `methods_profiles.py:450`, pin read `:433`; contract `:260` |
| `profiles.create` | present (name, description, soul, model/provider) | present. Also `clone_from`, `clone_all`, `clone_channels`, `no_skills`, `no_alias`, `share_auth`, `mirror_credentials` (on by default) | `methods_profiles.py:383`; params `contracts/...foreign_subagents.py:183-198` |
| `profiles.configure` | present; fields ui_meta, description, soul, model/provider, enabled_toolsets, disabled_skills, enabled_mcp_servers, confirm_expensive_model | present, all fields. Adds `ui_meta_expected_revisions` (per-key compare-and-swap) and returns `applied.ui_meta_conflicts`. A guarded model returns `confirm_required` + `confirm_message` and writes nothing. **Changed:** `enabled_toolsets` now writes `platform_toolsets.cli`, the enforced key (see Config internals) | handler `methods_profiles.py:625-647`; model guard `:533-556`; toolset pin `:559-570`; MCP toggles `:580-594`; sections `:597-622`; params `contracts/...foreign_subagents.py:264-277` |
| `profiles.set_asset` | present | present. `asset` must be `avatar`; PNG/JPEG/WebP only, max 2 MB; `clear: true` deletes | `methods_profiles.py:657-692` |
| `profiles.get_asset` | present | present. Absent asset is `found: false`, not an error | `methods_profiles.py:695-708` |
| `profiles.delete` (RPC) | not expected (REST used) | missing (REST `DELETE /api/profiles/{name}` is present) | only `profiles.{list,create,describe,configure,set_asset,get_asset,remember_onboarding}` exist |
| Profile errors (RPC) | n/a | `4063` name required, `4064` `profile '<name>' not found` | `methods_profiles.py:69-81` |
| `skills.manage` | present (per profile) | changed: actions are only `list`, `search`, `install`, `browse`, `inspect`. No toggle or uninstall | `methods_tools.py:1279`; actions `contracts/tools_mcp_plugins.py:144-149`; params `:152-159` |
| `mcp.servers.list` | present | present (no `name` required) | `methods_tools.py:1324`; contract `contracts/tools_mcp_plugins.py:386` |
| `mcp.servers.status` | not listed | present | `methods_tools.py:1334` |
| `mcp.servers.add` | present | present. `preset` (catalog id) and/or `config`; `bearer_token` goes to the profile `.env` | `methods_tools.py:1352`; params `contracts/tools_mcp_plugins.py:425-431` |
| `mcp.servers.set_api_key` | present | present (`name`, `value` required) | `methods_tools.py:1379` |
| `mcp.servers.test` | present | present | `methods_tools.py:1411`; contract `contracts/tools_mcp_plugins.py:477` |
| `mcp.servers.remove` | present | present | `methods_tools.py:1441` |
| `mcp.servers.oauth.*` | present | present: `start` (optional `client_redirect_uri`), `poll`, `cancel`, `callback` | `methods_tools.py:1452`, `:1477`, `:1484`, `:1492`; contracts `:504`, `:529`, `:539`, `:557` |
| `mcp.servers.enable` | not specified | missing as RPC. Use `profiles.configure enabled_mcp_servers` (replace semantics) or REST `PUT /api/mcp/servers/{name}/enabled` | — |
| `mcp.catalog` | present | present (profile-scoped) | `methods_tools.py:1304`; contract `contracts/tools_mcp_plugins.py:356` |
| `plugins.manage` | present | present. Actions `list`, `toggle`, `install`, `update`, `remove`, `settings`, `onboarding` | `methods_tools.py:1712`; actions `contracts/tools_mcp_plugins.py:582-589`; params `:592-604` |
| `cron.manage` | present (profile) | present. Actions `list`, `add`, `remove`, `pause`, `resume`; `profile` param | `methods_tools.py:1187`; `contracts/tools_commands.py:415-432` |
| `model.options` | present | present (profile-scoped; `explicit_only`, `include_unconfigured`, `refresh`) | `tui_gateway/methods_complete.py:335`; params `contracts/config_free_tier_control.py:216-220` |
| `reload.mcp` | present | changed: no `profile` param (process-wide; refreshes live sessions). Without `confirm: true` it may answer `{"status": "confirm_required", "message": ...}`, governed by `approvals.mcp_reload_confirm` (default true) | `methods_tools.py:282-289`, `:330-338`; params `contracts/tools_mcp_plugins.py:113-120` |
| `reload.env` | present | present | `methods_tools.py:251`; contract `contracts/tools_mcp_plugins.py:109` |
| `session.list` | present (profile, title, hidden) | present: `profile`, `title` (exact-title lookup, hidden rows resolve), `limit`, `include_hidden` | `tui_gateway/methods_session.py:488`; params `contracts/sessions.py:207-210` |
| `session.create` | present (profile, title, hidden) | present: `profile`, `title`, `hidden`, plus `model`, `provider`, `reasoning_effort`, `fast`, `follow_profile_config` | `methods_session.py:431`; params `contracts/sessions.py:118-132` |

## Dashboard REST routes

All routers live in `hermes_cli/web_routers/`.

| Capability | 0.21.2 expectation | 0.21.5 verdict | Evidence |
|---|---|---|---|
| `GET /api/env?profile=` | present, redacted | present. Rows carry `is_set` and `redacted_value`, never the raw value | `config_env.py:232-290` |
| `PUT /api/env?profile=` | present | present (`profile` also accepted in body). Rejects a redacted preview value with 400 | `config_env.py:292-303`; body `web_models.py:15-21` |
| `DELETE /api/env?profile=` | present | present (body `key`, optional `profile`); 404 when key missing | `config_env.py:957-972` |
| `POST /api/env/reveal` | present, never called | present (rate-limited, audit-logged). Must stay unused | `config_env.py:975-1000` |
| `GET /api/providers/oauth` | present | present (profile-scoped) | `oauth.py:619-638` |
| `POST /api/providers/oauth/{id}/start` | present for nous, openai-codex, minimax-oauth, xai-oauth | present, same four device-code starters. `qwen-oauth`, `copilot-acp`, `anthropic`, `claude-code` are `external` (400) | `oauth.py:720-739`; starters `oauth.py:548-551`; catalog `hermes_cli/web_server_oauth.py:137-160` |
| `GET /api/providers/oauth/{id}/poll/{sid}` | present | present (`?profile=` must match the session's profile) | `oauth.py:751-772` |
| `DELETE /api/providers/oauth/{id}` and `/sessions/{sid}` | present | present | `oauth.py:665`, `:775` |
| `POST /api/providers/validate` | present | present. Returns `{ok, reachable, message}`; no `profile` (probes the provider only) | `config_env.py:887-954` |
| `POST /api/model/set` | present with `confirm_required` round trip | present: `confirm_expensive_model`, `profile` (query or body). Changed: `reasoning_effort` here applies to auxiliary slots only, so the main default reasoning effort must go through `PUT /api/config` | `models.py:275-319`; body `web_models.py:102-115` |
| `GET /api/config?profile=` | present | present (`include_defaults` param) | `config_env.py:81-92` |
| `PUT /api/config?profile=` | present, merging | present, deep-merges over disk | `config_env.py:118-130` |
| `GET /api/config/raw?profile=` | present | present. Returns **unredacted** YAML plus `path` | `analytics.py:33-49` |
| `PUT /api/config/raw?profile=` | present | present (`profile` also in body). Full-document replace (`merge_existing=False`). Non-mapping gives 400 "YAML must be a mapping"; parse error gives 400 `Invalid YAML: <parser text>` (may quote file content) | `analytics.py:52-73`; body `web_models.py:508-510` |
| `GET /api/config/schema` | present | present, profile-scoped, **public** (no auth). Also public `GET /api/config/defaults` (= DEFAULT_CONFIG) | `config_env.py:95-107`; `hermes_cli/dashboard_auth/public_paths.py:17-18` |
| `GET /api/tools/toolsets?profile=` | present | present | `tools.py:230-277` |
| `PUT /api/tools/toolsets/{name}?profile=` | present, writes enforced `platform_toolsets` | present. Writes `platform_toolsets.<configuration platform>` (cli for most) via `_save_platform_tools`; config-only toolsets (stt) toggle `<name>.enabled` | `tools.py:280-342`; body `web_models.py:481-483` |
| `/api/skills` (list, toggle, profile) | present | present: `GET /api/skills?profile=`, `PUT /api/skills/toggle` (profile in query or body), `POST /api/skills`, `GET`/`PUT /api/skills/content` | `skills.py:343`, `:374-389`, `:392`, `:413`, `:427` |
| `/api/mcp/servers` | present | present: GET (env values redacted), POST, PUT, `DELETE /{name}`, `POST /{name}/test`, `POST /{name}/auth`, `PUT /{name}/enabled` (409 for plugin-provided servers), `GET /api/mcp/catalog`, `POST /api/mcp/catalog/install` | `mcp.py:94`, `:110`, `:151`, `:174`, `:195`, `:245`, `:363-375`, `:430`, `:492` |
| `DELETE /api/profiles/{name}` | present | present. May answer `ok` with `settlement_pending` + `retry_command` | `profiles.py:869-887` |
| `PATCH /api/profiles/{name}` | present (rename; not used) | present (stops the bot's gateway, renames) | `profiles.py:850-866` |
| `GET`/`PUT /api/profiles/{name}/soul` | present | present. GET returns `{content, exists}`; PUT is atomic | `profiles.py:890-925` |
| Other profile routes (not in plan) | — | `PUT /api/profiles/{name}/description`, `PUT /api/profiles/{name}/model`, `POST /api/profiles` | `profiles.py:928`, `:942`, `:704` |
| `GET /api/learning/graph?profile=` | present | present | `status.py:663-675` |
| `/api/learning/node` | GET, PUT, DELETE; no add | present. GET `?id=&profile=` (404 `not found` / `skill '<id>' not found`); PUT body `{id, content, profile}` and DELETE body `{id, profile}` (400 on failure). Profile is in the **body** for PUT/DELETE, not the query. **No POST/add** (KTD17 holds) | `status.py:688-707`; bodies `web_models.py:217-224`; `agent/learning_mutations.py:106-169` |
| `GET /api/cron/jobs?profile=` | present | changed: `profile` defaults to `"all"`, so the app must pass the bot's name to scope | `cron.py:233-235` |
| `POST /api/gateway/restart` | unknown | present. Spawns `hermes gateway restart` in the background (`_spawn_gateway_restart`). Not exercised; whether it works under Umbrel's supervisor is still unverified | `actions.py:139-144`; `hermes_cli/web_server.py:866-891` |
| Unknown route vs missing profile (404 shape) | unknown route = bare `{"detail":"Not Found"}`; missing profile = other 404 | **changed.** Unknown `GET /api/...` = 404 `{"detail": "No such API endpoint: /api/..."}` (or `{"error": "Headless backend ..."}` under `hermes serve`). Unknown **non-GET** `/api/...` = **405** `{"detail": "Method Not Allowed"}`, because the SPA catch-all `GET /{full_path:path}` matches every path. Missing profile = 404 `{"detail": "Profile '<name>' does not exist."}`; an invalid name = 400. Unauthenticated = 401 before routing | `hermes_cli/web_server_dashboard.py:217-223`, `:110-129`; `hermes_cli/web_server_profiles.py:190-199` |
| Bearer (native PKCE) on core routes | unknown (plugin routes only?) | **present on every non-public `/api/*` route** while the gate is on. `gated_auth_middleware` verifies `Authorization: Bearer <access token>` against the provider stack and attaches the session. `_require_token` (reveal, validate, oauth start/delete) accepts any verified session in gated mode. The live server is gated (`auth_required: true`, `native_pkce` flow advertised) | `hermes_cli/dashboard_auth/middleware.py:150-171`; `hermes_cli/web_server.py:431-446`, `:655-673`, `:1121-1128` |

## Config internals

| Item | 0.21.2 expectation | 0.21.5 verdict | Evidence |
|---|---|---|---|
| `DEFAULT_CONFIG` | in `hermes_cli/config.py` | changed location: defined in `hermes_cli/config_defaults.py:21`, re-exported from `config.py:559`. 98 roots (listed below). Lacks `platform_toolsets` and `mcp_servers` | `config_defaults.py:21` |
| `_EXTRA_KNOWN_ROOT_KEYS` | present, includes `platform_toolsets`, `mcp_servers` | present, both included (listed below). `_KNOWN_ROOT_KEYS = DEFAULT_CONFIG roots ∪ extras` | `hermes_cli/config.py:968-986` |
| `_SECRET_CONFIG_KEYS` | present | present, now with a companion suffix rule `_SECRET_CONFIG_KEY_SUFFIXES` and `_is_secret_config_key` (leaf segment, lower-cased, `-` folded to `_`) | `config.py:2794-2814` |
| `_SECRET_KEY_RE` | `hermes_cli/plugin_packs.py` | present, unchanged location. A different regex with the same name is in `hermes_cli/agent_import.py:35-37`; don't confuse them | `plugin_packs.py:21` |
| `_redact_mcp_env` | masks every env value | present: every non-empty env value goes through `redact_key` -> `mask_secret`; on error `***`. Headers are not passed through it (summary only reports `auth: "header"`) | `hermes_cli/web_server_mcp.py:73-81`, `:84-100` |
| `agent/redact.py` vendor prefixes | present | present, `_PREFIX_PATTERNS` (listed below) | `agent/redact.py:140-212`, matcher `:577-581` |
| `tools.enabled_toolsets` enforced? | no; only `platform_toolsets.<platform>` | still not enforced at runtime (read only by `tools/bot_mode_probe.py:354`). Gateway sessions read `platform_toolsets.cli` via `_get_platform_tools(cfg, "cli", ...)` for every session platform (then fold in session toolsets) | `tui_gateway/server.py:1907-1941` |
| DEFAULT_CONFIG includes `platform_toolsets` / `mcp_servers`? | no | no, both are extra known roots | runtime check plus `config.py:968-986` |

## Steel browser provider

Present in the custom image's plugin dir: `/opt/data/plugins/browser-steel` (`plugin.yaml`: `name: browser-steel`, `version: 1.0.0`, `kind: backend`; files `provider.py`, `config.py`, `scrape_tool.py`) and `/opt/data/plugins/steel-live-view` (a `dashboard/` folder). The `/opt/hermes/plugins/` tree has a `browser` folder but no Steel provider.

## Gaps vs plan

1. **KTD6 error mapping (U14).** The "bare `{"detail":"Not Found"}` = unavailable" rule doesn't match 0.21.5. Map these to `HermesAdminUnavailable`: a 404 whose `detail` starts with `No such API endpoint`, a 404 with an `error` body under headless serve, a bare `Not Found`, and a **405** `Method Not Allowed` (any missing PUT/POST/DELETE/PATCH route). `HermesAdminNotFound` covers 404 `Profile '<name>' does not exist.`, learning-node 404s (`not found`, `skill '<id>' not found`) and `DELETE /api/env` 404 `<KEY> not found in .env`. A 400 means an invalid profile name. Update U14's test scenario that assumes the bare body. The RPC side is unchanged: `-32601` = unavailable, `4064` = not found. (R17–R20, R23–R26.)
2. **KTD7 premise changed (U16, U18; R17).** `profiles.configure enabled_toolsets` now writes the enforced `platform_toolsets.cli`. The REST route is still correct and still the per-toolset path, so no change is required. The New Bot flow (U18) could set toolsets in its single `profiles.configure` call. Replace semantics: an empty list clears the pin.
3. **`reload.mcp` needs a confirm (U14, U16; R17).** It isn't profile-scoped, and by default it answers `confirm_required` (it invalidates the prompt cache) unless sent with `confirm: true`. U14 should surface that as a confirmation, like the model guard, or send `confirm: true` after the user's own Save.
4. **Skills toggle isn't in `skills.manage` (U16; R17).** Per-bot enable and disable must use `PUT /api/skills/toggle?profile=` or `profiles.configure disabled_skills`. `skills.manage` only lists, searches, installs, browses and inspects. There's no skill uninstall RPC (`DELETE /api/learning/node` archives learned skills).
5. **MCP "enable" (U16; R17).** There's no `mcp.servers.enable`. Use `PUT /api/mcp/servers/{name}/enabled?profile=`, which returns 409 for plugin-provided servers, or `profiles.configure enabled_mcp_servers`.
6. **Main reasoning effort (U17; R19).** `POST /api/model/set` `reasoning_effort` applies to auxiliary slots only. The default reasoning effort goes through the merging `PUT /api/config?profile=`, which KTD9 already allows for. Make sure U17 doesn't rely on `model/set` for it.
7. **Learning node profile placement (U14, U18; R18, KTD17).** PUT and DELETE take `profile` in the JSON body, while GET takes it in the query. No add route; KTD17's disabled "Add memory" stands.
8. **Cron scoping (U14, U20; R26).** `GET /api/cron/jobs` defaults to `profile=all`, so always pass the bot's name.
9. **Gateway restart (U16).** The route exists, so U14 can expose it. Its effect inside the Umbrel container is still unverified and shouldn't be tested live (Open Questions; stop condition). Keep it behind an explicit owner action.
10. **Secret detection (U14 `hermes_secret_redaction.dart`, U19; R20, R21, KTD9).**
    - 0.21.5 adds the suffix rule `_api_key`, `_token`, `_secret`, `_password`, `_key`, `_access_key`, and folds `-` to `_` in header names. The shared detector should mirror both.
    - `_SECRET_CONFIG_KEYS` deliberately excludes bare `auth`, because `mcp_servers.<s>.auth: oauth` is a mode enum. KTD9's union with `_SECRET_KEY_RE` (substring `auth`) will mask that enum and keys like `oauth`/`author`. That's over-masking, not a leak. U19 should exempt the `auth` key when its value is a known mode (`oauth`, `header`, `bearer`), or the placeholder round-trip must preserve it.
    - `GET /api/config/raw` is unredacted and the `Invalid YAML` error echoes parser text, so the "never show server error text unredacted" rule matters here.
    - `_EXTRA_KNOWN_ROOT_KEYS` isn't exposed over HTTP, so the client must ship the list below. `DEFAULT_CONFIG` roots can be read at runtime from public `GET /api/config/defaults`.
11. **Bearer auth (U14, U7 smoke; R4).** No gap. Native PKCE bearer works on all core admin routes while the gate is on, and the live server is gated. Note that a loopback (ungated) dashboard would accept only the per-start session token.

No KTD6–KTD9 or KTD17 route is missing. Everything the plan builds on exists, with the shape changes above.

## Secret-detection lists (verbatim from the 0.21.5 source)

`hermes_cli/config.py:2794-2804`

```python
_SECRET_CONFIG_KEYS = frozenset({
    "api_key", "apikey", "key", "token", "access_token", "refresh_token", "id_token",
    "secret", "client_secret", "password", "passwd", "authorization",
    "private_key", "bearer", "jwt"})
_SECRET_CONFIG_KEY_SUFFIXES = ("_api_key", "_token", "_secret", "_password", "_key", "_access_key")
_NON_SECRET_KEY_SUFFIXES = ("_url", "_host", "_user", "_id", "_domain", "_scheme")
_ENV_PLACEHOLDER_RE = re.compile(r"^\$\{[A-Za-z_][A-Za-z0-9_]*\}$")
```

`_is_secret_config_key` (`config.py:2808-2814`): `leaf = key.rsplit(".", 1)[-1].lower().replace("-", "_")`; if the key is env-routed (`_is_env_config_key`, a dotless key in `_ENV_CONFIG_KEYS` or ending `_API_KEY`/`_TOKEN`/`_SECRET` or starting `TERMINAL_SSH`, `config.py:836-846`), it's secret unless it ends in a `_NON_SECRET_KEY_SUFFIXES`; otherwise `leaf in _SECRET_CONFIG_KEYS or leaf.endswith(_SECRET_CONFIG_KEY_SUFFIXES)`. `redact_config_value` (`:2817-2833`) masks string values under such keys, except `${VAR}` placeholders.

`hermes_cli/plugin_packs.py:21`

```python
_SECRET_KEY_RE = re.compile(r"(?i)(token|secret|passw(or)?d|api[_-]?key|private[_-]?key|credential|auth)")
```

`hermes_cli/web_server_mcp.py:73-81` (`_redact_mcp_env`): every non-empty value under `env` becomes `redact_key(str(v))` (`mask_secret`), and empty values become `""`. On exception the value is `***`.

`agent/redact.py:140-212` (`_PREFIX_PATTERNS`, wrapped as `(?<![A-Za-z0-9_-])(...)(?![A-Za-z0-9_-])` at `:577-578`)

```
sk-[A-Za-z0-9_-](?:\.?[A-Za-z0-9_-]){9,}
ghp_[A-Za-z0-9]{10,}
github_pat_[A-Za-z0-9_]{10,}
gho_[A-Za-z0-9]{10,}
ghu_[A-Za-z0-9]{10,}
ghs_[A-Za-z0-9]{10,}
ghr_[A-Za-z0-9]{10,}
xapp-\d+-[A-Za-z0-9-]{10,}
xox[baprs]-[A-Za-z0-9-]{10,}
AIza[A-Za-z0-9_-]{30,}
pplx-[A-Za-z0-9]{10,}
fal_[A-Za-z0-9_-]{10,}
fc-[A-Za-z0-9]{10,}
bb_live_[A-Za-z0-9_-]{10,}
gAAAA[A-Za-z0-9_=-]{20,}
AKIA[A-Z0-9]{16}
sk_live_[A-Za-z0-9]{10,}
sk_test_[A-Za-z0-9]{10,}
rk_live_[A-Za-z0-9]{10,}
SG\.[A-Za-z0-9_-]{10,}
hf_[A-Za-z0-9]{10,}
r8_[A-Za-z0-9]{10,}
npm_[A-Za-z0-9]{10,}
pypi-[A-Za-z0-9_-]{10,}
dop_v1_[A-Za-z0-9]{10,}
doo_v1_[A-Za-z0-9]{10,}
am_(?:org_)?[A-Za-z0-9]{20,}
sk_[A-Za-z0-9_]{10,}
tvly-[A-Za-z0-9]{10,}
exa_[A-Za-z0-9]{10,}
gsk_[A-Za-z0-9]{10,}
syt_[A-Za-z0-9]{10,}
retaindb_[A-Za-z0-9]{10,}
hsk-[A-Za-z0-9]{10,}
mem0_[A-Za-z0-9]{10,}
brv_[A-Za-z0-9]{10,}
xai-[A-Za-z0-9]{30,}
ntn_[A-Za-z0-9]{10,}
fw-[A-Za-z0-9]{30,}
fw_[A-Za-z0-9]{30,}
fpk_[A-Za-z0-9]{30,}
glpat-[A-Za-z0-9_\-]{10,}
gloas-[A-Za-z0-9_\-]{10,}
gldt-[A-Za-z0-9_\-]{10,}
glrt-[A-Za-z0-9_.\-]{10,}
glrtr-[A-Za-z0-9_.\-]{10,}
glcbt-[A-Za-z0-9_\-]{10,}
glptt-[A-Za-z0-9_\-]{10,}
glft-[A-Za-z0-9_\-]{10,}
glimt-[A-Za-z0-9_\-]{10,}
glagent-[A-Za-z0-9_\-]{10,}
glsoat-[A-Za-z0-9_\-]{10,}
glffct-[A-Za-z0-9_\-]{10,}
glwt-[A-Za-z0-9_\-]{10,}
GR1348941[A-Za-z0-9_\-]{10,}
pk-lf-[A-Za-z0-9\-]{8,}
```

Other structural matchers in `agent/redact.py` that the detector may want: `_JWT_RE` `eyJ[A-Za-z0-9_-]{10,}(?:\.[A-Za-z0-9_=-]{4,}){0,2}` (`:543`), `_PRIVATE_KEY_RE` PEM private-key blocks (`:509`), `_TELEGRAM_RE` `(?<!\d)(bot)?(\d{8,}):([-A-Za-z0-9_]{30,})` (`:507`), `_URL_USERINFO_RE` (`:551`), and `_DB_CONNSTR_RE` (`:519`).

## Root-key lists

`DEFAULT_CONFIG` roots (`hermes_cli/config_defaults.py:21`): `_config_version, agent, approvals, auth, auxiliary, bedrock, bot_desktop, bot_mode, browser, checkpoints, code_execution, command_allowlist, compression, computer_use, context, context_file_max_chars, context_file_read_timeout, credential_pool_strategies, cron, curator, dashboard, database, delegation, desktop, discord, display, doctor, fallback, fallback_providers, file_read_max_chars, gateway, goals, honcho, hooks, hooks_auto_accept, human_delay, kanban, local_runtime, logging, loops, lsp, matrix, mattermost, max_concurrent_sessions, max_live_sessions, mcp, mcp_discovery_timeout, mcp_single_query_discovery_timeout, memory, moa, model, model_catalog, model_overrides, models_dev, monitoring, network, nous, onboarding, openrouter, paste_collapse_char_threshold, paste_collapse_threshold, paste_collapse_threshold_fallback, personalities, platform_hints, plugins, prefill_messages_file, privacy, prompt_caching, providers, proxy, quick_commands, runtime, secrets, security, session, sessions, skills, slack, streaming, stt, telegram, telemetry, terminal, timezone, tool_loop_guardrails, tool_output, tools, toolsets, tts, updates, vault, vertex, vision, voice, wake_word, web, whatsapp, x_search`

`_EXTRA_KNOWN_ROOT_KEYS` (`hermes_cli/config.py:968-986`): `allow_all_users, always_log_local, custom_providers, fallback_model, filter_silence_narration, group_sessions_per_user, image_gen, known_builtin_toolsets, known_plugin_toolsets, mcp_servers, multiplex_profiles, platform_toolsets, platforms, plugins, profile_routes, require_mention, reset_triggers, signal, smart_model_routing, stt_echo_transcripts, thread_sessions_per_user, timeouts, tool_gateway_declined_tools, unauthorized_dm_behavior, video_gen`
