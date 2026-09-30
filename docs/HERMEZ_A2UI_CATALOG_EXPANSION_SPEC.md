Correct. I’ll treat the **local commit you just supplied** as the authoritative baseline, not the last pushed GitHub SHA.

That commit establishes several things this work must not regress: `NotificationCenter` now owns notification-plugin initialization/taps independently of OpenWebUI sign-in; cold-launch taps drain once after splash; Hermes in-app banners render above any page; notification taps deep-link to the conversation or pending run; session navigation preserves the bot name; and completion notification text waits for the finished answer and uses turn-start runtime. Since you didn’t include the resulting SHA, I’ll identify the baseline by that commit message until it is pushed.

# Hermez A2UI Catalog Expansion + Visual Language Cleanup
## Implementation Specification & Runbook

**Repository:** `Revenue-Architect/conduit`  
**Branch:** `feat/hermez-motion-foundation`  
**Baseline:** latest local commit beginning **“Notification center (phase H), banner over any page, taps that deep-link”**  
**Existing GenUI:** pinned `genui 0.10.3`  
**A2UI:** v0.9  
**Scope:** Hermez A2UI/native visual answers only.

---

## 1. Objective

Expand the Hermez A2UI catalog so Hermes can communicate more often through compact native UI instead of prose, while tightening the visual language.

This work has two parts:

```text
A. REMOVE THE LEFT-EDGE STRIPE LANGUAGE

B. ADD HIGH-VALUE GENERIC VISUAL COMPONENTS
```

The resulting catalog should be expressive enough for:

```text
personal assistant
calendar/schedule
email/messages
tasks
Hermes runs
homelab/system status
project work
comparisons
technical commands
files/artifacts
multi-agent work
```

without creating domain-specific components for every product or service.

---

# 2. Hard regression boundary

The newest notification work is outside this task.

Do not regress or re-own any responsibilities introduced by the latest local commit.

In particular, do not alter the ownership of:

```text
NotificationCenter
local notification initialization
foreground notification taps
cold-launch notification taps
notification routing
global in-app banner
Hermes completion notification routing
Hermes "needs you" deep-link routing
session bot-name preservation
turn runtime calculation
final-answer notification text selection
```

Treat these files as **hands off unless a compile-only import adjustment is unavoidable**:

```text
lib/core/providers/app_startup_providers.dart
lib/core/router/app_router.dart
lib/features/hermes/services/hermes_run_notifications.dart
lib/features/hermes/widgets/hermes_session_tile.dart
lib/features/hermes/views/hermes_live_run_page.dart
lib/features/notifications/providers/notification_socket_listener.dart
lib/features/notifications/providers/notification_center.dart
lib/features/notifications/views/in_app_banner.dart
lib/main.dart
```

And preserve the new tests around them.

This A2UI project should not need meaningful changes to those files.

---

# 3. Existing A2UI foundation to preserve

Current custom components:

```text
StatusBadge
MetricTile
MiniChart

InfoRow
StepRail
ActionCallout
ArtifactTile
BotBadge
ExpandableSection
```

Current safety architecture remains:

```text
Hermes
  ↓
completed explicit ```a2ui block
  ↓
HermesRichOutputParser
  ↓
Hermes A2UI normalizer
  ↓
A2uiTransportAdapter
  ↓
SurfaceController
  ↓
safe Hermez catalog
  ↓
native Flutter widgets
```

Do not:

```text
stream partial A2UI JSON
allow arbitrary custom Dart
fetch network resources from catalog components
read arbitrary filesystem paths
add backend A2UI state
add another transport
```

---

# 4. New visual-language rule: no colored card-edge stripes

The existing `ActionCallout` currently deliberately renders:

```dart
Container(width: 4, color: edge)
```

on the left side.

Remove it.

This design is now prohibited for Hermez A2UI:

```text
▌ Card
▌ Card
▌ Card
```

The state belongs to the **whole object**, not a decorative strip.

---

# 5. Full-perimeter state outlines

Cards, callouts, actionable tiles and buttons should use a complete outline.

Conceptually:

```text
NEUTRAL

╭──────────────────────────────╮
│ Details                      │
╰──────────────────────────────╯
```

```text
ATTENTION

