# Build 223: fixes for the build-222 phone QA — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (chosen: native, one reviewer at the end). Steps use checkbox (`- [ ]`) syntax.

**Goal:** Fix everything wrong in `QA-BUILD-222.md`, without changing anything the owner's design rules do not ask for:
- a run that never settles after reopening the chat
- no live state on a new chat's first message
- a turn line that forgets its earlier work
- the blank gap
- the lingering plan pill
- raw tool JSON
- a Steel player stuck on "connecting"
- the small visual issues

**Architecture:** every fix is local to the code that causes the bug. No new providers or services, and no navigation changes.
- **Transport fixes (Tasks 1–2)** change when a Hermes stream is finished, and from which ref.
- **Chat fixes (Tasks 3–5)** change how a turn's rows are grouped and labelled.
- **Display fixes (Tasks 6–8)** are pure presentation.

**Tech stack:** Flutter, Riverpod 3.4.3 (`flutter_riverpod`), flutter_test.

**Spec:** `docs/ux-redesign-2026-10-24/QA-BUILD-222.md` (findings), with `HANDOFF.md` §1 (owner rules) and §3 (code map).

## Global constraints

- **Owner rules, inside a chat:** no cards, and no sheets except the model picker. Finished lines fold and never disappear. Use the accent (`palette.accent`) on inline elements.
- **No rule bends** except one: Task 8.2 bends the "calm header, avatar never moves" choice from `38fab7ad`, because the owner flagged the off-centre avatar.
- **Edits:** CRLF files on disk, so use the Edit tool. Run `dart format` only on the files touched.
- **Tests and analyze:**
  - Run tests with `--concurrency=1`, never at the same time as a build.
  - These failures already existed and stay as they are: `hermes_activity_presenter_test` "store a new turn drops finished delegates…", `hermes_inline_run_surface_test` ×2, `direct_send_history_links_test`.
  - `flutter analyze lib/features/hermes lib/features/chat` must add no new warnings.
- **Commits** stay local on `fix/restore-unifiedpush-20261020`. No push.

## Review focus

The inputs most likely to bite that the tests below do not exercise directly, each with the test that now pins it:

1. **The owner leaves a chat mid-run and never comes back** (another chat is opened). The run must still finish and persist without throwing. Pinned by Task 1 test b.
2. **A brand-new chat whose session reports `running:false` before any turn activity, then really finishes.** The stream must still end. Pinned by Task 2 tests b and c.
3. **A turn whose wake-up run never reached this connection** (app reconnected). The line must not pull in the previous turn's run. Pinned by Task 3 test c.
4. **A Hermes row that is the group's header** (shows the activity line) with empty text and only a `reasoning` status. It must not collapse. Pinned by Task 4 test b.
5. **A plan left unfinished in an earlier turn.** It must stay visible as "Paused". Pinned by Task 5 test c.

---

### Task 1: A run survives leaving the chat (F1)

**Root cause:**
- `ChatPage` passes its own `WidgetRef` down the send path. It goes through `durableSend` and `_sendMessageInternal` (`lib/features/chat/providers/chat_providers.dart:~11321`), then `_dispatchHermesRunFromChat` (`:12889`).
- Every visible update (`owner.isActive(ref)` at `:12035`, `updateProjectionIfOwned`, `appendProjectedContent`, `finishOwned` at `:13402-13506`) calls `ref.read`.
- Back on a docked phone runs `context.go(Routes.hermesHome)`, which unmounts `ChatPage`. Riverpod's `ConsumerStatefulElement._assertNotDisposed` then throws `StateError` on every `ref.read`.
- So the final text is never appended and `finishStreamingMessage` never runs; the row stays `isStreaming`.
- On reopen, `_shouldProtectLocalStreamingState` keeps that stale streaming tail and refuses the server snapshot.

**Secondary (F1b):** the same protection also keeps a *restored* running placeholder (`isRestoredHermesDesktopRunningMessage`) from being replaced by a settled transcript on a later reopen.

**Files:**
- Modify: `lib/features/chat/providers/chat_providers.dart`
  - top of `_sendMessageInternal` and of `_dispatchHermesRunFromChat`
  - the `catch` near `:17637`
  - the protection check near `:3978`
- Test: `test/features/chat/providers/chat_messages_notifier_streaming_seams_test.dart`

