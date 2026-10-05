import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../motion/hermez_motion.dart';
import 'hermez_chat_palette.dart';
import 'hermez_live.dart';

/// Where a piece of work stands.
enum HermezMorphState { idle, working, done, failed, attention }

/// One status object that moves between waiting, working and its outcome
/// without changing identity. A quiet track while idle; an arc that spins
/// while work runs; then the arc closes into a ring where it is, floods into
/// a solid disc from the centre and draws its mark (check, cross or bang).
/// Failure nudges sideways once. Nothing fades: strokes trim, the disc
/// scales, the object shakes. Adapted from SwiftPieces' Status Morph.
class HermezStatusMorph extends StatefulWidget {
  const HermezStatusMorph({
    super.key,
    required this.state,
    this.size = 22,
    this.tint,
    this.ink,
    this.onTint,
    this.onInk,
    this.semanticLabel,
  });

  final HermezMorphState state;
  final double size;

  /// The working arc and the failed/attention disc. Defaults to the accent.
  final Color? tint;

  /// The done disc and the idle track. Defaults to the ink.
  final Color? ink;

  /// The mark on a [tint] disc. Defaults to the accent's own ink.
  final Color? onTint;

  /// The mark on an [ink] disc. Defaults to the canvas.
  final Color? onInk;
  final String? semanticLabel;

  @override
  State<HermezStatusMorph> createState() => _HermezStatusMorphState();
}

class _HermezStatusMorphState extends State<HermezStatusMorph>
    with TickerProviderStateMixin {
  // ~1.1 turns a second while working.
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 910),
  );
  // 0: no arc, 1: the working arc (72 % of the ring).
  late final AnimationController _arc = AnimationController(
    vsync: this,
    duration: HermezMotion.settleFor(HermezMotionWeight.light),
  );
  // 0: the arc, 1: closed ring, solid disc and its mark drawn.
  late final AnimationController _resolve = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    reverseDuration: HermezMotion.settleFor(HermezMotionWeight.light),
  );
  late final AnimationController _nudge = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  /// The arc's angle when it stopped spinning, so it closes where it is.
  double _angle = 0;

  /// The outcome being drawn (kept while the disc collapses back).
  HermezMorphState _shown = HermezMorphState.idle;

  bool get _resolved =>
      widget.state == HermezMorphState.done ||
      widget.state == HermezMorphState.failed ||
      widget.state == HermezMorphState.attention;

  @override
  void initState() {
    super.initState();
    _shown = widget.state;
    // A status that is already settled when it first appears is drawn as
    // settled: it is not news.
    if (_resolved) {
      _arc.value = 1;
      _resolve.value = 1;
    } else if (widget.state == HermezMorphState.working) {
      _arc.value = 1;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSpin();
  }

  @override
  void didUpdateWidget(covariant HermezStatusMorph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state == widget.state) return;
    final motion = HermezLiveMotion.on(context);
    if (oldWidget.state == HermezMorphState.working) {
      _angle = (_angle + _spin.value * 2 * math.pi) % (2 * math.pi);
      _spin.value = 0;
    }
    switch (widget.state) {
      case HermezMorphState.idle:
        _resolve.value = 0;
        if (motion) {
          _arc.reverse();
        } else {
          _arc.value = 0;
        }
      case HermezMorphState.working:
        _arc.value = 1;
        // A new run: the disc goes back into the ring it came out of.
        if (motion) {
          _resolve.reverse();
        } else {
          _resolve.value = 0;
        }
      case HermezMorphState.done:
      case HermezMorphState.failed:
      case HermezMorphState.attention:
        _shown = widget.state;
        _arc.value = 1;
        if (motion) {
          _resolve.forward(from: 0);
          if (widget.state == HermezMorphState.failed) {
            _nudge.forward(from: 0);
          }
        } else {
          _resolve.value = 1;
        }
    }
    _syncSpin();
  }

  void _syncSpin() {
    final spin =
        widget.state == HermezMorphState.working &&
        HermezLiveMotion.on(context);
    if (spin && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!spin && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _arc.dispose();
    _resolve.dispose();
    _nudge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final tint = widget.tint ?? palette.accent;
    final ink = widget.ink ?? palette.ink;
    final shown = _resolved ? widget.state : _shown;
    final outcome = shown == HermezMorphState.done ? ink : tint;
    final mark = shown == HermezMorphState.done
        ? (widget.onInk ?? palette.canvas)
        : (widget.onTint ?? palette.onAccent);
    final painted = AnimatedBuilder(
      animation: Listenable.merge([_spin, _arc, _resolve, _nudge]),
      builder: (context, _) {
        final t = _nudge.value;
        // Three shrinking swings, over before the mark finishes drawing.
        final dx = _nudge.isAnimating
            ? math.sin(t * math.pi * 6) * (1 - t) * widget.size * 0.11
            : 0.0;
        return Transform.translate(
          offset: Offset(dx, 0),
          child: CustomPaint(
            size: Size.square(widget.size),
            painter: _MorphPainter(
              angle: _angle + _spin.value * 2 * math.pi,
              arc: Curves.easeOut.transform(_arc.value),
              resolve: _resolve.value,
              shown: shown,
              track: ink,
              working: tint,
              outcome: outcome,
              mark: mark,
            ),
          ),
        );
      },
    );
    final label = widget.semanticLabel;
    return label == null
        ? painted
        : Semantics(label: label, liveRegion: true, child: painted);
  }
}

