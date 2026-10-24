# Conduit UX strategy: from dashboard to messenger

Status: proposal for owner review. Written 2026-10-24 by Claude, acting as principal product designer.

Inputs:
- ChatGPT's package `Conduit_Claude_UX_Implementation_Package`
- Current code on `fix/restore-unifiedpush-20261020`
- On-device screenshots, builds 213–214
- Public material on Meta Muse and xAI Grok Bot
- Design references: Emil Kowalski's design-engineering principles, Apple's *Designing Fluid Interfaces*, the journey method

Not a pixel spec. It decides **what changes, where, and why**, then the order to build it.

---

## 1. The diagnosis in one paragraph

Conduit already has the hard parts. It has real agents, truthful live state, approvals, delegation, push, and a strong visual identity. But it presents them like an **operator console**: every capability gets its own card, label and count. On Home the thing that needs you sits three screens down, under a six-card bot grid. In chat, one delegated question produced six separate pieces of chrome:
1. a "Delegated" chip
2. a "Delegated work" card
3. a worker card inside it
4. a "Delegated work came back" note
5. a "Delegate finished" chip
6. an action row under every message

Muse and Grok Bot feel calm for one reason: **the conversation is the product, and everything else is a quiet annotation on it.** That is the whole strategy.

## 2. What to borrow, precisely

| From | Pattern | Why it fits Conduit |
|---|---|---|
| Muse | **One long-running thread with Chief.** You can keep adding requests while it works. | That's how you already use Chief. The UI should stop treating each turn as a separate run. |
| Muse | **Activity is a summary first, a log second.** "Did X, next Y", with the full log one tap away. | Replaces the stack of tool chips with one line per turn. |
| Muse | **Irreversible actions leave the chat stream** for an explicit Approve / Review moment. | You already have real approvals; they just look like every other card. |
| Muse | **Results take the shape of the task** (itinerary, checklist), not long text. | You already have OpenUI/A2UI. Keep it as the only "rich" surface. |
| Grok Bot | **Agents are teammates with presence.** A chief of staff sits over specialists, and they hand off in threads. | Chief, Scout, Ops, Kai, HerMuse and Architect already are exactly this. Show them as people, not profiles. |
| Grok Bot | **"Only pulls you in for judgment calls."** | Home should show *judgment calls first* and work-in-progress quietly. |
| Messengers (WhatsApp, iMessage) | **"typing…" becomes "working…"** in the inbox preview; an unread dot means it needs you. | Zero learning cost. Everyone already reads these signals. |

What I'm deliberately **not** borrowing: Grok Bot's marketplace and team tabs, and Muse's goal-tracking layer. We don't have those backends, and inventing them would break the "real Hermes truth wins" rule.

## 3. Where I agree and disagree with the ChatGPT package

**Agree (adopt as is):**
- Conversation-first.
- Delegated work threaded under the turn that started it.
- An attention-first Home.
- No invented progress, ETA or "Chief summary".
- One logical row per real thing, with deduplication.
- Reuse the existing providers and motion.
- Approvals keep their single canonical host.

**Disagree or go further:**

1. **The reference image's "68%" progress bar and cream/amber palette are out.** The package says so itself, in its own fine print. We keep Hermez: charcoal canvas, signal accent, bot avatars, technical caps, physical morphs.
2. **No bottom tab bar.** Home *is* the inbox, and the drawer already holds the secondary places. Four tabs (Home / Chat / Projects / You) would split one inbox into two lists and add a permanent 64dp strip. Muse and Grok Bot are both inbox-plus-thread, not tabbed.
3. **No search field until search exists.** The package agrees. I'd go further: when search lands, make it pull-down-to-reveal (iOS Messages), not a permanent bar.
4. **Chief appears twice in the reference** (a hero row, then again in Conversations). Merge them: Chief is the pinned first conversation, plus **a "Message Chief…" composer docked at the bottom of Home**. That composer is my main addition. Home becomes a launchpad you can type into instantly, the way Muse's home *is* the thread.
5. **The package keeps a per-message action row.** I'd show copy, speak, retry and "…" only on the **latest** assistant message, and on long-press for older ones. That's the single biggest calm win in chat.

## 4. Home, redesigned

### What changes