**Interfaces:**
- Produces: `dynamic hermesDetachedRef(dynamic ref)` (file-private `_detachedRef` is fine), in `chat_providers.dart`.
  - Returns `ProviderScope.containerOf(ref.context, listen: false)` when `ref is WidgetRef`; otherwise returns `ref` unchanged.

Steps:
- [ ] **Step 1: write two failing tests.**
  - **a.** `'Hermes reply finishes after the chat page unmounts'`:
    1. Capture a `WidgetRef` from a `Consumer` under `UncontrolledProviderScope(container: _testContainer(...))`.
    2. Send through `sendMessage(pageRef, …)` with `_SessionRecordingHermesApi(events: controller.stream)`, as in the Hermes send test at about `:1554`.
    3. Wait until the run starts, then `tester.pumpWidget(const SizedBox.shrink())`.
    4. Emit `HermesTokenDelta('OK')`, then `HermesRunDone()`.
    5. Expect `container.read(chatMessagesProvider).last.content == 'OK'` and `.isStreaming == false`.
  - **b.** The same setup, but after unmounting set the active conversation to a different conversation. Expect no exception (wrap in `runZonedGuarded` and collect errors; there must be none). Expect the projection store to finalize, so `projectionStore` reports no live projection for the message.
  - **c.** A restored-placeholder tail (`isRestoredHermesDesktopRunningMessage` true), then the active conversation is set to the same id with a settled server transcript. Expect the settled messages to be adopted. Put it next to the existing protection test at about `:5796`.
- [ ] **Step 2:** run the file and confirm a and c fail. a fails because content stays `''`, or because of the StateError.
- [ ] **Step 3: implement the fix.**
  - Call `ref = _detachedRef(ref);` as the first statement of both `_sendMessageInternal` and `_dispatchHermesRunFromChat`, and use the converted ref in the `catch` near `:17637`.
  - In the protection check, return false when `isRestoredHermesDesktopRunningMessage(state.last)`.
  - In the dispatch path, grep for WidgetRef-only members used on `ref` (`watch`, `listenManual`, `context`, `mounted`). Replace `listenManual` with `listen` (a `ProviderContainer` has `listen`), and close that subscription where the old one was closed (the `finally` at about `:13290`).
- [ ] **Step 4:** run the file, and the whole of `test/features/chat`; everything passes except the known failures.
- [ ] **Step 5: commit** "Keep a Hermes run's reply when its chat page closes".

### Task 2: A new chat's first message gets live state (F3)

**Root cause:**
- In `lib/features/hermes/services/hermes_desktop_turn_runtime.dart`, `session.create` answers without `running`, so a fresh session is parked at `unsupportedGateway`. The prompt-ack sets running only `if (hasAuthoritativeState())` (`:383`), so the orb never shows as running.
- Hermes then emits a session-build `session.info` with `running:false` (`tui_gateway/server.py`: `_session_info` always sets `"running": bool(...)`).
  - If that frame arrives before or around the prompt ack, it reaches `case 'session.info'` (`:244-254`) with `promptAcknowledged == true` and calls `finish(authoritativeIdle: true)`.
  - The stream ends within seconds: copy and regenerate appear, there is no stop button, and the line shows ✓ while tools keep arriving through the service-level activity.
  - This last step is inferred from the code; the device log in Task 9 confirms or refutes it.

**Files:**
- Modify: `lib/features/hermes/services/hermes_desktop_turn_runtime.dart`
- Test: `test/features/hermes/hermes_desktop_turn_state_test.dart` (uses `_GatewayHarness`)

**Interfaces:** none new. Local state inside `_runtimeStreamDesktopResponse`: `var turnActivitySeen = false;`.

Steps:
- [ ] **Step 1: write the failing tests.**
  - **a.** `'a fresh session is running once its first prompt is accepted'`:
    1. `session.create` with no `running`; `prompt.submit` → `{'status':'streaming'}`.
    2. `streamDesktopResponse(...)`, then expect `turnStateFor(id) == running`.
    3. Push `sessionInfo(running:false)` after a `message.start`, then expect `idle` and a `HermesRunDone`.
  - **b.** `'an idle session.info before any turn activity does not end the stream'`:
    1. Fresh session; push `session.info {running:false}` before the ack resolves, and once more right after it.
    2. Expect no `HermesRunDone`.
    3. Then push `message.start`, `message.delta`, `session.info {running:false}`, and expect a `HermesRunDone`.
  - **c.** `'an early idle frame is reconciled when no turn activity follows'`:
    1. Use fake async. The early `running:false` arrives with no activity after it.
    2. After `_earlyIdleRecheck` (5 s), `session.resume` reports `running:false`.
    3. Expect a `HermesRunDone`. When resume reports `running:true` instead, expect none.
