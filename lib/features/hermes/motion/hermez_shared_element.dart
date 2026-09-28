import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../../shared/theme/theme_extensions.dart';
import 'hermez_motion_tokens.dart';

/// How a shared object's appearance changes while it travels.
enum HermezMorphFlight {
  /// The larger (destination) rendering scales between both rectangles.
  /// Right for marks, icons, and images that keep their proportions.
  scale,

  /// A rounded slab whose color, radius, and border interpolate. The object's
  /// body: a card becoming a header surface or a sheet.
  surface,

  /// Decoration that stretches with its container: a surface's construction
  /// marks travel and resize with the object instead of popping in.
  stretch,
}

/// Cross-route continuity for one object. Backed by Flutter [Hero].
///
/// Each part of an object (its body, its mark, its title) is its own morph so
/// every part keeps its own geometry in flight. Parts never nest.
///
/// Reduced motion and a null [id] render the child in place with no flight.
class HermezMorph extends StatelessWidget {
  const HermezMorph({
    super.key,
    required this.id,
    required this.child,
    this.flight = HermezMorphFlight.scale,
    this.weight = HermezMotionWeight.heavy,
  });

  final String? id;
  final Widget child;
  final HermezMorphFlight flight;
  final HermezMotionWeight weight;

  @override
  Widget build(BuildContext context) {
    final tag = id;
    if (tag == null || context.reduceMotion) return child;
    final curve = HermezMotion.curveFor(weight);
    return Hero(
      tag: tag,
      curve: curve,
      reverseCurve: curve.flipped,
      createRectTween: _straight,
      flightShuttleBuilder: switch (flight) {
        HermezMorphFlight.scale => _scaleShuttle,
        HermezMorphFlight.surface => _surfaceShuttle,
        HermezMorphFlight.stretch => _stretchShuttle,
      },
      child: _MorphBody(child: child),
    );
  }
}

/// A title or label that keeps being text while it travels: size, weight,
/// color, and spacing interpolate instead of a bitmap stretching.
class HermezMorphText extends StatelessWidget {
  const HermezMorphText(
    this.text, {
    super.key,
    required this.id,
    required this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.weight = HermezMotionWeight.heavy,
  });

  final String? id;
  final String text;
  final TextStyle style;
  final int maxLines;
  final TextOverflow overflow;
  final HermezMotionWeight weight;

  @override
  Widget build(BuildContext context) {
    final body = Text(
      text,
      maxLines: maxLines,
      overflow: overflow,
      style: style,
    );
    final tag = id;
    if (tag == null || context.reduceMotion) return body;
    final curve = HermezMotion.curveFor(weight);
    return Hero(
      tag: tag,
      curve: curve,
      reverseCurve: curve.flipped,
      createRectTween: _straight,
      flightShuttleBuilder: _textShuttle,
      child: _MorphTextBody(
        text: text,
        style: style,
        maxLines: maxLines,
        child: body,
      ),
    );
  }
}

/// The body of a morphing object. Paint-only: content sits above it in a
/// [Stack] so its own parts can fly separately.
class HermezMorphSurface extends StatelessWidget {
  const HermezMorphSurface({
    super.key,
    required this.id,
    required this.decoration,
    this.child,
    this.weight = HermezMotionWeight.heavy,
  });

  final String? id;
  final BoxDecoration decoration;
  final Widget? child;
  final HermezMotionWeight weight;

  @override
  Widget build(BuildContext context) {
    final body = DecoratedBox(
      decoration: decoration,
      child: child ?? const SizedBox.expand(),
    );
    final tag = id;
    if (tag == null || context.reduceMotion) return body;
    final curve = HermezMotion.curveFor(weight);
    return Hero(
      tag: tag,
      curve: curve,
      reverseCurve: curve.flipped,
      createRectTween: _straight,
      flightShuttleBuilder: _surfaceShuttle,
      child: _MorphSurfaceBody(decoration: decoration, child: body),
    );
  }
}

RectTween _straight(Rect? begin, Rect? end) =>
    RectTween(begin: begin, end: end);

