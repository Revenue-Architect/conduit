import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// The app's scroll behaviour: Material everywhere, except that Android's
/// overscroll is [HermezStretchOverscroll] instead of Flutter's stretch.
///
/// Flutter's stretch (3.47, Impeller) re-renders the whole viewport through a
/// shader filter into an offscreen layer on every overscroll frame, and the
/// layer reallocates GPU memory as the stretch grows. On the S25 that was a
/// 30–40 ms frame each time a list met its edge, felt most on Home, whose
/// list is short enough that nearly every swipe reaches the top or bottom
/// (traced 2026-10-09: `Canvas::saveLayer` → `vkAllocateMemory`). Scaling
/// the viewport directly instead re-rasterised every visible glyph at each
/// new scale (`CreateGlyphAtlas`, up to 24 ms), so the edge gives by moving.
class HermezScrollBehavior extends MaterialScrollBehavior {
  const HermezScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (getPlatform(context) == TargetPlatform.android) {
      return HermezStretchOverscroll(
        axisDirection: details.direction,
        child: child,
      );
    }
    return super.buildOverscrollIndicator(context, child, details);
  }
}

/// Overscroll as a physical give: past the edge the content travels a short
/// way with growing resistance, a fling into the edge carries it briefly,
/// and the release settles home on a critically damped spring (no bounce or
/// rubber band, per the Hermez motion rules). It is drawn as a translation
/// only, which needs no offscreen layer and never re-rasterises text.
///
/// Like Flutter's indicators it asks first with an
/// [OverscrollIndicatorNotification], so an ancestor that turns overscroll
/// into its own gesture (a Hermez sheet's drag to dismiss) can disallow it.
class HermezStretchOverscroll extends StatefulWidget {
  const HermezStretchOverscroll({
    super.key,
    required this.axisDirection,
    required this.child,
  });

  final AxisDirection axisDirection;
  final Widget child;

  /// Largest give, as a fraction of the viewport.
  static const maxStretch = 0.06;

  @override
  State<HermezStretchOverscroll> createState() =>
      _HermezStretchOverscrollState();
}

/// Reads whether an ancestor disallowed the indicator. Flutter's own
/// indicators read [OverscrollIndicatorNotification.accepted] from inside
/// their library; outside it the flag is only reachable from a subclass.
class _IndicatorRequest extends OverscrollIndicatorNotification {
  _IndicatorRequest({required super.leading});

  // ignore: invalid_use_of_visible_for_testing_member
  bool get wasAccepted => accepted;
}

class _HermezStretchOverscrollState extends State<HermezStretchOverscroll>
    with SingleTickerProviderStateMixin {
  /// Signed stretch: positive at the leading edge (the top of a downward
  /// list), negative at the trailing edge.
  late final AnimationController _stretch = AnimationController.unbounded(
    vsync: this,
  );

  static final _settle = SpringDescription(
    mass: 1,
    stiffness: 320,
    damping: 2 * math.sqrt(320) * 0.98,
  );

  Axis get _axis => axisDirectionToAxis(widget.axisDirection);

  bool _allowed(bool leading) {
    final request = _IndicatorRequest(leading: leading);
    request.dispatch(context);
    return request.wasAccepted;
  }

  void _settleFrom(double velocity) {
    _stretch.animateWith(SpringSimulation(_settle, _stretch.value, 0, velocity))
    // The spring stops within its tolerance; finish exactly at rest so
    // the viewport is unscaled and unclipped again.
    .whenCompleteOrCancel(() {
      if (mounted && !_stretch.isAnimating) _stretch.value = 0;
    });
  }

  bool _handle(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != _axis) {
      return false;
    }
    final extent = notification.metrics.viewportDimension;
    if (extent <= 0) return false;
    const max = HermezStretchOverscroll.maxStretch;

    switch (notification) {
      case OverscrollNotification(:final overscroll, :final dragDetails):
        if (!_allowed(overscroll < 0)) return false;
        if (dragDetails != null) {
          // Pulling past the edge: each pixel stretches less than the last.
          _stretch.stop();
          final current = _stretch.value;
          final resistance = 1 - (current.abs() / max).clamp(0.0, 1.0);
          _stretch.value = (current - overscroll / extent * 0.5 * resistance)
              .clamp(-max, max);
        } else if (notification.velocity != 0) {
          // A fling meeting the edge: stretch with its speed, then settle.
          final velocity = (-notification.velocity / extent * 0.4).clamp(
            -3.0,
            3.0,
          );
          _settleFrom(velocity);
        }
      case ScrollUpdateNotification(:final scrollDelta?, dragDetails: _?)
          when _stretch.value != 0:
        // Moving back from a stretched edge relaxes the stretch first.
        final current = _stretch.value;
        final next = current - scrollDelta / extent * 0.5;
        _stretch.value = next.sign == current.sign ? next : 0;
      case ScrollEndNotification() when _stretch.value != 0:
        _settleFrom(0);
      default:
        break;
    }
    return false;
  }

  @override
  void dispose() {
    _stretch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _handle,
      child: AnimatedBuilder(
        animation: _stretch,
        child: widget.child,
        // The tree keeps one shape at rest and stretched, so the scrollable
        // underneath is never remounted when a stretch starts.
        builder: (context, child) {
          final stretch = _stretch.value;
          // Positive moves the content away from the leading edge.
          final towardEnd = axisDirectionIsReversed(widget.axisDirection)
              ? -stretch
              : stretch;
          return LayoutBuilder(
            builder: (context, constraints) {
              final vertical = _axis == Axis.vertical;
              final extent = vertical
                  ? constraints.maxHeight
                  : constraints.maxWidth;
              final distance = extent.isFinite ? towardEnd * extent : 0.0;
              // Whole logical pixels keep text on its pixel grid.
              final travel = distance.roundToDouble();
              return ClipRect(
                clipBehavior: travel == 0 ? Clip.none : Clip.hardEdge,
                child: Transform.translate(
                  offset: vertical ? Offset(0, travel) : Offset(travel, 0),
                  child: child,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
