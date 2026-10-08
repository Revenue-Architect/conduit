# Suggested Hermez A2UI catalog additions

Reviewed 2026-10-08 against the current Flutter catalog and official A2UI documentation.

Current app already has the no-asset Basic Catalog plus StatusBadge, MetricTile, MiniChart, InfoRow, StepRail, ActionCallout, ArtifactTile, BotBadge, ExpandableSection, ProgressMeter, ActivityFeed, ScheduleTile, MessagePreview, CommandBlock, TaskTile, KeyValueGrid and ComparisonCard. Image/audio/video are intentionally excluded from the generic catalog; Hermes attachments use authenticated app downloads.

These native component groups are implemented in the app's existing catalog:

| Priority | Addition | Value over existing components |
| --- | --- | --- |
| 1 | Document evidence: CitationCard / SourceExcerpt | Source document, page, excerpt and explicit provenance together. Useful for Paperless inspection reports, prescriptions and policy documents. Existing ArtifactTile identifies a file but does not expose cited passage/page semantics. |
| 2 | Responsive DataTable | Multiple records with shared columns; stack rows into readable records on narrow screens. Useful for bills, expenses, commitments, comparison reports. KeyValueGrid is facts about one object, and ComparisonCard is one option. |
| 3 | DraftReview / ChangeDiff | Full draft plus recipient/subject and visible proposed changes. Useful for follow-up emails and reviewing edits. These widgets are previews; opening them never sends or approves. MessagePreview is intentionally only a short excerpt. |
| 4 | MultiSeriesChart | Compare observed series on common axes with units, labels and legend. Existing MiniChart supports one line/bar series. Useful for speed tests, usage and spending. |
| 5 | Agenda / CalendarGrid | Bounded date selection and supplied event details with timezone. Existing ScheduleTile shows a single item. Useful for commitments and calendar planning; this is not a full calendar scheduler. |

All additions reuse the current Flutter/GenUI catalog and authenticated file path. No new servers or transports were added. Schemas, mobile instructions, validator and tests were updated together; arbitrary catalog URLs cannot install Flutter widgets.

Official references:
- https://a2ui.org/concepts/components/ — Basic Catalog and application-defined catalogs.
- https://a2ui.org/guides/authoring-components/ — custom component authoring.

Implementation status: all 15 component types are installed in build 152 with shared Hermez surfaces, typography, outlines and motion. DataTable includes local Records and Compare columns views; CitationCard, DataTable and DraftReview optionally embed an explicit conversational Button via actionChild. Installation and live verification are recorded in HERMEZ_AGENT_HANDOFF.md. Native testing caught a missing Material ancestor in build 150; build 151 corrected it and build 152 uses the existing Material-backed Hermez surface.

## Additional exploratory components

Implemented custom widgets; no extra external catalogs installed:

- DecisionTree: locally explore supplied options/trade-offs and reset choices; selection sends no decision.
- ScenarioSlider: recompute supplied numeric scenarios from a small allowlisted formula model; never execute arbitrary agent code.
- RelationshipMap: bounded nodes/edges with cited links between people, projects, documents and commitments. Native text detail view for small screens.
- RoomMap: show supplied normalized room geometry with local findings, plus an optional authenticated reference image; never invent geometry or room placement. Image-derived placement and automatic image overlays are not implemented.
- BeforeAfterViewer: compare two explicitly supplied authenticated attachments using the existing attachment pipeline.
- JourneyMap: interactive trip/day stages, location notes and costs, with existing schedule tiles as the baseline.
- EvidenceTrail: expand the chain from source excerpt to extracted fact to recommendation. Mark unknowns clearly.

Best distinctive starting points: DecisionTree and RoomMap, followed by ScenarioSlider for a concrete budgeting use case.
