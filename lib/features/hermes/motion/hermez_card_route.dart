import 'dart:math' as math;
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart' as mui;

import '../widgets/hermez_chat_palette.dart';

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
/// [from] names the control explicitly; otherwise the last fresh press is
/// used, and without either the card rises from the bottom edge.
Future<T?> pushHermezCard<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  BuildContext? from,
  Color? originColor,
  double maxHeightFactor = 0.86,
  String? semanticLabel,
}) {
  final palette = HermezChatPalette.forBrightness(Theme.of(context).brightness);
  Rect? rect;
  double radius = 16;
  final box = from?.findRenderObject();
  if (box is RenderBox && box.attached && box.hasSize) {
    rect = box.localToGlobal(Offset.zero) & box.size;
    radius = math.min(box.size.shortestSide / 2, 20);
  }
  if (rect == null) {
    final pressed = HermezPressOrigin.take();
    if (pressed != null) (rect, radius) = pressed;
  }
  return Navigator.of(context).push<T>(
    _HermezCardRoute<T>(
      builder: builder,
      originRect: rect,
      originRadius: radius,
      originColor: originColor ?? palette.surface,
      cardColor: palette.raised,
      maxHeightFactor: maxHeightFactor,
      semanticLabel: semanticLabel,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: Navigator.of(context).context,
      ),
    ),
  );
}

class _HermezCardRoute<T> extends PopupRoute<T> {
  _HermezCardRoute({
    required this.builder,
    required this.originRect,
    required this.originRadius,
    required this.originColor,
    required this.cardColor,
    required this.maxHeightFactor,
    required this.capturedThemes,
    this.semanticLabel,
  });

  final WidgetBuilder builder;
  final Rect? originRect;
  final double originRadius;
  final Color originColor;
  final Color cardColor;
  final double maxHeightFactor;
  final CapturedThemes capturedThemes;
  final String? semanticLabel;

  @override
  Color? get barrierColor => const Color(0x570A0C10); // 34% ink

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Close';

  // Timed to the owner's Morphlet reference recording: a control becomes
  // its card in about a third of a second with a small springy overshoot,
  // and folds back quicker and flat.
  @override
  Duration get transitionDuration => const Duration(milliseconds: 340);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 240);

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
            // The page behind blurs as well as dims, as in the reference.
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: animation,
                  builder: (context, _) {
                    final sigma = (reduce ? 1.0 : animation.value) * 14;
                    return sigma < 0.5
                        ? const SizedBox.expand()
                        : BackdropFilter(
                            filter: ImageFilter.blur(
                              sigmaX: sigma,
                              sigmaY: sigma,
                            ),
                            child: const SizedBox.expand(),
                          );
                  },
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                media.padding.top + 12,
                16,
                bottom,
              ),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 480,
                    maxHeight: media.size.height * maxHeightFactor,
                  ),
                  child: AnimatedBuilder(
                    animation: curved,
                    builder: (context, child) {
                      final t = reduce ? 1.0 : curved.value;
                      // The content is there from the first frame, blurred and
                      // faint, and sharpens as the card lands.
                      final clear = t.clamp(0.0, 1.0);
                      final blur = (1 - clear) * 10;
                      return _CardReveal(
                        t: t,
                        originRect: originRect,
                        originRadius: originRadius,
                        originColor: originColor,
                        cardColor: cardColor,
                        child: Opacity(
                          opacity: Curves.easeOut.transform(clear),
                          child: blur < 0.3
                              ? child
                              : ImageFiltered(
                                  imageFilter: ImageFilter.blur(
                                    sigmaX: blur,
                                    sigmaY: blur,
                                  ),
                                  child: child,
                                ),
                        ),
                      );
                    },
                    child: Material(
                      type: MaterialType.transparency,
                      // The material_ui fork's ink needs its own Material.
                      child: mui.Material(
                        type: mui.MaterialType.transparency,
                        child: _Grabbed(child: Builder(builder: builder)),
                      ),
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
class _Grabbed extends StatelessWidget {
  const _Grabbed({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
          child: SingleChildScrollView(
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
    required this.originRect,
    required this.originRadius,
    required this.originColor,
    required this.cardColor,
    required super.child,
  });

  final double t;
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
  Rect? _origin;
  double _originRadius = 16;
  Color _originColor = Colors.transparent;
  Color _cardColor = Colors.white;

  void update(_CardReveal w) {
    _t = w.t;
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
    final radius = lerpDouble(_originRadius, _radius, _t)!;
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
