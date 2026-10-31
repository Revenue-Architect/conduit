# Screens the direction left out (screens2)

Source: `build_screens2.py` writes `screens2.html`. Shots: `shots/screens2/` (3x, sheet `shots/screens2/sheet.png`) and `shots/screens2-small/` (375 x 667). Scan: no FAILs at either size. These pages extend DIRECTION.md; they do not change it. Settings pages and Spaces pages are pushed screens, so they have no dock (a back arrow in the sky band instead). Their one-line sub-title sits in the sheet under the band, not on the skyline.

Feature lists were read from the Flutter source (`profile_page.dart`, `app_customization_page.dart`, `personalization_page.dart`, `notification_settings_page.dart`, `push_settings_section.dart`, `push_pairing_page.dart`, `backend_chooser_page.dart`, `hermes_settings_page.dart`, `spaces/views/*`, `hermes_artifacts_page.dart`, `model_selector_sheet.dart`). Strings the app has today are kept; plain-language rewrites are noted.

## s01 All settings (`s01`, `s01b`, `s01-dark`)

Intent: every setting in one page, grouped by what you are doing (your team, chatting, this app, servers, about), not by who built the setting. `s01b` is the same page scrolled to the end; `s01-dark` is the evening-sky version.

Keeps:
- [x] Account header (name, email line, opens Account details)
- [x] Hermes Agent
- [x] Notifications
- [x] Chat
- [x] Personalization (only shown with an Open WebUI account or when direct is primary, as today)
- [x] Audio
- [x] Appearance (theme and language)
- [x] Connection (Open WebUI connection health; named "Open WebUI connection")
- [x] Workspace (only for server admins, as today)
- [x] Direct connections
- [x] About
- [x] Support Conduit: Buy Me a Coffee, GitHub Sponsors
- [x] Sign out (red, last)
- State not drawn: with no Open WebUI account, the "Open WebUI connection", "Workspace", account header and Sign out rows go, and "Connect to Open WebUI" (Add a self-hosted Open WebUI server) sits at the head of Servers. Same row style.

Changed: the three groups of the old list became five plain headings; the support block shrank from a titled section to two rows under "Support Conduit".

## s02 Chat (`s02`)

Intent: how a chat starts and how sending behaves, on one page, with the quick actions unfolded in place as chips.

Keeps:
- [x] Quick actions in chat (Web, Image Gen, server tools, model filters; multi-select; count; Clear all)
- [x] Send with Enter
- [x] Start temporary chats
- [x] Show citation page titles
- [x] Android digital assistant (opens the three-way choice as a card: quick overlay, new chat, voice call)
- [x] Model system prompts (expands to the per-model list; shown with an Open WebUI account)
- [x] Default model (see questions: it lives in Personalization today)
- Below the fold, not drawn: the expanded model list and its per-model prompt editor.

## s03, s03b, s03c Notifications

Intent: one long page, shown in three scroll positions. Top: what you hear about. Middle: is it working, and Push from Hermes health. Bottom: pairing and categories.

Keeps (every row that exists today):
- [x] Enable notifications; System notification settings (opens Android; here "Android notification settings")
- [x] In-app banners; System notifications; Sound; Always play sound (grey out when the master is off, as today)
- [x] Chat responses; Channel messages (Open WebUI only)
- [x] Health: Conduit notifications, System notifications, Android permission, Android channel, Send test notification, "where notifications appear" paragraph
- [x] Push from Hermes: headline, last push time, issue rows with their fix button (drawn: battery), Check again, Approvals, Pair again / Pair this phone, Unpair this phone
- [x] Categories: Receive push, Alerts, Proactive, Briefs, Agent messages, Watches, Status, Sound and vibration, footer about Approvals and critical alerts
- [x] The conditional "Open Android settings" fix row (shown only when Android blocks notifications) is not drawn; it is one more row in the health group.

Changed: order. Today the health block comes straight after the master switch; here the plain toggles come first and "Is it working" and push sit below. The caps eyebrows (NOTIFICATION HEALTH, PUSH FROM HERMES) became sentence-case headings. The strings in the app say "Hermez"; the mockups say "Conduit".

## s04 Spaces (`s04`)

Intent: your Spaces as plain rows, newest first, one tap to open; + creates one.

Keeps: [x] list with page count and updated time, [x] New Space, [x] empty-state sentence (shown as the footer line here; the real empty state replaces the list).
Not drawn: pull to refresh; loading and error states.

## s05 A Space's pages, with its menu card (`s05`)

Intent: the pages of one Space with search, and the ⋯ grown into one card. The ⋯ button is hidden because it is the card.

Keeps: [x] title and page count, [x] New Page (page-plus), [x] Search pages, [x] page rows (title, excerpt, time, "in parent", subpage count), [x] menu: Recently updated, Name (sort), Rename Space, Delete Space.
Nested, not drawn (same card, per the one-card rule): Rename Space becomes a one-field form; Delete Space becomes the confirm ("This permanently deletes the Space and its 7 Pages"); New Page becomes a one-field form.

