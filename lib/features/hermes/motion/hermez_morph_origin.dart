import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Where a Hermez object sits on the screen that opened a destination.
///
/// An expanding route grows out of this rectangle and contracts back into it.
/// It keeps a reference to the source render box so Back returns to where the
/// object is now, not where it was when tapped. When the source is gone the
/// captured rectangle is used.
///
/// This is passed with the navigation that opened the route. It is never
/// stored globally.
@immutable
class HermezMorphOrigin {
  const HermezMorphOrigin._({
    required Rect rect,
    required this.radius,
    required this.color,
    this.borderColor,
    this.snapshot,
    RenderBox? box,
    RenderObject? routeBox,
  }) : _rect = rect,
       _box = box,
       _routeBox = routeBox;

  /// An origin with a fixed rectangle. Used by tests and by callers that
  /// already know where the object is.
  const HermezMorphOrigin.rect(
    Rect rect, {
    double radius = 18,
    Color? color,
    Color? borderColor,
  }) : this._(
         rect: rect,
         radius: radius,
         color: color,
         borderColor: borderColor,
       );

  /// Captures the render box of [context] in its route's coordinate space.
  ///
  /// Returns null when [context] is not laid out yet.
  static HermezMorphOrigin? of(
    BuildContext context, {
    double radius = 18,
    Color? color,
    Color? borderColor,
    ui.Image? snapshot,
  }) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final routeBox = ModalRoute.of(context)?.subtreeContext?.findRenderObject();
    final rect = _measure(box, routeBox);
    if (rect == null) return null;
    return HermezMorphOrigin._(
      rect: rect,
      radius: radius,
      color: color,
      borderColor: borderColor,
      snapshot: snapshot,
      box: box,
      routeBox: routeBox,
    );
  }

  /// The drawing of [context]'s object at its own size, for [snapshot], when
  /// that object is a [RepaintBoundary]. Null otherwise.
  static ui.Image? capture(BuildContext context) {
    final boundary = context.findRenderObject();
    if (boundary is! RenderRepaintBoundary ||
        !boundary.attached ||
        !boundary.hasSize ||
        boundary.debugNeedsPaint) {
      return null;
    }
    try {
      return boundary.toImageSync(
        pixelRatio: MediaQuery.devicePixelRatioOf(context),
      );
    } catch (_) {
      return null;
    }
  }

  final Rect _rect;
  final RenderBox? _box;
  final RenderObject? _routeBox;

  /// Corner radius of the source object.
  final double radius;

  /// Fill of the source object. Null uses the destination surface color.
  final Color? color;

  /// Outline of the source object, if it has one. The growing aperture
  /// starts with it and thins it away.
  final Color? borderColor;

  /// What the source object looked like when it was opened, at its own
  /// size. A contracting destination uncovers this as it lands, so the
  /// object's own content is already in place when the route ends instead
  /// of appearing on the last frame.
  final ui.Image? snapshot;

  /// The source rectangle now, in the coordinate space of the route that
  /// holds it. Route-level transforms (a receding source screen) are excluded
  /// so this lines up with Flutter's Hero flights.
  Rect resolve() => _measure(_box, _routeBox) ?? _rect;

  static Rect? _measure(RenderBox? box, RenderObject? routeBox) {
    if (box == null || !box.attached || !box.hasSize) return null;
    try {
      final ancestor = routeBox != null && routeBox.attached ? routeBox : null;
      final topLeft = box.localToGlobal(Offset.zero, ancestor: ancestor);
      final rect = topLeft & box.size;
      return rect.isFinite ? rect : null;
    } catch (_) {
      return null;
    }
  }
}
