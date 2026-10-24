# Phone QA of build 222 (2026-10-24, 14:02–14:13)

Tested on the owner's Samsung S25 over wireless adb, in light mode, in one new Chief chat. The chat had three QA turns:

- **Plan turn:** "make a 3-step plan with your todo tool, then delegate to Scout asking it to reply PONG, then mark the plan done"
- **Browser turn:** example.com, wait 45 s, then iana.org
- **Reopen turn:** "use the terminal to run sleep 40, then reply OK". I left the chat while it ran (back to Home, then Chats) and reopened it.

## The seven unseen items (HANDOFF §6)

| # | Item | Result |
|---|---|---|
| 1 | Plan under the turn's line | **Pass.** The bars and steps sit under the line, not inside Full run details. The plan was showing about 27 s after send, when the `todo` call had already run; frames were taken every 4–5 s. |
| 2 | "Chief" waiting row without the Desktop avatar | **Pass.** After reopening the chat, the restored running row showed "Running command" in accent, with no avatar. |
| 3 | Turn folds when it settles, even after a remount | **Pass in the open chat** (plan turn and browser turn both folded). **Fail after reopening the chat:** see F1. |
| 4 | Accent on plan bars, todo checks, plan rail, timeline tiles | **Pass** for bars, checks and the unfolded line's rail. Timeline tiles were not checked (Full run details was not opened). |
| 5 | Readable tool text, inline inspector without the ACTION repeat | **Partial.** No ACTION repeat, and no untrusted-content notice. But the JSON is unpacked only at the top level: INPUT reads `calls: [{"arguments":{"merge":true,"todos":[…` and RESULT reads `todos: [{"id":"qa-plan",…`. "Took 0.0s" also looks wrong. See F4. |
| 6 | Thoughts split into separate lines; bulb for thoughts, notes icon for notes | **Pass.** Seven separate thought lines ("Locating todo guidance", "Checking task guidance", …), each with an accent bulb. No Hermes notes appeared, so the notes icon was not seen. |
| 7 | Meta step count on saved turns | **Shown, but wrong.** "gpt-6-luna · 3s · 5 steps" for a turn that took over a minute and shows 8 lines. See F2. |

## Findings, most serious first

**F1. A run never settles after you leave and reopen the chat.**
- Repro: send the sleep-40 prompt, tap back, open the chat again from Chats.
- What happens: the line goes from "Running command" to "Ran command ✓".
- The server finished the turn at 14:09:59 (`gui.log`: `status=complete duration=45.4s`), and `state.db` has the assistant's "OK".
- At 14:12:46 the phone still showed the stop button and the header's working dot, and the "OK" reply never appeared.
- Suspect: the restored running placeholder (the build 222 change that gives it Hermes metadata) is never swapped for the saved transcript once the run ends. Possibly the chat is not re-attached to the run's event stream after a remount.

**F2. After an async delegation, the turn's line describes only the last segment.**
- While the plan turn ran, the label went "Opened skill 2 times" → "Found tool and 2 more" → "Found tool and 6 more".
- Once the delegation came back, it settled on just **"Updated plan"**.
- Unfolded, it shows meta "3s · 5 steps" and only one tool step ("Updated plan updating 3 task(s)"). The earlier skill, todo and delegate steps are gone.
- The thoughts do cover the whole turn.
- So `hermesTurnSpanKey` merges thoughts across the `[ASYNC DELEGATION …]` wake-up, but the label, meta and steps come from the last row only.
- Also, "Updated plan updating 3 task(s)" repeats itself.

**F3. The first message of a new chat gets no live state.**
- In the new chat, the plan turn never showed the orb, the shimmer or the stop button.
- Within 5 s of sending, the row already had copy and regenerate actions. Every frame showed a finished ✓ line that grew as steps arrived.
- The second and third turns in the same chat did show the live line, accent shimmer and stop button.
- Suspect: the run starts before the new session id is known, so the chat polls instead of attaching to the live run.

**F4. Tool inspector JSON is shown raw below the top level.** `hermesReadableToolText` unpacks the top-level key only. The todo list should read as a list. "Took 0.0s" probably means there was no timing, not zero.

**F5. The Steel player stayed on "Session connecting..." for the whole 45 s browser run.**
- The section auto-opened and folded correctly, but no page ever drew.
- Earlier builds showed it live, so this is either a regression or a network or viewer problem.
- Check the viewer URL from the phone (the VPN icon was on).

**F6. Hermes put the internal Steel debug URL in its answer.** It wrote "watch the browser live at http://100.88.112.22:8300/v1/sessions/debug". This is a prompt or SOUL issue on the server: the app already shows the browser, so the raw tailnet URL is noise.

**F7. Smaller visual issues:**
- **Big blank gap** of about 150 px between the plan block and the Scout branch in the plan turn. This may be the HANDOFF §7.2 gap.
- **Scout branch dot:** "Replied in 3s" has a black dot. Accent or the muted token would fit the branch better.
- **Plan pill carries over:** "Plan 3/3" from the plan turn stayed in the context bar through the two unrelated turns after it.
- **Chat header off-centre:** when "Chief" collapses (scrolled to the top), the avatar sits left of centre (x ≈ 405 of 923).
- **Chats list:** the running spinner overlaps the title's ellipsis on the active chat. The row still said "5m ago" while new messages were arriving.
- **Home:** the Team row says "Chief · Used 5m ago" while Chief is running. The working-bots stack in the masthead does show Chief.

## Not covered in this pass

- dark mode
- 200% text
- tablet layout
- answering an approval or clarify question inline
- the plan tray's step actions
- the Full run details timeline (tiles, lighter rows)