- [ ] **Step 2:** run it and confirm a and b fail.
- [ ] **Step 3: implement the fix.**
  - At the ack: `if (hasAuthoritativeState() || freshSession) _applyAuthoritativeRunning(true, …)`. Use the same in the delivery-ambiguous "accepted" branch.
  - In `handleEvent`, set `turnActivitySeen = true` for any acknowledged event of type `message.*`, `tool.*`, `thinking.*`, `reasoning.*`, `subagent.*`, `*.request`, or a `session.info` with `running == true`.
  - In `case 'session.info'` with `running == false`:
    - finish only if `turnActivitySeen`;
    - otherwise schedule once a `Timer(_earlyIdleRecheck)` (`const Duration(seconds: 5)`). It runs `_resumeSnapshot(storedId, refresh: true)` and calls `finish(authoritativeIdle: true)` when `!terminal && !turnActivitySeen && reconciled.running != true`.
    - Cancel the timer in `finish`.
- [ ] **Step 4:** run `hermes_desktop_turn_state_test.dart` and every `test/features/hermes/hermes_desktop_*` test; they pass.
- [ ] **Step 5: commit** "Give a new Hermes chat's first run its live state".

### Task 3: A turn's line describes the whole turn (F2)

**Root cause:**
- In `lib/features/hermes/widgets/hermes_run_activity_orb.dart:86-131`, the thoughts come from every row of the turn. But the label, steps and meta come from `HermesRunSummary.latest(events)`, which is only the last terminal-delimited run.
- A delegation wake-up is a separate run.

**Files:**
- Modify:
  - `lib/features/hermes/services/hermes_live_activity.dart`
  - `lib/features/hermes/widgets/hermes_run_activity_orb.dart` (span, summary, meta, steps, step text, `_RunSteps` cap)
  - `lib/features/hermes/services/hermes_run_history.dart` (wake-up boundary)
- Test:
  - `test/features/hermes/hermes_run_summary_test.dart`
  - `test/features/hermes/hermes_run_inline_details_test.dart`
  - `test/features/hermes/hermes_unified_run_activity_test.dart`

**Interfaces (produces):**
- `factory HermesRunSummary.recent(List<HermesLiveActivityEvent> history, {required int runs, required bool running})`
  - The last `runs` terminal-delimited runs, with the open run counting as one while `running`.
  - `runs: 1` equals `latest`.
  - Clock-free: it counts terminal events and never compares timestamps.
- `HermesTurnSpan` gains `int runs`: 1 + the number of `hermesIsDelegationResultNotice` user rows inside the span.
- `int hermesToolCallCount(List<HermesActivityRow> rows, List<ChatStatusUpdate> statuses)`
  - The sum of `row.count` when there are rows; otherwise the number of non-hidden statuses with a tool name.
  - Thoughts, delegate notes and "Waiting for you" are not counted.

Steps:
- [ ] **Step 1: write the failing tests.**
  - **a.** Summary test. Run 1: `skill_view`, `skill_view`, `todo`, `delegate_task`, completed at 20 s. Run 2: `todo`, completed at 63 s.
    - `recent(runs: 2, running: false)` has 5 tool starts and `elapsed() == 62s`.
    - `recent(runs: 1)` equals `latest`.
    - While running with an open third run, `recent(runs: 2)` covers runs 2 and 3.
  - **b.** Inline-details test: `hermesRunSteps(rows([todo started with preview 'updating 3 task(s)']), const []).single.text == 'Updated plan'`. The plan family drops its object.
  - **c.** Unified activity test:
    - Setup: messages [u1, a1 (tools: `skill_view` ×2, `todo`, `delegate_task`), notice "[ASYNC DELEGATION …]", a2 (`todo`)], with the two-run history above, idle.
    - The line reads "Delegated and 2 more" (housekeeping skipped). Unfolded, it shows "Opened skill ×2", and the meta contains "5 steps".
    - **Variant (review focus 3):** the history holds an earlier unrelated run plus only run 1 (the wake-up run is missing). The turn shows run 1 only, because the backstop keeps the steps at or below the status count.
  - **d.** `_RunSteps`: 9 thoughts plus 2 tool steps. Both tool steps are visible.
