import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart' as mui;

import '../widgets/hermez_chat_palette.dart';
import 'hermez_morph_origin.dart';

/// Where the last press landed, recorded at press time (KaizenOS'
/// morphOrigin pattern): the control a card grows out of, without every
/// caller threading a context through. A press older than [_fresh] is stale.
class HermezPressOrigin {
  HermezPressOrigin._();

  static Rect? _rect;
  static double _radius = 16;
  static DateTime _at = DateTime.fromMillisecondsSinceEpoch(0);
  static bool _installed = false;
  static const _fresh = Duration(seconds: 2);

  /// Starts listening; idempotent. Called once at app start.
  static void install() {
    if (_installed) return;
    _installed = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  static void _onPointer(PointerEvent event) {
    if (event is! PointerDownEvent) return;
    final view = RendererBinding.instance.renderViews.firstOrNull;
    if (view == null) return;
    final result = HitTestResult();
    view.hitTest(result, position: event.position);
    final screen = view.size;
    // The pressed control: the innermost box of a control's size on the
    // hit path (not a glyph, not a whole page).
    for (final entry in result.path) {
      final target = entry.target;
      if (target is! RenderBox || !target.hasSize || !target.attached) continue;
      final size = target.size;
      if (size.width < 24 || size.height < 24) continue;
      if (size.width * size.height > screen.width * screen.height * 0.35) {
        break;
      }
      final topLeft = target.localToGlobal(Offset.zero);
      _rect = topLeft & size;
      _radius = math.min(size.shortestSide / 2, 20);
      _at = DateTime.now();
      return;
    }
  }

  /// The pressed control's rectangle if the press is fresh.
  static (Rect, double)? take() {
    final rect = _rect;
    if (rect == null || DateTime.now().difference(_at) > _fresh) return null;
    return (rect, _radius);
  }
}

/// Pushes one card (docs/app-design-2026-10-30, "One card"; Morphlet): the
/// control that was pressed grows into a floating card inset 16 from the
/// sides and 16 above the gesture area (or the keyboard), radius 32, on a
/// 34% scrim, and folds back into it on close. Shape, corners and colour
/// travel; the content is revealed by the growing clip, never stretched.
///
/// [from] (a context) or [origin] (a measured control) names the control
/// explicitly; otherwise the last fresh press is used, and without any the
/// card rises from the bottom edge.
Future<T?> pushHermezCard<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  BuildContext? from,
  HermezMorphOrigin? origin,
  Color? originColor,
  double maxHeightFactor = 0.86,
  String? semanticLabel,
  double? restingFactor,
  bool scrollsContent = true,
  bool dismissible = true,
  bool waitForClose = false,
}) async {
  final palette = HermezChatPalette.forBrightness(Theme.of(context).brightness);
  Rect? rect;
  double radius = 16;
  final box = from?.findRenderObject();
  if (box is RenderBox && box.attached && box.hasSize) {
    rect = box.localToGlobal(Offset.zero) & box.size;
    radius = math.min(box.size.shortestSide / 2, 20);
  }
  if (rect == null && origin != null) {
    rect = origin.resolve();
    radius = origin.radius;
    originColor ??= origin.color;
  }
  if (rect == null) {
    final pressed = HermezPressOrigin.take();
    if (pressed != null) (rect, radius) = pressed;
  }
  final route = _HermezCardRoute<T>(
    builder: builder,
    originRect: rect,
    originRadius: radius,
    originColor: originColor ?? palette.surface,
    cardColor: palette.raised,
    screenColor: palette.canvas,
    maxHeightFactor: maxHeightFactor,
    restingFactor: restingFactor,
    scrollsContent: scrollsContent,
    dismissible: dismissible,
    semanticLabel: semanticLabel,
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: Navigator.of(context).context,
    ),
  );
  final result = await Navigator.of(context).push<T>(route);
  // With [waitForClose], answer once the card has finished folding back:
  // sheet callers dispose controllers its fields still show until then.
  // Dialogs and menus answer on the tap, as they always have.
  if (waitForClose) await route.completed;
  return result;
}

class _HermezCardRoute<T> extends PopupRoute<T> {
  _HermezCardRoute({
    required this.builder,
    required this.originRect,
    required this.originRadius,
    required this.originColor,
    required this.cardColor,
    required this.screenColor,
    required this.maxHeightFactor,
    required this.capturedThemes,
    this.semanticLabel,
    this.restingFactor,
    this.scrollsContent = true,
    this.dismissible = true,
  });

  /// False for a question that must be answered: the scrim doesn't close
  /// it and it shows no grabber, only its answers.
  final bool dismissible;

