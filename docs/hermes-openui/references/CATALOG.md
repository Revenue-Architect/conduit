Hermes Desktop and Conduit OpenUI v1. This is a renderer in the existing chat, using the existing Hermes model, tools and session. No OpenUI Gateway is required.

## Syntax Rules

1. Each statement is on its own line: `identifier = Expression`
2. `root` is the entry point — every program must define `root = Stack(...)`
3. Expressions are: strings ("..."), numbers, booleans (true/false), null, arrays ([...]), objects ({...}), or component calls TypeName(arg1, arg2, ...)
4. Inline all component calls in the single root statement; do not define or use references.
5. Only the root assignment is supported. No additional variables or statements.
6. Arguments are POSITIONAL (order matters, not names). Write `SomeComp([children], "row", "l")` NOT `SomeComp([children], direction: "row", gap: "l")` — colon syntax is NOT supported and silently breaks
7. Optional arguments can be omitted from the end
- Strings use double quotes with backslash escaping

## Component Signatures

Arguments marked with ? are optional. All sub-components must be inline.

Stack(children: any[]) — Required root; vertical layout.
Grid(children: any[], columns?: number) — Responsive cards or metrics; wraps on small windows.
Card(title: string, description: string, children: any[]) — Panel with heading, subtitle and children.
Text(text: string, tone?: "neutral" | "accent" | "success" | "warning") — Plain text; never HTML or Markdown.
Metric(label: string, value: string, caption: string) — Large value with label and supporting detail; supplied or computed data only.
Badge(label: string, tone?: "neutral" | "accent" | "success" | "warning") — Short status with label, never colour alone.
Button(label: string, message: string, variant?: "primary" | "secondary") — Explicit conversational request. Sends message plus this form's current fields to the originating Hermes session; never invokes a tool or sends a draft.
Input(name: string, label: string, placeholder: string, initial: string) — Local text field inside Form; values sent only when Button is clicked.
Select(name: string, label: string, options: string[], initial: string) — Local select inside Form. Initial must be one of the options.
Checkbox(name: string, label: string, initial: boolean) — Local checkbox inside Form.
Form(name: string, children: any[]) — Collect form fields for its explicit Button. Never nest forms. At most 16 fields.
Table(columns: string[], rows: string[][]) — Bounded table. Every row has exactly one plain text cell per column. Scrolls horizontally.
BarChart(title: string, labels: string[], values: number[], unit: string) — Horizontal bars for aligned nonnegative values. Actual values remain visible.
Progress(label: string, value: number, max: number) — Progress toward a supplied positive maximum.
Row(children: any[]) — Wrapping horizontal group.
Section(title: string, children: any[]) — Heading and vertically stacked content.
Divider(label: string) — Quiet divider with optional label.
Heading(title: string, subtitle: string) — Section heading with optional description.
CodeBlock(language: string, code: string) — Read-only code with language label. Never executes.
Quote(quote: string, source: string) — Exact quotation and supplied attribution.
Callout(title: string, message: string, severity: "info" | "success" | "warning" | "error") — Labelled info, success, warning or error. Use supplied facts.
KeyValue(label: string, value: string) — A label/value row.
List(items: string[]) — Plain bullet list.
NumberedList(items: string[]) — Ordered plain text steps.
Checklist(items: string[]) — Local checklist; checking does not send a request or change operational state.
TimelineItem(time: string, title: string, detail: string) — A supplied timeline event; time is text, not an inferred deadline.
Timeline(children: any[]) — Vertical TimelineItem children only.
Step(title: string, detail: string, status: "pending" | "current" | "done") — A process step with explicit status.
Steps(children: any[]) — Process made of Step children only.
Details(title: string, children: any[], open?: boolean) — Local disclosure. Expands without sending a request.
AccordionItem(title: string, children: any[]) — A locally expandable accordion section.
Accordion(children: any[]) — Expandable AccordionItem children only.
Tab(title: string, children: any[]) — Named page inside Tabs.
Tabs(children: any[]) — Local tab navigation; only Tab children. Hidden pages remain mounted so form edits survive tab switching.
Carousel(children: any[]) — Local previous/next pages. Does not fetch content.
TagGroup(tags: string[]) — A group of plain labelled tags.
Avatar(name: string, detail: string) — Local initials avatar, without remote image fetches.
EmptyState(title: string, description: string) — Honest empty-state title and explanation.
Notification(title: string, message: string, source: string, time: string) — Display-only notice with source and time. Does not send a notification.
TextArea(name: string, label: string, placeholder: string, initial: string) — Multiline local form field.
NumberInput(name: string, label: string, min: number, max: number, initial: number) — Bounded numeric local form field.
DatePicker(name: string, label: string, initial: string) — ISO date form field. User input, not an authoritative scheduled deadline.
TimePicker(name: string, label: string, initial: string) — Local time form field in HH:mm. Does not schedule anything.
Slider(name: string, label: string, min: number, max: number, initial: number) — Bounded numeric form slider. Labelled output always shows current value.
Switch(name: string, label: string, initial: boolean) — Local form boolean toggle.
RadioGroup(name: string, label: string, options: string[], initial: string) — One local form choice from the supplied options.
MultiSelect(name: string, label: string, options: string[], initial: string[]) — Multiple local form choices.
Rating(name: string, label: string, initial: number) — Local form rating from 1 to 5.
LineChart(title: string, labels: string[], values: number[], unit: string) — Line chart with visible legend of exact nonnegative values.
AreaChart(title: string, labels: string[], values: number[], unit: string) — Filled line chart with exact values in legend.
PieChart(title: string, labels: string[], values: number[], unit: string) — Part-to-whole chart; exact legend values.
DonutChart(title: string, labels: string[], values: number[], unit: string) — Donut chart with central total and exact legend values.
Sparkline(label: string, values: number[]) — Compact trend from supplied values.
Gauge(label: string, value: number, max: number, unit: string) — Labelled circular progress with exact numerator and maximum.
Heatmap(title: string, columns: string[], rows: string[], values: number[][]) — Small numeric heatmap, actual values always printed. Every row matches column count.
Comparison(leftTitle: string, left: string, rightTitle: string, right: string) — Two text alternatives side by side.
Citation(source: string, location: string, excerpt: string, finding: string) — Supplied source, page/location, exact excerpt and separate interpretation. No invented sources or remote fetch.
DraftReview(recipient: string, subject: string, body: string) — Display-only unsent draft with distinct recipient, subject and body. Add a separate Button for edit requests.
AgendaItem(time: string, title: string, detail: string) — Supplied agenda time, title and detail.
Agenda(date: string, children: any[]) — Date-labelled list of AgendaItem children only.
TaskCard(title: string, detail: string, status: string, assignee: string) — Display task. Does not mutate a task system.
KanbanColumn(title: string, children: any[]) — A named lane of TaskCard children only.
Kanban(children: any[]) — Horizontally scrollable KanbanColumn children. Display-only; use explicit Buttons to request changes.
Scorecard(label: string, score: number, explanation: string) — Labelled numeric score and supplied rationale.
Price(amount: string, currency: string, period: string, note: string) — Price with explicit currency and period, based on supplied data.
ContactCard(name: string, role: string, email: string, phone: string) — Display supplied contact details; does not call or message anyone.
FileCard(name: string, type: string, size: string, description: string) — Supplied file name, type and summary. Does not open filesystem paths.
Breadcrumbs(items: string[]) — Display hierarchy; no navigation to arbitrary destinations.
Status(label: string, detail: string, severity: "info" | "success" | "warning" | "error") — Named status with explicit message.
DefinitionList(labels: string[], values: string[]) — Pairs of labels and descriptions.
Image(alt: string, src?: string) — Compact image. src is an https/http URL, a data:image URI or a MEDIA-declared path; without a usable src it shows a placeholder with the alt text. Tap opens a local zoom viewer; nothing is sent.
ImageBlock(src: string, alt?: string) — Full-width image block with the same src rules as Image. Failures show a placeholder with the alt text. Tap opens a local zoom viewer.
ImageGallery(images: {src: string, alt?: string, details?: string}[]) — Swipeable gallery of 1 to 12 images given as {src, alt, details} objects, with page dots. details is shown with the image. Local only; sends nothing.

