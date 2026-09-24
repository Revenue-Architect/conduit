# Hermes visual-first responses in Conduit

Status: visual-first A2UI implementation delivered; focused automated tests and live S25 dashboard, action, choice, Mermaid, and image paths verified. Broader acceptance remains open; see §12.
Date: 2026-09-24
Target: Conduit fork on `feat/hermes-rich-output`, Hermes 0.21.1, GenUI 0.10.3, A2UI v0.9, Galaxy S25 Ultra

## 1. Problem and desired result

The Hermes-to-Conduit A2UI path works: an explicit `a2ui` fence renders native Flutter components, and a button action returns through the existing Hermes chat. The result is not yet visually useful. The observed status response put long prose inside a card, repeated it around the card, and placed unweighted status text beside buttons in narrow `Row`s. Three rows overflowed; overlapping hit regions made a tap on a visible lower button send a Hermes action instead. A subsequent, vertically stacked card rendered cleanly.

The desired experience is a visual overview first, details on demand. A status answer should show a scannable state, a few meaningful numbers, and obvious actions within the phone's chat width. Charts, diagrams, and images should use the right renderer rather than being reduced to text in a card. The UI must be truthful about data freshness and must remain usable with large text, dark mode, missing data, and authentication expiry.

### Goals

- Make A2UI responses primarily visual and interactive when the request benefits from it.
- Use the existing GenUI basic catalog better before adding new widget types.
- Add a minimal, app-owned visual catalog for status, metrics, and small charts once its schemas and rendering are proven.
- Keep Hermes transport, authentication, session handling, and A2UI v0.9 unchanged.
- Keep images authenticated through Hermes `MEDIA:` and the existing artifact client; never allow arbitrary A2UI URLs to fetch from the device.
- Render old or malformed A2UI safely, without overflow or wrong-button taps.
- Preserve the original assistant content and diagnostic evidence; presentation may collapse it, but must not delete it.

### Non-goals

No A2UI v1.0, A2A/AG-UI server, arbitrary HTML/JavaScript/Dart, free-form generated Flutter widgets, cross-message surface mutation, streaming partial A2UI, new database, gallery, or general chart-design language. This spec does not change non-Hermes providers. Existing Mermaid and Chart.js handling remains unchanged; it is not an excuse to put generated JavaScript inside A2UI.

## 2. Current implementation and constraints

| Concern | Current behavior | Implication |
|---|---|---|
| A2UI parsing | `lib/features/hermes/services/hermes_rich_output_parser.dart` extracts only explicit completed `a2ui` fences. | Keep this boundary; ordinary JSON and Markdown remain ordinary content. |
| Surface | `lib/features/hermes/widgets/hermes_a2ui_surface.dart` passes complete payloads to `A2uiTransportAdapter` and `SurfaceController`. | Extend its catalog and validation, not the Hermes WebSocket transport. |
| Catalog | The wrapper uses `BasicCatalogItems.asNoAssetCatalog()` plus app-owned `StatusBadge`, `MetricTile`, and `MiniChart` items. | Built-in `Image`, `AudioPlayer`, and `Video` remain deliberately unavailable because they can load model-supplied URLs. The new items accept bounded data and perform no I/O. |
| Basic visual vocabulary | GenUI 0.10.3 provides `Card`, `Column`, `Row`, `List`, `Tabs`, `Icon`, `Divider`, text variants, buttons, and form controls. | A much better visual hierarchy is possible without a dependency change. `Icon` has a fixed set of names; `Text` has `h1`–`h5`, `caption`, and `body`. |
| Row layout | GenUI's `Row` uses `MainAxisSize.min`; a child gets flex only with integer `weight` (or catalog-defined implicit flexibility). | Long text and a button in an unweighted row can overflow and overlap hit targets. |
| Images | Hermes `MEDIA:` is rendered through authenticated `/api/fs/download`. | Prefer a separate image artifact alongside A2UI for the first release. |
| Charts and diagrams | Conduit's Markdown stack already has Mermaid and Chart.js renderers. | Preserve these for existing output. New A2UI charts should be native, data-only components rather than generated JS. |
| Interaction | `onSubmit` becomes `[A2UI_INTERACTION]` in the same Hermes session; the user bubble can show a short human label. | Keep this path. Do not add an action endpoint. |