| Today (top → bottom) | Proposed (top → bottom) |
|---|---|
| Large "Hermes / Y O U R  T H I N K I N G  P A R T N E R" title | Compact header: avatar presence, title, + |
| "Since you were away" card | Folded into Chief's row preview, plus one item in *Needs you* when actionable |
| BOTS 6 grid (about 1.5 screens) | **Removed.** Bots live as avatars in conversations, the + picker and the drawer |
| TODAY hero, ITEMS counter | One quiet line, "Later today · 2 routines", only when true |
| Schedule and Kanban tiles | Drawer |
| Recent (4) | **Conversations**, the main body of the page |
| Teams | Grouped into Conversations as group threads |
| Attention, Approvals and Artifacts tiles at the very bottom | **Needs you**, at the top, merged from the real sources |

### Wireframe (phone, dark)

```text
┌──────────────────────────────────────────┐
│ ≡   Conduit                    ◐◑◒    ＋ │  ← stacked avatars = who's working (live)
│                                          │
│ NEEDS YOU · 2                            │  ← hidden when empty
│ ● Approve sending the merchant follow-up │
│   Kai · draft ready        [Review] [✓]  │  ← simple ones resolve inline
│ ● Config change for payments service     │
│   Ops · needs a decision             ›   │
│                                          │
│ ◉ Chief                           10:18  │  ← pinned, the long-running thread
│   Asked Scout. PONG scout.               │
│ ◉ Kai                             9:52   │
│   working · checking service logs…       │  ← "typing…" idiom, accent text
│ ◉ Ops                             9:41   │
│   Test run complete. 2 minor warnings.   │
│ ◉◉ Launch planning (team)        Yday    │
│   HerMuse: next steps drafted            │
│                         Later today · 2 routines │
│ ┌──────────────────────────────────────┐ │
│ │ ＋  Message Chief…                  ◉ │ │  ← docked composer, sends to Chief
│ └──────────────────────────────────────┘ │
└──────────────────────────────────────────┘
```

### Why each piece exists

- **Header presence (stacked avatars).** It answers "is anything running?" without a section. Tapping it opens a sheet listing each working agent and its turn. It shows nothing when idle. This replaces both "Working now" and the "Delegated 1" context pill.
- **Needs you.** It's the only section with a heading, because it's the only one that asks something of you. Sources, all existing:
  - `hermesAttentionDecisionsProvider`
  - `approvalsPendingProvider`
  - `hermesAttentionPreparedProvider`
  - `hermesAttentionFailedJobsProvider`

  Merged and deduplicated by request id. The count in the title comes from the same list. A decision safe to resolve inline (an approval with a preview) gets **[Review] [✓]** right in the row. Everything else opens its thread at the exact turn.
- **Conversations.** A real messenger inbox. Each row has an avatar (36dp), name, time, a one-line preview, an unread dot, and a **live state that replaces the preview while an agent works** (accent-coloured "working · …", like "typing…"). Delegated child sessions don't appear as separate rows. They live inside the parent thread.
- **Docked composer.** "Message Chief…" sends straight into the Chief thread and morphs open into it, using the existing `HermezMorphOrigin`. The + still lets you pick another bot. This cuts the most common journey (open app → talk to Chief) from three taps to zero.

### Empty, stale and offline states

- **Nothing pending:** the Needs-you section disappears entirely. No "All clear" banner; the absence is the message.
- **No conversations yet:** a single line, "Start with Chief", and the composer. No fake agent placeholders.
- **Offline:** rows stay as last known with a "Not connected · Retry" line under the header. Live "working" states are suppressed while stale, because we never claim activity we can't see.

## 5. Chat, redesigned

### Principle: one turn shows one story

A turn is: your message → Chief's text → (an optional quiet work line) → (optional thread branches) → Chief's follow-up. Everything technical folds into the work line.

### Before and after, using the real PONG test from today

```text
TODAY (build 214)                          PROPOSED
───────────────────────────────            ───────────────────────────────
✓ Delegated ›                              Chief
┌ Delegated work ─────────────┐            Asked Scout.
│ 1 workers · 0 working · 1 c…│              │
└─────────────────────────────┘              └ ◉ Scout · Reply with PONG    ›
┌ ◉ scout   ● Complete ───────┐                  replied in 9s · mimo-flash
│ Reply with exactly the word…│            PONG scout
│ Complete · mimo-v2.6-flash ·│            ⧉  🔊  ↻  …    ← latest message only
└─────────────────────────────┘
Asked Scout.
⧉ 🔊 ↻ …
↵ Delegated work came back
✓ Delegate finished ›
PONG scout
⧉ 🔊 ↻ …
```

