# Hermez A2UI identity and native Hermes Kanban

Status: implementation specification and runbook, **not implementation**. Written 2026-09-26. This extends the existing debug-Android Hermez chat facelift; it does not authorize a Hermes upgrade or introduce the concept image's Home, Live, Spaces, or Focus destinations.

## Evidence and compatibility baseline

- Conduit `main` at `b09a8e370853848696bdc97ff0c5a81a670d6597` pins Flutter GenUI `0.10.3` and renders completed Hermes `a2ui` fences through `HermesA2uiSurface` and `BasicCatalogItems.asNoAssetCatalog()`. App-owned `StatusBadge`, `MetricTile`, and `MiniChart` live in `hermes_visual_catalog.dart`. Read-time layout repair already protects old metric rows. **Visual gap:** the current Hermez chat palette is not applied to the GenUI subtree, so A2UI can still look like default Conduit/Material cards. Existing MEDIA, Mermaid, Chart.js, tools, approvals, and sessions must not change.
- The live Umbrel container was inspected **read-only** on 2026-09-26: `hermes-agent_web_1`, image `hermes-agent-umbrel-teams:v2026.9.7-kai1`. Its installed `plugins/kanban/dashboard/plugin_api.py` mounts `/api/plugins/kanban/`. `GET /boards`, `GET /board?board=<slug>`, `GET /tasks/{id}?board=<slug>`, `POST /tasks?board=<slug>`, `PATCH /tasks/{id}?board=<slug>`, and `POST /tasks/{id}/comments?board=<slug>` are present. `WS /events` is also present, but needs the dashboard's canonical WebSocket authentication. We inspected source, **not private board contents**. Current upstream documentation can be newer than this installed image; installed routes and response shapes win.
- The installed board response is `{columns: [{name, tasks}], tenants, assignees, latest_event_id, now}`. Its lanes are `triage`, `todo`, `scheduled`, `ready`, `running`, `blocked`, `review`, `done`; `archived` is opt-in. Board selection is separate from the CLI's current-board pointer. Always pass the selected board slug on every scoped REST call and on any future event socket.
- The installed task-detail response contains `task`, `comments`, `events`, `attachments`, `links`, `child_results`, and `runs`. Board cards include derived age, latest-summary preview, link/comment counts, child progress, and diagnostics. Do not fabricate a progress percentage from `running` or from elapsed time.
- Hermes' dashboard plugin uses the same `kanban_db` domain layer as its CLI and agent tools. Conduit must consume that API, not open `kanban.db`, invoke a shell, or implement a second task engine.
- Flutter's GenUI remains alpha. A2UI v0.9 is the fork's current wire format. The v0.9 `createSurface.theme` field exists, but Hermez's look is a **client-owned presentation policy**, not an invitation for agent JSON to set arbitrary colors or fetch theme assets.

## Design intent and originality

Use the supplied concept image for hierarchy: large editorial type, warm paper/light surfaces, graphite machinery, fine technical borders, disciplined orange accents, and one tactile control at a time. AULUMU's own design language emphasizes purposeful geometry, precision, and material character; Andy Allen's (Not Boring) work emphasizes legible utility with memorable, intentional feedback. These are principles to reinterpret in native Flutter. Do not copy either company's trademarks, proprietary hardware renders, 3D objects, typography files, sounds, illustrations, or exact screens. No simulated weather, service state, task activity, or fake completion animation.

