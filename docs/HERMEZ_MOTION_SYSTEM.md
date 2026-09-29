# Hermez motion system

Hermez motion is spatial continuity. The object the user touches stays the same object on the next screen. **Nothing in Hermez animates opacity.** Objects compress, travel, grow, recede, unroll, and roll away on springs. The one intentional exception is the dim behind a sheet or dialog, which darkens with the sheet's position.

Conduit's generic durations stay in `lib/core/services/animation_service.dart`. Hermez motion lives in `lib/features/hermes/motion/`. Screens import `hermez_motion.dart`; they do not import `nib_motion` directly. `nib_motion` is pinned at exactly `0.3.1`.

## Weights and springs

Screens pick a `HermezMotionWeight`, never raw spring values.

| Weight | Use | Press scale | Spring (mass / stiffness / damping) | Settles in |
| --- | --- | --- | --- | --- |
| light | icons, chips, rows, small controls | 0.955 | 0.65 / 420 / 32 | ~0.30 s |
| medium | cards, sheets, sibling pages | 0.978 | 1 / 385 / 39.3 | ~0.43 s |
| heavy | a page growing out of a card | 0.99 | 1 / 300 / 34 | ~0.46 s |
| push (`springPush`, not a weight) | a sheet growing out of a card and pushing the screen above it | — | 1.7 / 210 / 37.8 | ~0.75 s both ways |

All three are critically damped (damping ratio 0.97 to 1.0). **Do not add a bouncy spring to a duration-driven animation.** The curve is clamped to [0, 1], so any overshoot turns into a dead hold: the old medium spring (0.9 / 340 / 30, ratio 0.86) reached 99 % at 0.24 s and then sat still until 0.41 s, so every medium open and close stopped, waited, and snapped when the route or presence finished. A test (`every Hermez spring keeps moving until it settles`) guards this.

`HermezSpringCurve` turns a spring into a `Curve` sampled over its own settle time (within 0.2 % of the target and barely moving), rescaled so that moment is exactly 1, so the last frame never jumps. Route controllers, `AnimatedSize`, Hero flights, and dialogs move with the same physics as NibMotion. Its output is clamped to [0, 1] (Hero and `Interval` assert that range). Reverse motion always uses `curve.flipped`, so Back starts moving immediately. Exits are faster than entries: expanding routes reverse on the medium spring.

## Primitives

- `HermezMotionSurface`: physical press. Compresses on pointer-down (before the gesture arena decides), springs back on lift or when the finger starts to scroll (12 px slop), fires on a real tap only, and is a semantic button. `onOpen` passes a `HermezMorphOrigin` so the destination can grow out of it. `HermezSurface` uses it for every tappable card.
- `HermezMorph` / `HermezMorphText` / `HermezMorphSurface`: Flutter `Hero` wrappers. Every part of an object is its own morph (`bot:kai#mark`, `#kind`, `#name`, `#about`, `#dot`, `#status`, `#motif`) so parts never nest and each keeps its geometry. Flights: `scale` (the detailed rendering scaled into the flight box), text (size, weight, colour, and line wrapping interpolate; `inherit` is normalised first), `stretch` (decorative marks resize with their container), `surface` (decoration lerp). Reduced motion or a null id renders the child with no flight.
- `HermezMorphOrigin`: the tapped object's rectangle in its route's coordinate space, plus radius, fill, and border. It holds the source render box so Back contracts into where the card is now. It travels only as navigation `extra`; it is never global state.
- Routes (`hermez_motion_route.dart`):
  - `HermezRouteMotion.expand`: the destination grows out of the origin as **one object**. The page is laid out once at its final size and scaled (`_HermezSheetFrame._zoom`) so it exactly fills the aperture, whose rect, radius, fill, shadow, and the source's border interpolate. Text, motifs, and decorations ride inside the container; nothing flies on its own path or timing. `HeroMode` is disabled inside expand routes. Expanding pages are non-opaque so the source stays painted and Back contracts on its first frame.
  - `HermezRouteExits.leaveForAnotherDestination()`: call before `router.go` to somewhere else (Bot Detail → new chat). The popping expand page then slides out instead of contracting into a card that is about to disappear.
  - `HermezRouteMotion.standard`: sibling push, slides in from the trailing edge; the page underneath shifts back 14 %. A leading-edge shadow is painted only while moving.
  - `pushHermezSheet` / `pushHermezSheetRoute`: a sheet that grows out of the tapped row or card (or rises from the bottom edge), drag-down to close, tap-outside or Back to close, lifts above the keyboard. The route page stays full screen at the navigator origin and the sheet is placed inside it; Hero flights measure against the page, so this matters. The returned future completes after the sheet has contracted home, so follow-up navigation never starts under a sheet in flight.
  - The screen under an expanding page recedes to scale 0.988; under a sibling push it shifts back.
  - **A sheet pushes the screen it grew out of** (`HermezCoverKind.lift`). `hermezSheetAperture` is the one geometry for both sides: the card first widens to the screen's width where it is, then its top edge rises to the sheet's top (ease-in-out cubic, so the push starts with resistance). The Hermez screen underneath is pushed up by exactly as far as that edge has risen above the card (`HermezRouteTransitions._pushAt`), so the content right above the card stays against the sheet. Closing runs it backwards and pulls the screen down, taking as long as the push (no fast exit for sheets). Dragging the sheet down pulls the screen with the finger. The pushed screen only translates; it does not recede. Sheets with no card keep a gentle lift (`liftFor`, 6 % of the height, 32 to 64 dp). The chat screen is a no-transition page and stays still.
  - `HermezPushPageTransitionsBuilder` replaces Android's fading Zoom transition for every Material route in the app.
