# Hermez chat facelift: implementation spec and runbook

Status: initial debug-Android, Hermes-chat polish implemented. The supplied Hermes concept image is visual direction for color, typography, and restraint; it is not a request to copy its artwork or add its Home, Live, Spaces, or Focus screens.

## Product boundary

Keep Conduit's existing chat route, drawer, sessions, composer behavior, assistant rendering, A2UI, MEDIA artifacts, Mermaid/Chart.js, approvals, tools, auth, and transport. No new navigation destinations, server requests, database fields, or Hermes configuration. The first pass is scoped to the Android debug build while a Hermes conversation/model is active. Release builds and non-Hermes chats retain their existing presentation.

## Visual implementation

- Debug launcher: label **Hermez** with an original geometric H icon. Package ID and app data stay unchanged, so `adb install -r` updates in place. Keep the high-resolution source and the deterministic icon-generation script in the repo; alter only debug Android resources.
- Existing chat: warm ivory or deep graphite canvas, high-contrast ink, one orange action accent, stronger chat title, more deliberate empty-state greeting, charcoal/ivory user bubble, and a cleaner composer surround. Match system light/dark modes without changing the global Conduit theme.
- All visual gates belong at the presentation boundary (`debug && Android && Hermes`). In particular, do not infer Hermes from the assistant's prose or from a generic fenced code block. Assistant messages and rich output are rendered by the existing widgets.
- Keep text readable at 320 logical pixels and 200% text scale. Preserve semantic button labels, focus order, tap targets, keyboard behavior, scroll position, and any loading/auth/error affordances.

## Verification and release gates

1. Record Git status/HEAD; back up modified source and launcher files. Do not touch the Umbrel or Hermes server for this cosmetic change.
2. Test the visual gate's eight Boolean combinations and render the greeting at narrow width, light/dark themes, and large text. Run focused chat/Hermes regressions and analyzer on touched code.
3. Build ARM64 Android debug, inspect manifest/package/launcher resources, and install over the existing S25 debug app with `adb install -r`. Confirm the new label/icon and preserved Hermes account/session. Open the existing chat and inspect the greeting, composer, user bubble, and an assistant response. Check both portrait and landscape if available.
4. Check that a non-Hermes conversation still uses the old styling and that rich outputs, sending, approvals, and background/resume have no behavioral changes. Record any unverified manual cases rather than declaring them passed.
5. Inspect the final diff for unrelated changes and secrets, commit the scoped result to `main`, push, and verify the remote SHA.

## Rollback and future work

The facelift is reversible by reverting the presentation-only commit and reinstalling the previous debug APK; it does not migrate app data. Any broader redesign needs a separate product specification and explicit authorization. In particular, the concept image's extra destinations, fictional weather/tasks, progress claims, custom transport, and focus timer are not part of this work.