The live `a2ui-mobile` Hermes skill is now v0.2.0. It teaches visual-first answer selection, concise narration, the three registered visual components, evidence/freshness, vertical actions, and compact examples. The skill is the model's design vocabulary; the Flutter catalog and normalizer remain the enforcement boundary.

## 3. Response selection: choose the right visual form

Hermes should select the form based on the user's task, not emit A2UI for every answer:

| User intent | Preferred output |
|---|---|
| Normal question or explanation | Markdown; no decorative card. |
| Architecture, sequence, or dependency graph | Existing Mermaid renderer, optionally followed by a short A2UI action menu. |
| Operational overview, choices, controls, or drill-down | A2UI visual-first surface. |
| Trend or comparison with actual numeric series | Native A2UI `MiniChart`, the existing chart renderer, or an authenticated generated image, as the task requires. Never fabricate a series. |
| Generated photo, screenshot, diagram, report, or plot artifact | `MEDIA:` image/file plus optional A2UI controls or summary. |
| A request explicitly asking for A2UI | A2UI if a valid, useful surface can be made; otherwise explain the limitation plainly. |

Mixed responses are allowed. Example: a one-sentence finding, a Mermaid architecture diagram, then a compact A2UI panel with “Inspect service” actions. Keep every renderer in its existing security boundary.

## 4. Visual answer contract

For a visual-first Hermes answer:

1. Lead with at most one short sentence outside the surface, unless a warning needs immediate explanation. Do not narrate every probe or repeat all card values in prose.
2. Put the most important state above the fold: title, aggregate status, and up to four top-level facts. Show timestamp and freshness. Use an explicit `Unknown` state rather than inferring success from reachability alone.
3. Use short labels and hierarchy: title (`Text` variant `h4`/`h5`), prominent metric, caption, divider, then action. One semantic purpose per card. Avoid paragraph-sized `Text` components.
4. Make drill-down buttons reveal details in the next Hermes turn. Their event names must identify the target unambiguously (`service.hermes_details`, `service.immich_details`); don't reuse a generic `details` event for several controls.
5. Reserve detailed command output, versions, addresses, and probe evidence for a “Details” action or a collapsed “How checked” section outside the card. Do not hide warnings, failures, or caveats.
6. Use no more than one primary surface per answer in the first release; multiple separate cards within it are fine. Keep a self-contained surface per assistant response.
7. For small screens, stack status and action vertically. A horizontal row may contain only short content, and any potentially wrapping child must have `weight: 1`. Do not rely on visual overflow as a way to reveal content.
8. Use status icon **and** word; color alone must not convey state. Use `check`, `warning`, `error`, or `help` from the supported icon set where appropriate. Do not imply a green/red icon tint from the basic catalog: it has no tint property.

Illustrative phone composition (not a new protocol):

```text
SYSTEM STATUS                Checked 18:04
3 online · 1 needs attention

✓ Hermes       Connected
  Gateway queue 0                 Details ›

✓ Immich       Online
  API responding                 Details ›

! NVR          Storage 86%
  Inspect before it fills         Inspect ›

STORAGE TREND
[native data-only chart, when available]
```

If only the basic catalog is available, use `Card` + `Column` + short `Text` + `Icon` + `Divider` + `Button`. Do not create a fake chart from Unicode blocks or text characters.

## 5. Phase 0 — prevent wrong-target taps in saved cards (implemented)

This is a safety prerequisite, independent of making new responses prettier. The observed saved card has unweighted `Row` text beside buttons. Overflowing paint can overlap hit regions, and a tap on the visible lower button sent the Hermes action.

The narrowly scoped, read-time compatibility normalizer is implemented in `lib/features/hermes/services/hermes_a2ui_layout_normalizer.dart`. For a completed, valid Hermes A2UI fence, it changes a `Row` to `Column` only when the row references an unweighted `Text` and a `Button`. The change is in the in-memory render payload; IDs, order, properties, and action JSON are retained, and the stored assistant message is not mutated. Other unsupported/malformed shapes fail closed to a non-interactive regeneration message. The normalizer also applies payload/component/depth limits and local GenUI schema validation before a surface is built.

Fixture tests compare action identity before/after normalization, cover the narrow-row repair and unsafe/malformed fallback, and verify unrelated payload shapes are not rewritten. The S25 Ultra replayed a previously saved malformed/unsafe response and showed the regeneration fallback rather than live overlapping controls. The fresh vertically stacked status surface also rendered cleanly and its service action went to the intended service. Additional device geometries remain part of the open acceptance matrix in §12. No broad regex or stored-message rewrite is used.

