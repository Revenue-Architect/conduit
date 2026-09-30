# A2UI v0.9 component guide (Conduit) — exact props

Source of truth: `catalog-v0_9-basic.json` and `common-types-v0_9.json` in this folder (fetched from a2ui.org, spec v0.9). Structural rules below are encoded in `/opt/data/scripts/a2ui_check.py` — run it after writing a surface.

## Message envelope

- Line 1: `{"version":"v0.9","createSurface":{"surfaceId":"<unique-id>","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}`
- Line 2: `{"version":"v0.9","updateComponents":{"surfaceId":"<same-id>","components":[...]}}`
- One object per line, complete JSON, inside a fenced `a2ui` block. Exactly one component with id `root`.
- Build a tree, not a flat list. A Button label is referenced by the Button's `child` and is **not** also a sibling in the surrounding `children` array. Likewise, a Card child or tab panel is not repeated at the parent level. Duplicate parentage makes text render twice and confuses layout.

## Components (exact props)

| Component | Required | Optional | Notes |
|---|---|---|---|
| Text | text | variant: h1 h2 h3 h4 h5 caption body | Keep short; no paragraphs in cards |
| Icon | name | | Enum list below |
| Image | url | fit, variant, description | NOT for Hermes-delivered images — use `MEDIA:` instead |
| Divider | — | axis: horizontal vertical | |
| Card | child | | Single child id; wrap multiples in a Column |
| Column | children | justify: start center end spaceBetween spaceAround spaceEvenly stretch; align | `weight` allowed on direct children only |
| Row | children | justify; align | Every direct width-consuming child needs a positive integer `weight`; use a Column for long text or cramped controls. |
| List | children | direction: vertical horizontal; align | |
| Tabs | tabs: [{"label","content"}] | activeTab | Pinned GenUI 0.10.3 uses label + content component id; Conduit repairs older title + child payloads at read time |
| Modal | trigger, content | | Both are component ids; trigger is usually a Button |
| Button | child, action | variant: default primary borderless | In this client, use only `{"event":{"name":"...","context":{...}}}`; no function calls |
| TextField | label | value, variant: shortText longText number obscured, validationRegexp | |
| CheckBox | label, value (bool) | | |
| ChoicePicker | options: [{"label","value"}], value: [strings] | variant: mutuallyExclusive multipleSelection; displayStyle: checkbox chips; filterable (bool); label | `value` is the array of selected values |
| Slider | value, max | min (default 0), label | |
| DateTimeInput | value (ISO 8601, "" if unset) | enableDate, enableTime, min, max, label | |
| StatusBadge | label, state: ok warning error unknown | detail | Always show a state word next to the icon |
| MetricTile | label, value (number) | unit, min, max, state, asOf, source | Only numbers actually observed |
| MiniChart | label, kind: line bar, points: [{"label","value"}] | unit, asOf, source | Only with >= 2 real observations |
| InfoRow | title (≤80) | detail (≤160), meta (≤60), icon, state: ok warning error unknown, compact (bool) | One labelled fact; replaces a table row. State shows as icon + word |
| StepRail | steps: 1–10 × {"label" (≤60), "state"} | per step: detail (≤120), meta (≤40) | step state: done current upcoming warning error |
| ActionCallout | title (≤100) | eyebrow (≤32), detail (≤200), tone: neutral attention success error, icon, actionChild (id) | The one thing needing attention or the next step |
| ArtifactTile | name (≤80), kind: document image spreadsheet audio video file | sizeLabel (≤24), detail (≤120), actionChild (id) | Names a file; never opens or fetches it |
| BotBadge | label (≤40), identity: neutral kai local autopilot fast strong | detail (≤80) | Who owns a workstream |
| ExpandableSection | title (≤60), child (id) | subtitle (≤120), count (0–9999), initiallyExpanded (bool) | Local disclosure; sends no turn |
| ProgressMeter | label (≤80), current (number ≥0), total (number >0) | unit (≤24), detail (≤120), state, segmented (bool) | Real counts only; percent is derived; over-total shown as is |
| ActivityFeed | items: 1–20 × {"title" (≤80)} | per item: detail (≤140), time (≤40), icon, state | Observed events in order; omit unknown times |
| ScheduleTile | title (≤80), start (≤40) | end, date (≤40), location (≤100), detail (≤120), owner (≤60), state, icon | Any timed item |
| MessagePreview | sender (≤80), preview (≤240) | title (≤100), timestamp (≤40), channel: email teams agentmail message unknown, unread (bool), importance: normal important | An excerpt, never the full message |
| CommandBlock | content (≤4000) | label (≤40), language: shell sql json yaml text, copyable (bool) | Never executed; Copy is local |
| TaskTile | title (≤100), status: todo in_progress blocked done unknown | assignee (≤60), due (≤40), priority: low normal high urgent, detail (≤160), countLabel (≤40) | Presentation only |
| KeyValueGrid | items: 1–8 × {"label" (≤40), "value" (≤120)} | title (≤60), compact (bool) | Renderer picks columns or stacking |
| ComparisonCard | title (≤80), facts: 1–8 × {"label" (≤40), "value" (≤100)} | per fact: state; subtitle (≤120), badge (≤40), detail (≤160) | Facts only; stack 2+ in a Column |