### Each element type, one hierarchy

| Element | Default presentation | On tap | Prominence |
|---|---|---|---|
| Tool activity (skills, searches, files) | **One line per turn:** "Worked 9s · 3 steps ›" in muted meta type | Unfolds the existing unified activity timeline in place | Lowest |
| Delegation, 1 agent | Thread branch: a 1dp rail from Chief's text, the agent's avatar (24dp), "Scout · goal", state as text | Expands in place: steps, Conversation, Open session, artifacts | Low |
| Delegation, 2+ agents | One branch header "3 agents · 2 working" with avatars stacked; children inside | Same | Low |
| "Came back" / "finished" notices | **Removed.** The branch's state flips to "replied in 9s", and Chief's follow-up reads as part of the same turn | — | — |
| Pending approval / your call | The **one** card we keep: a full outline, quiet surface, the question plus [Review] [Approve]. While pending it docks above the composer, so it can't scroll away | Existing review view | Highest, only while pending |
| Resolved approval | Shrinks to one audit line in history: "You approved · Send follow-up" | Opens the decision record | Low |
| File / artifact | An icon, the file name and its size | Existing artifact viewer | Medium |
| Browser session | An inline "Watch ›" on the work line | Existing Steel viewer | Low |
| Error | One plain line with the reason and **Details ›** | Technical detail | Medium |
| OpenUI / A2UI result | Unchanged. It *is* the answer, so it stays rich | — | Primary |

### Chrome around the thread

- **Action row:** on the latest assistant message only, plus long-press on any message for the same actions.
- **Timestamps:** hidden per message; one centred time label when 15+ minutes pass between messages (messenger idiom).
- **Context bar** ("Delegated 1", model pill): the model goes into the composer's + menu. Live delegation shows as a small stacked avatar on the header avatar. The bar disappears.
- **Header:** keep the avatar collapse you just tuned. Subtitle = live state ("Scout is working…") when true, else nothing.
- **Naming:** the default profile shows as "Default" everywhere. Display it as **Chief** (the profile id stays `default`). It's how you and SOUL already refer to it, and it makes every surface read like a team.

## 6. Visual identity: what stays, what bends

**Theme modes (owner, 2026-10-24):**
- **Dark mode:** a charcoal canvas (`#111215`) with charcoal surfaces.
- **Light mode:** a white canvas. Today's light canvas is `#F7F7F7`; move it to white, and give surfaces a faint grey (around `#F4F4F5`) so rows and the approval card still separate.
- **The navbar stays reversed:** dark in light mode, light in dark mode, as the user bubble already is. The docked "Message Chief…" bar on Home stays on the normal surface colour, so the navbar remains the only reversed chrome.

**Stays:** the charcoal (dark) / white (light) canvas; the single signal accent (red/orange) used for live state, selection and the primary action only; the anime bot avatars (circular, no fill); `HermezType`; technical uppercase for the few section labels (NEEDS YOU); the Nib springs and morph-from-origin navigation; the slash/arc/crop motifs.

**Rules I'd bend, and why:**

| Your rule | Bend | Why it's an improvement |
|---|---|---|
| No hairlines | A **1dp, low-opacity thread rail** connecting a branch to its turn. It's a connector, not a separator between cards. | It's the cheapest way to say "this belongs to that message" without a box. Messages (iOS) and Slack threads use it. |
| Status = soft tinted pill with a dot | In chat and the inbox, status becomes **text with a small dot, no pill** ("● working", "replied in 9s") | Pills on every row are the "everything is a chip" noise we're removing. Pills stay for real controls. |
| Motifs on surfaces | Motifs appear **only on the Chief row and the empty state**, not on every tile | One signature moment reads as brand; a motif on every card reads as texture. |
| Letter-spaced subtitle "Y O U R  T H I N K I N G…" | Dropped from Home | It costs a full line above the fold every launch. The brand lives in the avatars and accent. |

## 7. Motion and feel

