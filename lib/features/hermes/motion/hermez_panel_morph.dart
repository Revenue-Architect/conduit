import 'dart:math' as math;
import 'dart:ui' as ui show ImageFilter;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../feedback/hermez_feedback.dart';
import 'hermez_morph_origin.dart';

/// Builds the face of the button a panel grew out of. [turn] runs 0 to 1 as
/// the button becomes the panel: a caller turns its plus into a cross with it.
typedef HermezPanelFaceBuilder = Widget Function(
  BuildContext context,
  double turn,
);

/// The motion tokens of Transitions.dev's "Dropdown menu morph" (also named
/// "Plus to menu morph"), which this control reproduces.
///
/// This is the one Hermez control that deliberately cross-fades and blurs:
/// the reference design calls for it.
abstract final class HermezPanelMotion {
  /// `--morph-open-dur`: surface size and corner, content slide and scale.
  static const openDuration = Duration(milliseconds: 350);

  /// `--morph-close-dur`: surface size and corner on the way home.
  static const closeDuration = Duration(milliseconds: 250);

  /// `--morph-fade-dur`: the plus and the content cross-fade.
  static const fadeDuration = Duration(milliseconds: 200);

  /// `--morph-ease`: the surface opens with a slight overshoot.
  static const openEase = Cubic(0.34, 1.25, 0.64, 1);

  /// `--morph-close-ease`: everything else, and the close.
  static const closeEase = Cubic(0.22, 1, 0.36, 1);

  /// `--morph-r-open`: the open panel's corner radius.
  static const openRadius = 20.0;

  /// `--morph-slide`: the plus leaves this far, the content arrives from it.
  static const slide = 40.0;

  /// `--morph-rotate`: the plus turns into a cross.
  static const rotate = math.pi / 4;

  /// `--morph-scale`.
  static const scale = 0.97;

  /// `--morph-blur` (2px).
  static const blur = 2.0;
}

/// Where each part of the morph is at one moment. Each CSS property of the
/// reference has its own duration and easing; these are the same values,
/// derived from the one route animation.
@immutable
class HermezMorphFrame {
  const HermezMorphFrame({
    required this.size,
    required this.fade,
    required this.move,
  });

  /// The whole morph at rest, open (1) or closed (0).
  const HermezMorphFrame.at(double value)
    : size = value,
      fade = value,
      move = value;

  /// Surface size and corner: 0 the button, 1 the panel. Opening overshoots.
  final double size;

  /// Opacity and blur of the content (the plus is the inverse): 0 to 1.
  final double fade;

  /// Slide, scale, and the plus's turn: 0 to 1.
  final double move;