  /// False when the content scrolls itself between a fixed header and
  /// footer: it then gets the card's bounded height instead of a scroll view.
  final bool scrollsContent;

  /// Set for a full-height card: it rests at this fraction of the screen
  /// and springs up to [maxHeightFactor] (magnetic, like Today's sheet).
  final double? restingFactor;

  final WidgetBuilder builder;
  final Rect? originRect;
  final double originRadius;
  final Color originColor;
  final Color cardColor;
  final double maxHeightFactor;
  final CapturedThemes capturedThemes;
  final String? semanticLabel;

  /// What the card becomes when it grows into a screen (m11): the canvas.
  final Color screenColor;

  /// 0 as a card, 1 once it has grown to fill the screen.
  late final AnimationController _grow = AnimationController(
    vsync: navigator!,
    duration: const Duration(milliseconds: 340),
  );

  Future<void> _growToScreen() => _grow.forward().orCancel.catchError((_) {});

  Future<void> _shrinkToCard() => _grow.reverse().orCancel.catchError((_) {});

  @override
  void dispose() {
    _grow.dispose();
    super.dispose();
  }

  @override
  // 42% ink: a touch deeper than before, now that nothing blurs behind.
  Color? get barrierColor => const Color(0x6B0A0C10);

  @override
  bool get barrierDismissible => dismissible;

  @override
  String? get barrierLabel => 'Close';

  // Timed to the owner's Morphlet reference recording: a control becomes
  // its card in about a third of a second with a small springy overshoot,
  // and folds back quicker and flat.
  @override
  Duration get transitionDuration => const Duration(milliseconds: 440);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 320);

  /// A gentle overshoot (about 4%) that settles: the frame lands with give.
  static const Curve _land = Cubic(0.34, 1.28, 0.64, 1);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final media = MediaQuery.of(context);
    final bottom = math.max(media.viewInsets.bottom, media.padding.bottom) + 16;
    final reduce = media.disableAnimations;
    final curved = CurvedAnimation(
      parent: animation,
      curve: _land,
      reverseCurve: Curves.easeInCubic,
    );
    final page = capturedThemes.wrap(
      Semantics(
        scopesRoute: true,
        namesRoute: true,
        label: semanticLabel,
        explicitChildNodes: true,
        child: Stack(
          children: [
            AnimatedBuilder(
              animation: _grow,
              builder: (context, card) {
                // Growing into a screen (m11): the inset, the corners and
                // the height go, so the card is the screen it opens.
                final g = Curves.easeInOutCubic.transform(_grow.value);
                return Padding(
                  padding: EdgeInsets.lerp(
                    EdgeInsets.fromLTRB(16, media.padding.top + 12, 16, bottom),
                    EdgeInsets.zero,
                    g,
                  )!,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: lerpDouble(480, media.size.width, g)!,
                        maxHeight: lerpDouble(
                          media.size.height * maxHeightFactor,
                          media.size.height,
                          g,
                        )!,
                        minHeight: media.size.height * g,
                      ),
                      child: card,
                    ),
                  ),
                );
              },
              child: AnimatedBuilder(
                animation: Listenable.merge([curved, _grow]),
                builder: (context, child) {
                  final t = reduce ? 1.0 : curved.value;
                  final g = _grow.value;
                  // The content rides in the growing shape and clears as it
                  // lands. No blur, here or behind the card: a live
                  // full-screen blur re-ran on every frame the card moved
                  // and was what made the cards stutter on the phone.
                  final clear = Curves.easeOut.transform(
                    (t * 1.4).clamp(0.0, 1.0),
                  );
                  // Growing into a screen, the content leaves early, so the
                  // card arrives as the screen's canvas, not a fading list.
                  final leave = Curves.easeOut.transform(
                    (g * 2.5).clamp(0.0, 1.0),
                  );
                  return _CardReveal(
                    t: t,
                    grow: g,
                    originRect: originRect,
                    originRadius: originRadius,
                    originColor: originColor,
                    cardColor: Color.lerp(cardColor, screenColor, g)!,
                    child: Opacity(
                      opacity: clear * (1 - leave),
                      child: RepaintBoundary(child: child),
                    ),
                  );
                },
                child: Material(
                  type: MaterialType.transparency,
                  // The material_ui fork's ink needs its own Material.
                  child: mui.Material(
                    type: mui.MaterialType.transparency,
                    child: restingFactor == null
                        ? _Grabbed(
                            scrolls: scrollsContent,
                            grabber: dismissible,
                            child: _Unpadded(builder: builder),
                          )
                        : _MagneticCard(
                            resting: media.size.height * restingFactor!,
                            raised: media.size.height * maxHeightFactor,
                            onDismiss: () => Navigator.of(context).maybePop(),
                            child: _Unpadded(builder: builder),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    // Reduced motion: a 150 ms cross-fade, no travel.
    return reduce ? FadeTransition(opacity: animation, child: page) : page;
  }
}

/// The card's grabber and its own scrolling when content outgrows it.
/// The card already floats clear of the status bar, the gesture area and
/// the screen edges, so its content gets none of that padding again (a
/// SafeArea inside would open a status-bar gap at the card's top).
class _Unpadded extends StatelessWidget {
  const _Unpadded({required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => MediaQuery.removePadding(
    context: context,
    removeTop: true,
    removeBottom: true,
    removeLeft: true,
    removeRight: true,
    child: HermezCardScope(child: Builder(builder: builder)),
  );
}

/// Marks content shown in the one card, so a dialog body inside it can drop
/// its own chrome and take the card's layout.
class HermezCardScope extends InheritedWidget {
  const HermezCardScope({super.key, required super.child});

  static bool within(BuildContext context) =>
      context.getInheritedWidgetOfExactType<HermezCardScope>() != null;

  @override
  bool updateShouldNotify(HermezCardScope oldWidget) => false;
}

class _Grabbed extends StatelessWidget {
  const _Grabbed({
    required this.child,
    this.scrolls = true,
    this.grabber = true,
  });

  final Widget child;
  final bool scrolls;
  final bool grabber;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!grabber) const SizedBox(height: 14),
        if (grabber)
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 8, bottom: 2),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        Flexible(
          child: scrolls
              ? SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: child,
                )
              : Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: child,
                ),
        ),
      ],
    );
  }
}

