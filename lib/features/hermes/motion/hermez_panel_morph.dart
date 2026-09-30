import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';

import '../feedback/hermez_feedback.dart';
import 'hermez_morph_origin.dart';
import 'hermez_motion_route.dart' show hermezCurved;
import 'hermez_motion_tokens.dart';

/// Builds the face of the object a panel grew out of: what the button looked
/// like. [progress] runs from 0 (the button) to 1 (the open panel) and may
/// overshoot 1 slightly on the way open, so a caller can turn a glyph with it.
typedef HermezPanelFaceBuilder = Widget Function(
  BuildContext context,
  Animation<double> progress,
);

/// Motion for a button that becomes a panel.
///
/// Opening is a spring with a light bounce (about 3 %); closing is Hermez's
/// critically damped medium spring, so the panel goes home decisively and
/// without a wobble. The two settle in roughly 0.39 s and 0.32 s.
abstract final class HermezPanelMotion {
  static final HermezBounceCurve open = HermezBounceCurve();

  /// How far the face of the source slides toward the panel's inside, and
  /// how far the panel's content starts from, while it wipes across.
  static const faceSlide = 40.0;
}

/// A spring that is allowed to overshoot 1, unlike `HermezSpringCurve`, which
/// clamps. Route geometry may pass its target a little; nothing that needs
/// [0, 1] (opacity, intervals) should be driven by this.
class HermezBounceCurve extends Curve {
  HermezBounceCurve({
    double mass = 1,
    double stiffness = 520,
    double damping = 34,
  }) : _simulation = SpringSimulation(
         SpringDescription(mass: mass, stiffness: stiffness, damping: damping),
         0,
         1,
         0,
       ) {
    _settleSeconds = _settleTime(_simulation);
    _endValue = _simulation.x(_settleSeconds);
  }

  final SpringSimulation _simulation;
  late final double _settleSeconds;
  late final double _endValue;

  /// How long the spring takes to be visibly at rest.
  Duration get settleDuration =>
      Duration(microseconds: (_settleSeconds * 1e6).round());

  /// The highest value the curve reaches, as a multiple of the target.
  double get peak {
    var best = 0.0;
    for (var i = 0; i <= 200; i++) {
      best = math.max(best, transformInternal(i / 200));
    }
    return best;
  }

  @override
  double transformInternal(double t) =>
      _simulation.x(t * _settleSeconds) / _endValue;

  /// The last moment the spring is outside 0.2 % of its target or still
  /// moving, so an oscillation cannot be mistaken for rest at a crossing.
  static double _settleTime(SpringSimulation simulation) {
    const step = 1 / 600;
    var last = 0.0;
    for (var time = step; time < 3; time += step) {
      if ((simulation.x(time) - 1).abs() >= 0.002 ||
          simulation.dx(time).abs() >= 0.1) {
        last = time;
      }
    }
    return last + step;
  }
}

/// Pushes a panel that a button turns into.
///
/// The button's rectangle and corner radius grow into a content-sized panel
/// (top-anchored, centred, clear of the status bar and the keyboard). The
/// button's [faceBuilder] rides the growing surface, turns and shrinks away
/// while [builder]'s content slides across it from the side the button sits
/// on. Nothing changes opacity. Closing runs it home into the button.
///
/// The caller hides the real button while this is up (the face stands in for
/// it) and shows it again when the returned future completes, which is only
/// after the panel has finished contracting.
Future<T?> pushHermezPanel<T>(
  BuildContext context, {
  required HermezMorphOrigin origin,
  required HermezPanelFaceBuilder faceBuilder,
  required WidgetBuilder builder,
  ThemeData? theme,
  Color? surfaceColor,
  double radius = 28,
  double maxWidth = 440,
  double originElevation = 0,
  String? semanticLabel,
}) async {
  final navigator = Navigator.of(context);
  final route = HermezPanelRoute<T>(
    origin: origin,
    builder: builder,
    faceBuilder: faceBuilder,
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: navigator.context,
    ),
    theme: theme,
    surfaceColor: surfaceColor,
    radius: radius,
    maxWidth: maxWidth,
    originElevation: originElevation,
    semanticLabel: semanticLabel,
    reducedMotion: MediaQuery.maybeDisableAnimationsOf(context) ?? false,
  );
  final result = await navigator.push<T>(route);
  await route.completed;
  return result;
}