- `HermezEntrance(order:)`: currently a pass-through (`HermezEntrance.staggered = false`). Secondary content arrives with the container it belongs to; staggered parts read as separate objects.
- `HermezPresence` / `HermezReveal` / `HermezUnroll`: real mount and unmount. The section slides out from under its top edge and back under it, keeping its shape (a drawer), instead of being sliced by a clip sweeping across it. Children keep full width.
- `HermezSwitch.glyph` / `.unroll` / `.column`: fade-free `transitionBuilder`s and `layoutBuilder` for any `AnimatedSwitcher` in the app (code-block copy/collapse icons, the streaming footer, banners, selection checks). An `AnimatedSwitcher` without a `transitionBuilder` fades; always pass one, or `duration: Duration.zero` for text that changes in place.
- **Mobile side navigation** (`physical_side_nav.dart`, driven by `ResponsiveDrawerLayout`): the chat is a full-width sheet that slides off to the right (`x = W * p`) to reveal the navigation underneath. A 44 px return rail stays glued to its leading edge. One controller runs 520 ms on `Cubic(0.22, 0.61, 0.36, 1.0)` (Calendar-Master's navigation curve, not a Hermez spring) and reverses from the current frame. `sideNavGeometryFor` is the single geometry. The navigation labels settle in 30 ms apart from the same progress. They translate 14 px and are **the one sanctioned opacity change**, which the side-navigation spec asked for; everything else stays fade-free.
- `HermezSize`: `AnimatedSize` on a Hermez spring.
- `HermezMotionGroup`: short keyed column. Moved children travel (FLIP through NibMotion controllers), new ones unroll, removed ones roll away. Positions are recorded after each frame's layout and never read during a build.
- `HermezIconSwap`: an icon that changes meaning turns and scales in place.
- `HermezRouteCanvas`: the page canvas starts as the source card's colour and settles to the canvas colour (a colour change, not opacity).
- `ConduitDialogRoute` / `showConduitDialog` (`lib/shared/widgets/conduit_dialog_route.dart`): dialogs unfold from their centre line on a spring instead of fading. `ThemedDialogs`, `AdaptiveDialog`, Hermes, MCP, settings, and Kanban dialogs use it.

## Reference interactions

On expand routes and origin sheets the whole destination travels as one object. Part morphs (the "What travels" column) fly only when the same ids meet on a `standard` route.

| Interaction | What travels | What unrolls |
| --- | --- | --- |
| Home bot card → Bot Detail | mark, BOT, name, description, status dot, status text, etched motif | chat CTA, metrics, capabilities, conversations, schedules |
| Home Schedule card → Jobs | "Scheduled agents" title, card motif → header marks | subtitle, New job, job list |
| Home Board card → Kanban | "Kanban" title, card motif → header marks | board |
| Today row / Bot Detail schedule row → Scheduled Agent sheet | job title | sheet body |
| Kanban task card → task sheet | task title | sheet body |
| Artifact tile → artifact sheet | thumbnail image, file name | preview actions, related conversation |
| Inline run surface → attention sheet | the surface grows into the sheet | decision UI |
| Steer pill → steer field (`HermesRunActions`) | the pill itself stretches across its row; icon and label stay put, the send control grows in at the moving edge | the text field, uncovered by the travelling edge |
| Inline browser aperture → full-screen Steel | aperture grows; the WebView is created only after the route settles | caption |

Bot marks (`hermez_bot_mark.dart`) are drawn to match the reference renders: spherical white shell, side disc, dark visor turned right, glowing eyes, and profile parts (Kai crest and gem, Strong armour and lit slot, Fast fins and streaks, Local vents and lens, Autopilot antenna).

## Rules

- **One structure for the whole animation.** A transition must return the same widget types on every frame and at rest. Swapping wrappers (a slide for a scale when a route is pushed on top, dropping a clip when an unfold finishes, a slide-out on leave) remounts the page mid-motion and reads as a stutter; set a neutral value (scale 1, offset zero, `Clip.none`) instead. `HermezCoveredTransition`, `_HermezSheetFrame`, and `ConduitDialogRoute` follow this.
- **Never create a `CurvedAnimation` in `buildTransitions` or a builder that runs per frame.** Each one adds a status listener to the route controller that is never removed. Use `hermezCurved(parent, curve, reverseOf:)`, which shares one per parent and curve.
- **Reverse curves are mirrors.** A `reverseCurve` or `switchOutCurve` is played backwards, so an ease-out curve there starts slowly and slams into its last frame. Use `curve.flipped` (or `Curves.easeIn*` for an ease-out exit).
- **Do not nest size animations.** An `AnimatedSize` around content that already animates its own size (reveals, presence) trails behind every frame and settles late. The inline run surface dropped its outer `HermezSize` for this reason.

- No opacity animation anywhere in Hermez, including chat (streaming content, activity dot, greeting, scroll button, composer icons, loading states, image previews). Message entrance is instant; streaming tokens never animate.
- Measure positions only after layout. Reading `localToGlobal` during a build can throw when an ancestor is mid-layout and leaves the element tree half-updated (seen on device as `_dependents.isEmpty`).
- Platform views (Steel WebView) never sit inside an animated clip or transform. The inline browser block is deliberately plain.
- Morph ids come from model ids (`bot:<profile>`, `job:<profile>:<id>`, `kanban:<board>:<task>`, `artifact:<path>`, `session:<id>:browser`), never list positions.
- Reduced motion (`context.reduceMotion`): no flights, instant routes, no press scale, instant presence.
- Do not use `NibBounce`, `NibRubberBand`, `NibFloat`, `NibGlass`, or `NibScaffold`.
