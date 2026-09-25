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

## Icons

`accountCircle add arrowBack arrowForward attachFile calendarToday call camera check close delete download edit event error fastForward favorite favoriteOff folder help home info locationOn lock lockOpen mail menu moreVert moreHoriz notificationsOff notifications pause payment person phone photo play print refresh rewind search send settings share shoppingCart skipNext skipPrevious star starHalf starOff stop upload visibility visibilityOff volumeDown volumeMute volumeOff volumeUp warning`

## Dynamic values and checks

- Any string/number/boolean prop may instead be `{"path":"/json/pointer"}` (data binding) or a function call `{"call":"formatNumber","args":{...}}`. Hermes surfaces use literals; keep it simple.
- Interactive components optionally accept `checks`: `[{"condition": <DynamicBoolean>, "message": "..."}]` (client-side validation). Omit unless a form needs it.
- Functions available to bindings: required, regex, length, numeric, email, formatString, formatNumber, formatCurrency, formatDate, pluralize, openUrl, and, or, not.

## Phone rules recap

- ~300 logical px usable width; keep labels short, stack multiple actions, and keep each action target unambiguous. Use `Row` only for genuinely short, comparable values; use `List` or `Tabs` when that better matches the information. Do not force every question into a status card.