  /// [value] is the route animation (0 closed, 1 open, linear in time);
  /// [opening] is its direction.
  factory HermezMorphFrame.of(double value, {required bool opening}) {
    const open = HermezPanelMotion.openDuration;
    const close = HermezPanelMotion.closeDuration;
    const fade = HermezPanelMotion.fadeDuration;
    final ms = opening
        ? value * open.inMilliseconds
        : (1 - value) * close.inMilliseconds;
    double eased(Curve curve, Duration over) =>
        curve.transform((ms / over.inMilliseconds).clamp(0.0, 1.0));
    if (opening) {
      return HermezMorphFrame(
        size: eased(HermezPanelMotion.openEase, open),
        fade: eased(HermezPanelMotion.closeEase, fade),
        move: eased(HermezPanelMotion.closeEase, open),
      );
    }
    return HermezMorphFrame(
      size: 1 - eased(HermezPanelMotion.closeEase, close),
      fade: 1 - eased(HermezPanelMotion.closeEase, fade),
      move: 1 - eased(HermezPanelMotion.closeEase, open),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HermezMorphFrame &&
      other.size == size &&
      other.fade == fade &&
      other.move == move;

  @override
  int get hashCode => Object.hash(size, fade, move);
}

/// Pushes a panel that a button turns into.
///
/// One object: the button's own surface expands in place into the panel,
/// the way the reference grows a menu out of its plus. It stays anchored to
/// the button's nearest corner and grows toward the rest of the screen; its
/// corner radius relaxes to 20. The plus slides, blurs, fades and turns into
/// a cross while the panel's content slides in from the same side,
/// sharpening and fading in. Closing reverses it back into the button.
///
/// With the keyboard up the anchored edge moves above it, so the whole panel
/// rises as one object. The caller hides the real button while this is up
/// and shows it again when the returned future completes, which is only after
/// the panel has gone home.
Future<T?> pushHermezPanel<T>(
  BuildContext context, {
  required HermezMorphOrigin origin,
  required HermezPanelFaceBuilder faceBuilder,
  required WidgetBuilder builder,
  ThemeData? theme,
  Color? surfaceColor,
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
  final double maxWidth;
  final double originElevation;
  final String? semanticLabel;
  final bool reducedMotion;

  @override
  Duration get transitionDuration =>
      reducedMotion ? Duration.zero : HermezPanelMotion.openDuration;

  @override
  Duration get reverseTransitionDuration =>
      reducedMotion ? Duration.zero : HermezPanelMotion.closeDuration;

  @override
  bool get barrierDismissible => true;

  @override
  Color? get barrierColor => const Color(0x52000000);

  @override
  String? get barrierLabel => 'Dismiss';

  @override
  bool didPop(T? result) {
    final popped = super.didPop(result);
    // The panel returns into the button it came from: a soft closing latch.
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
    Widget page = _HermezPanelPage<T>(route: this, animation: animation);
    final theme = this.theme;
    if (theme != null) page = Theme(data: theme, child: page);
    return capturedThemes.wrap(page);
  }
}

class _HermezPanelPage<T> extends StatefulWidget {
  const _HermezPanelPage({required this.route, required this.animation});

  final HermezPanelRoute<T> route;
  final Animation<double> animation;

  @override
  State<_HermezPanelPage<T>> createState() => _HermezPanelPageState<T>();
}

class _HermezPanelPageState<T> extends State<_HermezPanelPage<T>> {
  HermezPanelRoute<T> get route => widget.route;
  Animation<double> get animation => widget.animation;

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
    // Built once: only the morph moves while it opens, so the panel's own
    // widgets are not rebuilt on every animation frame.
    final content = RepaintBoundary(
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
                    Theme.of(context).textTheme.bodyMedium ?? const TextStyle(),
                child: route.builder(context),
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
        animation: animation,
        child: content,
        builder: (context, content) {
          final media = MediaQuery.of(context);
          final status = animation.status;
          final frame = switch (status) {
            AnimationStatus.completed => const HermezMorphFrame.at(1),
            AnimationStatus.dismissed => const HermezMorphFrame.at(0),
            _ => HermezMorphFrame.of(
              animation.value,
              opening: status == AnimationStatus.forward,
            ),
          };
          // Input waits for the panel to be open: a moving target cannot
          // be aimed at. A tap on it meanwhile is swallowed, not read as a
          // tap outside; tapping outside still closes it at any moment.
          final interactive = status == AnimationStatus.completed;
          return HermezPanelMorph(
            frame: frame,
            resolveOrigin: route.origin.resolve,
            originRadius: route.origin.radius,
            originColor: route.origin.color ?? surface,
            originElevation: route.originElevation,
            surfaceColor: surface,
            maxWidth: route.maxWidth,
            padding: EdgeInsets.fromLTRB(
              math.max(16, media.padding.left),
              media.padding.top + 12,
              math.max(16, media.padding.right),
              media.viewInsets.bottom > 0
                  ? media.viewInsets.bottom + 12
                  : math.max(12, media.padding.bottom),
            ),
            face: frame.fade >= 1
                ? null
                : ExcludeSemantics(
                    child: _PlusFace(
                      frame: frame,
                      child: route.faceBuilder(context, frame.move),
                    ),
                  ),
            content: AbsorbPointer(
              absorbing: !interactive,
              child: _MenuContent(frame: frame, child: content!),
            ),
          );
        },
      ),
    );
  }
}

double _towardInside(BuildContext context) =>
    Directionality.of(context) == TextDirection.rtl ? -1 : 1;

/// `.t-morph-plus` leaving: fades and blurs over the fade duration, slides
/// away over the open duration. Its glyph turns via the face builder.
class _PlusFace extends StatelessWidget {
  const _PlusFace({required this.frame, required this.child});

  final HermezMorphFrame frame;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final sigma = HermezPanelMotion.blur * frame.fade;
    return Opacity(
      opacity: (1 - frame.fade).clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(
          -HermezPanelMotion.slide * frame.move * _towardInside(context),
          0,
        ),
        child: ImageFiltered(
          enabled: sigma > 0.01,
          imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: child,
        ),
      ),
    );
  }
}

