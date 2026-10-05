# Hermes Spaces plugin

Spaces and Pages: persistent Markdown working documents shared by the user
(in Conduit) and Hermes. One Hermes **user plugin**; no new service, database
server, agent runtime or Hermes core change. Steel, Hindsight, the proactive
system and skills are untouched.

| Piece | File | Runs in |
| --- | --- | --- |
| SQLite store (spaces, pages, page_chats) | `spaces_store.py` | both |
| Five agent tools (`spaces` toolset, no delete) | `tools.py` | agent processes |
| `pre_llm_call` hook: Page metadata for Page-bound sessions | `context_hook.py` | agent processes |
| REST API at `/api/plugins/spaces/` (dashboard auth) | `dashboard/plugin_api.py` | dashboard |
| Hidden dashboard registration (UI lives in Conduit) | `dashboard/manifest.json`, `dashboard/dist/index.js` | dashboard |

Data: `<hermes root>/spaces/spaces.db` (`/opt/data/spaces/spaces.db` on the
Umbrel), shared by every profile. WAL, `foreign_keys`, `busy_timeout=5000`.
Every mutation is `BEGIN IMMEDIATE` with an expected-revision check, so a stale
writer always gets `409 revision_conflict` and never overwrites.

## Contracts

- Page bodies are untrusted document data. The tools say so; the hook never
  injects a body, only `space_id`, `page_id`, `title`, `current_revision` and
  the instruction to `spaces_read_page` before answering or editing.
- `spaces_edit_page` requires the revision from the latest read. A conflict
  returns `{"ok": false, "error": "revision_conflict", "current_revision": n,
  "instruction": "Read the page again before attempting another edit."}`.
- `source_session_id` comes from the tool runtime (`session_id` kwarg), never
  from model arguments.
- REST errors: `{"error": <code>, "message": ..., ...}`. Codes: `not_found`
  (404), `invalid_request` / `invalid_parent` (422), `revision_conflict`,
  `name_taken`, `space_not_empty`, `page_has_subpages`, `session_already_bound`
  (409).

## Install (what was done on the Umbrel, 2026-10-04)

1. Back up `config.yaml` (root and each profile) as `*.bak-<date>-spaces`.
2. Copy this folder to `/opt/data/plugins/spaces` (owner `hermes`).
3. `hermes plugins doctor spaces` (must report OK, 5 tools, 1 hook).
4. `hermes plugins enable spaces` (root; do **not** grant tool override).
5. **Every profile needs the plugin in its own `plugins/` dir.** Under a
   profile Hermes discovers bundled plugins and `<profile>/plugins/` only,
   not the root user plugins (a root-only install worked for `default` and
   the dashboard API, but Kai never saw the tools or the hook). For each
   profile with a `config.yaml`:
   `ln -s /opt/data/plugins/spaces /opt/data/profiles/<p>/plugins/spaces`
   and add `spaces` to that profile's `plugins.enabled` (create the
   `plugins:` block if missing). Check with
   `hermes --profile <p> tools list | grep spaces`. Done for autopilot,
   fast, hermuse, kai, local and strong; the `*skills` profiles have no
   config and were left alone. One shared DB: the store resolves the
   Hermes root, not the profile home.
6. `docker restart hermes-agent_web_1`; check the log line
   `Mounted plugin API routes: /api/plugins/spaces/` and that an
   unauthenticated `GET /api/plugins/spaces/health` returns 401.

## Tool search

Hermes' tool search defers every plugin tool: the model sees it in a
catalog and calls it through the `tool_call` bridge. Only
`tools.tool_search.enabled: off` keeps plugin tools in the direct list, and
that changes every tool, so it was left alone. The `pre_llm_call` hook names
`spaces_read_page` and the Page id, which is enough for the model to reach it
(verified with Kai). Conduit's activity rows unwrap the bridge and show the
Spaces tool by name.

## Tests

Stdlib `unittest`, runnable in the Hermes venv (FastAPI only there):

```
cd hermes-plugins/spaces
python -m unittest discover -s tests          # 25 pass, API tests skip
# inside the container, from a /tmp copy:
/opt/hermes/.venv/bin/python -m unittest discover -s tests   # all 30
```

## Backup

The DB lives in Hermes' persistent data path and is covered by host
snapshots. Application-consistent copy:

```
sqlite3 /opt/data/spaces/spaces.db ".backup '/opt/data/backups/spaces-YYYYMMDD.db'"
```

Before a schema migration: back up, record `PRAGMA user_version`, migrate in
one transaction, `PRAGMA integrity_check`, then start.

## Rollback

Remove `spaces` from `plugins.enabled` (root and profiles) and restart
Hermes. Keep `spaces.db`. Conduit's health probe then fails and the Spaces
entry disappears; nothing else depends on the plugin.
