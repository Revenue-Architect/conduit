---
name: a2ui-mobile
description: "Use when a compact native visual or interaction would improve a Conduit answer: plans, schedules, budgets, choices, comparisons, checklists, forms, itineraries, status, and dashboards across any topic. Users need not say A2UI, GenUI, visual, or name components. Compose A2UI v0.9 when it adds value."
version: 0.8.1
author: Kamranur Rahman, Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [A2UI, GenUI, Conduit, Flutter]
    related_skills: [png-text-cards, mermaid-diagrams, pdf]
---

# A2UI Mobile Skill

If the user explicitly requests A2UI or GenUI, produce a native surface. The output contract is a closed fenced `a2ui` block with one complete v0.9 JSON message per line: `createSurface` followed by `updateComponents`. A `json` or `jsonl` fence is displayed as code in Conduit. Legacy messages named `surfaceUpdate`, `beginRendering`, or `dataModelUpdate` are not supported. Check those four details before answering, regardless of the subject of the surface.

Create concise, visual-first native interfaces that Hermes can render in Conduit. Consider an A2UI surface for an actionable plan, schedule, budget, choice, comparison, checklist, form, itinerary, or status view even when the user does not request a visual. Use it when interaction, scanning, comparison, or a native control materially improves on Markdown. Do not turn ordinary prose into a decorative card.

## Choose the right output

- Use Markdown for ordinary explanations and short answers.
- Use Mermaid for architecture, sequence, and dependency diagrams.
- Use A2UI for a scannable native view or meaningful interaction: status, comparison, choices, forms, checklists, lists, grouped details, and simple trends. The subject can be any domain, not just services.
- Use Conduit's existing Chart.js renderer for a chart that needs more than one simple series or detailed axes.
- Use an authenticated `MEDIA:` artifact for an actual generated image, screenshot, or report. Do not put image URLs in A2UI.
- Combine formats only when each adds useful information; for example, one sentence, a Mermaid diagram, and a small action surface.

## Choose a composition by intent

Infer the user's task and select the smallest useful composition. These are starting points, not templates to copy verbatim. Change component choice, order, wording, and actions to fit the data and the question. A terse request does not require the user to name A2UI or a component.

| Intent | Useful composition |
|---|---|
| Overview or monitoring | StatusBadge for observed states; MetricTile for measured numbers; a focused details action when useful |
| Decide among options | Distinct Buttons for a few immediate choices; ChoicePicker for a single or multi-selection that needs confirmation |
| Enter or update information | Only the needed TextField, CheckBox, Slider, ChoicePicker, or DateTimeInput controls, then one clear submit action |
| Review a checklist or sequence | List or Column of short items; CheckBox only if the user must mark items; no fake completion state |
| Compare items | Equal-weight Row for short MetricTiles, or stacked Cards/List for longer descriptions; state the basis and units |
| Explore grouped details | Tabs when groups are distinct and each has useful content; otherwise a Column or specific details action |
| See change over time | MiniChart for one series of 2–60 observed samples; MetricTile for one value; Chart.js for complex visualization |
| Get a diagram, image, or report | Mermaid, `MEDIA:`, or a document artifact respectively; A2UI may complement but should not replace the actual artifact |

Exact required/optional props for every component are in `references/component-guide.md` (raw catalog JSONs sit beside it).

## Visual-first response shape

When A2UI is the main answer:

1. Start with at most one short sentence. Let the native surface carry the details; do not repeat its contents in paragraphs before or after it.
2. Put the user's requested answer first, then a few scannable facts or controls. Use a short title, concise labels, clear grouping, and actions only where they help.
3. Put long supporting detail behind a specific “Details” action or in brief surrounding prose. Never hide a warning, failure, limitation, or uncertainty.
4. Include when a live value was checked and what evidence supports it. Use `unknown` or “Not checked” when there is no evidence. Do not infer full service health from a single reachable endpoint.
5. Do not fabricate history, trend points, units, timestamps, thresholds, or service state.

## Protocol

- Use A2UI v0.9 only.
- Use catalog ID `https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json`.
- Put A2UI messages only inside a fenced `a2ui` block. Send complete JSON messages, one object per line; never stream partial JSON.
- A surface normally has one `createSurface` followed by `updateComponents`.
- Give each response a unique `surfaceId`. Component IDs must be unique, with exactly one component whose ID is `root`.
- Keep each surface self-contained. After an action, Hermes receives a normal turn; return an updated surface in the next answer rather than relying on older surfaces changing.
- Build a tree: each visible node has one parent. A Button's label Text is its `child`; do not also put that label in the surrounding Column/List. The same applies to Card children, tab content, and modal content.
- Use only the built-in GenUI basic components and the app components documented below. Never emit HTML, JavaScript, Dart, custom component definitions, or executable code.

