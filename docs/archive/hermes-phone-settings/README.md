# Hermes settings and bots, archived for the phone

Kept from the dropped Windows desktop project (October 2026) so the phone app
can pick it up later. Nothing here is wired into the app or analyzed
(`docs/archive/**` is excluded in `analysis_options.yaml`), and the tests here
don't run.

## What's here

`files/` holds whole files at the path they belong at in the repo:

| Path | What it is |
| --- | --- |
| `lib/features/hermes/admin/` | Admin client for Hermes 0.21.5: allowlisted REST and RPC, error mapping, profile create/configure/delete, SOUL, avatar, learning graph (memory), cron, config document with backups, shared secret redaction |
| `lib/features/hermes/settings/` | Settings shell with categories (Connection, Tools, Models, Advanced), per-bot scope chip, masked secret field, and pages: tools and extensions, models and providers (write-only keys), advanced config editor, bot editor (name, title, description, SOUL, look, memory, delete) |
| `lib/features/hermes/bots/hermes_bot_screen.dart` | Bot roster with live state from Active Work, New bot, Edit |
| `test/features/hermes/` | Tests for the above |
| `docs/plans/hermes-0-21-5-admin-probe.md` | What the live Hermes 0.21.5 server answered for each admin route (404 vs 405, RPC codes, which params go in body vs query) |

`patches/` holds the edits the same work made to existing files, as
`git diff` output against `65ef1a68`. Each also carries desktop-only lines;
take only the settings and bot parts:

- `hermes_desktop_administration.patch`, `hermes_desktop_api_service.patch`:
  the admin extension the client calls (`requestAdminJson`,
  `ensureAdminConnected`, `requestAdminMcp`). Skip `reconcileNow` and
  `isAttached`.
- `app_router.patch`, `navigation_service.patch`: the
  `/profile/hermes/settings/:category` and `/profile/hermes/roster` routes.
  Skip `_desktopRedirect`.
- `hermes_settings_page.patch`, `hermes_settings_sections.patch`,
  `profile_page.patch`: the phone's "Bots and server" entries and the
  `embedded` mode.
- `hermes_page_chrome.patch`, `hermes_bot_detail_page.patch`,
  `hermes_mcp_page.patch`, `persistence_keys.patch`: small supporting edits;
  most of these are desktop width limits and can be dropped.

## Bringing it back

1. Copy `files/` over the repo root.
2. Apply the settings and bot hunks of the patches by hand
   (`git apply --include=... ` or edit).
3. Remove the desktop links, which point at code that no longer exists:
   - `hermes_bot_screen.dart`: imports of `desktop/input/hermez_desktop_shortcuts.dart`
     and `desktop/shell/desktop_nav_scope.dart`; drop `desktopNavMenuLeading`
     and replace `DesktopRefreshScope` with a `RefreshIndicator`.
   - `hermes_settings_shell.dart`: `desktop_nav_scope.dart` and
     `desktopNavMenuLeading`; the shell's two-pane layout was the desktop
     view, the phone uses `HermesSettingsCategoryPage` per category.
   - `hermes_advanced_config_page.dart`: `HermezDesktop.isActive` for the
     side-by-side review; use a width check alone.
   - the two settings tests set `HermezDesktop.debugIsActiveOverride`;
     drop the desktop cases.
4. `dart run build_runner build`, `flutter analyze`, run the tests above.