## 6. Phase A — improve Hermes output without a client dependency change (skill deployed)

### Server-side skill update

The single live/root `a2ui-mobile` skill was backed up and updated to v0.2.0. It now includes:

- The response-selection matrix in §3 and visual answer contract in §4.
- Three tested v0.9 examples: compact multi-service overview, choice/action panel, and metric drill-down. Each example must use only components verified in the local GenUI 0.10.3 catalog.
- A strict instruction to make the A2UI surface the primary presentation and avoid prose that duplicates it.
- A narrow-screen checklist: about 300 logical pixels of usable content width, weighted text in any row, short button labels, no broad tables.
- Data integrity instructions: timestamp and source for live values; `Unknown`/`Not checked` when there is no evidence; do not invent history for charts.
- A rule to use `MEDIA:` for generated images and existing Mermaid for graph structures.

The deployment was limited to that skill file; its pre-update SHA-256 was verified against a timestamped backup, and the deployed v0.2.0 SHA-256 was verified after copy. No Gateway, authentication, Tailscale, port, model, or DeepSeek settings were changed. Do not globally inject GenUI's full generated schema into every Hermes turn. If Hermes repeatedly emits invalid components, add an on-demand reference inside the skill rather than bloating the global prompt.

### Basic-catalog examples to QA

- System status: three service sections, short state labels, one unambiguous action each.
- Choice flow: `ChoicePicker` or buttons with an immediately understandable selection.
- Form: a short `TextField`/`Slider` panel when the user truly needs input, with clear submit semantics.
- Unknown/error state: do not render reassuring success visuals without a successful check.

### Acceptance gate A — live response selection verified; broader layout matrix open

On the S25 Ultra, status, service drill-down, choice, diagram, and image requests produced the intended renderers in the same Hermes session. The dashboard's Hermes action sent the intended same-session follow-up, and the choice panel showed four distinct controls. Saved-card action geometry now passes widget tests at 320/360/412 logical pixels, light/dark theme, and 200% text; a live device session was checked at the S25's configured 200% text scale. Other actions and device widths still require the remaining checks in §12.

## 7. Phase B — add three trusted native visual components (implemented)

GenUI's catalog extension API keeps `BasicCatalogItems.asNoAssetCatalog()` and adds only app-owned `CatalogItem`s in `lib/features/hermes/widgets/hermes_visual_catalog.dart`. These items accept validated declarative data and render Flutter widgets; no component interprets HTML, scripts, arbitrary URLs, shell commands, or model-supplied colors. Invalid input yields a safe local fallback; the surrounding Markdown remains available.

| Component | Required data | Optional data | Rendering and fallback |
|---|---|---|---|
| `StatusBadge` | `label`, `state` (`ok`, `warning`, `error`, `unknown`) | `detail` | Theme-aware semantic icon + word; wrap/stack on small widths. Unknown is neutral. No color-only signal. |
| `MetricTile` | `label`, numeric `value`, `unit` | `min`, `max`, `state`, `asOf`, `source` | Large value, short caption, optional bounded progress track when min/max are valid; otherwise value-only. Unit and timestamp are visible or accessible. |
| `MiniChart` | `kind` (`line` or `bar`), label, one ordered series of finite numeric points with labels | `unit`, `asOf`, `source` | Native Flutter-painted chart; fixed-height, at most 60 points, readable axis endpoints and accessible text summary. Empty/one-point data gets a clear fallback, not an invented trend. |

The names and fields above are the public schema implemented through `CatalogItem.dataSchema` and exercised by catalog/widget tests. Runtime validation bounds labels/details, accepts only finite numbers and parseable timestamps, and caps charts at 60 points. Invalid data fails closed to “Visual unavailable” without crashing the chat. `MetricTile` keeps an out-of-range value visible and labels it rather than clamping it into a false healthy range. Empty and one-point charts report the available evidence instead of inventing a trend. Chart labels use compact scientific notation for extremes, and painting normalizes values before subtraction so opposite finite extremes cannot overflow the numeric scale. Do not smooth or interpolate values that were not observed.

Illustrative v0.9 wire example for the shipped visual catalog (the values are examples, not measured state):