- [ ] **Step 2:** run the tests and confirm they fail.
- [ ] **Step 3: implement the fix.**
  - **Line, steps and meta:**
    - Build the turn's run with `HermesRunSummary.recent(events, runs: span.runs, running: running)` and use it for the label, steps and meta.
    - Keep `HermesRunSummary.latest(...)` only for `hermesRunUsedBrowser` (the Steel section).
    - **Backstop** (only when settled): if `run.steps` exceeds the status tool count while the status count is above 0, reduce `runs` one at a time until it fits. If the rows still don't match, pass empty rows, so the turn-wide statuses drive the label and steps.
  - **Meta:** `hermesToolCallCount(rows, statuses)`, without the `math.max`.
  - **Step text:** join `verb · object`. Drop the object for `HermesActivityFamily.plan`.
  - **Label:** when settled, the lead skips housekeeping verbs (plan, find-tool, open-skill), the same way `prep` does today for skills.
  - **`_RunSteps`:** cap thoughts at 6 and tool steps at 8, separately, each with its own "N more".
  - **`hermes_run_history.dart`:** `hermesCurrentAnswerMessages` and `hermesAnswerTranscript` do not stop at a user row for which `hermesIsDelegationResultNotice(content)` is true.
- [ ] **Step 4:** run all of `test/features/hermes`; it passes except the known failures.
- [ ] **Step 5: commit** "Describe the whole turn on its activity line".

### Task 4: No blank gap from empty continuation rows (F7a, HANDOFF §7.2)

**Root cause:** `debugCanCollapseGroupedAssistantRowForTesting` (`lib/features/chat/views/chat_page.dart:5522`) requires `statusHistory.isEmpty`. Since `bacea16c`, each Hermes row keeps a `reasoning` status, and on a unified-activity row that draws nothing. Each such row leaves an empty `Container(margin: bottom 16)`. The call site (`:3605`) also only collapses rows whose tool statuses moved.

**Files:**
- Modify: `lib/features/chat/views/chat_page.dart` (the predicate and the call site)
- Test: `test/features/chat/assistant_group_header_test.dart`

**Interfaces:** the predicate gains a check that the message is a Hermes row: `transport == kHermesTransport` and a valid `hermesSessionId`. Such a row counts as empty when every status is non-tool (not `hermes_tool_*`).

Steps:
- [ ] **Step 1: write the failing tests.**
  - **a.** An empty Hermes-transport row with `[reasoning]` collapses (`showModelHeader:false, showActionBar:false` → true).
  - **b.** The same row with `showModelHeader:true` stays false. That row hosts the line (review focus 4).
  - **c.** The same row without Hermes metadata stays false.
  - **d.** A Hermes row with an `error` stays false.
- [ ] **Step 2:** confirm a fails.
- [ ] **Step 3: implement the fix.**
  - Predicate: `(hermesRow ? statusHistory.every((s) => !_isHermesToolStatus(s)) : statusHistory.isEmpty)`.
  - Call site: collapse when `(statusesMoved || hermesRow) && canCollapse`.
  - Keep `leadsElsewhere` as it is: it only hides a duplicate line under a row that already has text.
- [ ] **Step 4:** run `test/features/chat` and `test/features/hermes`.
- [ ] **Step 5: commit** "Collapse empty Hermes continuation rows".

### Task 5: The plan pill belongs to its turn (F7b)

**Files:**
- Modify: `lib/features/hermes/widgets/hermes_chat_context_bar.dart`
- Create: `test/features/hermes/hermes_chat_context_bar_test.dart`

**Interfaces (produces):** `bool hermesLatestTurnUsedPlan(List<ChatMessage> all)`, in `hermes_chat_context_bar.dart`.
- Walk back from the end.
- An owner user row that is not a delegation notice → false.
- An assistant row with a status whose `hermesStatusToolName` is `todo` or `todo_list` → true.

**Rule:**
- `planVisible = plan != null && !plan.isEmpty && sessionId != null && (plan.hasActiveWork || latestTurnUsedPlan)`.
- Use it for both the pill and the tray (`showPlan`).
- Read it with `ref.watch(chatMessagesProvider.select(hermesLatestTurnUsedPlan))`.