Visual QA covers both modes equally. Check light mode against the white canvas and dark mode against charcoal, and check the reversed navbar in both.

Use the existing Nib springs: critically damped by default, never bouncy for state changes.

| Moment | Motion | Rule it follows |
|---|---|---|
| Branch expand / collapse | Height grows from the tapped row and pushes later messages; the chevron rotates; the scroll stays anchored | Apple: spatial consistency. Fold back along the same path. |
| Agent state change | Crossfade only the state text (≈150ms ease-out). No avatar pulse loops. "Working" uses one static accent ring, not a spinner | Emil: frequent events animate least. |
| Approval docking | Slides up from the composer edge; resolves in place: disabled → "Approving…" → audit line | Feedback on press. No premature success. |
| Composer → Chief thread (Home) | The existing morph from origin, so the composer grows into the thread | Origin-aware motion |
| Row press | Scale 0.97, 100–160ms | Instant press feedback |
| Reduce motion | Opacity crossfades only | Accessibility |

Haptics: approve/deny and expand only, never passive progress.

## 8. Build order

Each step ships on its own and is QA'd on the S25 before the next.

1. **Chat calm (largest daily impact, lowest risk).** Action row on the latest message only; one work line per turn; delegation as a thread branch; remove the came-back/finished notices; drop the context bar; display "Chief". Files: `hermes_turn_delegation.dart`, `hermes_inline_delegation.dart`, `hermes_delegated_worker_card.dart`, `hermes_unified_activity_timeline.dart`, `hermes_chat_context_bar.dart`, `assistant_message_widget.dart`, `user_message_bubble.dart`.
2. **Approvals as the one card.** Composer docking while pending, an audit line after. Files: `hermes_approval_card.dart`, `hermes_pending_decision_store.dart` (read-only use), `chat_page.dart` (surgical).
3. **Home inbox.** Header presence, Needs you (merged sources), the conversation inbox with live state, the docked composer, and moving the secondary places to the drawer. Files: `hermes_home_page.dart` (rewrite of the build tree; keep every route), `hermes_session_tile.dart`, `hermes_home_presence.dart`, `hermes_attention_page.dart` (providers reused, page kept as "See all").
4. **Polish pass.** Motion tuning frame-by-frame; dark and light; 200% text; narrow phone; TalkBack labels; before/after screenshots against this doc.

Explicitly out of scope: server changes, new APIs or polling, a new navigation framework, search.

## 8b. Owner decisions (2026-10-24) and how they were built

- **Bottom dock, not drawer.** On phones, Home is a tab shell (Home / Chats / Work / You) with a floating pill dock. It's drawn in the **opposite theme**, the material of the side navigation it replaces (dark under a light app, light under a dark one). It moves on the side navigation's curve:
  - the selection glides between tabs
  - tabs settle in with the 30ms stagger
  - an arriving tab slides 18dp from the side it came from, with no fade
  - the dock slides away while the keyboard is up

  Code: `widgets/hermes_tab_dock.dart`, `views/hermes_tab_shell.dart`. Tablets keep their sidebar.
- **Progress bars, only where the fraction is real.**
  - A delegation batch shows "2 of 3" with a bar of finished workers over total.
  - The plan pill shows its done/total steps as a bar.
  - A single delegate has no bar, because Hermes reports no fraction for it. A "68%" there would be invented.
- **"Chief"** is the display name for the `default` profile everywhere (`hermesProfileDisplayName`).
- **The action row** shows on the newest Hermes answer only. Older answers keep long-press text selection, which offers the system Copy.

## 8c. Second polish pass (2026-10-24, evening)

The owner said the UI still felt messy and asked for:
- one navigation
- seamless inline elements everywhere except A2UI and OpenUI
- Home and Work swapped

What changed:
- **One navigation on phones.** Hermes phones use the dock only. The drawer is gone there (`hermesPhoneUsesDock`), and a chat's leading control is a back arrow to Home.
- **Home and Work swapped.**
  - **Home** is now the hub: Team, Work (schedules, Kanban, Teams, Spaces, Artifacts), Decisions and Hermes. Its top bar is the masthead: "Conduit" at the left, the editorial construction marks behind the bar, and the working-bots stack plus the **+** for a new chat at the right (`HermesPageChrome.brandHeader`).
  - **Work** is now what needs you and what's running: Needs you, the conversation inbox, later today and the away digest. The Needs-you dot moved to the Work tab.
  - Tablets are unchanged: the inbox page is still their first page, with + and Profile.