/// Paints the card at its rect between the control and its final place,
/// and reveals its content (laid out at the final size) through that rect.
class _CardReveal extends SingleChildRenderObjectWidget {
  const _CardReveal({
    required this.t,
    this.grow = 0,
    required this.originRect,
    required this.originRadius,
    required this.originColor,
    required this.cardColor,
    required super.child,
  });

  final double t;
  final double grow;
  final Rect? originRect;
  final double originRadius;
  final Color originColor;
  final Color cardColor;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCardReveal()..update(this);

  @override
  void updateRenderObject(BuildContext context, _RenderCardReveal render) =>
      render.update(this);
}

class _RenderCardReveal extends RenderProxyBox {
  double _t = 0;
  double _grow = 0;
  Rect? _origin;
  double _originRadius = 16;
  Color _originColor = Colors.transparent;
  Color _cardColor = Colors.white;

  void update(_CardReveal w) {
    _t = w.t;
    _grow = w.grow;
    _origin = w.originRect;
    _originRadius = w.originRadius;
    _originColor = w.originColor;
    _cardColor = w.cardColor;
    markNeedsPaint();
  }

  static const _radius = 32.0;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      _t > 0.98 && super.hitTest(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    final finalRect = offset & size;
    // Without a control the card rises from the bottom edge.
    final globalTopLeft = localToGlobal(Offset.zero);
    final start = _origin == null
        ? Rect.fromLTWH(
            finalRect.left,
            finalRect.bottom + 24,
            finalRect.width,
            finalRect.height * 0.6,
          )
        : _origin!.shift(offset - globalTopLeft);
    final rect = Rect.lerp(start, finalRect, _t)!;
    final radius = lerpDouble(_originRadius, _radius, _t)! * (1 - _grow);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final canvas = context.canvas;
    final color = Color.lerp(_originColor, _cardColor, math.min(1, _t * 1.6))!;
    canvas.drawShadow(
      Path()..addRRect(rrect),
      const Color(0x3D0A0C10),
      18 * _t,
      false,
    );
    canvas.drawRRect(rrect, Paint()..color = color);
    // The content arrives after the shape has left the control.
    // The widget above fades and sharpens the content; here it only rides
    // inside the growing shape.
    const reveal = 1.0;
    if (_t > 0) {
      context.pushClipRRect(needsCompositing, Offset.zero, rect, rrect, (
        context,
        _,
      ) {
        context.pushOpacity(offset, (reveal * 255).round(), (context, o) {
          context.paintChild(child, o);
        });
      });
    }
  }
}

/// Grows the card around [context] into the whole screen (m11, "the card
/// becomes the screen"): call it, then open the screen that takes its place.
Future<void> growHermezCardToScreen(BuildContext context) {
  final route = ModalRoute.of(context);
  return route is _HermezCardRoute ? route._growToScreen() : Future.value();
}

/// Returns a grown card to its card shape, when the screen it was opening
/// could not open.
Future<void> shrinkHermezCardToCard(BuildContext context) {
  final route = ModalRoute.of(context);
  return route is _HermezCardRoute ? route._shrinkToCard() : Future.value();
}

