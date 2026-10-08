# Hermez A2UI catalog extension implementation contract

Order: complete and install the InfoRow recovery APK first; then implement the additional widgets and install the next APK in place. Preserve package ID, signing key, connection preferences, credentials and server data.

Extend the existing native Flutter/GenUI catalog. All components are bounded data displays. Local expansion, selection and scenario controls never send a Hermes turn. Explicit existing Button actions retain current consent/approval behavior. No new backend, queue, transport, external image fetch or credential authority.

Components requested across the recommendation groups:
1. CitationCard: source title, page/location, excerpt, optional finding; explicit provenance.
2. SourceExcerpt: cited passage with source and location.
3. DataTable: bounded columns and rows; readable stacked records on narrow screens.
4. DraftReview: recipient/subject/body preview; no automatic send.
5. ChangeDiff: before/after text with added/removed lines; no automatic apply.
6. MultiSeriesChart: bounded observed numeric series, shared scale, legend, units.
7. Agenda: bounded dated events with timezone; local date selection.
8. CalendarGrid: supplied events arranged in a bounded week; no inferred appointments.
9. DecisionTree: bounded explicit nodes/options, local branch selection and reset.
10. ScenarioSlider: deterministic allowlisted numeric calculation with explicit assumptions, bounded input and result; no arbitrary code execution.
11. RelationshipMap: explicit nodes/edges, deterministic layout, locally selectable node evidence.
12. RoomMap: supplied bounded room geometry with labeled findings; locally selectable room details. Do not invent floor-plan dimensions.
13. BeforeAfterViewer: supplied before/after text, local comparison control. Authenticated media reuse only if the existing artifact pipeline supplies the media; never load arbitrary URLs.
14. JourneyMap: supplied itinerary/stages with times, places and costs; expandable stage details.
15. EvidenceTrail: supplied source -> fact -> interpretation links with provenance and uncertainty; expandable evidence.

Tests: valid rendering for each component, invalid/oversized data rejection, narrow screens and large text, local interactions cause no turn, explicit buttons retain existing dispatch behavior, no I/O from pure catalog builders. Use complete representative payloads through the actual normalizer and GenUI renderer. Install and inspect the final APK without clearing storage. Update generation instructions and validator consistently before advertising availability.

Existing catalog remains available; recommendations are additive. No Stremio/TorBox changes, no unrelated server services or model/auth changes.