## Structure components (Conduit)

Data-only components rendered natively by Conduit. They make no network or file access, take no URLs or file tokens, and reject unknown props: an invalid value shows a small “Visual unavailable” notice (or the whole card is declined) instead of the component. Lengths are character limits.

- **InfoRow** — `{"id":"r1","component":"InfoRow","title":"NVR","detail":"Storage at 91%","meta":"checked 18:04","icon":"storage","state":"warning"}`. `compact: true` tightens vertical padding for lists of 4+ rows. Icon enum: `check warning error info clock calendar person bot file link storage server chart task`. A Column of InfoRows is the default replacement for a Markdown table.
- **StepRail** — `{"id":"plan","component":"StepRail","steps":[{"label":"Build","state":"done"},{"label":"UAT","state":"current","meta":"Nov 18"},{"label":"Launch","state":"upcoming"}]}`. A vertical rail; each state is also written as a word. Use `warning`/`error` for a blocked stage and say why in `detail`.
- **ActionCallout** — `{"id":"next","component":"ActionCallout","eyebrow":"Needs you","title":"Approve the refund?","detail":"Carrier confirmed delivery.","tone":"attention","actionChild":"choices"}`. `actionChild` references a Button, or a Row of 2–3 Buttons with `weight: 1` each. Use at most one per surface.
- **ArtifactTile** — `{"id":"f1","component":"ArtifactTile","name":"launch-brief.md","kind":"document","sizeLabel":"2 KB"}`. Only names and describes. Deliver the real file with `MEDIA:<absolute-path>`; an optional `actionChild` Button asks Hermes about it in chat.
- **BotBadge** — `{"id":"b1","component":"BotBadge","label":"Kai","identity":"kai","detail":"Inventory migration"}`. Pair each badge with the InfoRow(s) describing that bot's work.
- **ExpandableSection** — `{"id":"ev","component":"ExpandableSection","title":"Evidence","subtitle":"6 sources reviewed","count":3,"child":"ev-list"}`. The header shows `TITLE / count`; the child is usually a Column of InfoRows. Opening and closing happen on the phone only and never send `[A2UI_INTERACTION]`, even on a read-only or busy message. A Button inside still sends exactly one turn when tapped. Keep warnings, failures, and limitations outside it.

In a Row, every structure component needs a positive integer `weight`; they are designed for Columns. `ProgressMeter`, `ActivityFeed`, `ScheduleTile`, `MessagePreview`, `CommandBlock`, `TaskTile`, `KeyValueGrid`, and `ComparisonCard` are never Row children at all.

## Visual language

- Cards, callouts, tiles, buttons and bordered containers use a complete perimeter border. Do not render decorative accent strips or colored side edges. Semantic state may affect the entire outline, icon and technical label.
- Vertical lines remain allowed where they encode sequence, connection, hierarchy or progress (StepRail, timelines).
- State is never color alone: every state also has a word or glyph.
- Button variants: `primary` is the filled signal object (one per decision at most), default is an outlined surface object, `borderless` is a bare text action. Destructive intent is expressed by an `ActionCallout` with `tone: "error"` around an ordinary Button, not by inventing props or event names.

## Icons

`accountCircle add arrowBack arrowForward attachFile calendarToday call camera check close delete download edit event error fastForward favorite favoriteOff folder help home info locationOn lock lockOpen mail menu moreVert moreHoriz notificationsOff notifications pause payment person phone photo play print refresh rewind search send settings share shoppingCart skipNext skipPrevious star starHalf starOff stop upload visibility visibilityOff volumeDown volumeMute volumeOff volumeUp warning`

## Dynamic values and checks

- Any string/number/boolean prop may instead be `{"path":"/json/pointer"}` (data binding) or a function call `{"call":"formatNumber","args":{...}}`. Hermes surfaces use literals; keep it simple.
- Interactive components optionally accept `checks`: `[{"condition": <DynamicBoolean>, "message": "..."}]` (client-side validation). Omit unless a form needs it.
- Functions available to bindings: required, regex, length, numeric, email, formatString, formatNumber, formatCurrency, formatDate, pluralize, openUrl, and, or, not.

## Phone rules recap

- ~300 logical px usable width; keep labels short, stack multiple actions, and keep each action target unambiguous. Use `Row` only for genuinely short, comparable values; use `List` or `Tabs` when that better matches the information. Do not force every question into a status card.
