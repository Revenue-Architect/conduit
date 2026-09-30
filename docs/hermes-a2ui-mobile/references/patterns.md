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
{"version":"v0.9","updateComponents":{"surfaceId":"service-tabs-01","components":[{"id":"root","component":"Card","child":"content"},{"id":"content","component":"Column","children":["title","tabs"]},{"id":"title","component":"Text","text":"Hermes","variant":"h4"},{"id":"tabs","component":"Tabs","tabs":[{"label":"Status","content":"status"},{"label":"Details","content":"details"}]},{"id":"status","component":"Column","children":["badge","uptime"]},{"id":"badge","component":"StatusBadge","label":"Gateway","state":"ok","detail":"checked 21:31 UTC"},{"id":"uptime","component":"Text","text":"Up 14h 22m"},{"id":"details","component":"Column","children":["ver","mem"]},{"id":"ver","component":"Text","text":"Version v0.21.1"},{"id":"mem","component":"Text","text":"Memory 1.04 GiB"}]}}
```

Notes: tab titles live inside the Tabs component; a refresh action returns the whole surface again.

## 4. Comparison — two numbers side by side

```a2ui
{"version":"v0.9","createSurface":{"surfaceId":"plan-comparison-01","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"plan-comparison-01","components":[{"id":"root","component":"Card","child":"content"},{"id":"content","component":"Column","children":["title","row","note"]},{"id":"title","component":"Text","text":"Plan comparison","variant":"h4"},{"id":"row","component":"Row","children":["pro","basic"]},{"id":"pro","component":"MetricTile","label":"Pro","value":35,"unit":"CAD/mo","weight":1},{"id":"basic","component":"MetricTile","label":"Basic","value":12,"unit":"CAD/mo","weight":1},{"id":"note","component":"Text","text":"Entered by hand; no live pricing checked.","variant":"caption"}]}}
```

Notes: give every direct width-consuming Row child a positive integer weight. `weight: 1` on both direct MetricTile children keeps short comparable values side by side; use a Column when values/labels are long or controls would be cramped. Conduit repairs existing saved messages at render time, but new output should already follow this rule.

## 5. Compact two-metric overview — synthetic values

These are illustrative layout values only, not live measurements. Overview dashboards follow the same finite-width rule as comparison cards.

```a2ui
{"version":"v0.9","createSurface":{"surfaceId":"synthetic-overview-01","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"synthetic-overview-01","components":[{"id":"root","component":"Card","child":"content"},{"id":"content","component":"Column","children":["title","metrics","note"]},{"id":"title","component":"Text","text":"System overview","variant":"h4"},{"id":"metrics","component":"Row","children":["cpu","memory"]},{"id":"cpu","component":"MetricTile","label":"CPU use","value":38,"unit":"%","min":0,"max":100,"source":"Synthetic sample","weight":1},{"id":"memory","component":"MetricTile","label":"Memory used","value":6.4,"unit":"GiB","weight":1},{"id":"note","component":"Text","text":"Illustrative values only; not a live check.","variant":"caption"}]}}
```

Both direct MetricTile children have positive weights so the ranged CPU indicator receives finite width. Use a Column instead if actual labels or values are long.

## 6. Multi-select picker — choose several options

```a2ui
{"version":"v0.9","createSurface":{"surfaceId":"alert-topics-01","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"alert-topics-01","components":[{"id":"root","component":"Card","child":"content"},{"id":"content","component":"Column","children":["title","picker","save"]},{"id":"title","component":"Text","text":"Alert topics","variant":"h4"},{"id":"picker","component":"ChoicePicker","label":"Notify me about","variant":"multipleSelection","displayStyle":"chips","options":[{"label":"Backups","value":"backups"},{"label":"Storage","value":"storage"},{"label":"Meetings","value":"meetings"}],"value":[]},{"id":"save","component":"Button","child":"save-label","action":{"event":{"name":"alerts.set_topics"}}},{"id":"save-label","component":"Text","text":"Save topics"}]}}
```

Notes: `value` starts as the currently selected option values (often `[]`). `variant: "mutuallyExclusive"` (default) makes it single-choice; `displayStyle: "checkbox"` (default) shows checkboxes instead of chips.

## Structure patterns

These use Conduit's structure components (see `component-guide.md`). Values are illustrative; show only what was actually checked or done this turn.

## 7. Service status — rows, not a table

```a2ui
{"version":"v0.9","createSurface":{"surfaceId":"service-status-01","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"service-status-01","components":[{"id":"root","component":"Card","child":"body"},{"id":"body","component":"Column","children":["h","s1","s2","s3","details"]},{"id":"h","component":"Text","text":"Services · checked 18:04","variant":"h5"},{"id":"s1","component":"InfoRow","title":"Hermes","detail":"Gateway connected","state":"ok","icon":"server","compact":true},{"id":"s2","component":"InfoRow","title":"Immich","detail":"API responded","state":"ok","icon":"server","compact":true},{"id":"s3","component":"InfoRow","title":"NVR","detail":"Storage at 91%","state":"warning","icon":"storage","compact":true},{"id":"details","component":"ExpandableSection","title":"Checks run","count":2,"child":"checks"},{"id":"checks","component":"Column","children":["c1","c2"]},{"id":"c1","component":"InfoRow","title":"Container list","detail":"All 3 running"},{"id":"c2","component":"InfoRow","title":"NVR volume","detail":"1.8 of 2.0 TB used"}]}}
```

Surrounding prose: one sentence at most, such as “Only the NVR needs attention.”

## 8. Multi-agent workstreams

```a2ui
{"version":"v0.9","createSurface":{"surfaceId":"workstreams-01","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"workstreams-01","components":[{"id":"root","component":"Card","child":"body"},{"id":"body","component":"Column","children":["b1","r1","b2","r2","next"]},{"id":"b1","component":"BotBadge","label":"Kai","identity":"kai","detail":"Inventory migration"},{"id":"r1","component":"InfoRow","title":"Running","detail":"412 of 600 products synced","state":"ok","compact":true},{"id":"b2","component":"BotBadge","label":"Strong","identity":"strong","detail":"Code review"},{"id":"r2","component":"InfoRow","title":"Blocked","detail":"Waiting on API access","state":"error","compact":true},{"id":"next","component":"ActionCallout","eyebrow":"Next","title":"Grant API access to unblock the review","tone":"attention"}]}}
```

One BotBadge per bot that actually worked, each followed by what it did. Use this instead of an `Owner | Status` table.

## 9. Project timeline

```a2ui
{"version":"v0.9","createSurface":{"surfaceId":"project-timeline-01","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"project-timeline-01","components":[{"id":"root","component":"StepRail","steps":[{"label":"Discovery","state":"done"},{"label":"Implementation","state":"done"},{"label":"Validation","state":"current","detail":"One item left"},{"label":"Release","state":"upcoming","meta":"Nov 23"}]}]}}
```

Mark `done` only for stages that are actually complete.

## 10. Decision needed

```a2ui
{"version":"v0.9","createSurface":{"surfaceId":"decision-01","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"decision-01","components":[{"id":"root","component":"ActionCallout","eyebrow":"Needs you","title":"Approve the refund for order 1042?","detail":"Both items returned; carrier confirmed delivery.","tone":"attention","icon":"task","actionChild":"choices"},{"id":"choices","component":"Row","children":["approve","hold"]},{"id":"approve","component":"Button","child":"approve-label","action":{"event":{"name":"refund.approve","context":{"order":"1042"}}},"weight":1},{"id":"approve-label","component":"Text","text":"Approve"},{"id":"hold","component":"Button","child":"hold-label","action":{"event":{"name":"refund.hold","context":{"order":"1042"}}},"weight":1},{"id":"hold-label","component":"Text","text":"Hold"}]}}
```

Each choice is one Button with its own event and `weight: 1`. A tap sends one turn and changes nothing by itself.

## 11. Artifact summary

```a2ui
{"version":"v0.9","createSurface":{"surfaceId":"artifacts-01","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"artifacts-01","components":[{"id":"root","component":"Column","children":["a1","a2"]},{"id":"a1","component":"ArtifactTile","name":"launch-brief.md","kind":"document","sizeLabel":"2 KB","detail":"Final copy for review"},{"id":"a2","component":"ArtifactTile","name":"inventory-map.csv","kind":"spreadsheet","sizeLabel":"48 KB"}]}}
```

Tiles name the files; deliver the files themselves with `MEDIA:` lines outside the fence.

## 12. Visual executive summary

```a2ui
{"version":"v0.9","createSurface":{"surfaceId":"exec-summary-01","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"exec-summary-01","components":[{"id":"root","component":"Card","child":"body"},{"id":"body","component":"Column","children":["h","metrics","rail","risks","next"]},{"id":"h","component":"Text","text":"Q4 launch","variant":"h4"},{"id":"metrics","component":"Row","children":["m1","m2"]},{"id":"m1","component":"MetricTile","label":"Tasks done","value":18,"unit":"of 24","weight":1},{"id":"m2","component":"MetricTile","label":"Open risks","value":2,"state":"warning","weight":1},{"id":"rail","component":"StepRail","steps":[{"label":"Build","state":"done"},{"label":"UAT","state":"current","meta":"Nov 18"},{"label":"Launch","state":"upcoming","meta":"Nov 23"}]},{"id":"risks","component":"ExpandableSection","title":"Risks","count":2,"child":"risk-list"},{"id":"risk-list","component":"Column","children":["k1","k2"]},{"id":"k1","component":"InfoRow","title":"Payment provider","detail":"Sandbox approval pending","state":"warning"},{"id":"k2","component":"InfoRow","title":"Copy review","detail":"Legal sign-off due Nov 16","state":"unknown"},{"id":"next","component":"ActionCallout","eyebrow":"Next","title":"Chase the payment provider approval","tone":"neutral"}]}}
```

Numbers, where it stands, what could go wrong (one tap away), and the next step, in one surface.

## 13. Expandable evidence

```a2ui
{"version":"v0.9","createSurface":{"surfaceId":"evidence-01","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"evidence-01","components":[{"id":"root","component":"Column","children":["answer","evidence","question"]},{"id":"answer","component":"StatusBadge","label":"Option A","state":"ok","detail":"Best supported by evidence"},{"id":"evidence","component":"ExpandableSection","title":"Evidence","subtitle":"6 sources reviewed","count":3,"child":"ev"},{"id":"ev","component":"Column","children":["e1","e2","e3"]},{"id":"e1","component":"InfoRow","title":"Vendor benchmark","detail":"A is 2x faster on the sample workload","icon":"chart"},{"id":"e2","component":"InfoRow","title":"Pricing page","detail":"A costs 15% less at our volume","icon":"link"},{"id":"e3","component":"InfoRow","title":"Support thread","detail":"B deprecates an API we need","icon":"info"},{"id":"question","component":"ActionCallout","eyebrow":"Open question","title":"Confirm API availability for option A","tone":"attention"}]}}
```

The conclusion and the open question stay visible; supporting evidence sits one tap away.

## 14. Plan with next action

```a2ui
{"version":"v0.9","createSurface":{"surfaceId":"plan-01","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"plan-01","components":[{"id":"root","component":"Column","children":["plan","next"]},{"id":"plan","component":"StepRail","steps":[{"label":"Back up the database","state":"upcoming"},{"label":"Apply the migration","state":"upcoming"},{"label":"Verify and reopen","state":"upcoming","detail":"Smoke test checkout"}]},{"id":"next","component":"ActionCallout","eyebrow":"Next","title":"Start with the backup","tone":"neutral","actionChild":"go"},{"id":"go","component":"Button","child":"go-label","action":{"event":{"name":"plan.start_backup"}}},{"id":"go-label","component":"Text","text":"Start backup"}]}}
```

A rollout or plan is a StepRail; the single next step is an ActionCallout with one Button.

## Personal and work patterns

These use the personal and work components. Each surface is one Column; none of these objects goes in a Row.

## 15. Progress / migration

```a2ui
{"version":"v0.9","createSurface":{"surfaceId":"migration-01","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"migration-01","components":[{"id":"root","component":"Column","children":["progress","rail"]},{"id":"progress","component":"ProgressMeter","label":"Migration","current":412,"total":600,"unit":"products","detail":"Variants validated as they move"},{"id":"rail","component":"StepRail","steps":[{"label":"Export","state":"done"},{"label":"Import","state":"current","detail":"412 of 600"},{"label":"Verify","state":"upcoming"}]}]}}
```

Real counts only. The percent comes from current and total.

## 16. Recent activity

```a2ui
{"version":"v0.9","createSurface":{"surfaceId":"activity-01","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"activity-01","components":[{"id":"root","component":"Column","children":["feed"]},{"id":"feed","component":"ActivityFeed","items":[{"time":"11:42","title":"Browser opened Shopify"},{"time":"11:43","title":"Inventory export loaded"},{"time":"11:44","title":"412 products validated","state":"ok"},{"time":"11:45","title":"3 records need review","state":"warning"}]}]}}
```

Only events that happened. Leave `time` out when it is not known.

## 17. Daily schedule

```a2ui
{"version":"v0.9","createSurface":{"surfaceId":"day-01","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"day-01","components":[{"id":"root","component":"Column","children":["a","b"]},{"id":"a","component":"ScheduleTile","title":"Dentist","start":"14:30","end":"15:15","location":"Downtown"},{"id":"b","component":"ScheduleTile","title":"Morning brief","start":"09:00","date":"Daily","owner":"Kai","icon":"bot"}]}}
```

One ScheduleTile per timed item, stacked.

## 18. Inbox summary

```a2ui
{"version":"v0.9","createSurface":{"surfaceId":"inbox-01","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"inbox-01","components":[{"id":"root","component":"Column","children":["m1","m2","next"]},{"id":"m1","component":"MessagePreview","channel":"email","sender":"Georgia","title":"Trail Together follow-up","preview":"Just have a few follow-up questions about the rollout.","timestamp":"10:42 AM","unread":true,"importance":"important"},{"id":"m2","component":"MessagePreview","channel":"teams","sender":"Mahedi","preview":"Replied to your thread about the SOW.","timestamp":"12:59 PM"},{"id":"next","component":"ActionCallout","eyebrow":"Needs you","title":"Reply to Georgia today","tone":"attention"}]}}
```

An excerpt per message, never the full email.

## 19. Task status

```a2ui
{"version":"v0.9","createSurface":{"surfaceId":"tasks-01","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"tasks-01","components":[{"id":"root","component":"Column","children":["t1","t2"]},{"id":"t1","component":"TaskTile","title":"Trail certificates","status":"in_progress","assignee":"Kai","due":"Nov 11","detail":"Generate and email donor certificates"},{"id":"t2","component":"TaskTile","title":"Donor list","status":"blocked","assignee":"Finance","detail":"Waiting on the final export"}]}}
```

Only blocked tasks outline themselves; the rest stay neutral.

## 20. Technical command

```a2ui
{"version":"v0.9","createSurface":{"surfaceId":"command-01","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"command-01","components":[{"id":"root","component":"Column","children":["why","cmd"]},{"id":"why","component":"InfoRow","title":"NVR stopped recording","detail":"The container exited after the disk filled","state":"error"},{"id":"cmd","component":"CommandBlock","label":"Command","language":"shell","content":"docker compose restart nvr"}]}}
```

Never executed. Copy is local and sends nothing to Hermes.

## 21. Metadata / details

```a2ui
{"version":"v0.9","createSurface":{"surfaceId":"server-01","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"server-01","components":[{"id":"root","component":"Column","children":["state","facts"]},{"id":"state","component":"StatusBadge","label":"Local model","state":"ok"},{"id":"facts","component":"KeyValueGrid","title":"Server","items":[{"label":"Model","value":"Qwen 27B"},{"label":"Profile","value":"Local"},{"label":"Uptime","value":"14h 22m"}]}]}}
```

Facts about one object. Conduit decides columns or stacking.

## 22. Comparison

```a2ui
{"version":"v0.9","createSurface":{"surfaceId":"compare-01","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"compare-01","components":[{"id":"root","component":"Column","children":["a","b"]},{"id":"a","component":"ComparisonCard","title":"Option A","badge":"Local","facts":[{"label":"Cost","value":"$12 / month"},{"label":"Runs locally","value":"Yes","state":"ok"},{"label":"Memory","value":"17 GB"}]},{"id":"b","component":"ComparisonCard","title":"Option B","badge":"Hosted","facts":[{"label":"Cost","value":"$20 / month"},{"label":"Runs locally","value":"No","state":"warning"},{"label":"Memory","value":"—"}]}]}}
```

Facts only, one card per option, stacked. No winner or score.

## 23. Agent run summary

```a2ui
{"version":"v0.9","createSurface":{"surfaceId":"run-01","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"run-01","components":[{"id":"root","component":"Column","children":["bot","progress","feed","details"]},{"id":"bot","component":"BotBadge","label":"Kai","identity":"kai","detail":"Inventory migration"},{"id":"progress","component":"ProgressMeter","label":"Products","current":412,"total":600,"segmented":true},{"id":"feed","component":"ActivityFeed","compact":true,"items":[{"title":"Exported inventory","state":"ok"},{"title":"Validating variants"}]},{"id":"details","component":"ExpandableSection","title":"Details","child":"notes"},{"id":"notes","component":"InfoRow","title":"3 SKUs skipped","detail":"Missing barcodes","state":"warning"}]}}
```

Who, how far, what happened, and the rest one tap away.

## 24. Personal morning brief

```a2ui
{"version":"v0.9","createSurface":{"surfaceId":"brief-01","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"brief-01","components":[{"id":"root","component":"Column","children":["s1","m1","t1"]},{"id":"s1","component":"ScheduleTile","title":"Shopify & Ironman demo","start":"12:00","end":"13:00"},{"id":"m1","component":"MessagePreview","channel":"agentmail","sender":"Jarvis","preview":"Quick one: Mahedi asked about timing in the Kaizen thread.","unread":true},{"id":"t1","component":"TaskTile","title":"Send the SOW revision","status":"todo","due":"Today","priority":"high"}]}}
```

One sentence before the surface at most.
