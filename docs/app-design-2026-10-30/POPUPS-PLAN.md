# Remaining pop-ups: plan

Status 2026-10-30, branch `feat/today-p0-foundations`. Mockups: `popups.html`, rendered to `shots/popups/`.

## The real count

The guard test counts Flutter's own pop-up calls (`showDialog`, `showModalBottomSheet`, `PopupMenuButton`, `AlertDialog`, `showCupertino*`): **32 uses in 16 files**. It does not count the app's own wrappers, which are pop-ups too:
- `ThemedDialogs.showCustom`
- `ThemedSheets.showCustom` / `showRoundedPage` / `showAdaptive`
- `showConduitDialog`
- the Hermes morph sheets (`pushHermezSheet`, `pushHermezPanel`)

Counting every call site outside the card code itself, **81 surfaces** are left. They fall into seven patterns. Each pattern is one reusable card, so the work is seven card variants plus wiring, not 81 designs.

## Patterns

| | Pattern | What it is | Count | Card |
|---|---|---|---|---|
| F | Hermes sheets | `pushHermezSheet` / `pushHermezPanel`: active work, attention, completed run, delegates, plan, scheduled agent, tool inspector, job editor, MCP add/preset/key, Kanban task and create, run details, new chat, Spaces move/version/save-as/chat picker | 26 | **Full-height card.** One change: re-implement `pushHermezSheet` on the floating card with resting and raised snaps. |
| E | Content sheets | `ThemedSheets.showCustom` / `showRoundedPage` / `showAdaptive` with lists, browsers or previews: chat share, server-file attach (×4), chat composer sheets (×2), channel thread, workspace (relationship, prompt history, access grants ×2, import, URL import, valves, attach existing), details block, release notes, code and Mermaid previews, MCP content, audio player (×2) | 25 | **Full-height card**, the same variant as F. Content that brings its own `DraggableScrollableSheet` is hosted at its sizes. |
| C | Pickers | One choice from a list: push distributor, push channel, folder model picker, `adaptive_selection_sheet`, bot icon picker | 5 (+4 in F) | **Select card** (Morphlet's MorphSelect): the field or chip grows into the options and folds back showing the new value. |
| B | Forms and prompts | One or more fields: streaming input, attach webpage (×2), prompt variables, channel form, file browser rename/create (×3), `adaptive_feedback.inputShow` (Android path), accessible modal | 10 | **Form card**: fields on hairlines, focused field on a 2 dp ink line, rides above the keyboard, one primary button. |
| A | Questions | Yes/no or few choices: deny approval, unpair push, sign-out options, `adaptive_feedback.show` (Android path), error dialogs (×2) | 6 | **Confirm card** (built). Must-answer variant: no scrim dismiss, no ×, the answer buttons only. Errors get Retry and Close. |
| D | Row menus | Spaces library and page editor `PopupMenuButton`, citation badge | 3 | **Menu card** (built for adaptive menus): the row's ⋯ grows into the actions; destructive actions in the failure red. |
| G | iOS native | Cupertino dialogs, action sheets and menus on the iOS paths | 6 | **Keep native on iOS.** Conduit runs on the S25; these stay in the allowlist, with that as the reason. |

## Order

1. **F first:** re-implement `pushHermezSheet` and `pushHermezPanel` on the card. That converts 26 surfaces with one change, all of them Hermes screens you use daily.
2. **The full-height card variant** (resting and raised, magnetic like Today's sheet), then point E's helpers at it: `ThemedSheets.showCustom`, `showRoundedPage`, `showAdaptive`.
3. **C:** a `HermezSelectCard` (grows from the field and folds back with the value), then the five pickers.
4. **B:** `HermezFormCard` (generalises `promptHermezCard` to several fields), then the ten forms.
5. **A:** must-answer confirms and error cards on the existing confirm card.
6. **D:** the three row menus onto the menu card.
7. **The guard:** extend its pattern to the wrappers above. Its ceiling then covers all 81, and it can only go down.

## Checks

- The existing tests for each migrated surface pass. Where a test pins the old bottom sheet or dialog, it is updated to assert the card instead (as `themed_sheets_test` was).
- One regression test per pattern on its rule:
  - a full-height card snaps between two detents;
  - a select card returns the picked value;
  - a form card keeps typed text across a nested step;
  - a must-answer card cannot be dismissed by the scrim.
- On the S25, a screen recording of one surface per pattern, compared frame by frame with the Morphlet reference, as done for the card itself.