/// The card around [cardContext] becomes the screen [open] goes to (m11),
/// with [open] loading while the card grows rather than after it, so no
/// blank screen waits between them. Opening replaces the card; when [open]
/// stays (it failed and said so), the card returns to its shape.
Future<void> openFromHermesCard(
  BuildContext cardContext,
  Future<void> Function() open,
) async {
  final route = ModalRoute.of(cardContext);
  await Future.wait([growHermezCardToScreen(cardContext), open()]);
  if (route is _HermezCardRoute && route.isCurrent) {
    await route._shrinkToCard();
  }
}

/// The rect the card around [context] grew out of, or null outside a card.
@visibleForTesting
Rect? hermezCardOriginOf(BuildContext context) {
  final route = ModalRoute.of(context);
  return route is _HermezCardRoute ? route.originRect : null;
}

/// Pushes a full-height card: content that fills a sheet and scrolls inside
/// it (the Hermes sheets). It rests at [restingFactor] of the screen and
/// springs up to [raisedFactor]; dragging below resting closes it.
Future<T?> pushHermezFullCard<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  BuildContext? from,
  HermezMorphOrigin? origin,
  double restingFactor = 0.62,
  double raisedFactor = 0.91,
  String? semanticLabel,
}) => pushHermezCard<T>(
  context,
  builder: builder,
  from: from,
  origin: origin,
  maxHeightFactor: raisedFactor,
  restingFactor: math.min(restingFactor, raisedFactor),
  waitForClose: true,
  semanticLabel: semanticLabel,
);

/// A card with two magnetic detents. The top band (grabber and title)
/// drags it; release springs to the detent the velocity or position points
/// at, and dragging well below resting closes the card. The content gets a
/// definite height and keeps its own scrolling.
class _MagneticCard extends StatefulWidget {
  const _MagneticCard({
    required this.resting,
    required this.raised,
    required this.onDismiss,
    required this.child,
  });

  final double resting;
  final double raised;
  final VoidCallback onDismiss;
  final Widget child;

  @override
  State<_MagneticCard> createState() => _MagneticCardState();
}

class _MagneticCardState extends State<_MagneticCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _height = AnimationController.unbounded(
    vsync: this,
    value: widget.resting,
  );

  // The reference's settle: a little give, then still.
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 260,
    damping: 26,
  );

  static const _settle = SpringDescription(
    mass: 1,
    stiffness: 380,
    damping: 39,
  );

  @override
  void dispose() {
    _height.dispose();
    super.dispose();
  }

  // Where the drag began: a fling down closes the card only from resting.
  double _start = 0;

  void _drag(DragUpdateDetails details) {
    _height.value = (_height.value - details.delta.dy).clamp(
      widget.resting * 0.6,
      widget.raised,
    );
  }

  void _release(DragEndDetails details) {
    final v = -(details.primaryVelocity ?? 0); // positive: upward
    final h = _height.value;
    final fromResting = _start <= widget.resting + 4;
    if (h < widget.resting * 0.8 || (v < -900 && fromResting)) {
      widget.onDismiss();
      return;
    }
    final target = v > 500
        ? widget.raised
        : v < -500
        ? widget.resting
        : (h - widget.resting).abs() < (h - widget.raised).abs()
        ? widget.resting
        : widget.raised;
    _height.animateWith(SpringSimulation(_spring, h, target, v));
  }

  void _springTo(double target) {
    if (MediaQuery.of(context).disableAnimations) {
      _height.value = target;
      return;
    }
    // A step changing the height settles without give: critically damped,
    // so it never wobbles against the step growing inside it.
    _height.animateWith(SpringSimulation(_settle, _height.value, target, 0));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _height,
    builder: (context, child) =>
        SizedBox(height: _height.value.clamp(0.0, widget.raised), child: child),
    child: HermezCardDetents._(
      raise: () => _springTo(widget.raised),
      rest: () => _springTo(widget.resting),
      child: Stack(
        children: [
          Positioned.fill(child: widget.child),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 44,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragStart: (_) {
                _height.stop();
                _start = _height.value;
              },
              onVerticalDragUpdate: _drag,
              onVerticalDragEnd: _release,
            ),
          ),
        ],
      ),
    ),
  );
}

/// A full-height card's two heights, for a step inside it (a detail, a
/// form) that needs the card taller, and the step back that rests it again.
class HermezCardDetents extends InheritedWidget {
  const HermezCardDetents._({
    required this.raise,
    required this.rest,
    required super.child,
  });

  final VoidCallback raise;
  final VoidCallback rest;

  static HermezCardDetents? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<HermezCardDetents>();

  @override
  bool updateShouldNotify(HermezCardDetents oldWidget) => false;
}