## s06 Page editor (`s06`, `s06b`)

Intent: a calm sheet to write on, with Ask Hermes in the header and the formatting bar over the keyboard. `s06b` is the same page when it changed elsewhere.

Keeps: [x] autosave status ("Saved"), [x] title field, [x] visual editor, [x] formatting toolbar (bold, italic, strike, code, heading, bullets, numbers, quote, link) while the body has focus, [x] Ask Hermes, [x] ⋯ (New subpage, Move page, Markdown source or Visual editor, Copy Markdown, Delete page), [x] conflict banner with Review latest, Keep my draft, Use latest, Copy draft.
Changed: Ask Hermes lost its sparkle icon (nothing sparkles). The keyboard is not drawn; the bar sits where it would ride above it.
Not drawn: the ⋯ menu card, the bot picker card that Ask Hermes opens, Move page's card, Markdown source mode (monospace is the one place a mono face would be right; owner to say if source mode should look different), the leave-without-saving confirm and the save-error banner.

## s07, s07b Artifacts

Intent: what Hermes made, as things you can pick up. `s07b` shows a file opened: the tile became the card.

Keeps: [x] title and "Files Hermes made for you", [x] Refresh, [x] filters All, Images, Docs, Media, [x] file count, [x] two-column tiles with thumbnail (images) or file glyph, name, type, [x] opened view: preview, File context (Source, Conversation, Type, First seen, saved-at path), Related conversation (the card grows into that chat).
Not drawn: the Kanban attachment panel that heads the page when opened from a Kanban task; the "unavailable or sign-in expired" state; the "Source unavailable" variant of the related-conversation row; audio and video previews.

## s08a, s08b, s08 Onboarding

Intent: first run on the sky: choose, connect Hermes, pair this phone. Steps "1 of 3", "2 of 3", "3 of 3". `s08` is the one asked for; `s08a` and `s08b` give it its context.

Keeps:
- [x] s08a: Open WebUI, Hermes Agent, Connect directly (OpenAI-compatible and Ollama), "add more later" (`backend_chooser_page.dart`; the iOS-only Apple sections are left off)
- [x] s08b: connection mode (Responses API / Desktop Gateway), Server URL, API key, optional Memory key, Connect Hermes
- [x] s08: one-time code from the Umbrel, the command to run, Pairing code, Name for this phone, Gateway address, Pair; five-minute and single-use note; "QR scanning is not available"
Not drawn: Desktop Gateway mode (profile picker, Legacy / Native / Dashboard sign-in), the Open WebUI sign-in pages, direct-connection editor, pairing error line, the busy state of Pair.
The command is set in Geist, not a mono face, per the round-4 rule.

## s09 Model picker (`s09`)

Intent: the full picker as the full-height card, over the chat it opened from; its chip is hidden because it became the card.

Keeps: [x] search, [x] Pinned models (with a pin mark), [x] Open WebUI models, [x] direct models (with Ollama "Loaded" and its actions button), [x] capability tags (Reasoning, Multimodal), [x] long-press to pin or unpin (not drawn; same card), [x] Effort, [x] Fast tier (Hermes models only), [x] selected check.
Changed: today search hides behind "More models"; here search is always on top and the old "More models" step becomes the scrolling list, so there is no second view. Effort opens the reasoning-level step by reshaping the same card (as m05).

## Questions for the owner

1. **Default model**: today it is on Personalization (with the image model, your prompt and memories). s02 puts it on Chat. Move it, or leave it on Personalization and drop the row from Chat?
2. **Where does "Is it working" go**: moved below the toggles in Notifications. Is that right, or should health stay first because that is what you open the page for?
3. **Haptics while streaming** and **transport mode** stay on the Open WebUI connection page. Should "no haptics while streaming" move to Chat with the other behaviour switches?
4. **Pairing**: in the app, Hermes connects with a server URL and key (or gateway sign-in); the pairing code only pairs push alerts. Onboarding shows both as steps 2 and 3. If you want Hermes itself to connect with a code, that is a Hermes feature that does not exist, so it is left out.
5. **Skip in onboarding**: no "Not now" is drawn, because the app has no such control today. Pairing can already be done later under Notifications. Add one?
6. **Space icons**: a Space can carry an emoji icon in the data. The mockups show the folder glyph only (emoji in chrome fails the scan). Keep the folder, or draw the Space's own icon when it has one?
7. **Tile detail on Artifacts**: tiles show only the type. The app already knows which bot made a file and when it was first seen. Add "kai · 6:12" under the name?
8. **Nested forms** (Rename, New Page, New Space, delete confirms) are described, not drawn. Draw them as a storyboard like m10?
9. **Markdown source mode** in the page editor: leave as-is, or design it?