Steps:
- [ ] **Step 1: write the failing tests.** Each uses a 3/3 completed snapshot, idle.
  - **a.** [u1, a1 with a `todo` status, u2, a2] → no `ctx-plan`.
  - **b.** [u1, a1 with a `todo` status] → `ctx-plan` is shown.
  - **c.** A snapshot with 1 of 3 pending and history a → `ctx-plan` is shown with "Paused".
- [ ] **Step 2:** confirm a fails.
- [ ] **Step 3:** implement the rule.
- [ ] **Step 4:** run the new test, then `test/features/hermes`.
- [ ] **Step 5: commit** "Show the plan pill only for the plan in play".

### Task 6: Readable tool text, and no "0.0s" (F4)

**Files:**
- Modify:
  - `lib/features/hermes/sheets/hermes_tool_inspector_sheet.dart` (`hermesReadableToolText`, the "Took" fact)
  - `lib/features/hermes/services/hermes_activity_presenter.dart` (`durationLabel`)
  - `lib/features/hermes/widgets/hermes_activity_view.dart` (2 duration sites)
- Test: `test/features/hermes/hermes_activity_presenter_test.dart`

**Interfaces (produces):** `static String? HermesActivityPresenter.durationLabel(Duration? d)`. It returns null when `d == null || d.inMilliseconds < 100`, else `formatDuration(d)`.

**Rendering rules** for `hermesReadableToolText`:
- Strip the untrusted-content notice as today. Non-JSON text and invalid JSON pass through unchanged.
- `{"calls":[{name, arguments}]}` with exactly one call becomes its `arguments`, decoded first if it is a JSON string.
- Rendering is recursive, YAML-like, with 2-space indents:
  - Top-level key order stays: `output, result, code, command, query`, then the rest.
  - A scalar is `key: value`.
  - A multi-line string, or one over 80 characters, is `key:` followed by the string on its own lines, indented one level below the key; a top-level key's string is not indented.
  - A map is `key:` followed by its children.
  - A list of scalars is `key: a, b, c`, or bullets when that line would be over 80 characters.
  - A list of maps is `key:` followed by `- ` items, each item's further keys aligned under its first.
  - Deeper than depth 4, the subtree becomes compact JSON.
- No hard wrapping: Copy must stay faithful.

Steps:
- [ ] **Step 1: write the failing tests.**
  - The todo `calls` envelope renders exactly:
    ```
    merge: true
    todos:
      - content: Create this three-step QA plan
        id: qa-plan
        status: completed
    ```
  - `{"exit_code":0,"output":"a\nb"}` → `output:\na\nb\nexit_code: 0`.
  - The notice is stripped; plain text is unchanged; invalid JSON is unchanged; depth 5 falls back to compact JSON.
  - `durationLabel(20 ms) == null` and `durationLabel(1200 ms) == '1.2s'`.
- [ ] **Step 2:** confirm they fail.
- [ ] **Step 3:** implement, and use `durationLabel` at the three sites. The "Took" fact is omitted when the label is null.
- [ ] **Step 4:** run `test/features/hermes`.
- [ ] **Step 5: commit** "Show tool input and results as readable text".

### Task 7: The Steel player reloads once the browser session exists (F5)

**Root cause:**
- "Session connecting..." is Steel's own page inside the WebView.
- The section mounts at the first browser `tool.start`, before Hermes has created a Steel session, and nothing ever reloads it.
- This is inferred: the device check in Task 9 confirms it. Network or a different backend are the alternatives.

**Files:**
- Modify:
  - `lib/features/hermes/widgets/hermes_steel_live_view.dart` (`HermesRunBrowserSection`)
  - `lib/features/hermes/widgets/hermes_run_activity_orb.dart` (passes the token)
- Test: `test/features/hermes/hermes_steel_viewer_test.dart` (the `viewerBuilder` seam)

**Interfaces:**
- `HermesRunBrowserSection({…, int refreshToken = 0})`.
- The orb passes `hermesBrowserToolsCompleted(run) > 0 ? 1 : 0`. This new helper lives next to `hermesRunUsedBrowser` in `hermes_inline_run_surface.dart` and counts browser `toolCompleted` events.
- The viewer sits in `KeyedSubtree(key: ValueKey('steel-$refreshToken-$_manualReloads'))`.
- A refresh `IconButton` (`Icons.refresh_rounded`, tooltip "Reload the browser view") next to the full-screen button bumps `_manualReloads`.