class _MorphPainter extends CustomPainter {
  _MorphPainter({
    required this.angle,
    required this.arc,
    required this.resolve,
    required this.shown,
    required this.track,
    required this.working,
    required this.outcome,
    required this.mark,
  });

  final double angle;
  final double arc;
  final double resolve;
  final HermezMorphState shown;
  final Color track;
  final Color working;
  final Color outcome;
  final Color mark;

  static double _phase(double t, double from, double to) =>
      ((t - from) / (to - from)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final stroke = math.max(1.6, s * 0.1);
    final center = size.center(Offset.zero);
    final radius = (s - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final close = Curves.easeOut.transform(_phase(resolve, 0, 0.45));
    final flood = HermezMotion.curveMedium.transform(
      _phase(resolve, 0.22, 0.78),
    );
    final draw = Curves.easeOut.transform(_phase(resolve, 0.5, 1));

    // The quiet track under a working arc; gone once the ring closes.
    if (close < 1) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = track.withValues(alpha: 0.12),
      );
    }

    final sweep = (lerpDouble(0.72, 1, close)! * arc) * 2 * math.pi;
    if (sweep > 0.001) {
      canvas.drawArc(
        rect,
        angle - math.pi / 2,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = Color.lerp(working, outcome, close)!,
      );
    }

    if (flood > 0) {
      canvas.drawCircle(
        center,
        (radius + stroke / 2) * flood,
        Paint()..color = outcome,
      );
    }

    if (draw > 0) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 1.05
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = mark;
      Offset p(double x, double y) => Offset(x * s, y * s);
      switch (shown) {
        case HermezMorphState.failed:
          _trimmed(canvas, [p(0.36, 0.36), p(0.64, 0.64)], draw * 2, paint);
          _trimmed(
            canvas,
            [p(0.64, 0.36), p(0.36, 0.64)],
            (draw * 2 - 1).clamp(0.0, 1.0),
            paint,
          );
        case HermezMorphState.attention:
          _trimmed(canvas, [p(0.5, 0.3), p(0.5, 0.58)], draw * 1.4, paint);
          if (draw > 0.75) {
            canvas.drawCircle(
              p(0.5, 0.72),
              stroke * 0.6 * _phase(draw, 0.75, 1),
              Paint()..color = mark,
            );
          }
        case _:
          _trimmed(
            canvas,
            [p(0.3, 0.52), p(0.44, 0.66), p(0.71, 0.37)],
            draw,
            paint,
          );
      }
    }
  }

  /// Draws [points] as a polyline, only the first [t] of its length.
  static void _trimmed(Canvas canvas, List<Offset> points, double t, Paint p) {
    final f = t.clamp(0.0, 1.0);
    if (f <= 0) return;
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += (points[i] - points[i - 1]).distance;
    }
    var left = total * f;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length && left > 0; i++) {
      final a = points[i - 1];
      final b = points[i];
      final length = (b - a).distance;
      final k = math.min(1.0, left / length);
      final end = Offset.lerp(a, b, k)!;
      path.lineTo(end.dx, end.dy);
      left -= length;
    }
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_MorphPainter old) =>
      old.angle != angle ||
      old.arc != arc ||
      old.resolve != resolve ||
      old.shown != shown ||
      old.track != track ||
      old.working != working ||
      old.outcome != outcome ||
      old.mark != mark;
}