- **Thinking, inline and kept.**
  - Hermes saves a short reasoning summary on every answer (for example "Validating card layout"). Conduit now maps it from the transcript, so it survives reloads.
  - While the model thinks, the activity line shows the current thought. Tapping the line unfolds the thoughts as quiet lines on the rail, ahead of the tool steps.
  - When the run ends, the unfolded steps fold back into one line ("Thought · Validating card layout") instead of disappearing.
  - A turn with nothing to show rolls its line away rather than popping it out.
- **A stalled model says so.** Hermes's provider-wait notice ("⏳ waiting on gpt-6-luna…") used to be dropped. It now drives the activity line: "gpt-6-luna is slow to reply", then "· retrying soon" near the watchdog. It clears when the model answers. The "endless thinking" on 2026-10-24 was a 300 s upstream stall that Hermes's watchdog retried; the app was not at fault.
- **Run details without boxes.** The unfolded steps now carry most of the old sheet:
  - a meta line (model · time · steps)
  - tool steps that open the existing tool inspector
  - the watch-only Steel browser, as a "Watch the browser" line that unfolds the player in place, with a full-screen button

  The "Full run details" sheet is still there for everything else, but its sections sit on the canvas with no panel boxes.

### Later the same evening: no sheets in chat

The owner asked for:
- full run details without a sheet
- livelier inline elements
- the sheets that popped up in chat folded into the line

What changed:
- **Full run details unfold in place** under the answer's steps (`HermesLiveRunPage(inline: true)`).
  - No chrome, headline or completion sheet; the run's parts sit on the rail.
  - It contains the timeline with folded outputs, the plan, errors, Steer and Stop.
  - A pending question opens the steps and details by itself.
  - The short step list hides while the full timeline shows, so nothing repeats.
- **Tool steps unfold their input and result** under the line (`HermesToolInspectorInline`), with the run switcher and copy, instead of the inspector sheet.
- **Questions and approvals are answered inline** (`HermesAttentionResolutionInline`), under the question row, with the same send path. A lone question opens itself.
- **Plan and delegates pills unfold a tray above the composer**, the way agent chats attach a plan or queue to the input. The pill turns to ink while its tray is open. The model pill stays a picker.
- **The whole turn is one answer.** An activity line now covers every message from the owner's prompt to the next one, including the async continuation after Hermes's hidden `[ASYNC DELEGATION …]` wake-up. Later pieces of the turn show no second line.
- **Motion.**
  - A working label carries a light band moving across it (`HermezShimmerText`), and new labels rise in as the old ones leave.
  - Each step rises 6 dp into place once.
  - Chevrons turn as things unfold.
  - All of it stops under reduced motion.
- **Near-white:**
  - The light canvas is `#FDFDFD`.
  - A2UI and OpenUI panels sit on that canvas with the border token only (`hermezGenerativeTheme`), instead of the grey `#F5F5F6` surface.
  - Dark mode is unchanged.
- **Back from a chat** returns to the dock tab it was opened from.

## 9. Decisions I needed from you (answered: all yes, with the dock at the bottom)

1. **Docked "Message Chief…" composer on Home.** I recommend yes.
2. **Display the `default` profile as "Chief".** I recommend yes.
3. **Bottom tab bar or drawer.** I recommend keeping the drawer, with no tabs.
4. **Action row on the latest message only.** I recommend yes.

## Sources

- [Meta introduces Muse (The Rundown)](https://www.therundown.ai/news/meta-muse-personal-ai-agent)
- [Meta Muse personal AI agent (onlinemarketing.de)](https://onlinemarketing.de/technologie/meta-muse-persoenlicher-ai-agent)
- [Muse UX analysis (woshipm)](https://www.woshipm.com/ai/6471448.html)
- [Introducing Grok Bot (xAI)](https://x.ai/news/introducing-grok-bot)
- [Grokbot agent app overview (MindStudio)](https://www.mindstudio.ai/blog/grokbot-xai-agent-app)
- [Grok Bot messenger launch (Forklog)](https://forklog.com/en/news/spacexai-launches-grok-bot-messenger-with-ai-agents)