```a2ui
{"version":"v0.9","createSurface":{"surfaceId":"system-visual","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"system-visual","components":[{"id":"root","component":"Column","children":["title","gateway","disk","trend","details"]},{"id":"title","component":"Text","text":"System overview","variant":"h4"},{"id":"gateway","component":"StatusBadge","label":"Hermes gateway","state":"ok","detail":"Connected"},{"id":"disk","component":"MetricTile","label":"Storage used","value":86,"unit":"%","min":0,"max":100,"state":"warning","asOf":"2026-09-24T18:04:00Z","source":"Hermes filesystem check"},{"id":"trend","component":"MiniChart","kind":"line","label":"Storage used","unit":"%","points":[{"label":"Sep 22","value":80},{"label":"Sep 23","value":83},{"label":"Sep 24","value":86}],"asOf":"2026-09-24T18:04:00Z","source":"Daily storage samples"},{"id":"details","component":"Button","child":"details-label","action":{"event":{"name":"service.hermes_details"}}},{"id":"details-label","component":"Text","text":"Details"}]}}
```

The example demonstrates a data-only single-series chart and unique action, not a claim that the shown values were measured. The actual catalog schema and JSON example must be tested together before deployment.

Implementation home: `lib/features/hermes/widgets/hermes_visual_catalog.dart`; the surface registers the catalog through `hermes_a2ui_surface.dart`. The integration remains a thin GenUI wrapper. No Hermes transport or generic Markdown grammar change was needed. The visual examples were added to the Hermes skill after the catalog shipped in the installed app.

### Acceptance gate B — automated and first-device checks passed; full matrix open

- `StatusBadge` conveys all four states in light/dark themes and at 200% text scale without clipped words or touch targets.
- `MetricTile` shows 86% disk use with a labeled progress track and does not imply the unit or denominator when absent.
- `MiniChart` renders a known seven-point fixture with correct order, extrema, units, and text summary; malformed, empty, oversized, and non-finite data yield safe fallbacks.
- All three render from an explicit `a2ui` fence only for Hermes messages. Non-Hermes models cannot instantiate them through ordinary Markdown.
- A live button in the surface sends exactly one same-session action with the intended service name. The Hermes details action was tapped on the S25 Ultra and the follow-up appeared in the same conversation.

## 8. Phase C — authenticated visual artifacts (client implementation present)

The current wrapper intentionally excludes GenUI's built-in `Image`: its implementation uses `Image.network` for HTTP URLs, which would let an agent response initiate device requests to arbitrary origins. Do **not** switch from `asNoAssetCatalog()` to unrestricted `asCatalog()`.

The client implementation parses explicit Hermes `MEDIA:` directives, fetches bytes through the exact-origin authenticated artifact client, renders images inline, and uses a lazy native file card for other supported file types. Automated tests cover parsing, successful and unauthorized/missing downloads, inline image rendering, and tap-to-download behavior. Device-level verification of every image/file type is still required. Let Hermes emit `MEDIA:/approved/path/image.png` adjacent to the A2UI surface; this provides actual images and plots without a new image catalog item.

If an image must appear *inside* a generated layout, add a separate `HermesArtifactImage` app-owned catalog item. It should accept an artifact path/reference, reuse the existing Hermes artifact client and exact-origin cookie rules, allow only raster image MIME types after response validation, cap bytes and decoded pixel dimensions, show loading/missing/auth-expired states, and never accept remote URLs. Prove that an A2UI payload containing `https://tracking.invalid/pixel.png` triggers no network request. Video/audio remain out of scope.

## 9. Phase D — make chat presentation support visual answers (partial)

The model-side skill alone cannot remove already-emitted progress chatter. For completed Hermes replies containing a valid A2UI surface, present the surface prominently and optionally collapse tool/probe narration under a “How this was checked” disclosure. Preserve the full text for copy, accessibility, and audit; never silently drop warnings or error explanations. A critical warning must remain visible above the surface. Do not apply this treatment to non-Hermes messages or to malformed A2UI that cannot render.

Hermes-only completed `a2ui` fences are split at the rendering layer and shown as native surfaces alongside the existing Markdown segments. Explicit `MEDIA:` artifacts are rendered in the same Hermes-scoped path. No generic provider or Markdown behavior is changed. The broader proposal to collapse tool/probe narration under “How this was checked” is **not implemented**; leave the full explanation visible until tool events and final prose can be distinguished reliably. Do not use fragile regexes that might hide important content.