## Components available in Conduit

Built-in components include `Card`, `Column`, `Row`, `Text`, `Icon`, `Divider`, `List`, `Tabs`, `Button`, `ChoicePicker`, `CheckBox`, `TextField`, `Slider`, and `DateTimeInput`.

For `Tabs`, pinned Flutter GenUI 0.10.3 requires entries shaped as `{"label":"Overview","content":"overview-component-id"}`. Do not use the upstream v0.9 `title`/`child` spelling for new Conduit output. Conduit repairs that older spelling at read time for saved messages.

Conduit also provides these data-only visual components:

- `StatusBadge`: required `label` and `state` (`ok`, `warning`, `error`, `unknown`); optional short `detail`. Always use a state word as well as its icon. Unknown must be neutral.
- `MetricTile`: required `label` and observed numeric `value`; optional `unit`, `min`, `max`, `state`, ISO 8601 `asOf`, and short `source`. Give units for percentages, sizes, latency, and counts. Only provide `min` and `max` when the range is meaningful.
- `MiniChart`: required `label`, `kind` (`line` or `bar`), and ordered `points`, each with a short `label` and finite numeric `value`; optional `unit`, ISO 8601 `asOf`, and `source`. Limit to 60 real observations. Use it only with at least two observations. For one observation, use a `MetricTile`; for no data, say so without drawing a chart.

Exact props for every component — including forms (`TextField`, `CheckBox`, `ChoicePicker`, `Slider`, `DateTimeInput`) and `Tabs`/`Modal` — are in `references/component-guide.md`; complete worked surfaces in `references/patterns.md`.

Do not place remote image URLs in `Image`; that component is unavailable for agent-provided network assets. Return image files with `MEDIA:<absolute-path>` so Conduit can fetch them through authenticated Hermes file routes.

## Phone layout

- Design for about 300 logical pixels of content width inside the phone chat column. Keep all text and buttons within that width, including at larger text scale.
- Prefer a `Column` for mixed content and actions. Use a `Row` only when side-by-side reading helps; use `List` for repeated items and `Tabs` for genuinely distinct groups.
- Every direct `MetricTile`, `MiniChart`, `StatusBadge`, `Slider`, `TextField`, `ChoicePicker`, `DateTimeInput`, `Card`, `Column`, `Row`, `List`, or `Tabs` child in a `Row` must have a positive integer `weight`. This applies to overview dashboards as well as comparison cards. For two short comparable metrics, use `weight: 1` on both tiles. Conduit's read-time repair protects saved older messages, but author new output correctly.
- Use a `Column` when a value or label is long, when a chart or control needs room, or when a weighted interactive row would be cramped or make reading order unclear. Do not force a side-by-side layout just to make a dashboard compact.
- Never put a long sentence beside a button in a `Row`. If a short row is essential, give the wrapping `Text` child an integer `weight` of 1 and keep the button label short. Conduit repairs the known unweighted Text+Button row by stacking it, but generated output should already be correct.
- Keep multiple actions vertically stacked. Give each a semantic event name identifying intent and target, such as `item.inspect` with a small `context` containing the item ID. Do not reuse one ambiguous action for different targets.
- Keep titles and labels short. Avoid broad tables, paragraphs inside cards, nested card stacks, and long button labels.
- Use the supported icons `check`, `warning`, `error`, and `help` with the state word. Color is never the only status signal.

## Interaction and truth defaults

- A tap sends a follow-up turn in the same chat. It is not a direct launch or mutation. Read-only requests must remain read-only, including any checks Hermes performs. For a requested change, show the proposed values and obtain explicit confirmation before an external mutation; do not imply a button alone performed it.
- One self-contained surface per reply is the default. Use a unique `surfaceId`, one `root`, and one closed `a2ui` fence; don't depend on old chat cards updating.
- Give actions semantic names and the minimum context needed to identify the selected item. After an action, answer the new question and choose the appropriate next composition; do not force every follow-up into a status card.
- For live state, show what was checked, when, and at what scope. For user-provided or illustrative data, say so; do not pretend it was freshly measured. Unknown stays unknown.
- Around a surface, use at most one short introductory sentence unless essential context or caveats require more. Do not repeat the whole card in prose.

## Example: visual service overview