Steps:
- [ ] **Step 1: write the failing test.** A probe viewer counts `initState`. Pump with token 0, then token 1, and expect 2. Pump token 1 again and expect still 2. Tap refresh and expect 3.
- [ ] **Step 2:** confirm it fails.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** run the steel test file, then `test/features/hermes`.
- [ ] **Step 5: commit** "Reload the watch-only browser once its session exists".

### Task 8: Small visuals (F7c)

**Files and fixes:**
1. **Delegate dot:** `lib/features/hermes/widgets/hermes_delegated_worker_card.dart:~564`. Pass `ink: palette.accent` when the worker is completed.
   - Test: `test/features/hermes/hermes_inline_delegation_test.dart`. The `HermezLiveDot.ink` equals the accent.
2. **Header centre:** `_HermesBotToolbarTitle` (`lib/features/chat/views/chat_page.dart:287`).
   - The name's `Align` uses `widthFactor: 1 - collapse` inside a `ClipRect`.
   - The working dot's width is removed in proportion to the collapse.
   - Collapsed, the group is the avatar alone, so it centres.
   - **Rule bent:** "avatar x never moves" from `38fab7ad`. The avatar now glides about 25 dp to centre, in step with the scroll collapse, because the owner flagged the off-centre avatar.
   - Test: rewrite `test/features/chat/hermes_bot_header_collapse_test.dart:192-222`. When collapsed, the avatar centre is `closeTo(screenCentre, 0.5)`.
3. **Chats list:** `lib/features/hermes/widgets/hermes_session_tile.dart:~229`.
   - Put `SizedBox(width: Spacing.sm)` before the spinner.
   - While the open chat is generating, the compact subtitle's time reads "Working now".
   - Test: `test/features/hermes/hermes_session_tile_test.dart`. Spinner left ≥ title right + 8.
4. **Home Team row:**
   - Extract `Set<String> hermesWorkingProfiles(WidgetRef ref)` from the masthead stack in `lib/features/hermes/widgets/hermes_home_working.dart`, so the stack and `HermesWorkPage` share it.
   - `HermesWorkTeamRow` gains `bool working`. Its status shows "Working…" in accent when `working || running`.
   - Match on `hermesProfileDisplayName`, case-insensitive.
   - Test: `test/features/hermes/hermes_work_page_test.dart`, with the active-work override. "Working…" shows once.

Steps:
- [ ] **Step 1:** write the four failing tests.
- [ ] **Step 2:** confirm they fail.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** run `test/features/hermes` and `test/features/chat`.
- [ ] **Step 5: commit** "Tidy the delegate dot, header centre, chat list and Home team status".

### Task 9: Verify, build 223, and phone QA

- [ ] **Step 1:** run `flutter analyze lib/features/hermes lib/features/chat`: no new issues.
- [ ] **Step 2:** run the full `test/features/hermes test/features/chat` suite, then `test/core`. Only the known failures remain.
- [ ] **Step 3:** kill the Gradle daemons, build `--profile --build-number 223` with the Steel define, install it, and kill the daemons again.
- [ ] **Step 4: phone QA** (Conduit in front, guards on).
  1. **New chat**, plan + Scout prompt.
     - The live orb, shimmer and stop button appear from the first second.
     - The finished line names the real work, and its steps include the skills, todo and delegate.
     - The meta time covers the whole turn.
     - There is no gap above the Scout branch.
     - The Scout dot is accent.
     - Run `adb logcat` during the first send to confirm the early `session.info` theory from Task 2.
  2. **Browser prompt.**
     - The player draws the page after the first navigation.
     - Chief's answer has no viewer URL (this is a new session, so the new SOUL applies).
     - The plan pill is gone, because this turn has no plan.
  3. **Sleep-40 prompt**, then Back, Chats, reopen.
     - "OK" appears and the stop button clears.
  4. **Tool step.** Unfold it: the todo list is readable, with no "Took 0.0s".
  5. **Header and lists.**
     - Scroll to the top: the avatar is centred.
     - In Chats, the spinner sits clear of the title.
     - On Home, the team row says "Working…" during a run.
- [ ] **Step 5:** write `QA-BUILD-223.md`, update `FINDINGS-BACKLOG.md`, delete the screenshots and kill the daemons.

## Done already (server)

**F6:** the Steel viewer URL rule was removed from `/opt/data/SOUL.md` and `/opt/data/profiles/kai/SOUL.md`, backed up as `*.bak-20261024-liveview-url`. It applies to new sessions.