The old saved-card compatibility work is Phase 0, not a side effect of this presentation phase. Do not describe the historical card as fixed merely because the new model output is vertically stacked.

## 10. Action and data contracts

All A2UI actions continue to use GenUI `onSubmit` and Conduit's existing Hermes send path. The transmitted turn remains `[A2UI_INTERACTION]` plus v0.9 JSON. The chat bubble shows a short, human-readable label, but the stored protocol payload remains unchanged. Buttons must be disabled while a turn is already being sent; duplicate taps must not create duplicate Hermes turns. Action `name` and `sourceComponentId` identify the exact control; include only the minimal context Hermes needs. A “Details” action requests information; it must not be presented as opening another app or changing a service unless that behavior is separately implemented and confirmed.

Every live value should carry: value/state, unit where applicable, source or probe description, and `asOf` timestamp. A stale value is labeled stale; missing data is unknown. Charts may use only actual ordered observations. The client validates type/size/range; Hermes is responsible for sourcing and describing the data. The UI must not transform “endpoint reachable” into “whole service healthy.”

## 11. Security, accessibility, and performance

- Only catalog-registered Flutter components are executable/renderable. No arbitrary code, web content, model-specified widget classes, or network URLs in new components.
- Keep the existing exact-Hermes-origin artifact cookie policy. Never embed cookies, tokens, local secrets, or authenticated URLs in A2UI JSON, logs, or persistence.
- Bound A2UI payload size, component count/depth, string lengths, and chart points before handing a surface to GenUI. Proposed initial ceilings: 256 KB per fenced block, 100 components, depth 12; tune from tests and surface a graceful error. Avoid synchronous work that blocks a chat scroll frame.
- Use theme colors and semantic words/icons. Minimum tap target 48 logical pixels; support screen readers with component label, state, numeric value/unit, and chart summary. Test text scale 1.0, 1.3, and 2.0, light/dark mode, and reduced-motion settings.
- Never let visual layout change action identity. Test geometric hit targets, not only absence of overflow messages.
- Lazy-build or limit expensive surfaces in long histories; preserve scroll position and ensure surfaces rebuild after background/foreground and scroll-away/back.
- Keep malformed-surface fallback readable; never let a failed A2UI block make the surrounding Markdown or `MEDIA:` artifact disappear.

## 12. Verification matrix

| Scenario | Expected result |
|---|---|
| Three-service overview | Visual hierarchy, concise labels, unambiguous per-service actions; no repeated wall of prose. |
| Tap each service action | Exactly one turn, correct target, readable user bubble, correct follow-up. |
| 320/360/412 px and 200% text | No stripe/overflow, clipping, overlapped tap target, or hidden warning. |
| Old saved overflowing card | Either proven safe read-time layout adaptation or explicit graceful fallback; no wrong-target tap. |
| Unknown/offline/stale service | Neutral/error state and timestamp truthfully represented; no fabricated success. |
| Metric with missing denominator | Number remains visible, no false percentage/progress track. |
| Chart: empty, one, seven, excessive, malformed points | Safe fallback or accurate graphic and accessible summary; no crash/hang. |
| Agent-supplied remote image URL | No request; image catalog remains unavailable. |
| Authenticated `MEDIA:` image | Inline image still works before and after A2UI surface. |
| Mermaid and legacy Chart.js | Existing renderers still work. |
| Background/resume and scroll recycling | Surface and action remain usable; no duplicate submissions. |
| Non-Hermes response and ordinary JSON fence | No A2UI execution or visual-catalog interpretation. |

Use parser/schema/unit tests, narrow-width Flutter widget and golden tests, an action-routing integration test, and screenshots plus tap tests on the S25 Ultra. Run `flutter analyze`, relevant `flutter test` suites, an Android debug build, and a live Hermes test after each phase. The user waived Kimi CLI QA on 2026-09-24.

### Verification snapshot (2026-09-24)

