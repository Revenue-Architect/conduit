# Extended native components (build 152+)

Put rich objects in a Column, never a Row. Each object requires title (1–120 chars). Controls are local only. Existing Button actions remain separate and require ordinary consent. No arbitrary URL fields are accepted. Optional BeforeAfterViewer beforeMedia + afterMedia and RoomMap backgroundMedia must exactly match image MEDIA directives supplied outside the A2UI fence in this same message. Those previews reuse authenticated downloads; undeclared paths display an unavailable notice and never fetch. The room reference image and geometry diagram are separate.

These fixtures are complete valid examples. Field names and bounds are exact; do not abbreviate them.

Hermez styling is renderer-owned: shared surfaces, type, full outlines and spring compartments. CitationCard, DataTable and DraftReview accept an optional `actionChild` (existing Button/Column component ID, 1–128 chars). This explicitly starts a normal Hermes reply; it never automatically sends or approves a draft. Buttons stay locked on busy/read-only surfaces. Local table/date/branch/slider choices are presentation only and are not sent as action context. Use existing form bindings or distinct Buttons when Hermes needs a selection. See `review-response-demo.md` for a complete example.

## CitationCard

Required: title, source, location, excerpt.

```a2ui
{"version": "v0.9", "createSurface": {"surfaceId": "extension-CitationCard", "catalogId": "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version": "v0.9", "updateComponents": {"surfaceId": "extension-CitationCard", "components": [{"id": "root", "component": "CitationCard", "title": "CitationCard", "source": "Inspection report", "location": "Page 8", "excerpt": "Observed staining.", "finding": "Ask an inspector about the source."}]}}
```

## SourceExcerpt

Required: title, source, location, excerpt.

```a2ui
{"version": "v0.9", "createSurface": {"surfaceId": "extension-SourceExcerpt", "catalogId": "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version": "v0.9", "updateComponents": {"surfaceId": "extension-SourceExcerpt", "components": [{"id": "root", "component": "SourceExcerpt", "title": "SourceExcerpt", "source": "Inspection report", "location": "Page 8", "excerpt": "Observed staining."}]}}
```

## DataTable

Required: title, columns, rows.

All cells remain selectable and untruncated. Records is the mobile-friendly stacked view; Compare columns opens a horizontally scrollable table with shared column headers. Both controls are local.

```a2ui
{"version": "v0.9", "createSurface": {"surfaceId": "extension-DataTable", "catalogId": "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version": "v0.9", "updateComponents": {"surfaceId": "extension-DataTable", "components": [{"id": "root", "component": "DataTable", "title": "DataTable", "columns": ["Item", "Cost"], "rows": [["Option A", "$10"], ["Option B", "$20"]]}]}}
```

## DraftReview

Required: title, recipient, subject, body.

Displays separate To, Subject and Message fields with a DRAFT / NOT SENT label. An optional `actionChild` can request an edit or review in chat; sending still requires explicit consent and the normal Hermes tool path.

```a2ui
{"version": "v0.9", "createSurface": {"surfaceId": "extension-DraftReview", "catalogId": "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version": "v0.9", "updateComponents": {"surfaceId": "extension-DraftReview", "components": [{"id": "root", "component": "DraftReview", "title": "DraftReview", "recipient": "client@example.test", "subject": "Checking in", "body": "Hello, would you like to discuss the proposal?"}]}}
```

## ChangeDiff

Required: title, before, after.

```a2ui
{"version": "v0.9", "createSurface": {"surfaceId": "extension-ChangeDiff", "catalogId": "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version": "v0.9", "updateComponents": {"surfaceId": "extension-ChangeDiff", "components": [{"id": "root", "component": "ChangeDiff", "title": "ChangeDiff", "before": "Listen on LAN\nKeep logs", "after": "Listen locally\nKeep logs"}]}}
```

## BeforeAfterViewer

Required: title, before, after.

```a2ui
{"version": "v0.9", "createSurface": {"surfaceId": "extension-BeforeAfterViewer", "catalogId": "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version": "v0.9", "updateComponents": {"surfaceId": "extension-BeforeAfterViewer", "components": [{"id": "root", "component": "BeforeAfterViewer", "title": "BeforeAfterViewer", "before": "Original description", "after": "Revised description"}]}}
```

## MultiSeriesChart

Required: title, labels, unit, series.

```a2ui
{"version": "v0.9", "createSurface": {"surfaceId": "extension-MultiSeriesChart", "catalogId": "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version": "v0.9", "updateComponents": {"surfaceId": "extension-MultiSeriesChart", "components": [{"id": "root", "component": "MultiSeriesChart", "title": "MultiSeriesChart", "labels": ["Mon", "Tue", "Wed"], "unit": "ms", "series": [{"label": "A", "values": [5, 8, 6]}, {"label": "B", "values": [8, 4, 9]}]}]}}
```

## Agenda

Required: title, timezone, events.

```a2ui
{"version": "v0.9", "createSurface": {"surfaceId": "extension-Agenda", "catalogId": "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version": "v0.9", "updateComponents": {"surfaceId": "extension-Agenda", "components": [{"id": "root", "component": "Agenda", "title": "Agenda", "timezone": "America/Toronto", "events": [{"date": "2026-10-08", "time": "09:00", "label": "Planning", "detail": "Review supplied tasks."}, {"date": "2026-10-09", "time": "10:00", "label": "Review", "detail": "Discuss findings."}]}]}}
```

## CalendarGrid

Required: title, timezone, events.

