# Hermez vs Muse and Grok Bot: where the Hermes surface is unused

Written 2026-09-28. Question: is the app using what Hermes and its API expose well enough to compete with Meta's Muse and xAI's Grok Bot?

**Short answer.** The core is already ahead on agent depth: named bots, cron, Kanban, live activity with a browser view, and approvals all exist and are real. What is missing is the layer that makes Muse and Grok Bot feel like a person who works for you: the app never speaks first, has no voice or wake word, does not show memory or skills, and does not use most of the session and gateway API. Most of the gap is client work, not new backend.

## How this was checked

- **Hermes side:** the official [features overview](https://hermes-agent.nousresearch.com/docs/user-guide/features/overview), the [release notes](https://github.com/NousResearch/hermes-agent/releases) (the Umbrel install reports Hermes 2026.9.14; upstream is at v0.21.5), the gateway's JSON-RPC method list (`tui_gateway/server.py` on `main`), and the dashboard's session routes (`web_routers/sessions.py`). The audio and memory-provider routers could not be read (GitHub rate-limited), so those rows are marked unverified.
- **App side:** searched `lib/` for each RPC method and route by name. "0 files" means the string does not appear anywhere in the client. Method names are from upstream `main`; the installed 2026.9.14 gateway may lag, so probe with `commands.catalog` / `config.get` before building on any of them.
- **Competitors:** press and vendor pages only ([Meta announcement](https://about.fb.com/news/2026/09/introducing-muse-personal-ai-agent/), [TechCrunch on upcoming Muse features](https://techcrunch.com/2026/09/23/everything-new-coming-to-metas-ai-agent-muse/), [Composio's Grok Bot guide](https://composio.dev/content/guide-to-frok-bot), [Layer3 Labs](https://www.layer3labs.io/guides/what-is-grok-bot)). I have not used either product. Both are recent launches (Muse 2026-09-08, Grok Bot 2026-08-11) and details will move.

## What Muse and Grok Bot sell

| Pillar | Muse (Meta) | Grok Bot (xAI) |
| --- | --- | --- |
| Acts, not just answers | Books, buys, schedules, manages email | Operates a cloud computer: clicks, types, navigates |
| Keeps working when you leave | "Keeps working after people close the app, and comes back when something changes or when it needs approval" | 24/7 on always-on virtual computers |
| Asks before sensitive actions | Checks before sending email or purchasing; full audit trail of what it did and plans to do | Approval boundaries for sending, publishing, deleting, purchasing; passwords/2FA/CAPTCHA stay with the human |
| Remembers you | Proactive suggestions from what it knows | Persistent memory, corrections carried forward |
| Learns tasks | Custom connector platform | Teach-a-task: watch one browser workflow, draft a reusable skill |
| Multiple agents | One agent | Two to six named bots in a group chat that hand work to each other |
| Channels | App, WhatsApp, voice, smart glasses, own email address (coming) | Desktop and phone apps with synced bots |
| Access control | Per-connector read/send scopes, revocable | Connectors, plugins, MCP |

## What Hermez already does well

| Capability | Where |
| --- | --- |
| Named bots as first-class objects with their own identity, status, history | Home, Bot Detail, `hermez_bot_mark.dart` |
| Scheduled agents (cron) with run history, enable/disable, run now | `hermes_jobs_page.dart`, scheduled agent sheet |
| Kanban board with tasks, comments, runs, attachments | `kanban/` |
| Live run surface: activity feed, Steer, Stop, browser watch (Steel) | `hermes_inline_run_surface.dart`, `hermes_live_run_page.dart` |
| Human approvals as a first-class flow, dismissal never means approve | Attention page, resolution sheet, pending store |
| Artifacts from chats, with provenance | Artifacts page |
| MCP server management, including OAuth | `hermes_mcp_page.dart` |
| Rich agent-drawn UI (A2UI) inside chat | `hermes_a2ui_*` |
| Home-screen widget, local notifications, voice-assistant entry | inherited from Conduit; not yet Hermes-aware |

Hermes' own Bot Mode and teammate protocol map onto Grok Bot's "group of named bots", and the app already lists the roster. That is the strongest structural advantage: the ideas competitors just shipped are already in the backend.

## Gaps, ranked by how much they close the distance

### 1. The app never speaks first (highest impact, medium effort)

Muse's core promise is "comes back when it needs approval or something changes." Hermez only shows attention items when the app is open. Pending decisions are polled from a local store and refreshed on foreground.

- The gateway has `notification.show` / `notification.clear` events and `session.events.since`, and `session.active_list`. **None appear in the client.**
- The app has `flutter_local_notifications` (used for Conduit's voice call) but nothing Hermes-specific, and no push channel (no FCM, no WorkManager).
- Proposal, in order of cost: (a) a foreground service or periodic WorkManager task over the tailnet that asks `session.active_list` and pending approvals and raises a local notification ("kai needs approval to send this email"); (b) tap-through straight to the Attention sheet; (c) approve or deny from the notification when the action is unambiguous. No new server is needed, and it respects the rule of not adding another backend.
- Also: a "Since you were away" digest at the top of Home from `events.since` (runs finished, artifacts created, jobs that failed). Muse and Grok Bot both lean on this.

### 2. No voice, no wake word (high impact, medium effort)

Hermes exposes `voice.toggle`, `voice.record`, `voice.tts`, `wake.start`, `wake.status`, plus documented TTS across ten providers and "Hey Hermes". The Hermes code shows **0 files** using any of them. Conduit's own voice mode exists but talks to Conduit's stack, not Hermes bots.

- Proposal: hold-to-talk in the chat composer through `voice.record`, spoken replies through `voice.tts` with a per-bot voice (bots already have a mark and a personality; a voice completes the identity), then hands-free through the existing Android voice-interaction service. This is the cheapest route to feeling like Muse's voice mode.

### 3. Memory and skills are invisible (high impact, low to medium effort)

Grok Bot's pitch includes memory and teach-a-task. Hermes has MEMORY.md, USER.md, SOUL.md per profile, memory providers (Honcho, Mem0), a skills hub, and `skills.manage`, `skills.reload`, `learning.frames`. The app shows a skills count on Bot Detail and nothing more.

- Proposal: a Bot Detail "What kai knows" section (memory entries, read-only first, then edit/delete), "What kai can do" (skills, with enable/disable), and a "Save this as a skill" action on a finished run. Trust follows from being able to see and correct what the bot believes. The memory-provider and profile routers were not readable; probe the live gateway before committing to the read/write shape.

### 4. Bots cannot be created or shaped from the phone (medium impact, low effort)

`profiles.create`, `profiles.configure`, `profiles.describe`, `profiles.set_asset` exist. **0 files** use them. Today the roster is whatever exists on the Umbrel host. Grok Bot's "create a persistent named agent with a role" is the first thing a new user does.

- Proposal: a "New bot" flow (name, role/description, model, tool access), which also creates the identity mark from the name (the mark is already derived from it). Pair it with `session.compress` and `session.usage` to show cost and context left on Bot Detail.

### 5. Sessions API is barely used (medium impact, low effort)

Dashboard routes include `GET /api/sessions/search` (full-text search across messages), `PATCH` for archive/hide/pin/unread, `/export`, `/stats`, `/timeline`, `messages/around`. The app uses list, get, messages, and some PATCH. It does not use search or export at all.

- Proposal: real conversation search (it is the thing users reach for first once they have 90-message chats), pin/archive/unread on rows, and export/share of a chat as Markdown.

### 6. Bots do not talk to each other in view (medium impact, medium effort)

`bot_relay.*` and `subagent.*` events exist; the client handles `subagent.*` in two files but has no `bot_relay` support. Grok Bot's headline is bots passing work to each other in a group chat.

- Proposal: a "team" view on Home: bots working together on one task, shown as one thread with hand-offs visible (Kai researched, Strong verified). Kanban already models the work; this shows it live. Verify what the `bot_relay` contract actually delivers before designing UI.

### 7. Generated media, projects, browser control, and the rest (lower impact, pick by need)

| Gateway surface | Used? | Why it matters |
| --- | --- | --- |
| `image.generate` (eleven models via FAL) | No | Chat image generation; Muse's recipe-reel-to-list style tasks need vision plus generation |
| `projects.*` (discover repos, tree, project sessions) | 1 file | Group chats by project the way developers expect |
| `browser.manage` | No | Choose or restart the browser backend from the app |
| `process.list` | No | Show background processes a bot started |
| `complete.slash`, `commands.catalog` | Partial | Slash-command menu in the composer |
| `session.branch`, `session.foreign.*` | Branch only | Import chats from other tools |
| `pet.*` | No | Hermes' own companion character; the bot marks may make this redundant |
| `billing.*`, `subscription.*` | No | Only relevant if you use Nous Portal |
| `wake.*`, `voice.*` | No | See gap 2 |

Skip `pet.*` and `billing.*` unless there is a reason; do not build UI for a contract you cannot test.

## What not to copy

- **Purchases and payments.** Muse leads with checkout (Stripe Link one-time cards). Hermes has no payments surface, and this app should not grow one. A personal agent that buys things needs its own trust and safety work; keep approvals as the only way an irreversible action proceeds.
- **Avatar video and glasses.** Muse's real-time avatar and glasses are hardware and model bets, not app features. xAI is already retiring its own 3D companion mode.
- **A single shared cloud computer.** Grok Bot's bots share one computer and xAI itself says they are not separate security boundaries. Hermes profiles are separate, which is a real advantage; do not blur it in the UI.

## Suggested order

1. **Notifications and the "since you were away" digest** (gap 1). Biggest change in feel; no backend change.
2. **Voice through Hermes** (gap 2). Reuses the voice service; per-bot voice.
3. **Memory and skills view** (gap 3). Trust and differentiation; start read-only.
4. **Conversation search, pin, export** (gap 5). Small, and used daily.
5. **Create a bot** (gap 4), then **team view** (gap 6).

Each item needs a probe against the installed Hermes 2026.9.14 before UI work, because the method names above come from upstream `main`.

## What I could not verify

- The audio and memory-provider dashboard routers (rate-limited), so how memory is read and edited over HTTP is unknown.
- Whether the installed 2026.9.14 gateway has every method listed here; upstream is at v0.21.5.
- Anything about Muse and Grok Bot beyond press and vendor descriptions. Grok Bot access is limited to SuperGrok Heavy and Cursor plans, so its real behavior is not something I could test.