/// The route behind [pushHermezPanel]: a popup over the screen it came from,
/// dismissed by Back or by tapping outside it.
class HermezPanelRoute<T> extends PopupRoute<T> {
  HermezPanelRoute({
    required this.origin,
    required this.builder,
    required this.faceBuilder,
    required this.capturedThemes,
    this.theme,
    this.surfaceColor,
    this.radius = 28,
    this.maxWidth = 440,
    this.originElevation = 0,
    this.semanticLabel,
    this.reducedMotion = false,
    super.settings,
  });

  final HermezMorphOrigin origin;
  final WidgetBuilder builder;
  final HermezPanelFaceBuilder faceBuilder;
  final CapturedThemes capturedThemes;
  final ThemeData? theme;
  final Color? surfaceColor;
  final double radius;
  final double maxWidth;
  final double originElevation;
  final String? semanticLabel;
  final bool reducedMotion;

  @override
  Duration get transitionDuration =>
      reducedMotion ? Duration.zero : HermezPanelMotion.open.settleDuration;

  // Leaving is quicker than arriving: the object returns home decisively.
  @override
  Duration get reverseTransitionDuration => reducedMotion
      ? Duration.zero
      : HermezMotion.settleFor(HermezMotionWeight.medium);

  @override
  bool get barrierDismissible => true;

  @override
  Color? get barrierColor => const Color(0x8A000000);

  @override
  String? get barrierLabel => 'Dismiss';

  @override
  bool didPop(T? result) {
    final popped = super.didPop(result);
    // The object returns into the button it came from: a soft closing latch.
    if (popped && !reducedMotion) {
      HermezFeedback.play(HermezFeedbackCue.objectClose);
    }
    return popped;
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final progress = hermezCurved(
      animation,
      HermezPanelMotion.open,
      reverseOf: HermezMotion.curveMedium,
    );
    Widget page = _HermezPanelPage<T>(
      route: this,
      animation: animation,
      progress: progress,
    );
    final theme = this.theme;
    if (theme != null) page = Theme(data: theme, child: page);
    return capturedThemes.wrap(page);
  }
}

class _HermezPanelPage<T> extends StatefulWidget {
  const _HermezPanelPage({
    required this.route,
    required this.animation,
    required this.progress,
  });

  final HermezPanelRoute<T> route;
  final Animation<double> animation;
  final Animation<double> progress;

  @override
  State<_HermezPanelPage<T>> createState() => _HermezPanelPageState<T>();
}

class _HermezPanelPageState<T> extends State<_HermezPanelPage<T>> {
  HermezPanelRoute<T> get route => widget.route;
  Animation<double> get animation => widget.animation;
  Animation<double> get progress => widget.progress;

  @override
  void initState() {
    super.initState();
    // The last value notification arrives before the status flips to
    // completed, so input would never unlock from the value alone.
    animation.addStatusListener(_onStatus);
  }

  @override
  void dispose() {
    animation.removeStatusListener(_onStatus);
    super.dispose();
  }

