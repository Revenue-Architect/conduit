# Hermez motion system

Hermez motion is spatial continuity. A control the user touches should be the same object on the next screen. This is not a visual redesign and it is not the generic Conduit animation service.

Conduit durations and curves stay in `lib/core/services/animation_service.dart`. Hermez springs, shared elements, and route shells stay in `lib/features/hermes/motion/`. Product screens import `hermez_motion.dart`. They do not import `nib_motion` directly.

`nib_motion` is pinned at `0.3.1`.

## Weights

Screens choose `HermezMotionWeight`, not raw stiffness.

| Weight | Use | Press scale | Spring |
| --- | --- | --- | --- |
| light | icons, chips, small controls | 0.96 | mass 0.65, stiffness 420, damping 32 |
| medium | cards, bot tiles, sheets | 0.98 | mass 0.9, stiffness 340, damping 30 |
| heavy | large panel expansion | 0.99 | mass 1.1, stiffness 260, damping 28 |

Larger objects move less.

## Primitives

- `HermezMotionSurface` — press spring, then the tap. Reduced motion keeps the tap and skips the scale.
- `HermezMorph` — Flutter `Hero`. Reduced motion, or a null id, renders the child with no flight.
- `HermezPresence` — enter/exit for something that really mounts and unmounts. Stable keys. Do not replay this on every Riverpod rebuild.
- `HermezMotionGroup` — FLIP for a small keyed set. Do not wrap a long scrolling list.
- `buildHermezMotionPage` — Hermes route shell. `standard` is a short fade and a few pixels of rise. `morph` keeps the page still so the shared element is the motion. While a route covers another Hermes page, the source scales to `0.988` and fades to `0.94`.

## Shared-element ids

```text
bot:<profile>
```

`hermezBotMorphId` returns null unless the profile matches Hermes' profile pattern, so two invalid names cannot collide.

The first reference interaction is Home bot card → Bot Detail. The mark and name are the shared object. Back uses the same route transition in reverse. The card still opens `RouteNames.hermesBotDetail` for that profile.

## Reduced motion

`context.reduceMotion` is authoritative. `HermesPageChrome` passes it into `NibMotionConfig`. Reduced motion uses a short fade instead of a flight. Navigation still completes.

## Not in this pass

Schedule → Jobs, Kanban task flights, artifact preview flights, and Steel fullscreen expansion are later, after the bot transition is tuned on the S25 Ultra. The inline live-activity surface already grows in place with `AnimatedSize`. Do not replace that control tree to add motion.

Do not use `NibBounce`, `NibRubberBand`, or `NibFloat`. Do not animate streaming chat tokens.