╭──────────────────────────────╮
│ NEEDS YOU                    │
│ Confirm API access           │
╰──────────────────────────────╯
```

The full border may use the semantic state color.

Use approximately:

```text
neutral     palette.border
attention   palette.accent
success     success color
error       danger color
```

Suggested widths:

```text
neutral     1.0
semantic    1.25–1.5
focused     2.0 where appropriate
```

Do not make semantic cards visually heavy.

---

# 6. Preserve Hermez Orange / Hermez Red

The latest pushed theme work introduced:

```text
Hermez Orange
Hermez Red (#E3192B)
```

All new catalog components must read:

```dart
HermezChatPalette.forBrightness(...)
```

or the renderer's current theme.

Do not hard-code the old orange.

Signal-dependent components must automatically follow:

```text
Orange theme → orange accent
Red theme    → red accent
```

Status semantics remain separate:

```text
success ≠ accent
warning ≠ accent
danger  ≠ accent
```

Do not turn success green into Hermez Red just because Red is active.

---

# 7. Important exception: structural vertical lines remain allowed

This ban applies to decorative edge strips.

Do **not** remove meaningful lines from:

```text
StepRail
timelines
connection graphs
progress topology
```

Example still correct:

```text
● Discovery
│
● Build
│
○ Launch
```

The rule is:

> Vertical lines may represent sequence, connection or progress. They may not be decorative colored edge strips attached to rectangular cards/buttons.

---

# 8. Refactor `ActionCallout`

Current architecture:

```text
DecoratedBox
  ↓
ClipRRect
  ↓
IntrinsicHeight
  ↓
Row
  ├ 4px colored strip
  └ body
```

Simplify to:

```text
Container / DecoratedBox
  ↓
Padding
  ↓
Column
```

Calculate:

```dart
final semanticColor = switch (tone) {
  'attention' => palette.accent,
  'success'   => status.success,
  'error'     => status.danger,
  _           => palette.border,
};
```

Use semantic color for:

```text
full border
eyebrow
optional icon
```

Do not recolor ordinary body copy.

---

# 9. Take ownership of the A2UI Button renderer

Current `_hermezButton` still relies on the Basic Catalog button renderer with a local `ColorScheme` workaround.

Replace this with a Hermez-owned renderer while preserving:

```text
GenUI action dispatch
validation/check behavior
surface interaction lock
exactly-once event semantics
```

Do not reimplement event semantics incorrectly.

If necessary, extract/reuse the safe action-dispatch logic rather than changing its meaning.

---

# 10. Button visual variants

Continue accepting the A2UI-compatible variants:

```text
default
primary
borderless
```

Map them into Hermez presentation.

### `primary`

```text
filled signal object
```

Use:

```text
background = palette.accent
foreground = palette.onAccent
```

So Hermez Red correctly gets white foreground.

### `default`

Render as:

```text
surface background
full palette.border outline
ink foreground
```

### `borderless`

No perimeter container, but preserve minimum touch target.

---

# 11. Destructive buttons

A2UI's current basic button schema does not necessarily encode a destructive variant.

Do not invent incompatible props casually.

Where destructive state is needed, prefer:

```text
ActionCallout tone="error"
  ↓
regular child Button
```

or add a tightly validated Hermez-specific action component only if real use requires it later.

Do not overload an event name to choose visual style.

---

# 12. Button geometry

Maintain:

```text
minimum touch target ≥44dp
prefer 48dp
12–14px corner radius
full perimeter
no left edge
no Material elevation
```

At 200% text:

```text
label wraps if needed
button grows vertically
no horizontal clipping
```

---

# 13. New component: `ProgressMeter`

Add to:

```text
lib/features/hermes/widgets/hermes_visual_structure.dart
```

Purpose:

```text
actual count progress
migration progress
task completion
validation progress
multi-agent work completion
```

Schema:

```text
ProgressMeter
├ label: required string ≤80
├ current: required finite number
├ total: required finite number >0
├ unit: optional string ≤24
├ detail: optional string ≤120
├ state: optional ok|warning|error|unknown
└ segmented: optional bool
```

Rules:

```text
current >= 0
total > 0
```

If `current > total`, either:

```text
render safely as >100% with truthful values
```

or reject if product semantics require bounds.

Do not silently clamp displayed values.

---

# 14. Progress presentation

Recommended:

```text
MIGRATION / 69%

412 / 600 PRODUCTS

■■■■■■■■■■■■■■□□□□□□
```

Do not rely on color alone.

Show:

```text
numeric values
+
visual bar
```

The percentage may be mathematically derived from real current/total values.

That's allowed.

Do not invent progress from text such as:

```text
"almost done"
```

---

# 15. `ProgressMeter` state color

Normal progress:

```text
palette.accent
```

Warning/error:

```text
actual semantic status colors
```

Full-outline container if wrapped.

No left edge.

---

# 16. New component: `ActivityFeed`

Purpose:

```text
what just happened?
```

Different from `StepRail`.

`StepRail`:

```text
plan/stages
```

`ActivityFeed`:

```text
historical events
```

Schema:

```text
ActivityFeed
├ items: required list 1–20
│   ├ title: required ≤80
│   ├ detail?: ≤140
│   ├ time?: ≤40
│   ├ icon?: validated icon
│   └ state?: ok|warning|error|unknown
└ compact?: bool
```

---

# 17. Activity presentation

Example:

```text
ACTIVITY

11:42
● Browser opened Shopify

11:43
● Inventory export loaded

11:44
✓ 412 products validated

11:45
! 3 records need review
```

Use a neutral continuity rail only if it improves scanning.

Avoid making it look identical to `StepRail`.

---

# 18. ActivityFeed truth rule

Only include events actually supplied by Hermes.

Do not:

```text
create timestamps
infer missing tool activity
merge events speculatively
```

If time is unavailable, omit it.

---

# 19. New component: `ScheduleTile`

Generic enough for:

```text
calendar events
appointments
scheduled agents
timed tasks
reminders
```

Schema:

```text
ScheduleTile
├ title: required ≤80
├ start: required ≤40
├ end?: ≤40
├ date?: ≤40
├ location?: ≤100
├ detail?: ≤120
├ owner?: ≤60
├ state?: ok|warning|error|unknown
└ icon?: validated icon
```

Do not make it specifically depend on Outlook or Google Calendar.

---

# 20. Schedule presentation

Example:

```text
14:30
Dentist

45 min · Downtown
```

Scheduled agent example:

```text
09:00
Morning Brief

Daily · Kai
```

Use full perimeter.

No colored stripe.

---

# 21. New component: `MessagePreview`

Purpose:

```text
email
Teams
AgentMail
future supported communication channels
```

Schema:

```text
MessagePreview
├ sender: required ≤80
├ title?: ≤100
├ preview: required ≤240
├ timestamp?: ≤40
├ channel?: email|teams|agentmail|message|unknown
├ unread?: bool
└ importance?: normal|important
```

No fetching.

No replying.

No opening external apps directly.

---

# 22. MessagePreview design

Example:

```text
EMAIL

Georgia Sigurdson
Trail Together follow-up

Just have a few follow-up questions…

10:42 AM
```

Unread should be indicated with:

```text
typography + semantic mark
```

not only color.

---

# 23. New component: `CommandBlock`

Purpose:

```text
shell command
SQL
JSON snippet
configuration value
technical command awaiting review
```

Schema:

```text
CommandBlock
├ content: required string ≤4000
├ label?: ≤40
├ language?: shell|sql|json|yaml|text
└ copyable?: bool = true
```

Absolutely no execution.

---

# 24. CommandBlock local Copy action

Copy is:

```text
presentation-only local action
```

It must use the same local-control mechanism as `ExpandableSection`.

Therefore:

```text
copy tap
→ clipboard
→ no [A2UI_INTERACTION]
→ no Hermes turn
```

Wrap its local affordance with:

```dart
HermesA2uiLocalControl
```

It must remain usable even when the surface is interaction-locked.

---

# 25. CommandBlock visual

Example:

```text
COMMAND

╭──────────────────────────────╮
│ docker compose restart nvr   │
│                        COPY  │
╰──────────────────────────────╯
```

Use monospace content.

Don't syntax-highlight aggressively in V1.

---

# 26. New component: `TaskTile`

Generic task representation.

Schema:

```text
TaskTile
├ title: required ≤100
├ status: required
│  todo
│  in_progress
│  blocked
│  done
│  unknown
├ assignee?: ≤60
├ due?: ≤40
├ priority?: low|normal|high|urgent
├ detail?: ≤160
└ countLabel?: ≤40
```

Don't bind it to Hermes Kanban IDs.

It's presentation only.

---

# 27. TaskTile visual

Example:

```text
TRAIL CERTIFICATES        RUNNING

Kai
Due Nov 11

Generate and email donor certificates
```

Full perimeter state outline only when semantically useful.

Do not turn every task into an orange/red box.

Neutral task cards should use the neutral border.

---

# 28. New component: `KeyValueGrid`

Purpose:

```text
small sets of factual metadata
```

Schema:

```text
KeyValueGrid
├ title?: ≤60
├ items: required 1–8
│   ├ label: ≤40
│   └ value: ≤120
└ compact?: bool
```

No arbitrary columns.

---

# 29. KeyValueGrid presentation

Wide-enough phone:

```text
MODEL       Qwen 27B
PROFILE     Local
STATUS      Running
UPTIME      14h 22m
```

Narrow/large text:

```text
MODEL
Qwen 27B

PROFILE
Local
```

The renderer chooses based on available width/text scale.

Hermes should not choose layout direction.

---

# 30. New component: `ComparisonCard`

Implement last.

Schema:

```text
ComparisonCard
├ title: required ≤80
├ subtitle?: ≤120
├ badge?: ≤40
├ facts: required 1–8
│   ├ label: ≤40
│   ├ value: ≤100
│   └ state?: ok|warning|error|unknown
└ detail?: ≤160
```

It must not contain:

```text
winner
rank
score
best
recommended
```

as special component semantics.

It presents facts.

---

# 31. Comparison layout

Stack on mobile:

```text
OPTION A
────────────
COST       $12
LOCAL      YES
MEMORY     17 GB

OPTION B
────────────
COST       $20
LOCAL      NO
MEMORY     —
```

Use two separate `ComparisonCard`s in a `Column`.

Do not attempt a desktop-style comparison table.

---

# 32. Catalog organization

Split the file if `hermes_visual_structure.dart` becomes unwieldy.

Suggested structure:

```text
widgets/a2ui/
├ hermes_visual_catalog.dart
├ hermes_visual_status.dart
├ hermes_visual_structure.dart
├ hermes_visual_activity.dart
├ hermes_visual_personal.dart
├ hermes_visual_technical.dart
└ hermes_visual_compare.dart
```

But do not refactor merely for neatness if the current file remains manageable.

Fastest maintainable path wins.

---

# 33. Final intended catalog

### Data

```text
StatusBadge
MetricTile
MiniChart
ProgressMeter
KeyValueGrid
```

### Structure

```text
InfoRow
StepRail
ActivityFeed
ExpandableSection
ComparisonCard
```

### Personal-agent surfaces

```text
ScheduleTile
TaskTile
MessagePreview
ArtifactTile
BotBadge
```

### Action

```text
ActionCallout
Button
ChoicePicker
TextField
CheckBox
DateTimeInput
```

### Technical

```text
CommandBlock
```

That is enough.

Do not create dozens more components during this implementation.

---

# 34. Normalizer updates

Update:

```text
lib/features/hermes/services/hermes_a2ui_layout_normalizer.dart
```

Current `_stackInRowComponentTypes` includes the existing structure widgets.

Add these as full-width-by-default:

```text
ProgressMeter
ActivityFeed
ScheduleTile
MessagePreview
CommandBlock
TaskTile
KeyValueGrid
ComparisonCard
```

Do **not** allow these to accidentally become narrow unweighted Row children.

`MetricTile` remains the primary deliberate side-by-side visual primitive.

---

# 35. Row rules

Continue:

```text
MetricTile + MetricTile
→ safe weighted Row
```

But:

```text
MessagePreview + MessagePreview
→ Column

TaskTile + TaskTile
→ Column

ScheduleTile + ScheduleTile
→ Column

ComparisonCard + ComparisonCard
→ Column

ActivityFeed in Row
→ Column

CommandBlock in Row
→ Column
```

Optimize for ~300 logical px.

---

# 36. Component graph safety

Update the A2UI validator/catalog schema normally.

Do not weaken:

```text
max payload size
max component count
max graph depth
rooted graph validation
cycle rejection
action validation
safe event context validation
```

New components should remain simple leaf components except where explicitly referencing children.

---

# 37. Local-interaction safety

Two A2UI interactions are presentation-only:

```text
ExpandableSection open/close
CommandBlock copy
```

Both must:

```text
work while surface interaction is locked
send no Hermes event
send no chat turn
perform no backend call
```

Do not broaden `HermesA2uiLocalControl` into an unrestricted bypass.

Only explicitly local controls should use it.

---

# 38. Update A2UI skill policy

Modify:

```text
docs/hermes-a2ui-mobile/SKILL.md
```

Teach Hermes the new mapping.

Add:

```text
real current/total progress
→ ProgressMeter

recent chronological events
→ ActivityFeed

calendar/timed object
→ ScheduleTile

email/message preview
→ MessagePreview

technical command
→ CommandBlock

task/action item
→ TaskTile

small factual metadata
→ KeyValueGrid

two or more structured alternatives
→ ComparisonCard
```

---

# 39. Distinguish similar components

The skill needs explicit rules.

### `MetricTile` vs `ProgressMeter`

```text
86% disk use
→ MetricTile

412 / 600 products migrated
→ ProgressMeter
```

### `StepRail` vs `ActivityFeed`

```text
Discovery → Build → UAT → Launch
→ StepRail

11:42 searched
11:43 fetched
11:44 generated
→ ActivityFeed
```

### `InfoRow` vs `KeyValueGrid`

```text
list of services/statuses
→ InfoRow

metadata about one object
→ KeyValueGrid
```

### `TaskTile` vs `ActionCallout`

```text
task exists
→ TaskTile

user needs to do something now
→ ActionCallout
```

---

# 40. Command usage rule

When Hermes gives:

```text
one short command
```

prefer `CommandBlock`.

For:

```text
large code
program source
multi-file code
```

normal Markdown/code remains better.

Do not force every code answer into A2UI.

---

# 41. Message usage rule

Use `MessagePreview` for:

```text
mail/chat summaries
recent important messages
what needs attention
```

Do not reproduce full emails inside it.

Use:

```text
sender
subject/title
brief preview
time
```

Then provide detail via prose or expandable section if needed.

---

# 42. Comparison usage rule

Use comparison cards only when the user needs to inspect multiple options.

Don't convert:

```text
"A costs $12 and B costs $20."
```

into a giant comparison UI unless there are enough dimensions to justify it.

---

# 43. Visual composition examples

### Homelab

```text
MetricTile
MetricTile
ProgressMeter
ActivityFeed
ActionCallout
```

### Email morning brief

```text
MessagePreview
MessagePreview
MessagePreview
ActionCallout
```

### Day plan

```text
ScheduleTile
ScheduleTile
TaskTile
```

### Autonomous Hermes run

```text
BotBadge
ProgressMeter
ActivityFeed
ExpandableSection
```

### Project status

```text
ProgressMeter
StepRail
TaskTile
ActionCallout
```

### Server detail

```text
StatusBadge
KeyValueGrid
MiniChart
ActivityFeed
```

### Technical instruction

```text
InfoRow
CommandBlock
ActionCallout
```

---

# 44. Full-perimeter component rule

Update documentation:

```text
docs/hermes-a2ui-mobile/references/component-guide.md
```

with this explicit rule:

> Cards, callouts, tiles, buttons and bordered containers must use a complete perimeter border. Do not render decorative accent strips or colored side edges. Semantic state may affect the entire outline, icon and technical label.

And:

> Vertical lines remain allowed where they encode sequence, connection, hierarchy or progress.

---

# 45. Update patterns

Add canonical patterns to:

```text
docs/hermes-a2ui-mobile/references/patterns.md
```

Recommended:

```text
15. Progress / migration
16. Recent activity
17. Daily schedule
18. Inbox summary
19. Task status
20. Technical command
21. Metadata/details
22. Comparison
23. Agent run summary
24. Personal morning brief
```

All examples must pass the validator.

---

# 46. Tests — no left-edge stripe

Add a focused widget test against `ActionCallout`.

Verify the renderer no longer contains the old 4px signal strip.

Prefer testing the resulting decoration rather than brittle pixel screenshots.

At minimum verify:

```text
full border is semantic color for attention
full border is danger color for error
neutral uses palette.border
no separate vertical edge widget exists
```

Test both:

```text
Hermez Orange
Hermez Red
```

---

# 47. Theme tests

Every new component must render under:

```text
light + orange
dark + orange
light + red
dark + red
```

Do not hard-code:

```text
#FF5A26
#FF6A36
#E3192B
```

inside component implementations except theme definitions.

---

# 48. Button tests

Verify:

```text
default has full outline
primary uses accent fill
Red primary uses white label
borderless has no outline
tap dispatches exactly one event
surface lock blocks remote action
large text doesn't overflow
```

This is important because replacing the Basic Catalog renderer can accidentally break event behavior.

---

# 49. ProgressMeter tests

Cover:

```text
0 / total
partial
complete
current > total if allowed
invalid total
NaN/infinity rejection
warning state
200% text
320px width
```

No fictitious progress.

---

# 50. ActivityFeed tests

Cover:

```text
one event
20 events
missing times
warning/error
long detail
compact mode
200% text
```

No overflow.

---

# 51. ScheduleTile tests

Cover:

```text
start only
start + end
location
owner
state
long event name
large text
```

---

# 52. MessagePreview tests

Cover:

```text
email
Teams
AgentMail
unread
important
no subject
long preview truncation
large text
```

No remote fetch.

---

# 53. CommandBlock tests

Cover:

```text
shell
SQL
JSON
multiline text
copy
surface locked
```

Critical assertion:

```text
Copy
→ clipboard changed
→ zero A2UI interaction events
```

---

# 54. TaskTile tests

Cover every status:

```text
todo
in_progress
blocked
done
unknown
```

and:

```text
assignee
due
priority
large text
```

---

# 55. KeyValueGrid tests

Verify responsive reflow.

At:

```text
412px, 100% text
```

compact two-column representation is allowed.

At:

```text
320px, 200% text
```

must switch to stacked label/value layout.

No overflow.

---

# 56. ComparisonCard tests

Cover:

```text
1 fact
8 facts
state facts
long title
long values
200% text
```

It should remain a vertically readable card.

No horizontal table behavior.

---

# 57. Normalizer regression tests

Update the normalizer test set.

Assert:

```text
Row[ProgressMeter, ...] → Column
Row[TaskTile, TaskTile] → Column
Row[ScheduleTile, ScheduleTile] → Column
Row[ComparisonCard, ComparisonCard] → Column
Row[MessagePreview, MessagePreview] → Column
```

Continue preserving:

```text
MetricTile + MetricTile → weighted Row
Button + Button → weighted Row
```

---

# 58. A2UI smoke flow

Extend the existing A2UI smoke/integration test, but keep it small.

One representative surface:

```text
BotBadge
ProgressMeter
ActivityFeed
ExpandableSection
CommandBlock
ActionCallout + Button
```

Verify:

```text
renders
expand is local
copy is local
Button sends exactly one turn
locked surface blocks Button
local controls remain usable
```

---

# 59. Performance

Do not add expensive animations to A2UI.

These are response surfaces, not continuous dashboard widgets.

Avoid:

```text
continuous repaint
blur effects
animated gradients
ambient loops
large shaders
```

`ProgressMeter` may animate on initial appearance only if it can reuse the existing Hermez motion primitives safely.

V1 can be static.

---

# 60. A2UI and physical motion

Do not turn every generated card into a `HermezMotionSurface`.

Static informational objects remain static.

Only actual controls should feel pressable:

```text
Button
ExpandableSection header
CommandBlock Copy
ChoicePicker
form controls
```

This prevents generated answers from feeling like every visual element is a button.

---

# 61. Accessibility

Every component needs meaningful semantics.

Examples:

`ProgressMeter`:

```text
Migration. 412 of 600 products. 68.7 percent.
```

`ScheduleTile`:

```text
Dentist, starts 2:30 PM, Downtown.
```

`MessagePreview`:

```text
Unread email from Georgia Sigurdson, Trail Together follow-up.
```

`CommandBlock`:

```text
Shell command. docker compose restart nvr. Copy command button.
```

State must never be communicated through color alone.

---

# 62. Keep catalog data-only

None of these new components may:

```text
query Gmail
query Calendar
query Hermes
query Kanban
download artifacts
open sockets
call HTTP
execute commands
inspect filesystem
```

Hermes retrieves data first.

A2UI receives a representation of that data.

---

# 63. Files expected to change

Likely:

```text
lib/features/hermes/widgets/hermes_visual_catalog.dart
lib/features/hermes/widgets/hermes_visual_structure.dart
lib/features/hermes/widgets/hermez_visual_theme.dart
lib/features/hermes/services/hermes_a2ui_layout_normalizer.dart

docs/hermes-a2ui-mobile/SKILL.md
docs/hermes-a2ui-mobile/references/component-guide.md
docs/hermes-a2ui-mobile/references/patterns.md
docs/hermes-a2ui-mobile/a2ui_check.py

test/features/hermes/hermes_visual_catalog_test.dart
test/features/hermes/*a2ui*
test/fixtures/hermes/a2ui/*
```

Potentially add one or more focused new visual-component source files rather than making `hermes_visual_structure.dart` enormous.

---

# 64. Files that should not change for this work

Do not change the newly committed notification path:

```text
app_startup_providers.dart
notification_center.dart
notification_socket_listener.dart
notification_router ownership
in_app_banner.dart
hermes_run_notifications.dart
main.dart
app_router.dart
```

unless required to resolve an unrelated compile conflict.

If Claude finds itself modifying these to implement a `ProgressMeter`, something has gone wrong.

---

# 65. Implementation order

### Phase 1 — visual-language cleanup

Do first:

```text
remove ActionCallout edge stripe
establish full-border rule
take ownership of Button renderer
Orange + Red tests
```

This immediately fixes the current visual annoyance.

### Phase 2 — highest-value components

Implement:

```text
ProgressMeter
ActivityFeed
ScheduleTile
MessagePreview
```

These have the biggest impact on your normal assistant use.

### Phase 3 — technical/work components

Implement:

```text
CommandBlock
TaskTile
KeyValueGrid
```

### Phase 4 — comparison

Implement:

```text
ComparisonCard
```

only after everything above is stable.

### Phase 5 — authoring

Update:

```text
SKILL
component guide
patterns
validator
fixtures
```

### Phase 6 — QA

Run:

```text
focused catalog tests
normalizer tests
A2UI interaction-lock tests
chat tests
Android ARM64 build
S25 device QA
```

---

# 66. Device QA examples

Ask real Hermes:

```text
How are my services doing?
```

Expected:

```text
StatusBadge / MetricTile / ProgressMeter
```

Ask:

```text
What has Hermes been doing?
```

Expected:

```text
ActivityFeed
```

Ask:

```text
What's on my calendar today?
```

Expected:

```text
ScheduleTile
```

Ask:

```text
Anything important in my messages?
```

Expected:

```text
MessagePreview
```

Ask:

```text
What's still left on Trail Together?
```

Expected:

```text
ProgressMeter + TaskTile + StepRail
```

Ask:

```text
What command should I run?
```

Expected:

```text
CommandBlock
```

Ask:

```text
Tell me about this server.
```

Expected:

```text
KeyValueGrid + metrics
```

Ask:

```text
Compare A and B.
```

Expected:

```text
ComparisonCard ×2
```

And:

```text
What is 2+2?
```

Expected:

```text
4
```

not A2UI.

---

# 67. Definition of Done — visual language

Done when:

```text
✓ no ActionCallout left stripe
✓ no new A2UI card has a decorative colored side edge
✓ semantic state uses whole outline
✓ buttons use whole-object styling
✓ Orange and Red palettes both work
✓ StepRail topology remains intact
```

---

# 68. Definition of Done — catalog

Done when the catalog includes:

```text
ProgressMeter
ActivityFeed
ScheduleTile
MessagePreview
CommandBlock
TaskTile
KeyValueGrid
ComparisonCard
```

with bounded schemas, native rendering, docs and tests.

---

# 69. Definition of Done — behavior

Done when Hermes naturally produces answers like:

```text
1 concise sentence
+
native visual UI
```

instead of:

```text
six paragraphs
+
Markdown table
+
file names
```

where structured visuals communicate the information better.

---

# 70. Definition of Done — regression safety

The latest notification work must still pass unchanged:

```text
✓ NotificationCenter starts independently of OWUI login
✓ foreground notification taps route
✓ cold-start notification taps route once
✓ banner appears above any page
✓ finished notification opens the correct conversation
✓ needs-you notification opens the pending run
✓ bot name is preserved opening chat from lists
✓ final answer is used for notification body
✓ run duration still counts from turn start
```

And there must be:

```text
no backend changes
no new sockets
no notification ownership changes
no session routing regressions
no Hermes protocol changes
no A2UI network/file access
```

The guiding design rule for Claude should be:

> **A Hermez visual response should feel like one coherent physical instrument. State changes the whole object; it does not paint a random stripe on its side. Add reusable visual primitives only when they let Hermes communicate substantially more information with less prose.**