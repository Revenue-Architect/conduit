# Conduit delegation bridge

This extension projects existing Hermes work into Conduit. Hermes remains responsible for execution, task status, authentication, and session ownership.

## Installed files

| Source | Container destination |
|---|---|
| `ask-specialist.py` | `/opt/data/bin/ask-specialist` |
| `conduit_delegation.py` | `/opt/data/bin/conduit_delegation.py` |
| `plugin.yaml`, `__init__.py` | `/opt/data/plugins/conduit-delegation/` |
| `manifest.json`, `projection_api.py`, `dist/index.js` | `/opt/data/plugins/conduit-delegation/dashboard/` (retain `dist/`) |

Back up the installed wrapper before replacing it. Preserve its executable mode. The wrapper keeps the existing oneshot source normalization and depth guard:

```python
child_env["HERMES_SESSION_SOURCE"] = "oneshot"
child_env["HERMES_SESSION_SOURCE_EXPLICIT"] = "1"
child_env[DEPTH_ENV] = "1"
```

Enable `conduit-delegation` through Hermes's plugin CLI. Other profiles use symlinks to the same plugin directory. Hook changes reload through that CLI. The gateway caches dashboard API modules, so an API change needs a restart of the affected idle gateway; enabling hooks alone does not reload Python routes.

## Data flow

The terminal hook carries Hermes's actual parent session, profile, turn, and tool-call IDs into the specialist wrapper. Lifecycle receipts sit beside existing specialist handoffs. The authenticated plugin router checks parent ownership before returning workers or artifacts.

Native workers recover from recorded tool results and `async_delegations`. Kanban workers require both the task's stored parent session and an exact creation-tool result. No title or bot-name matching is used.

Conduit reads this projection every eight seconds while the parent is visible. Native events continue through the existing gateway stream. Transcript reads use the child's explicit profile and session; they never resume it or submit a prompt.

## Verification and recovery

Run `python -m unittest discover -s scripts/hermes/inline-delegation -p test_projection.py -v` from the repository. Android projection and widget tests are under `test/features/hermes/`.

A native worker's cold recovery record may lack a child session ID. Its activity and result remain available, but the app cannot open an unreported session. Named specialists remain read-only. Kanban tasks open the existing task view when no chat session is reported.

To roll back, disable this plugin and restore the saved wrapper. Keep existing handoffs and native task/session records. No database migration or model change is involved.