## Examples

root = Stack([Card("Weekend ideas", "Example data", [Grid([Metric("Reading", "$0", "At home"), Metric("Museum", "$20", "Admission")], 2), BarChart("Example costs", ["Reading", "Museum"], [0, 20], "CAD"), Form("weekend", [Select("activity", "Activity", ["Reading", "Museum"], "Reading"), Input("note", "Notes", "Optional", ""), Button("Plan this", "Suggest a plan using my selected activity and note.")])])])

## Important Rules
- Choose components that best represent the content (tables for comparisons, charts for trends, forms for input, etc.)

## Final Verification
Before finishing, walk your output and verify:
1. root = Stack(...) is the FIRST line (for optimal streaming).
2. There is exactly one root assignment, all component calls inline, no unresolved references.

- Only use this format when the CURRENT turn advertises [Client capability: Hermes Desktop OpenUI v1] or [Client capability: Conduit OpenUI v1], or this current user turn is an OpenUI interaction with context.renderer=openui. Otherwise use supported A2UI or normal text.
- Use a closed fenced openui block, containing exactly one root = Stack([...]) statement. Inline all component calls. No named references, extra statements, functions, actions, queries, mutations, reactive bindings or expressions. URLs are allowed only as image src values (Image, ImageBlock, ImageGallery).
- All arguments are positional in the declared schema order. Required arguments first. Omit optional trailing arguments or give their exact enum values. Never add invented components or props.
- At most 64KiB, 200 components, 16 levels of component nesting. Plain short answers stay prose. Mark synthetic data as examples. Cite factual evidence outside the UI or use the existing A2UI CitationCard. Use A2UI DraftReview for unsent recipient/subject/message review.
- A2UI and OpenUI may appear in separate fences in the same reply. Preserve strict A2UI v0.9 JSONL. Never put A2UI JSON into an openui fence or OpenUI Lang into an a2ui fence.
- Image components (Conduit only until Desktop exposes them; use them only when the client advertises Image, ImageBlock and ImageGallery): src is an https:// or http:// image URL (any host, including the user's own LAN or Tailscale server), a data:image/(png|jpeg|gif|webp|avif|bmp);base64 URI (keep it under 48 KB; the whole program is capped at 64 KiB) or a path from a MEDIA: line in the same reply. Other schemes (javascript:, file:, content:, intent:) and non-image responses are rejected. Only the image is fetched, with no cookies, credentials or referrer. Write meaningful alt text; an unavailable image shows a placeholder with that alt text. ImageGallery takes an array of {src, alt, details} objects, at most 12.
- Buttons on an older reply are disabled once a newer user turn exists, so put the actions the user should take in the latest reply. Local tabs, selections and galleries keep working on older replies.
- Button(label,message) sends an ordinary conversational request through [A2UI_INTERACTION] with context.renderer=openui. Only explicit button clicks send; typing/selecting/checking stays local. Form(name,children) includes current field values, including unchanged defaults. No button auto-sends email or applies a change.
- Use one unique field name per Form. Never nest Forms. Input/Select/Checkbox must be inside Form. Select initial must equal an option. Table row widths equal column count; BarChart labels and values have equal length; Progress value does not exceed max.
