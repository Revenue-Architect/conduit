# A2UI composition examples

Complete JSONL for fenced `a2ui` blocks. Adapt these structures to the user's domain and requested interaction; do not copy the sample's values, controls, or event names by default. Every example below passes `python3 /opt/data/scripts/a2ui_check.py --from-md` on this file. Values are illustrative — only present measurements, freshness, and counts actually verified this turn. A tap is a follow-up chat turn; it never implies Conduit changes anything by itself.

## 1. Form card — capture values

```a2ui
{"version":"v0.9","createSurface":{"surfaceId":"daily-log-form-01","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"daily-log-form-01","components":[{"id":"root","component":"Card","child":"content"},{"id":"content","component":"Column","children":["title","weight","sleep","workout","save"]},{"id":"title","component":"Text","text":"Daily log","variant":"h4"},{"id":"weight","component":"TextField","label":"Weight (kg)","variant":"number"},{"id":"sleep","component":"Slider","label":"Sleep (hours)","value":7,"max":12},{"id":"workout","component":"CheckBox","label":"Workout done","value":false},{"id":"save","component":"Button","child":"save-label","action":{"event":{"name":"log.save_entry"}}},{"id":"save-label","component":"Text","text":"Save entry"}]}}
```

Notes: inputs return their current values with the event. Include only fields relevant to the user's request; these are not a mandatory form schema. `DateTimeInput` (ISO 8601 `value`, `enableDate`/`enableTime`) works the same way for scheduling asks. An event proposing an external write is not permission to perform it without the user's approval.

## 2. Checklist card — quick confirmations

```a2ui
{"version":"v0.9","createSurface":{"surfaceId":"prep-checklist-01","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"prep-checklist-01","components":[{"id":"root","component":"Card","child":"content"},{"id":"content","component":"Column","children":["title","pack","charge","keys","done"]},{"id":"title","component":"Text","text":"Morning prep","variant":"h4"},{"id":"pack","component":"CheckBox","label":"Bag packed","value":false},{"id":"charge","component":"CheckBox","label":"Phone charged","value":false},{"id":"keys","component":"CheckBox","label":"Keys","value":false},{"id":"done","component":"Button","child":"done-label","action":{"event":{"name":"checklist.confirm","context":{"list":"morning_prep"}}}},{"id":"done-label","component":"Text","text":"Confirm"}]}}
```

## 3. Tabs — group one service by area

```a2ui
{"version":"v0.9","createSurface":{"surfaceId":"service-tabs-01","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"service-tabs-01","components":[{"id":"root","component":"Card","child":"content"},{"id":"content","component":"Column","children":["title","tabs"]},{"id":"title","component":"Text","text":"Hermes","variant":"h4"},{"id":"tabs","component":"Tabs","tabs":[{"title":"Status","child":"status"},{"title":"Details","child":"details"}]},{"id":"status","component":"Column","children":["badge","uptime"]},{"id":"badge","component":"StatusBadge","label":"Gateway","state":"ok","detail":"checked 21:31 UTC"},{"id":"uptime","component":"Text","text":"Up 14h 22m"},{"id":"details","component":"Column","children":["ver","mem"]},{"id":"ver","component":"Text","text":"Version v0.21.1"},{"id":"mem","component":"Text","text":"Memory 1.04 GiB"}]}}
```

Notes: tab titles live inside the Tabs component; a refresh action returns the whole surface again.

## 4. Comparison — two numbers side by side

```a2ui
{"version":"v0.9","createSurface":{"surfaceId":"plan-comparison-01","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"plan-comparison-01","components":[{"id":"root","component":"Card","child":"content"},{"id":"content","component":"Column","children":["title","row","note"]},{"id":"title","component":"Text","text":"Plan comparison","variant":"h4"},{"id":"row","component":"Row","children":["pro","basic"]},{"id":"pro","component":"MetricTile","label":"Pro","value":35,"unit":"CAD/mo","weight":1},{"id":"basic","component":"MetricTile","label":"Basic","value":12,"unit":"CAD/mo","weight":1},{"id":"note","component":"Text","text":"Entered by hand; no live pricing checked.","variant":"caption"}]}}
```

Notes: `weight: 1` on the direct Row children keeps the tiles side by side; without weights Conduit stacks them.

## 5. Multi-select picker — choose several options

```a2ui
{"version":"v0.9","createSurface":{"surfaceId":"alert-topics-01","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"alert-topics-01","components":[{"id":"root","component":"Card","child":"content"},{"id":"content","component":"Column","children":["title","picker","save"]},{"id":"title","component":"Text","text":"Alert topics","variant":"h4"},{"id":"picker","component":"ChoicePicker","label":"Notify me about","variant":"multipleSelection","displayStyle":"chips","options":[{"label":"Backups","value":"backups"},{"label":"Storage","value":"storage"},{"label":"Meetings","value":"meetings"}],"value":[]},{"id":"save","component":"Button","child":"save-label","action":{"event":{"name":"alerts.set_topics"}}},{"id":"save-label","component":"Text","text":"Save topics"}]}}
```

Notes: `value` starts as the currently selected option values (often `[]`). `variant: "mutuallyExclusive"` (default) makes it single-choice; `displayStyle: "checkbox"` (default) shows checkboxes instead of chips.