/// `.t-morph-menu` arriving: fades and sharpens over the fade duration,
/// slides in and scales up over the open duration.
class _MenuContent extends StatelessWidget {
  const _MenuContent({required this.frame, required this.child});

  final HermezMorphFrame frame;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final sigma = HermezPanelMotion.blur * (1 - frame.fade);
    final scale = lerpDouble(HermezPanelMotion.scale, 1, frame.move)!;
    return Opacity(
      opacity: frame.fade.clamp(0.0, 1.0),
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..translateByDouble(
            HermezPanelMotion.slide * (1 - frame.move) * _towardInside(context),
            0,
            0,
            1,
          )
          ..scaleByDouble(scale, scale, 1, 1),
        child: ImageFiltered(
          enabled: sigma > 0.01,
          imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: child,
        ),
      ),
    );
  }
}

/// The two things a [HermezPanelMorph] lays out: the panel and the button's
/// face.
enum HermezPanelSlot { content, face }

/// Lays out a content-sized panel anchored to the corner of the button it
/// grows out of, and paints the one surface that travels between the two.
///
/// The panel is laid out once, at its final size, aligned to the button's
/// nearest corner and kept on screen and above the keyboard. The surface
/// (`.t-morph`) expands from the button's rectangle to the panel's; its
/// corner radius goes from the button's to 20. The content sits at the
/// panel's final place and is revealed as the surface grows over it; the
/// button's face rides the anchored corner. When the content changes size (a
/// section opening, an error appearing) the panel follows it with its
/// anchored edge fixed.
class HermezPanelMorph
    extends SlottedMultiChildRenderObjectWidget<HermezPanelSlot, RenderBox> {
  const HermezPanelMorph({
    super.key,
    required this.frame,
    required this.resolveOrigin,
    required this.originRadius,
    required this.originColor,
    required this.originElevation,
    required this.surfaceColor,
    required this.maxWidth,
    required this.padding,
    required this.content,
    this.face,
  });

  final HermezMorphFrame frame;

  /// Where the button is, in this widget's coordinate space.
  final Rect Function() resolveOrigin;
  final double originRadius;
  final Color originColor;
  final double originElevation;
  final Color surfaceColor;
  final double maxWidth;

  /// Clear space around the panel: the safe area, the keyboard and margins.
  final EdgeInsets padding;
  final Widget content;

  /// The button's face while it is still visible; null once it has gone.
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
        frame: frame,
        resolveOrigin: resolveOrigin,
        originRadius: originRadius,
        originColor: originColor,
        originElevation: originElevation,
        surfaceColor: surfaceColor,
        maxWidth: maxWidth,
        padding: padding,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderHermezPanelMorph renderObject,
  ) {
    renderObject
      ..frame = frame
      ..resolveOrigin = resolveOrigin
      ..originRadius = originRadius
      ..originColor = originColor
      ..originElevation = originElevation
      ..surfaceColor = surfaceColor
      ..maxWidth = maxWidth
      ..padding = padding;
  }
}

