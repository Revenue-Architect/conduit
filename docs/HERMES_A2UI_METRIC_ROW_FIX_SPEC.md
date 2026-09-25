# Hermes A2UI blank dashboard: diagnosis and fix specification

Status: client fix, local regression suite, and ARM64 release build are complete. Device install/visual acceptance and publishing the updated live Hermes skill/checker remain pending. The installed S25 package reports `com.android.vending` as installer and is signed `CN=cogwheel`; this checkout has no release signing configuration/key (`android/key.properties` is absent), and the local debug signer does not match. `adb install -r` rejected the unsigned APK before changing the installed app; its data remains untouched. Continue via the same Play distribution/signing path or with the exact matching signing key. Do not update the live skill until the client is installed and verified. The existing Conduit/Hermes architecture, Gateway, auth, ports, model, and Umbrel services remain out of scope for this fix.

## Observed failure

On 2026-09-24, the Galaxy S25 Ultra displayed a recent completed Hermes reply ending with “live Umbrel board below,” but no native board appeared between that sentence and the assistant action bar. Two consecutive wireless-ADB screenshots of the same visible chat had zero dark-content samples in the expected surface region. This is a screen-specific diagnostic, not a general image-based test to ship.

The authoritative Hermes message contains one closed `a2ui` fence with two v0.9 JSON messages (`createSurface`, `updateComponents`), 22 components, two `Row`s, and four `MetricTile`s. At least one tile has `min`/`max` and therefore renders a progress indicator. The live server-side A2UI checker reported zero errors and warnings. The exact payload also passed Conduit's `normalizeHermesA2uiPayload` preflight. Thus the model did produce A2UI and the preflight did not reject it.

Feeding that same payload to `HermesA2uiSurface` in a Flutter widget test reproduced a rendering exception: `BoxConstraints forces an infinite width`, originating at the `LinearProgressIndicator` in `lib/features/hermes/widgets/hermes_visual_catalog.dart` (currently around line 234). A minimized surface containing only `root: Row` and one ranged `MetricTile` reproduces the exception when the tile has no `weight`. The otherwise identical tile with `weight: 1` passes. Adding `weight: 1` to the four metric tiles in the captured payload makes the complete surface render without exceptions at 360 px and 320 px, including 200% text scale. No production source was modified to run these diagnostics.

## Cause and confidence

Flutter lays out a non-flex child of a horizontal `Row` with unbounded horizontal constraints. A ranged `MetricTile` contains a full-width `LinearProgressIndicator`, which requires a finite width. The current A2UI normalizer only repairs an unweighted `Row` that mixes `Text` and `Button`; it leaves `Row` + `MetricTile` unchanged. The server-side checker accepts that shape, and the model emitted it despite guidance to weight comparison tiles.

This is a confirmed deterministic renderer defect and the strongest explanation for the blank phone surface. A device-side Flutter exception was not captured in logcat, so the diagnosis does **not** prove that no second live-message issue exists. The fix's device acceptance gate below must verify that the same saved message appears after the repair. Do not treat changing Hermes's prose alone as a fix: previously saved A2UI cards must become safe at read time.

## Required implementation

### 1. Make A2UI rows finite-width before GenUI builds them

Extend the existing read-time normalizer in `lib/features/hermes/services/hermes_a2ui_layout_normalizer.dart`; do not change Hermes transport, the generic Markdown renderer, or persisted messages. Inspect each `Row`'s resolved direct children after schema and graph validation:

- For a row consisting of short, comparable visual tiles such as `MetricTile`, give every unweighted tile a positive `weight` in the normalized in-memory payload. Preserve component IDs, order, values, units, sources, timestamps, and actions. The captured two-tile metric rows are the primary case.
- For a mixed row in which assigning flex would leave an interactive control cramped or make reading order ambiguous, normalize the row to a vertical `Column`. Keep the existing `Text` + `Button` protection and expand the policy to other width-dependent components, including `MiniChart` and built-in controls that require bounded width. Document the exact type policy in code; do not add an arbitrary fixed pixel width to a tile.
- Never assign `weight` to an already weighted child or alter an explicit user/model layout that is demonstrably safe. Make normalization idempotent.
- Bound component count/depth as today, and fail closed with a visible, readable fallback if the graph cannot be made safe. The surrounding Markdown and any `MEDIA:` artifact must remain visible.

The normalization policy should preserve useful side-by-side comparison on a phone when safe; it should not flatten every visual dashboard into a text-like vertical stack. If a two-column layout cannot fit at 320 logical pixels or 200% text, stack that row responsively rather than overflow or suppress the whole surface. A width-aware choice belongs at the surface/layout boundary, not in Hermes's JSON transport.

### 2. Make app-owned visual components robust to constraints

