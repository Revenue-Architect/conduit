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
/// It also carries the object's face: a drawing of the source at its own
/// size. A destination that grows out of the object dissolves out of this
/// face, and one that contracts home dissolves back into it, so the object's
/// own content is in place on the last frame instead of appearing in one.
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
    RenderBox? box,
    RenderObject? routeBox,
    _HermezFace? face,
  }) : _rect = rect,
       _box = box,
       _routeBox = routeBox,
       _face = face;

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
  /// The face is [snapshot] when given; otherwise it is drawn from the first
  /// [RepaintBoundary] the size of the object at the top of its subtree (wrap
  /// a source in one to give it a face). Returns null when [context] is not
  /// laid out yet.
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
    final face = _HermezFace(
      boundary: _boundaryOf(box),
      pixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
      image: snapshot,
    );
    if (face.image == null) face.capture();
    return HermezMorphOrigin._(
      rect: rect,
      radius: radius,
      color: color,
      borderColor: borderColor,
      box: box,
      routeBox: routeBox,
      face: face,
    );
  }

  /// The drawing of [context]'s object at its own size, for [snapshot], when
  /// that object is a [RepaintBoundary]. Null otherwise.
  static ui.Image? capture(BuildContext context) {
    final boundary = context.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return null;
    return _draw(boundary, MediaQuery.maybeDevicePixelRatioOf(context) ?? 1);
  }

  final Rect _rect;
  final RenderBox? _box;
  final RenderObject? _routeBox;
  final _HermezFace? _face;

  /// Corner radius of the source object.
  final double radius;

  /// Fill of the source object. Null uses the destination surface color.
  final Color? color;

  /// Outline of the source object, if it has one. The growing aperture
  /// starts with it and thins it away.
  final Color? borderColor;

  /// What the source object looks like, at its own size: drawn when it was
  /// opened, and again by [refreshFace] as a destination starts back.
  ui.Image? get snapshot => _face?.image;

  /// Redraws the face from the live object as it looks now (after an edit,
  /// a toggle, or with the press released), so a contracting destination
  /// lands on exactly what will be there when it ends. Keeps the previous
  /// face when the object is gone or not painted.
  void refreshFace() => _face?.capture();

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

  /// The repaint boundary that draws the whole object: the first one down
  /// the single-child chain from [box] whose size is the object's own.
  static RenderRepaintBoundary? _boundaryOf(RenderBox box) {
    RenderObject node = box;
    for (var depth = 0; depth < 32; depth++) {
      if (node is RenderRepaintBoundary) {
        return node.hasSize &&
                (node.size.width - box.size.width).abs() < 1 &&
                (node.size.height - box.size.height).abs() < 1
            ? node
            : null;
      }
      RenderObject? only;
      var count = 0;
      node.visitChildren((child) {
        count++;
        only = child;
      });
      if (count != 1 || only == null) return null;
      node = only!;
    }
    return null;
  }

  static ui.Image? _draw(RenderRepaintBoundary boundary, double pixelRatio) {
    if (!boundary.attached || !boundary.hasSize || boundary.debugNeedsPaint) {
      return null;
    }
    try {
      return boundary.toImageSync(pixelRatio: pixelRatio);
    } catch (_) {
      return null;
    }
  }
}

/// The current face of one origin. Mutable on purpose: an origin is passed
/// by value through navigation, but its face is redrawn when the destination
/// starts back so it matches the live object.
class _HermezFace {
  _HermezFace({required this.boundary, required this.pixelRatio, this.image});

  final RenderRepaintBoundary? boundary;
  final double pixelRatio;
  ui.Image? image;

  void capture() {
    final source = boundary;
    if (source == null) return;
    final drawn = HermezMorphOrigin._draw(source, pixelRatio);
    if (drawn != null) image = drawn;
  }
}