class RenderHermezPanelMorph extends RenderBox
    with SlottedContainerRenderObjectMixin<HermezPanelSlot, RenderBox> {
  RenderHermezPanelMorph({
    required HermezMorphFrame frame,
    required Rect Function() resolveOrigin,
    required double originRadius,
    required Color originColor,
    required double originElevation,
    required Color surfaceColor,
    required double maxWidth,
    required EdgeInsets padding,
  }) : _frame = frame,
       _resolveOrigin = resolveOrigin,
       _originRadius = originRadius,
       _originColor = originColor,
       _originElevation = originElevation,
       _surfaceColor = surfaceColor,
       _maxWidth = maxWidth,
       _padding = padding;

  HermezMorphFrame _frame;
  set frame(HermezMorphFrame value) {
    if (_frame == value) return;
    _frame = value;
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

  // Geometry from the last layout.
  Rect _origin = Rect.zero;
  Rect _panel = Rect.zero;
  bool _anchorRight = true;
  bool _anchorBottom = true;

  /// The travelling surface as painted last frame. For tests.
  @visibleForTesting
  Rect get apertureRect => _apertureAt(_frame.size);

  /// Where the panel rests once fully open. For tests.
  @visibleForTesting
  Rect get panelRect => _panel;

  /// The source button's rectangle. For tests.
  @visibleForTesting
  Rect get originRect => _origin;

  /// Whether the panel grows upward from the button (anchored at its
  /// bottom edge).
  @visibleForTesting
  bool get anchoredBottom => _anchorBottom;

  RenderBox? get _content => childForSlot(HermezPanelSlot.content);
  RenderBox? get _face => childForSlot(HermezPanelSlot.face);

  Rect _apertureAt(double t) => Rect.fromLTRB(
    lerpDouble(_origin.left, _panel.left, t)!,
    lerpDouble(_origin.top, _panel.top, t)!,
    lerpDouble(_origin.right, _panel.right, t)!,
    lerpDouble(_origin.bottom, _panel.bottom, t)!,
  );

  /// The face rides the surface's anchored corner (the plus sits at the
  /// morph's corner in the reference).
  Offset get _faceOffset {
    final aperture = apertureRect;
    return Offset(
      _anchorRight ? aperture.right - _origin.width : aperture.left,
      _anchorBottom ? aperture.bottom - _origin.height : aperture.top,
    );
  }

  @override
  bool get sizedByParent => false;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    size = constraints.biggest;
    _origin = _resolveOrigin();
    final free = _padding.deflateRect(Offset.zero & size);
    _anchorRight = _origin.center.dx >= size.width / 2;
    _anchorBottom = _origin.center.dy >= size.height / 2;

    final width = math.max(0.0, math.min(free.width, _maxWidth));
    // The anchored edge lines up with the button's, kept on screen and above
    // the keyboard; the panel extends from it toward the rest of the screen.
    // When the content grows past that (a compartment opening), the panel
    // slides off the anchor to use the whole clear height before it scrolls.
    final edge = _anchorBottom
        ? math.min(_origin.bottom, free.bottom)
        : math.max(_origin.top, free.top);
    final content = _content;
    var height = 0.0;
    if (content != null) {
      content.layout(
        BoxConstraints(
          minWidth: width,
          maxWidth: width,
          maxHeight: math.max(0.0, free.height),
        ),
        parentUsesSize: true,
      );
      height = content.size.height;
    }
    final preferredTop = _anchorBottom ? edge - height : edge;
    final top = math.max(
      free.top,
      math.min(preferredTop, free.bottom - height),
    );
    final left = _anchorRight
        ? math.max(free.left, math.min(_origin.right, free.right) - width)
        : math.min(math.max(_origin.left, free.left), free.right - width);
    _panel = Rect.fromLTWH(left, top, width, height);
    final face = _face;
    if (face != null) face.layout(BoxConstraints.tight(_origin.size));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final t = _frame.size;
    final settled = t.clamp(0.0, 1.0);
    final aperture = _apertureAt(t);
    final radius = lerpDouble(
      _originRadius,
      HermezPanelMotion.openRadius,
      settled,
    )!;
    final rrect = RRect.fromRectAndRadius(
      aperture.shift(offset),
      Radius.circular(radius),
    );
    // The surface is the button's colour until the content has faded in.
    final slab = Color.lerp(
      _originColor,
      _surfaceColor,
      _frame.fade.clamp(0.0, 1.0),
    )!;
    final elevation = lerpDouble(_originElevation, 12, settled)!;
    if (elevation > 0) {
      context.canvas.drawShadow(
        Path()..addRRect(rrect),
        const Color(0xFF000000),
        elevation,
        false,
      );
    }
    context.canvas.drawRRect(rrect, Paint()..color = slab);

    context.pushClipRRect(needsCompositing, Offset.zero, offset & size, rrect, (
      context,
      _,
    ) {
      final content = _content;
      if (content != null && _frame.fade > 0) {
        context.paintChild(content, offset + _panel.topLeft);
      }
      final face = _face;
      if (face != null) context.paintChild(face, offset + _faceOffset);
    });
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final at = identical(child, _content) ? _panel.topLeft : _faceOffset;
    transform.translateByDouble(at.dx, at.dy, 0, 1);
  }

  @override
  bool hitTestSelf(Offset position) => false;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final content = _content;
    if (content == null || !apertureRect.contains(position)) return false;
    return result.addWithPaintOffset(
      offset: _panel.topLeft,
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
