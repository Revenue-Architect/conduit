# Phone QA of builds 223–229 (2026-10-24, 16:08–17:46)

Tested on the owner's S25 over wireless adb, in light mode. These builds fix the findings in `QA-BUILD-222.md` (plan: `PLAN-BUILD-223-FIXES.md`), plus the issues the owner raised during the session. Build 227 was a diagnostic build (`--dart-define=CONDUIT_DIAG=true`) that logged every event the turn stream saw.

## Verified on the phone (build 228 unless noted)

| Finding | Result |
|---|---|
| F1: leaving a chat mid-run, then reopening it | **Fixed.** I left during a browser run and reopened from Chats. The run settled with Chief's answer, the stop button cleared, and the line folded to "Browsed". |
| F3: a new chat's first message has no live state | **Fixed** (223+). The live accent line and stop button show from the first second. |
| New: a new chat's run never ends after a delegation | **Fixed.** The 227 logs showed three orderings of the parent run's end and the wake-up run (see below). All three settle in 228, with both of Chief's answers shown. |
| F2: the line describes only the last part of the turn | **Fixed.** It reads "Delegated and 7 more", and its meta is "48s · 11 steps" with the skill, tool-finding, todo and delegate steps listed. |
| F4: raw tool JSON | Fixed in code and tests; not unfolded on the phone this time. |
| F5: Steel player stuck on "Session connecting…" | **Fixed in 229.** In 228, only a manual reopen joined the session (the owner caught this). In 229 the player reloads every 4 s while it still says it is connecting, at most 15 times. On the phone, the auto-opened player showed example.com live about 16 s in, untouched. |
| F6: Chief pastes the Steel debug URL | **Fixed** in new chats (SOUL lines removed). |
| F7: Scout dot black | **Fixed** (accent). |
| F7: blank gap above the delegate branch | **Smaller** (from about 110 dp to about 50 dp). Not gone. |
| F7: plan pill lingers on later turns | **Fixed.** No pill on the browser turn after the plan turn. |
| F7: header avatar off-centre | **Fixed.** The avatar sits at the toolbar centre and never moves; long names keep their width. |
| F7: Chats list spinner and stale "5m ago" | **Fixed.** A running chat shows "Working now" with a spaced spinner, and other chats' times refresh. |
| Owner: the plan shows twice when unfolded | **Fixed.** The full plan unfolds in place of its preview, and its header's chevron folds it back. |
| Owner: no typographic hierarchy | **Fixed.** See the scale below. |

## Why a new chat's run hung (the 227 logs)

Hermes ends a run with an idle `session.info`, but a delegation wake-up can start within about 35 ms of the parent ending. The three orderings seen:

1. **The parent's idle report never comes.** The stream follows the wake-up and ends on its idle report.
2. **The parent's idle report comes before the wake-up.** The stream ends, and the wake-up arrives with no stream following it.
3. **The parent's idle report comes after the wake-up's `message.start`.** The stream ends mid wake-up.

In orderings 2 and 3, the wake-up came in through the restored running row, which nothing replaced: the stop button and the "pending" text stayed.

The fix:
- An idle report for a session no stream follows now re-reads the transcript.
- A restored running row no longer blocks that settled transcript.

(Build 223's hang was a different bug: a 5-second re-resume rebound the session to a new runtime id. It was removed in 224.)

## Inline type scale

Chat body text is about 17 sp. Everything a turn unfolds sits below it:

| Element | Size and weight |
|---|---|
| Turn line | 14 / 600 |
| Section caps (plan status) | 10 caps |
| Plan rows, thoughts, steps | 13.5 / 400 (the step in progress: 600) |
| Meta | 12 |
| "Full run details" | 13 / 600 |
| Plan actions | compact 13 / 600 pills, 34 dp |

The modal plan sheet and the composer pills keep their sizes.

## Still open

- **Gap above the delegate branch:** a gap of about 50 dp remains between the plan and the delegate branch.
- **Turn label count:** the label counts kinds of work ("and 7 more"), which may still read as noisy. A wording choice for the owner.
- **Not checked on the phone:** dark mode, 200% text, tablet, an approval answered inline, and the plan step actions.