  void _onStatus(AnimationStatus status) {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final surface = route.surfaceColor ?? Theme.of(context).colorScheme.surface;
    // Built once: only the morph's geometry changes while it opens, so the
    // panel's own widgets are not rebuilt on every animation frame.
    final content = RepaintBoundary(
      child: ColoredBox(
        color: surface,
        child: Material(
          type: MaterialType.transparency,
          child: Builder(
            builder: (context) => MediaQuery.removePadding(
              context: context,
              removeTop: true,
              removeBottom: true,
              child: MediaQuery.removeViewInsets(
                context: context,
                removeBottom: true,
                child: DefaultTextStyle(
                  style:
                      Theme.of(context).textTheme.bodyMedium ??
                      const TextStyle(),
                  child: route.builder(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Semantics(
      scopesRoute: true,
      namesRoute: route.semanticLabel != null,
      explicitChildNodes: true,
      label: route.semanticLabel,
      child: AnimatedBuilder(
        animation: progress,
        child: content,
        builder: (context, content) {
          final media = MediaQuery.of(context);
          // Input waits for the panel to be at rest: a moving target cannot
          // be aimed at. A tap on it meanwhile is swallowed, not read as a
          // tap outside; tapping outside still closes it at any moment.
          final interactive = animation.status == AnimationStatus.completed;
          // Gone by half way open: mounted only while it can be seen.
          final face = progress.value >= 0.6
              ? null
              : ExcludeSemantics(
                  child: RepaintBoundary(
                    child: route.faceBuilder(context, progress),
                  ),
                );
          return HermezPanelMorph(
            progress: progress,
            resolveOrigin: route.origin.resolve,
            originRadius: route.origin.radius,
            originColor:
                route.origin.color ?? route.surfaceColor ?? Colors.grey,
            originElevation: route.originElevation,
            surfaceColor: surface,
            radius: route.radius,
            maxWidth: route.maxWidth,
            padding: EdgeInsets.fromLTRB(
              math.max(16, media.padding.left),
              media.padding.top + 12,
              math.max(16, media.padding.right),
              media.viewInsets.bottom > 0
                  ? media.viewInsets.bottom + 12
                  : math.max(12, media.padding.bottom),
            ),
            textDirection: Directionality.of(context),
            face: face,
            content: AbsorbPointer(absorbing: !interactive, child: content!),
          );
        },
      ),
    );
  }
}

/// The two things a [HermezPanelMorph] paints: the panel and the button's
/// face.
enum HermezPanelSlot { content, face }

/// Lays out a content-sized panel and paints it grown out of a button.
///
/// The panel is laid out once, at its final size. What the user sees is a
/// rounded aperture that travels from the button's rectangle to the panel's,
/// carrying the panel's own colour, with the button's face and the panel's
/// content revealed through it. When the panel's content changes size (a
/// section opening, an error appearing) the panel follows it every frame with
/// its top edge fixed, so it behaves like any other Hermez section.
class HermezPanelMorph
    extends SlottedMultiChildRenderObjectWidget<HermezPanelSlot, RenderBox> {
  const HermezPanelMorph({
    super.key,
    required this.progress,
    required this.resolveOrigin,
    required this.originRadius,
    required this.originColor,
    required this.originElevation,
    required this.surfaceColor,
    required this.radius,
    required this.maxWidth,
    required this.padding,
    required this.textDirection,
    required this.content,
    this.face,
  });

  final Animation<double> progress;

  /// Where the button is now, in this widget's coordinate space.
  final Rect Function() resolveOrigin;
  final double originRadius;
  final Color originColor;
  final double originElevation;
  final Color surfaceColor;
  final double radius;
  final double maxWidth;

  /// Clear space around the panel: the safe area, the keyboard and margins.
  final EdgeInsets padding;
  final TextDirection textDirection;
  final Widget content;

  /// The button's face while the panel is not fully open; null once it is.
  final Widget? face;

  @override
  Iterable<HermezPanelSlot> get slots => HermezPanelSlot.values;

  @override
  Widget? childForSlot(HermezPanelSlot slot) => switch (slot) {
    HermezPanelSlot.content => content,
    HermezPanelSlot.face => face,
  };

  @override
  RenderHermezPanelMorph createRenderObject(BuildContext context) =>
      RenderHermezPanelMorph(
        progress: progress,
        resolveOrigin: resolveOrigin,
        originRadius: originRadius,
        originColor: originColor,
        originElevation: originElevation,
        surfaceColor: surfaceColor,
        radius: radius,
        maxWidth: maxWidth,
        padding: padding,
        textDirection: textDirection,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderHermezPanelMorph renderObject,
  ) {
    renderObject
      ..progress = progress
      ..resolveOrigin = resolveOrigin
      ..originRadius = originRadius
      ..originColor = originColor
      ..originElevation = originElevation
      ..surfaceColor = surfaceColor
      ..radius = radius
      ..maxWidth = maxWidth
      ..padding = padding
      ..textDirection = textDirection;
  }
}

class RenderHermezPanelMorph extends RenderBox
    with SlottedContainerRenderObjectMixin<HermezPanelSlot, RenderBox> {
  RenderHermezPanelMorph({
    required Animation<double> progress,
    required Rect Function() resolveOrigin,
    required double originRadius,
    required Color originColor,
    required double originElevation,
    required Color surfaceColor,
    required double radius,
    required double maxWidth,
    required EdgeInsets padding,
    required TextDirection textDirection,
  }) : _progress = progress,
       _resolveOrigin = resolveOrigin,
       _originRadius = originRadius,
       _originColor = originColor,
       _originElevation = originElevation,
       _surfaceColor = surfaceColor,
       _radius = radius,
       _maxWidth = maxWidth,
       _padding = padding,
       _textDirection = textDirection;

  Animation<double> _progress;
  set progress(Animation<double> value) {
    if (identical(_progress, value)) return;
    if (attached) _progress.removeListener(_onProgress);
    _progress = value;
    if (attached) _progress.addListener(_onProgress);
    markNeedsPaint();
  }

  Rect Function() _resolveOrigin;
  set resolveOrigin(Rect Function() value) {
    if (_resolveOrigin == value) return;
    _resolveOrigin = value;
    markNeedsLayout();
  }

  double _originRadius;
  set originRadius(double value) {
    if (_originRadius == value) return;
    _originRadius = value;
    markNeedsPaint();
  }

  Color _originColor;
  set originColor(Color value) {
    if (_originColor == value) return;
    _originColor = value;
    markNeedsPaint();
  }

  double _originElevation;
  set originElevation(double value) {
    if (_originElevation == value) return;
    _originElevation = value;
    markNeedsPaint();
  }

  Color _surfaceColor;
  set surfaceColor(Color value) {
    if (_surfaceColor == value) return;
    _surfaceColor = value;
    markNeedsPaint();
  }

  double _radius;
  set radius(double value) {
    if (_radius == value) return;
    _radius = value;
    markNeedsPaint();
  }

  double _maxWidth;
  set maxWidth(double value) {
    if (_maxWidth == value) return;
    _maxWidth = value;
    markNeedsLayout();
  }

  EdgeInsets _padding;
  set padding(EdgeInsets value) {
    if (_padding == value) return;
    _padding = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  // Geometry from the last layout.
  Rect _origin = Rect.zero;
  Rect _panel = Rect.zero;
  bool _anchorEnd = true;
  bool _anchorBottom = true;

  // Geometry from the last paint, for hit testing and transforms.
  Rect _aperture = Rect.zero;
  Offset _contentOffset = Offset.zero;
  Offset _faceOrigin = Offset.zero;

  /// The travelling surface as painted last frame. For tests.
  @visibleForTesting
  Rect get apertureRect => _aperture;

  /// Where the panel rests once fully open. For tests.
  @visibleForTesting
  Rect get panelRect => _panel;

  /// The source button's rectangle. For tests.
  @visibleForTesting
  Rect get originRect => _origin;

  RenderBox? get _content => childForSlot(HermezPanelSlot.content);
  RenderBox? get _face => childForSlot(HermezPanelSlot.face);

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _progress.addListener(_onProgress);
  }

  @override
  void detach() {
    _progress.removeListener(_onProgress);
    super.detach();
  }

  void _onProgress() {
    markNeedsPaint();
    // The content's place is final once the panel is open.
    if (_progress.value >= 1) markNeedsSemanticsUpdate();
  }

  @override
  bool get sizedByParent => false;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    size = constraints.biggest;
    final content = _content;
    final available = math.max(
      0.0,
      math.min(size.width - _padding.horizontal, _maxWidth),
    );
    final maxHeight = math.max(0.0, size.height - _padding.vertical);
    if (content != null) {
      content.layout(
        BoxConstraints(
          minWidth: available,
          maxWidth: available,
          maxHeight: maxHeight,
        ),
        parentUsesSize: true,
      );
      _panel = Rect.fromLTWH(
        (size.width - available) / 2,
        _padding.top,
        available,
        content.size.height,
      );
    } else {
      _panel = Rect.zero;
    }
    _origin = _resolveOrigin();
    final face = _face;
    if (face != null) face.layout(BoxConstraints.tight(_origin.size));
    // The button's face rides the corner of the surface nearest the button.
    _anchorEnd = _origin.center.dx >= _panel.center.dx;
    _anchorBottom = _origin.center.dy >= _panel.center.dy;
  }

  static double _smooth(double value, double from, double to) {
    final x = ((value - from) / (to - from)).clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final content = _content;
    if (content == null) return;
    final t = _progress.value;
    final settled = t.clamp(0.0, 1.0);

    // The surface travels from the button to the panel. Unclamped, so the
    // opening bounce carries it a hair past the panel and back.
    final aperture = Rect.fromLTRB(
      lerpDouble(_origin.left, _panel.left, t)!,
      lerpDouble(_origin.top, _panel.top, t)!,
      lerpDouble(_origin.right, _panel.right, t)!,
      lerpDouble(_origin.bottom, _panel.bottom, t)!,
    );
    _aperture = aperture;
    final radius = lerpDouble(_originRadius, _radius, settled)!;
    final rrect = RRect.fromRectAndRadius(
      aperture.shift(offset),
      Radius.circular(radius),
    );

    // The surface is the button's colour until the content has covered it.
    final slab = Color.lerp(
      _originColor,
      _surfaceColor,
      _smooth(settled, 0.45, 0.85),
    )!;
    final elevation = lerpDouble(_originElevation, 14, settled)!;
    if (elevation > 0) {
      context.canvas.drawShadow(
        Path()..addRRect(rrect),
        const Color(0xFF000000),
        elevation,
        false,
      );
    }
    context.canvas.drawRRect(rrect, Paint()..color = slab);

    // The content wipes across from the button's side; the face turns and
    // shrinks away toward the inside as it is covered.
    final wipe = _smooth(settled, 0.10, 0.72);
    final side = _anchorEnd ? 1.0 : -1.0;
    _contentOffset = Offset(
      aperture.left + (1 - wipe) * aperture.width * side,
      aperture.top,
    );
    final fade = _smooth(settled, 0.0, 0.5);
    final face = _face;

    context.pushClipRRect(
      needsCompositing,
      Offset.zero,
      offset & size,
      RRect.fromRectAndRadius(aperture.shift(offset), Radius.circular(radius)),
      (context, _) {
        if (face != null && fade < 0.98) {
          final at = Offset(
            _anchorEnd ? aperture.right - _origin.width : aperture.left,
            _anchorBottom ? aperture.bottom - _origin.height : aperture.top,
          );
          final center =
              at +
              Offset(_origin.width / 2, _origin.height / 2) +
              Offset(-side * HermezPanelMotion.faceSlide * fade, 0);
          _faceOrigin = at;
          final scale = 1 - fade;
          final transform = Matrix4.identity()
            ..translateByDouble(
              center.dx + offset.dx,
              center.dy + offset.dy,
              0,
              1,
            )
            ..scaleByDouble(scale, scale, 1, 1)
            ..translateByDouble(-_origin.width / 2, -_origin.height / 2, 0, 1);
          context.pushTransform(needsCompositing, Offset.zero, transform, (
            context,
            _,
          ) {
            context.paintChild(face, Offset.zero);
          });
        }
        // Skipped while it is still wholly outside the aperture.
        if (wipe > 0) {
          context.paintChild(content, offset + _contentOffset);
        }
      },
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (identical(child, _content)) {
      transform.translateByDouble(_contentOffset.dx, _contentOffset.dy, 0, 1);
    } else if (identical(child, _face)) {
      transform.translateByDouble(_faceOrigin.dx, _faceOrigin.dy, 0, 1);
    }
  }

  @override
  bool hitTestSelf(Offset position) => false;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final content = _content;
    if (content == null || !_aperture.contains(position)) return false;
    return result.addWithPaintOffset(
      offset: _contentOffset,
      position: position,
      hitTest: (result, transformed) =>
          content.hitTest(result, position: transformed),
    );
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    // Only the panel is announced; the button's face is a picture of it.
    final content = _content;
    if (content != null) visitor(content);
  }
}