- **Passed:** 694 Hermes/chat regression tests, 141 existing Markdown renderer/compiler tests (including Mermaid and Chart.js), and 98 assistant-image/chat-page layout/navigation tests. The A2UI geometry tests cover 320/360/412 logical pixels at 200% text in both light and dark themes, with disjoint 48 px action targets and correct tap routing. Visual-catalog tests cover four states, a metric without a denominator, a seven-sample chart, an oversized chart fallback, and opposite near-limit finite chart values.
- **Passed after the final provider-isolation change:** 656 focused Hermes/chat tests; targeted `dart analyze` of the Hermes feature and three touched chat UI files reported no issues. The Android ARM64 APK was rebuilt and installed over the existing S25 Ultra debug app; Android reports version 4.1.7 and the original first-install timestamp, confirming an update rather than a data-wiping reinstall. The user was actively using other phone apps, so a post-update Hermes screen inspection was not completed.
- **Passed:** Android ARM64 debug APK build and install/update on the Galaxy S25 Ultra; existing app data was preserved.
- **Passed on device:** visual status dashboard with three service states, per-service actions, verified metrics, and timestamp at the device's configured 200% text scale; tapping “Hermes details” generated the correctly targeted same-session follow-up surface.
- **Passed on device:** a read-only four-service A2UI choice panel with separate native controls and descriptions; the existing Mermaid renderer showed a diagram from a fresh Hermes answer.
- **Passed on device:** a freshly generated `MEDIA:` PNG appeared inline with the requested HERMES MOBILE TEST text. After moving Conduit to the background and relaunching it, the image remained visible in the same conversation.
- **Passed on device:** a fresh `MEDIA:` PDF appeared as a native card; Open handed it to Android's PDF-app chooser, and Share opened the Android share sheet with one PDF. The external viewer's rendering of the document was not confirmed.
- **Passed on device:** older unsafe saved A2UI content failed closed to a regeneration message instead of leaving overlapping interactive controls.
- **Passed safety check:** Android app-op reports `RECORD_AUDIO: ignore`; microphone permission was not granted.
- **Skill polish:** the live `a2ui-mobile` skill is v0.5.0. Its versioned deployment source is `docs/hermes-a2ui-mobile/`. It now chooses components by user intent across overviews, comparisons, choices, forms, checklists, grouped details, trends, and artifacts instead of treating service status as the default answer. Its examples no longer duplicate Button label nodes in parent `children` arrays. The companion validator rejects multiply parented components and non-finite numeric values; all eight fenced examples pass with zero warnings. The prior skill, references, and validator are backed up on Umbrel under `/home/umbrel/.local/share/kai-hermes-backups/a2ui-mobile-pre-polish-20260924/`.
- **Provider isolation:** A2UI interaction-bubble presentation and its copy label are gated to native Hermes conversations; non-Hermes user text resembling the protocol stays literal. A dedicated widget regression test covers that boundary.
- **Not a clean project-wide gate:** repository-wide `flutter analyze` reported 439 diagnostics; the targeted Hermes/chat-file analysis subsequently passed. The full test suite was interrupted after more than 5,200 tests and 25 failures. A Hermes mapper expectation affected by the new transport tag was corrected, and the focused Hermes/chat runs passed; this does not turn the earlier project-wide run into a pass.
- **Not yet evidenced:** 320/360/412 widths on separate physical devices, legacy Chart.js on device, long-history scroll recycling, reduced-motion/screen-reader checks, and rendering the PDF in a chosen external viewer. Kimi review was explicitly waived by the user.

## 13. Rollout and rollback

Before each phase, record the current branch/commit and dirty status, then back up the touched files and the live Hermes skill. Do not overwrite or discard unrelated uncommitted work. Fix the saved-card wrong-target tap in Phase 0 first. Ship Phase A to the installed debug app and verify new conversations. Ship Phase B only after its schemas and fixture tests pass; update Hermes's skill **after** the client can render those components. Phase C and D are separate gates. A failed phase rolls back only its own files/skill revision from the verified backup; do not alter Dashboard auth, Desktop Gateway, Tailscale, port mappings, model, or DeepSeek configuration.

The visual-first improvement is implemented and its first live device scenario is verified. Broader release acceptance remains open until the outstanding checks above pass. The old stored-card issue is mitigated by a read-time safe fallback/normalization; do not claim every historic payload is repairable merely because the new cards look better.

## References

- Local GenUI 0.10.3 sources: `../toolchain/pub-cache/hosted/pub.dev/genui-0.10.3/lib/src/catalog/basic_catalog.dart` and `basic_catalog_widgets/`.
- [Flutter GenUI concepts and catalog model](https://docs.flutter.dev/ai/genui/components).
- [Flutter GenUI overview](https://docs.flutter.dev/ai/genui).
- [Flutter GenUI input and events](https://docs.flutter.dev/ai/genui/input-events).