class _MorphBody extends StatelessWidget {
  const _MorphBody({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Material(type: MaterialType.transparency, child: child);
}

class _MorphTextBody extends StatelessWidget {
  const _MorphTextBody({
    required this.text,
    required this.style,
    required this.maxLines,
    required this.child,
  });

  final String text;
  final TextStyle style;
  final int maxLines;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Material(type: MaterialType.transparency, child: child);
}

class _MorphSurfaceBody extends StatelessWidget {
  const _MorphSurfaceBody({required this.decoration, required this.child});

  final BoxDecoration decoration;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// The destination of a push, which is the source of the matching pop, is
/// the object's detailed form. It flies in both directions.
(BuildContext compact, BuildContext detailed) _ends(
  HeroFlightDirection direction,
  BuildContext from,
  BuildContext to,
) => direction == HeroFlightDirection.push ? (from, to) : (to, from);

Widget? _heroChild(BuildContext context) {
  final widget = context.widget;
  return widget is Hero ? widget.child : null;
}

Widget _scaleShuttle(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  final (_, detailed) = _ends(direction, fromHeroContext, toHeroContext);
  final child = _heroChild(detailed) ?? const SizedBox.shrink();
  final box = detailed.findRenderObject();
  final size = box is RenderBox && box.hasSize ? box.size : null;
  if (size == null || size.isEmpty) return child;
  return FittedBox(
    fit: BoxFit.contain,
    alignment: Alignment.topLeft,
    child: SizedBox.fromSize(size: size, child: child),
  );
}

Widget _textShuttle(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  final (compact, detailed) = _ends(direction, fromHeroContext, toHeroContext);
  final a = _heroChild(compact);
  final b = _heroChild(detailed);
  if (a is! _MorphTextBody || b is! _MorphTextBody) {
    return b ?? a ?? const SizedBox.shrink();
  }
  final singleLine = a.maxLines == 1 && b.maxLines == 1;
  // TextStyle.lerp refuses styles with different `inherit` values (theme
  // text styles often have inherit: false). Align them before interpolating.
  final from = a.style.inherit == b.style.inherit
      ? a.style
      : a.style.copyWith(inherit: b.style.inherit);
  final to = b.style;
  return Material(
    type: MaterialType.transparency,
    child: AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        final style = TextStyle.lerp(
          from,
          to,
          t.clamp(0.0, 1.0),
        )!.copyWith(fontSize: lerpDouble(from.fontSize, to.fontSize, t));
        if (singleLine) {
          return ClipRect(
            child: OverflowBox(
              alignment: AlignmentDirectional.topStart,
              minWidth: 0,
              maxWidth: double.infinity,
              minHeight: 0,
              maxHeight: double.infinity,
              child: Text(
                b.text,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                style: style,
              ),
            ),
          );
        }
        // Multi-line text reflows inside the travelling box, like text in a
        // container that is being resized. Lines are never cut off: a line
        // that wraps while the box is narrow hangs below it until it fits.
        final lines = t < 0.5 ? a.maxLines : b.maxLines;
        return LayoutBuilder(
          builder: (context, constraints) => OverflowBox(
            alignment: AlignmentDirectional.topStart,
            minWidth: constraints.maxWidth,
            maxWidth: constraints.maxWidth,
            minHeight: 0,
            maxHeight: double.infinity,
            child: Text(
              b.text,
              maxLines: math.max(lines, 2),
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        );
      },
    ),
  );
}

Widget _surfaceShuttle(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  final (compact, detailed) = _ends(direction, fromHeroContext, toHeroContext);
  final a = _heroChild(compact);
  final b = _heroChild(detailed);
  if (a is! _MorphSurfaceBody || b is! _MorphSurfaceBody) {
    return b ?? a ?? const SizedBox.shrink();
  }
  return AnimatedBuilder(
    animation: animation,
    builder: (context, _) => DecoratedBox(
      decoration: BoxDecoration.lerp(
        a.decoration,
        b.decoration,
        animation.value.clamp(0.0, 1.0),
      )!,
      child: const SizedBox.expand(),
    ),
  );
}

Widget _stretchShuttle(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  final (_, detailed) = _ends(direction, fromHeroContext, toHeroContext);
  final child = _heroChild(detailed) ?? const SizedBox.shrink();
  final box = detailed.findRenderObject();
  final size = box is RenderBox && box.hasSize ? box.size : null;
  if (size == null || size.isEmpty) return child;
  return IgnorePointer(
    child: FittedBox(
      fit: BoxFit.fill,
      child: SizedBox.fromSize(size: size, child: child),
    ),
  );
}