Review `MetricTile` and `MiniChart` in `lib/features/hermes/widgets/hermes_visual_catalog.dart` under bounded and unbounded parent constraints. Their normal presentation must have a finite width; malformed parent layout must yield a safe fallback rather than an uncaught layout exception. Do not solve this with a hard-coded width that can exceed a narrow chat column. Preserve the semantic value/unit/range/source labels and the rule that a metric without a meaningful denominator has no progress track.

### 3. Close the model-output gap without relying on it for safety

Update the versioned `docs/hermes-a2ui-mobile/` skill and the single live Umbrel copy **after** the client fix is installed. State that *every* `Row` containing `MetricTile`, `MiniChart`, or another width-consuming child needs explicit positive `weight` on those direct children; use a `Column` when values or labels are long. This applies to overview dashboards as well as comparison cards. Add a valid two-metric overview example that resembles the failing structure without using private live values.

Update `a2ui_check.py` to reject (or at minimum loudly warn on) unweighted rows with width-dependent children. Add a negative fixture for the minimized `Row` + ranged `MetricTile` and a positive weighted fixture. The server checker is authoring guidance; the Conduit client remains the safety boundary for existing and third-party A2UI payloads.

## Verification gates

1. Before editing, record the Conduit commit/dirty state, snapshot touched client files, and back up the exact live Hermes skill/checker. Do not change Umbrel services, Gateway, Dashboard auth, Tailscale, ports, or model configuration.
2. Add a permanent sanitized regression fixture with `root: Row` → ranged `MetricTile` (no private service data). A test must fail on the current implementation with the infinite-width error, then pass after the client fix. Also test the full *shape* of the observed 22-component dashboard using synthetic labels and numbers.
3. Test unweighted, explicitly weighted, mixed visual/control, and already-safe rows. Assert normalized graph/action IDs, idempotence, absence of Flutter exceptions and overflow, and visible values/units/source. Run at 320/360/412 logical pixels, 1×/2× text, and light/dark themes. Verify a `MetricTile` with no `min`/`max` has no invented progress bar.
4. Add an `AssistantMessageWidget` integration test: a completed Hermes-tagged assistant reply with Markdown followed by an explicit `a2ui` fence shows both prose and a native `Surface`, not raw JSON or blank space. A non-Hermes message and an ordinary `json` fence remain on the existing Markdown path. Test scroll-away/back and background/resume surface reconstruction.
5. Test a button tap from the repaired card sends exactly one same-session `[A2UI_INTERACTION]` turn with the correct target. Existing Mermaid, Chart.js, `MEDIA:` image/file handling, and Markdown suites must remain green.
6. Run the targeted Dart analyzer, focused Flutter tests, and an ARM64 Android build. Install over the existing S25 app with `adb install -r` (preserve data). On the phone, reopen the **same saved chat** and confirm the formerly blank board now appears; then request a fresh mixed-metric dashboard and tap its actions. Capture a screenshot and check 200% text scale. Do not mark the fix done from widget tests alone.
7. Revalidate the live Hermes skill examples, check Hermes container restart count and Umbrel unhealthy-container status, and record any pre-existing unrelated host failures separately. Stop or roll back only the changed client/skill files if the acceptance check fails.

### Current verification result

- Pass: targeted Dart analyzer after the final client edit; 841-test Hermes/chat/Markdown regression run; focused A2UI surface/normalizer suite (38 tests); AssistantMessageWidget Markdown+A2UI integration and action test; A2UI skill/pattern examples (9 blocks); positive weighted checker fixture; Python syntax check; ARM64 release APK build.
- Expected negative: unweighted ranged `MetricTile` fixture exits with one checker error naming the missing positive weight.
- Blocked: phone install and same-chat/200%-text acceptance. The release artifact has no certificate because `android/key.properties` is absent. `dumpsys package` reports `com.android.vending` as installer; the existing split APK is signed by `CN=cogwheel`, which does not match the local debug key. No signing-key file was found in the repository/workspace or standard Android key locations. The unsigned install was rejected before replacement. No uninstall, data clear, or signer-mismatched install was attempted.
- Pending: copy the versioned skill/references and checker to the single live Umbrel skill only after successful in-place client install and phone acceptance; then validate live examples and recheck service health/restart counts.
- Read-only Umbrel recheck: Hermes container running with restart count 0; Paperless running/healthy with restart count 1 (pre-existing); no unhealthy containers reported. No Umbrel service or configuration was changed.

## Explicit non-goals

No new A2UI protocol version, catalog, backend, database migration, artifact service, cross-message card state, streaming partial JSON, generic Markdown change, Hermes core patch, or Umbrel service restart. This task fixes finite-width layout and authoring validation for already supported A2UI components.
