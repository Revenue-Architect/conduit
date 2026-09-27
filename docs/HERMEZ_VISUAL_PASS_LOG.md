# Hermez visual pass — handoff

Date: 2026-09-27. Frontend only. No Hermes API, provider contract, Kanban, artifact, session, approval, or Desktop Gateway behavior was intentionally changed.

## Ask

Recompose the existing Hermez screens so they follow the mockup grammar (hierarchy, card anatomy, bot identity, sheets) without copying pixels or inventing data. Then stop the recent-conversations surfaces from painting Flutter overflow errors.

## What landed

- `lib/features/hermes/widgets/hermez_surfaces.dart` — hero, utility, list, and technical surfaces, plus `HermezSectionBar` (wraps instead of overflowing).
- `lib/features/hermes/widgets/hermez_bot_mark.dart` — drawn marks for kai, local, fast, strong, autopilot, and a neutral default. Identity comes from the profile name only.
- `lib/features/hermes/widgets/hermez_relative_time.dart` — `Today, 12:39 PM` / `Yesterday` / `1h ago`. No raw `DateTime` strings.
- Home, bot detail, the conversations list, the empty chat, and the shared sheet shell use those pieces.
- Recent rows no longer use a long error dump as the title. A failed per-bot refresh no longer repeats an error line when chats are already on screen. A failed session-list refresh stays a single quiet line instead of the settings essay, and pull-to-refresh swallows that failure so it does not become a framework exception.

## Codex continuation

- Home recent conversations now have a widget regression test that opens the exact stored session and lands on Chat. The compact row has its own transparent Material ancestor so its tap works inside the context-menu wrapper.
- The mobile drawer closes when Chat becomes the destination, including when the drawer shell is first mounted after selecting a session on Home.
- The idle Home shortcut into Live Run was removed. The real active-work card is shown only for a running Desktop turn and opens that conversation's inline activity panel.
- The in-chat Live activity disclosure is visible only while the selected native Hermes Desktop session is running, reconnecting, or synchronizing. It disappears when idle. Its height and chat overlap spacing scale with accessibility text; the previous 320 px / 200% overflow is covered by a regression test.
- The user screenshots revealed a second missing-Material failure in populated Run activity. The event timeline now owns a transparent Material ancestor, with a 200%-text event regression test. The Home recent-row test covers the other screenshot failure.
- Bot marks are derived only from the canonical profile name, not a potentially misleading bot title.

## Left alone

- Session open, create, fork, rename, and delete.
- `listSessions`, profile session queries, Kanban client, artifact client, auth, and gateway transport.
- Navigation routes and Hermes session contracts. Home → a recent chat still calls `openHermesSession`; only the tap surface and drawer close behavior changed.

## Checks

- `flutter test test/features/hermes/hermez_relative_time_test.dart test/features/hermes/hermez_chat_visuals_test.dart test/features/hermes/hermez_modal_sheets_test.dart`
- `flutter test test/features/hermes/hermes_destinations_smoke_test.dart` passed after the overflow fix, including 200% text. The Home smoke drag targets the vertical list, because the bot strip is its own horizontal list. A fresh debug APK was built afterward.
- Debug APK: `flutter build apk --debug --target-platform android-arm64`
- Install, when the phone authorizes wireless debugging: `adb -s 192.168.2.70:5555 install -r build/app/outputs/flutter-apk/app-debug.apk`
- The S25 Ultra later authorized wireless ADB. The corrected APK was installed with `adb install -r` (data preserved). A Home screenshot showed real bots, schedules, Kanban, and recent conversations with no error panel; tapping a Home recent conversation opened its existing Hermes transcript in Chat, not the sidebar. Chat at idle showed no stale Run activity card. Filtered `flutter:E` and `AndroidRuntime:E` logcat had no errors from that flow.
- The focused visual, session, Kanban, artifact, and Chat back-navigation widget suites passed, including the two screenshot-specific missing-Material regressions and 320 px / 200% text.

## Device acceptance remaining

- An actual long-running Hermes turn was not started during this pass; active-to-idle Live activity transitions were verified in widget tests, while on-device QA verified the idle state.
- The entire visual pass was not exhaustively screenshot-compared on every screen at 200% device text scale. The targeted 320 px / 200% widget tests passed.