```a2ui
{"version": "v0.9", "createSurface": {"surfaceId": "extension-CalendarGrid", "catalogId": "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version": "v0.9", "updateComponents": {"surfaceId": "extension-CalendarGrid", "components": [{"id": "root", "component": "CalendarGrid", "title": "CalendarGrid", "timezone": "America/Toronto", "events": [{"date": "2026-10-08", "time": "09:00", "label": "Planning", "detail": "Review supplied tasks."}, {"date": "2026-10-09", "time": "10:00", "label": "Review", "detail": "Discuss findings."}]}]}}
```

## DecisionTree

Required: title, start, nodes.

```a2ui
{"version": "v0.9", "createSurface": {"surfaceId": "extension-DecisionTree", "catalogId": "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version": "v0.9", "updateComponents": {"surfaceId": "extension-DecisionTree", "components": [{"id": "root", "component": "DecisionTree", "title": "DecisionTree", "start": "a", "nodes": [{"id": "a", "label": "Choose a route", "detail": "Two supplied choices.", "options": [{"label": "Explore", "target": "b"}]}, {"id": "b", "label": "Selected route", "detail": "This is a local choice only.", "options": []}]}]}}
```

## ScenarioSlider

Required: title, inputLabel, unit, min, max, value, multiplier, offset, assumptions.

```a2ui
{"version": "v0.9", "createSurface": {"surfaceId": "extension-ScenarioSlider", "catalogId": "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version": "v0.9", "updateComponents": {"surfaceId": "extension-ScenarioSlider", "components": [{"id": "root", "component": "ScenarioSlider", "title": "ScenarioSlider", "inputLabel": "Hours", "unit": "USD", "min": 0, "max": 10, "value": 2, "multiplier": 20, "offset": 5, "assumptions": "Estimate = hours \u00d7 $20 + $5. No taxes included."}]}}
```

## RelationshipMap

Required: title, nodes, edges.

```a2ui
{"version": "v0.9", "createSurface": {"surfaceId": "extension-RelationshipMap", "catalogId": "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version": "v0.9", "updateComponents": {"surfaceId": "extension-RelationshipMap", "components": [{"id": "root", "component": "RelationshipMap", "title": "RelationshipMap", "nodes": [{"id": "a", "label": "Project", "detail": "Provided project context"}, {"id": "b", "label": "Client", "detail": "Provided client context"}], "edges": [{"source": "a", "target": "b", "label": "owned by"}]}]}}
```

## RoomMap

Required: title, rooms, provenance.

```a2ui
{"version": "v0.9", "createSurface": {"surfaceId": "extension-RoomMap", "catalogId": "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version": "v0.9", "updateComponents": {"surfaceId": "extension-RoomMap", "components": [{"id": "root", "component": "RoomMap", "title": "RoomMap", "provenance": "Illustrative supplied geometry, not a measured floor plan.", "rooms": [{"id": "a", "label": "Kitchen", "detail": "Review the supplied finding.", "x": 0, "y": 0, "width": 0.5, "height": 1}, {"id": "b", "label": "Office", "detail": "No further finding supplied.", "x": 0.5, "y": 0, "width": 0.5, "height": 1}]}]}}
```

## JourneyMap

Required: title, stages.

```a2ui
{"version": "v0.9", "createSurface": {"surfaceId": "extension-JourneyMap", "catalogId": "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version": "v0.9", "updateComponents": {"surfaceId": "extension-JourneyMap", "components": [{"id": "root", "component": "JourneyMap", "title": "JourneyMap", "stages": [{"label": "Arrival", "time": "09:00", "place": "Station", "cost": "$5", "detail": "Walk to the meeting."}]}]}}
```

## EvidenceTrail

Required: title, items.

```a2ui
{"version": "v0.9", "createSurface": {"surfaceId": "extension-EvidenceTrail", "catalogId": "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version": "v0.9", "updateComponents": {"surfaceId": "extension-EvidenceTrail", "components": [{"id": "root", "component": "EvidenceTrail", "title": "EvidenceTrail", "items": [{"source": "Inspection report", "location": "Page 8", "fact": "Observed staining.", "interpretation": "Cause needs inspection.", "uncertainty": "Source not established."}]}]}}
```

ScenarioSlider uses result = input × multiplier + offset only. It is an estimate and requires explicit assumptions. CalendarGrid accepts a supplied seven-day window, not a whole unbounded month. RoomMap uses provided normalized geometry (x/y/width/height in 0..1); never infer a real floor plan. ChangeDiff is a line comparison, not an applicable patch. RelationshipMap edge arrows are specified by the supplied source/target and displayed in the textual edge list. All source/fact/interpretation data must come from available evidence.

Machine-readable bounds: `extension-schemas.json`.

## Authenticated image comparison

Optional BeforeAfterViewer fields: `beforeMedia` and `afterMedia` (both together, each ≤1000 chars). Optional RoomMap field: `backgroundMedia` (≤1000 chars). Use exact paths of actual image artifacts and include their MEDIA directives outside the A2UI fence in the same reply. The app never fetches an undeclared path. `before` and `after` still contain supplied captions or text. A room reference image is displayed separately from supplied normalized geometry; do not imply inferred measurements or an automatic overlay.

Example only; substitute files that actually exist:

MEDIA:/opt/data/artifacts/before.png
MEDIA:/opt/data/artifacts/after.png

```a2ui
{"version":"v0.9","createSurface":{"surfaceId":"image-comparison","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"image-comparison","components":[{"id":"root","component":"BeforeAfterViewer","title":"Image comparison","before":"Supplied original image","after":"Supplied revised image","beforeMedia":"/opt/data/artifacts/before.png","afterMedia":"/opt/data/artifacts/after.png"}]}}
```