```a2ui
{"version":"v0.9","createSurface":{"surfaceId":"service-overview-01","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"service-overview-01","components":[{"id":"root","component":"Card","child":"content"},{"id":"content","component":"Column","children":["title","summary","hermes","hermes-action","immich","immich-action","nvr","nvr-action"]},{"id":"title","component":"Text","text":"System status","variant":"h4"},{"id":"summary","component":"Text","text":"2 online · 1 needs attention","variant":"caption"},{"id":"hermes","component":"StatusBadge","label":"Hermes","state":"ok","detail":"Gateway connected · checked 18:04 UTC"},{"id":"hermes-action","component":"Button","child":"hermes-action-label","action":{"event":{"name":"service.hermes_details"}}},{"id":"hermes-action-label","component":"Text","text":"Hermes details"},{"id":"immich","component":"StatusBadge","label":"Immich","state":"ok","detail":"API responded · checked 18:04 UTC"},{"id":"immich-action","component":"Button","child":"immich-action-label","action":{"event":{"name":"service.immich_details"}}},{"id":"immich-action-label","component":"Text","text":"Immich details"},{"id":"nvr","component":"StatusBadge","label":"NVR","state":"warning","detail":"Storage 86% · checked 18:04 UTC"},{"id":"nvr-action","component":"Button","child":"nvr-action-label","action":{"event":{"name":"service.nvr_storage_details"}}},{"id":"nvr-action-label","component":"Text","text":"Storage details"}]}}
```

Only use values supported by checks performed for that answer. The values above illustrate layout; they are not default service facts.

## Example: choice and action panel

```a2ui
{"version":"v0.9","createSurface":{"surfaceId":"connection-choice-01","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"connection-choice-01","components":[{"id":"root","component":"Card","child":"content"},{"id":"content","component":"Column","children":["title","question","wifi","ethernet"]},{"id":"title","component":"Text","text":"Choose a connection","variant":"h4"},{"id":"question","component":"Text","text":"Which connection should I inspect?"},{"id":"wifi","component":"Button","child":"wifi-label","action":{"event":{"name":"network.inspect_wifi"}}},{"id":"wifi-label","component":"Text","text":"Wi-Fi"},{"id":"ethernet","component":"Button","child":"ethernet-label","action":{"event":{"name":"network.inspect_ethernet"}}},{"id":"ethernet-label","component":"Text","text":"Ethernet"}]}}
```

Use one distinct, descriptive event per choice. A button asks Hermes to continue the conversation; it does not imply that Conduit launches or changes the selected service.

## Example: metric, observed trend, and drill-down

```a2ui
{"version":"v0.9","createSurface":{"surfaceId":"storage-trend-01","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"storage-trend-01","components":[{"id":"root","component":"Card","child":"content"},{"id":"content","component":"Column","children":["title","metric","trend","details"]},{"id":"title","component":"Text","text":"Storage","variant":"h4"},{"id":"metric","component":"MetricTile","label":"Used","value":86,"unit":"%","min":0,"max":100,"state":"warning","asOf":"2026-09-24T18:04:00Z","source":"Filesystem check"},{"id":"trend","component":"MiniChart","label":"Daily use","kind":"line","unit":"%","points":[{"label":"Sep 22","value":80},{"label":"Sep 23","value":83},{"label":"Sep 24","value":86}],"asOf":"2026-09-24T18:04:00Z","source":"Daily filesystem samples"},{"id":"details","component":"Button","child":"details-label","action":{"event":{"name":"storage.filesystem_details"}}},{"id":"details-label","component":"Text","text":"Filesystem details"}]}}
```

Use real ordered samples only. The example's values are illustrative and must not be presented as current measurements without performing the check.

## Actions

Use a short, unique action name and only the context needed to understand the user's selection. A tap is a request for Hermes to answer in the same chat, not a promise to launch or alter a service. Do not produce several action payloads for one tap. After the action, respond normally and provide another complete surface only when it helps.

## Before sending

- The fence is closed; every line is valid JSON; every message uses v0.9, the same surface ID, and the exact catalog ID.
- The component graph has unique IDs, one `root`, and valid references.
- The surface is the main presentation and surrounding prose does not duplicate it.
- Live state has truthful evidence and freshness; unknown data is marked unknown.
- Every row fits a phone. Prefer stacked service/action layouts.
- Charts use two or more actual samples; absent and single-sample data do not become an invented trend.
- No A2UI component contains a remote asset URL or executable code.
- Ran `python3 /opt/data/scripts/a2ui_check.py --from-md <file>` (or on the JSONL payload) — prints OK for every payload with zero errors.