Design system, three layers (the skill's linked reference files are absent locally, so this is the explicit project contract):

| Layer | Tokens / use |
| --- | --- |
| Primitive | Existing Hermez palette: light canvas `#F6F5F2`, light surface `#FFFFFF`, ink `#17181C`, orange `#FF5A26`, border `#DAD9D5`; dark canvas `#111215`, surface `#24252A`, ink `#F6F5F2`, orange `#FF6A36`, border `#434449`. Muted labels come from `HermezChatPalette`. |
| Semantic | `canvas`, `surface`, `ink`, `muted`, `border`, `action`, `onAction`; **separate** `success`, `warning`, `danger`, `unknown` status colors with text/icon labels. Orange denotes an action or emphasis, not automatically “healthy.” Verify contrast in both modes; do not make color the only status signal. |
| Component | A2UI card, metric, badge, chart, field, action button; Kanban lane, task card, status chip, detail sheet, activity row. Each maps semantic tokens to explicit normal/pressed/disabled/loading/error states. No per-response magic hex values. |

Use a compact spacing scale (4/8/12/16/24 logical px), consistent radii (10/16/24), low or zero elevation, thin borders, and generous typography. The existing system font may remain; use weight, size, line height, and tracking rather than adding a new font dependency. Minimum touch target 48 dp on Android. Motion: brief, purposeful tap/transition feedback (roughly 120–220 ms); respect reduced-motion and do not animate merely because a worker is `running`. Haptics belong to confirmed user actions, not passive updates. Maintain readable numbers and controls at 320 dp and 200% text scale.

## Part A — Align all existing Hermes A2UI responses

### Scope and technical route

1. Begin with the existing **debug Android + Hermes** gate. Extract the current `HermezChatPalette` into a small renderer-owned `HermezVisualTokens`/theme helper shared by the chat and A2UI. Do not change Conduit's global theme, the A2UI JSON, or persisted messages. Theme the subtree in `HermesA2uiSurface` so **previously saved A2UI** re-renders with the new identity.
2. Override a local Flutter `ThemeData`/`ColorScheme`, `CardThemeData`, text styles, divider, input decoration, and button themes for the GenUI subtree. GenUI 0.10.3's built-in `Card` reads `colorScheme.surface`; its `Button` reads `colorScheme.primary/onPrimary` and uses Material buttons. Confirm the other supported basic controls against the pinned package before styling them. Let the app, not the model, supply the palette. Keep `asNoAssetCatalog()`; never enable model-supplied image/audio/video URLs to achieve the look.
3. Update app-owned `StatusBadge`, `MetricTile`, and `MiniChart` to use the same semantic tokens. Preserve their bounded-data validation, finite-width fallback, accessible summaries, units, sources, timestamps, and action IDs. Use accent for chart/primary-action emphasis; keep health states distinct and labeled. A metric without a meaningful range still has **no progress track**. No invented samples, percent, or trend.
4. Use composition, not decorative density, for variety: an overview can have one prominent metric plus a focused status list; a comparison can have two weighted metrics; a timeline can be a list with clear sequence; a planner can use choice/date/text controls; a budget or trend can use `MiniChart` only for real observations. Ordinary prose stays Markdown. The `a2ui` fence remains the explicit render boundary. The existing Hermes mobile A2UI skill can describe these composition patterns, but must not force every request into a dashboard or inject style properties into JSON.
5. Do **not** add an A2UI `KanbanCard` component for the board. Kanban is durable server state and belongs in a native destination, not a generated per-message surface. A2UI can later link to a particular task only through a reviewed, explicit action contract.

Composition fixtures must cover more than monitoring: a trip itinerary (sequence and date controls), budget planner (real amounts and a comparison chart), meal plan (choices and actions), project sprint (prioritized tasks), and one status dashboard (measured metrics). A plain-language request should be enough for Hermes to select an appropriate composition. Do not require the user to name `MetricTile` or `Column`, and do not convert every answer to cards.

### A2UI acceptance gate

- Golden/widget tests at 320/360/412 dp, light/dark, 1×/2× text, for saved fixtures: project sprint, trip itinerary, meal-plan form, budget planner, and metric dashboard. Compare meaningful structure, contrast, and legibility; avoid brittle pixel checks for system fonts. Test an arbitrary ordinary `json` fence remains code.
- Verify built-in `Card`, primary/default/borderless `Button`, TextField, ChoicePicker, CheckBox, Slider, and DateTimeInput inherit the Hermez subtree theme; custom badge/metric/chart use the same tokens. Focus states and disabled actions remain clear; screen-reader labels convey numbers and state.
- Re-run metric-row finite-width regressions, A2UI action-once test, malformed-surface fallback, MEDIA image/file, Mermaid/Chart.js, and non-Hermes chat tests. Investigate the previously observed malformed-surface test stall before calling the full A2UI suite green.
- Install the debug build over the existing S25 app (`adb install -r`, no data clear). Reopen **old saved** A2UI examples and request varied new examples with ordinary prompts rather than requiring explicit component lists. Confirm dark/light, large text, scrolling, and background/resume. Do not roll this into release until accepted.

## Part B — Add one native Kanban destination

### Product boundary and mobile information architecture

Add **Kanban** as one entry in the existing Hermes-capable drawer, plus one route. Keep Chat as Chat; do not create the image's other four destinations or replace the current shell. A phone cannot show eight tiny columns: use a board selector, compact counts/filters, a horizontally scrollable **lane selector**, and a vertically scrolling list for the selected lane. On wide tablet/landscape widths, allow a multi-column board using the same task-card component. Open a card into a detail sheet with description, assignee, priority, dependencies/child progress, comments, run history, diagnostics, and attachment metadata only where supported. Show actual data provenance and timestamps; label missing data as unknown rather than zero.

The visual hierarchy is: board name and refresh state; lane name/count; task title; status word/icon; assignee and priority; a small factual footer for age, comments, dependencies, or child completion. A task card should not lead with a giant fake progress ring. Use one distinctive orange affordance for the primary action, a restrained graphite/ivory body, and semantic status accents. Selecting a card opens details without moving it. Loading, empty lane, offline-stale, auth-expired, and permission/transition-conflict states each need explicit copy and a recovery action.

Important installed semantics:

- `running` is a dispatcher claim, **not** a status users can set directly. The installed PATCH route rejects a direct move to `running`.
- `ready` can be refused by unfinished parent dependencies (HTTP 409 with blocker information). `blocked` and `scheduled` have distinct meanings. `review` is not `done`; `archived` is hidden unless requested. Model the installed eight lanes, not a generic To Do / Doing / Done board.
- A task can be active when the app is backgrounded; a local optimistic state must never become the source of truth. Every mutation uses the server endpoint and then refreshes the selected board/task. Never silently retry a non-idempotent create. An idempotency key is available for explicit create-retry handling.

### Data and auth architecture

Use the **existing Hermes Dashboard origin and Dashboard session**. Native PKCE alone is not evidence that the Dashboard plugin accepts the call. Start with `HermesDashboardRestBridge` for small JSON reads/writes: it already loads the Dashboard-authenticated origin, sends `credentials: include`, preserves configured access headers, rejects redirects, and caps textual responses at 4 MB/2 MB decoded text. Verify same-origin `https` when configured and keep cookies, access headers, and any ephemeral token out of persisted tasks, logs, Markdown, URLs, and analytics. Do not enlarge that bridge's cap for a big board; show a bounded error and evaluate a dedicated exact-origin JSON client only if real board size demands it. No new backend or Hermes core patch.

Map `GET /boards`, `GET /board?board=<slug>`, and `GET /tasks/{id}?board=<slug>` into small typed Dart DTOs with tolerant unknown fields and explicit null states. Pass `board=<selected slug>` on **every** scoped request; never rely on the server/CLI current-board pointer. For V1 use pull-to-refresh, refresh on return to foreground, and an optional modest visible-screen poll. Do not assume a WebSocket token can be reused from a REST cookie: if live events are added, use the installed `/events?board=<slug>&since=<cursor>` with its canonical WS auth, a fresh socket on board switch, cursor dedupe, reconnect/backoff, lifecycle disposal, and a full REST reconciliation after gaps. Never log the token-bearing URL. A failed socket must leave manual refresh working.

Suggested typed boundary: `KanbanBoardRef(slug, name, counts)`, `KanbanSnapshot(boardSlug, fetchedAt, latestEventId, lanes)`, `KanbanTaskSummary(id, title, status, assignee?, priority, createdAt?, childDone?, childTotal?, diagnostics?)`, and `KanbanTaskDetail(summary, body?, comments, events, links, runs, attachments)`. Preserve unknown server fields only in an in-memory DTO extension if needed; never round-trip a task by serializing an old GET object into PATCH. The PATCH body contains only the field the user changed. Reject a response whose board slug does not match the selected board generation, including after rapid board switching.

Auth/error states: 401/403 → Dashboard sign-in affordance, 404 → missing board/task, 409 → human-readable conflicting dependency/transition, 5xx/offline → preserve last visible read-only snapshot marked stale (in memory only), malformed/oversize response → fail visibly without crashing chat. Keep Kanban data out of Conduit's conversation database. Attachments use the installed authenticated attachment endpoint if/when downloaded; do not render server filesystem paths as mobile URLs.

### Mutations and release slices

| Slice | Allowed functionality | Gate |
| --- | --- | --- |
| K0 read-only | Discover boards; view eight lanes, filters, task detail, run/comment/dependency summaries; pull-to-refresh. | Verify exact installed response fixtures, empty/error/auth states, board scoping, 100+ cards without UI jank, narrow/large-text layouts. |
| K1 safe edits | Create triage/todo task with chosen board; add comment; edit title/assignee/priority; explicit status actions with server confirmation. | Distinct confirmation for `done`, `archive`, `block`, and any action affecting a `running` worker. Handle 400/409 and double taps. Never offer direct `running`. Refresh after writes; no offline write queue. |
| K2 live | Authenticated board-pinned event socket and background/resume reconciliation. | Reconnect, cursor gap, board-switch, auth expiry, duplicate event, and no-cross-board tests. Add only if K0/K1 are stable. |

The earliest useful release is K0 + a task detail sheet; K1 is not required to ship a visual board. Defer bulk drag/drop, board administration/deletion, dispatcher nudges, worker termination, log streaming, attachment upload/delete, tenant administration, and cross-board analytics. Those are consequential operational controls and need separate UX/security review.

### Proposed client footprint

- `lib/features/hermes/kanban/models/` — typed board/task/detail/status DTOs and JSON fixtures.
- `lib/features/hermes/kanban/services/hermes_kanban_client.dart` — exact-origin Dashboard REST adapter, with board slug on every scoped call; no direct SQLite or CLI.
- `lib/features/hermes/kanban/providers/` — selected-board/selected-lane state and invalidation, isolated from chat sessions.
- `lib/features/hermes/kanban/views/hermes_kanban_page.dart` and a task-detail sheet, using shared Hermez tokens and existing router/drawer.
- Small route/drawer edits only; no shell redesign, database migration, extra daemon, or Hermes upgrade.

## Runbook: snapshots, build, verification, rollback

0. **Inventory/snapshot.** Record Conduit HEAD/dirty state, running Hermes image tag, current Android package/signature, auth mode, and the installed API route/response contract without reading private task bodies into the repo. Back up touched Flutter sources and current debug APK outside Git. Do not alter Umbrel services, ports, Gateway, model, auth configuration, or task DB.
1. **A2UI identity.** Implement Part A behind the existing debug Android Hermes gate. Add tests before/with code; run targeted analyzer and tests. Build/install over the S25. Compare saved and varied new A2UI answers, light/dark and 200% text. Roll back only the client theme/catalog changes if an existing surface regresses.
2. **Kanban contract.** Verify `GET /boards`, `/board`, and one synthetic/authorized task-detail response against the installed image in a controlled environment. Note: the installed plugin's `_conn()` can initialize a missing board DB even on GET, so avoid casual production probes during spec work. Save **sanitized** fixtures and verify auth failures/size limits. No server patch.
3. **K0 page.** Add the single route and drawer entry. Keep all server operations read-only. Test empty/default/multiple boards, every installed lane, archived opt-in, filters, long titles, null assignee, unknown fields, stale offline state, and auth expiry. Test 320/360/412 dp, 200% text, screen reader, reduced motion, portrait/landscape.
4. **K1 actions** only after K0 works on device. Test server-validated transitions, dependency 409, direct-running refusal, double-submit, board switch during pending request, and auth expiry mid-write. Require confirmation where an action can stop work or hide a task. Show the actual server result after refresh; never claim success from animation alone.
5. **K2 events** only if needed. Verify board-pinned WS authentication and lifecycle; otherwise keep explicit refresh. Test no leaks, reconnects, and no cross-board updates.
6. **Regression + release.** Run A2UI/MEDIA/Mermaid/Chart.js, chat send, tools/approvals, backgrounding, and existing Hermes session tests. Build ARM64 debug and install with `-r`; inspect S25 screenshots and error logs. Check Umbrel container restart count/unhealthy services before and after; any pre-existing host issue is recorded separately. Commit client changes only after QA. Roll back by reverting the relevant client commits/reinstalling prior debug APK; Kanban remains server-owned and no task DB migration is involved.

## Sources reviewed 2026-09-26

- [AULUMU brand story](https://aulumu.com/pages/story-of-aulumu) — purposeful structural/industrial design language; visual inspiration only.
- [Apple Developer interview with Andy Allen on (Not Boring) Habits](https://developer.apple.com/news/?id=9ab1g4r3) and [(Not Boring) Timer listing](https://apps.apple.com/us/app/not-boring-timer/id1531048091) — intentional delight, legibility, haptics and motion; no copied assets.
- [Flutter GenUI overview](https://docs.flutter.dev/ai/genui) and [components](https://docs.flutter.dev/ai/genui/components) — catalog-owned native widgets; alpha status.
- [A2UI v0.9 specification](https://a2ui.org/specification/v0.9-a2ui/) — surface/catalog/theme semantics.
- [Hermes upstream Kanban reference](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/kanban.md) — architecture and human/agent routes. Installed `v2026.9.7-kai1` source was checked separately and is authoritative for implementation.
