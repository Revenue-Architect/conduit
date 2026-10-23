# Hermez visual system

The supplied mockups are a reference for visual grammar, not fixed screen
coordinates or sample data. Native Flutter UI must remain responsive and wired
to real Conduit/Hermes behavior. If a value or action is not supported by
Hermes, omit it rather than inventing one.

## Three layers

- **Function:** real cards, controls, status, navigation, sheets, and data.
- **Surface:** pure white or neutral light-gray canvas, white cards, thin neutral
  borders, generous but disciplined spacing, soft corners, strong dark type,
  muted secondary type, and sparse orange signals. Dark mode uses the existing
  palette's equivalent roles.
- **Atmosphere:** faint construction lines, asymmetric crops, occasional
  micro-labels or restrained accent marks. These are brand elements, not
  controls; they sit behind content, ignore input, and never obscure text.

Use `hermez_chat_palette.dart` and `hermez_visual_theme.dart` as the source of
truth. `HermezTechnicalBackground` provides deterministic light-geometry,
mechanical, and editorial variants. Apply a variant to occasional hero or
context surfaces, not every repeated row. Keep dense lists quieter.

Do not use raster screenshots as backgrounds, fake controls, fabricated
metrics, broad gradients, neon, glass, heavy shadows, or a parallel theme.
Mechanical motifs should relate to state or action (for example, a live run),
not be pasted into unrelated screens. Preserve rounded sheet, dimmed origin,
grab handle, scrollable content, and sticky actions where a sheet is used.

## Review gate

After functional QA, compare each screen with the references for whitespace
rhythm, type contrast, border/radius consistency, orange-to-neutral balance,
asymmetry, technical linework, and information density. Check narrow widths,
large text, light/dark mode, and tap targets. If removing the Hermes logo makes
the screen look like a stock Material dashboard, refine it before calling it
finished. Atmospheric details are required but must remain subtle.

## Generated UI design rules (October 22, 2026)

These rules apply to both A2UI and OpenUI on Conduit and Hermes Desktop.

- Never use colored left borders, accent rails, side stripes or a colored edge to decorate a card, heading, quote, verdict or callout. Use a quiet uniform outline or spacing.
- Use neutral surfaces and readable type. Avoid large tinted status slabs, decorative gradients, glass effects, glow, heavy shadows, oversized verdict cards and repetitive rounded card grids.
- Use a status label or icon only when it conveys actual state. Do not add a success badge to an opinion, recommendation or ordinary explanation. Keep semantic color small and purposeful; never communicate state with color alone.
- Keep table headers neutral. Use color for meaningful data distinctions and charts, not decoration. Avoid rainbow sections, gratuitous emoji, redundant pills and excessive uppercase micro-labels.
- Keep rich UI useful: concise headings, compact rows, checklists, comparisons, charts and working controls. Group related content without boxing every paragraph. Match the host theme, light/dark mode and mobile width.
