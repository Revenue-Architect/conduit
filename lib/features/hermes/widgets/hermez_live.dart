import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/theme/theme_extensions.dart';
import '../models/hermes_todo.dart';
import '../motion/hermez_motion.dart';
import 'hermez_chat_palette.dart';

/// Continuous live motion (a breathing dot, a travelling band) never settles
/// by design. Under `flutter test`, where `pumpAndSettle` waits for
/// stillness, it is off unless a test turns it on; reduced motion always
/// turns it off. Like everything in Hermez it moves position and scale,
/// never opacity.
abstract final class HermezLiveMotion {
  /// Same switch as [HermezBotPresence.loopsEnabled].
  @visibleForTesting
  static bool enabled = !Platform.environment.containsKey('FLUTTER_TEST');

  static bool on(BuildContext context) => enabled && !context.reduceMotion;
}

/// The one status mark every live surface uses (run, plan, delegates,
/// teams, Active Work), so "working" always looks the same.
enum HermezLiveState { working, attention, done, failed, idle }

/// A small dot. Working breathes the way a bot mark does: a slow
/// compression and swell (~0.8 Hz: alive, not anxious). Needing attention
/// adds a still ring. Everything else is still.
class HermezLiveDot extends StatefulWidget {
  const HermezLiveDot({
    super.key,
    required this.state,
    this.size = 8,
    this.semanticLabel,
    this.ink,
  });

  final HermezLiveState state;
  final double size;
  final String? semanticLabel;

  /// The still states' colour on a surface that keeps its own ground in
  /// both themes (Home's dark technical cards); the theme's ink otherwise.
  final Color? ink;

  @override
  State<HermezLiveDot> createState() => _HermezLiveDotState();
}

class _HermezLiveDotState extends State<HermezLiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant HermezLiveDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _sync();
  }

  void _sync() {
    final breathe =
        widget.state == HermezLiveState.working && HermezLiveMotion.on(context);
    if (breathe && !_breath.isAnimating) {
      _breath.repeat();
    } else if (!breathe && _breath.isAnimating) {
      _breath
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final color = switch (widget.state) {
      HermezLiveState.working ||
      HermezLiveState.attention ||
      HermezLiveState.failed => palette.accent,
      HermezLiveState.done => widget.ink ?? palette.ink,
      HermezLiveState.idle =>
        widget.ink?.withValues(alpha: 0.5) ?? palette.muted,
    };
    return Semantics(
      label: widget.semanticLabel,
      child: SizedBox.square(
        dimension: widget.size * 2.4,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _breath,
            builder: (context, _) => CustomPaint(
              painter: _LiveDotPainter(
                color: color,
                radius: widget.size / 2,
                // 0.86 at rest of the breath to 1.14 at its fullest.
                scale: _breath.isAnimating
                    ? 0.86 +
                          0.28 *
                              (0.5 -
                                  0.5 * math.cos(_breath.value * 2 * math.pi))
                    : 1,
                ring: widget.state == HermezLiveState.attention,
                ringColor: palette.accent.withValues(alpha: 0.45),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveDotPainter extends CustomPainter {
  const _LiveDotPainter({
    required this.color,
    required this.radius,
    required this.scale,
    required this.ring,
    required this.ringColor,
  });

  final Color color;
  final double radius;
  final double scale;
  final bool ring;
  final Color ringColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    if (ring) {
      canvas.drawCircle(
        center,
        radius + 3,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = ringColor,
      );
    }
    canvas.drawCircle(center, radius * scale, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_LiveDotPainter old) =>
      old.scale != scale ||
      old.color != color ||
      old.ring != ring ||
      old.radius != radius;
}

/// Text that is happening now. Like all text that changes in place in
/// Hermez, a new line simply replaces the old one: no roll, no fade. A
/// screen reader hears each change as it lands.
class HermezLiveText extends StatelessWidget {
  const HermezLiveText(
    this.text, {
    super.key,
    required this.style,
    this.live = true,
    this.maxLines = 1,
  });

  final String text;
  final TextStyle style;

  /// Announce changes to assistive technology.
  final bool live;
  final int maxLines;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: live,
    child: Text(
      text,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: style,
    ),
  );
}

/// A count that changes in place: tabular, so neighbours never shift.
class HermezRollingCount extends StatelessWidget {
  const HermezRollingCount({
    super.key,
    required this.value,
    required this.style,
  });

  final String value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Text(
    value,
    style: style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
  );
}

/// A plan's progress drawn as its real steps: one segment per step that
/// counts, solid when done. The step in progress carries a darker band that
/// travels along it while the run is live. No percentages.
class HermezPlanBar extends StatefulWidget {
  const HermezPlanBar({
    super.key,
    required this.snapshot,
    this.height = 4,
    this.paused = false,
  });

  final HermesTodoSnapshot snapshot;
  final double height;
  final bool paused;

  @override
  State<HermezPlanBar> createState() => _HermezPlanBarState();
}

class _HermezPlanBarState extends State<HermezPlanBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _travel = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  bool get _live => widget.snapshot.active > 0 && !widget.paused;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant HermezPlanBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final run = _live && HermezLiveMotion.on(context);
    if (run && !_travel.isAnimating) {
      _travel.repeat();
    } else if (!run && _travel.isAnimating) {
      _travel.stop();
    }
  }

  @override
  void dispose() {
    _travel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final top = [
      for (final row in widget.snapshot.outline)
        if (row.depth == 0 && row.item.status != HermesTodoStatus.cancelled)
          row.item.status,
    ];
    final statuses = top.isEmpty
        ? [
            for (final item in widget.snapshot.items)
              if (item.status != HermesTodoStatus.cancelled) item.status,
          ]
        : top;
    return Semantics(
      label:
          'Plan, ${widget.snapshot.completed} of ${widget.snapshot.total} steps done',
      child: SizedBox(
        height: widget.height,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _travel,
            builder: (context, _) => CustomPaint(
              size: Size.infinite,
              painter: _PlanBarPainter(
                statuses: statuses,
                done: palette.ink,
                live: palette.accent,
                band: Color.lerp(palette.accent, palette.ink, 0.35)!,
                track: Color.lerp(palette.surface, palette.ink, 0.09)!,
                travel: _travel.isAnimating
                    ? Curves.easeInOutSine.transform(_travel.value)
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlanBarPainter extends CustomPainter {
  const _PlanBarPainter({
    required this.statuses,
    required this.done,
    required this.live,
    required this.band,
    required this.track,
    required this.travel,
  });

  final List<HermesTodoStatus> statuses;
  final Color done;
  final Color live;
  final Color band;
  final Color track;

  /// Where the band is along a live segment, 0..1; null when still.
  final double? travel;

  @override
  void paint(Canvas canvas, Size size) {
    if (statuses.isEmpty) return;
    final gap = statuses.length > 24 ? 1.5 : 3.0;
    final width = (size.width - gap * (statuses.length - 1)) / statuses.length;
    final radius = Radius.circular(size.height / 2);
    for (var i = 0; i < statuses.length; i++) {
      final left = i * (width + gap);
      final rect = RRect.fromLTRBR(
        left,
        0,
        left + math.max(width, 1),
        size.height,
        radius,
      );
      final status = statuses[i];
      canvas.drawRRect(
        rect,
        Paint()
          ..color = switch (status) {
            HermesTodoStatus.completed => done,
            HermesTodoStatus.inProgress => live,
            _ => track,
          },
      );
      final at = travel;
      if (status == HermesTodoStatus.inProgress && at != null) {
        final span = math.max(width, 1.0);
        final bandWidth = math.max(span * 0.34, 6.0);
        final x = left - bandWidth + (span + bandWidth) * at;
        canvas
          ..save()
          ..clipRRect(rect)
          ..drawRect(
            Rect.fromLTWH(x, 0, bandWidth, size.height),
            Paint()..color = band,
          )
          ..restore();
      }
    }
  }

  @override
  bool shouldRepaint(_PlanBarPainter old) =>
      old.travel != travel ||
      old.live != live ||
      old.done != done ||
      old.track != track ||
      !_same(old.statuses, statuses);

  static bool _same(List<HermesTodoStatus> a, List<HermesTodoStatus> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// A plan step's status glyph: an empty ring, a ring drawing itself round,
/// a check that draws itself in when the step completes, or a stroke for
/// cancelled. Strokes and scale only.
class HermezTodoGlyph extends StatelessWidget {
  const HermezTodoGlyph({super.key, required this.status, this.size = 18});

  final HermesTodoStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final reduced = context.reduceMotion;
    return SizedBox.square(
      dimension: size,
      child: TweenAnimationBuilder<double>(
        key: ValueKey(status),
        tween: Tween(begin: reduced ? 1 : 0, end: 1),
        duration: reduced
            ? Duration.zero
            : HermezMotion.settleFor(HermezMotionWeight.medium),
        curve: HermezMotion.curveMedium,
        builder: (context, t, _) => CustomPaint(
          painter: _TodoGlyphPainter(
            status: status,
            t: t,
            ink: palette.ink,
            accent: palette.accent,
            muted: palette.muted,
            surface: palette.surface,
          ),
        ),
      ),
    );
  }
}

class _TodoGlyphPainter extends CustomPainter {
  const _TodoGlyphPainter({
    required this.status,
    required this.t,
    required this.ink,
    required this.accent,
    required this.muted,
    required this.surface,
  });

  final HermesTodoStatus status;
  final double t;
  final Color ink;
  final Color accent;
  final Color muted;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2 - 1.5;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    switch (status) {
      case HermesTodoStatus.pending:
        canvas.drawCircle(center, r, stroke..color = muted);
      case HermesTodoStatus.inProgress:
        canvas.drawCircle(
          center,
          r,
          stroke..color = Color.lerp(surface, accent, 0.4)!,
        );
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: r),
          -math.pi / 2,
          math.pi * 1.2 * t,
          false,
          stroke..color = accent,
        );
        canvas.drawCircle(center, r * 0.32 * t, Paint()..color = accent);
      case HermesTodoStatus.completed:
        canvas.drawCircle(center, r * (0.85 + 0.15 * t), Paint()..color = ink);
        final path = Path()
          ..moveTo(center.dx - r * 0.42, center.dy + r * 0.02)
          ..lineTo(center.dx - r * 0.1, center.dy + r * 0.34)
          ..lineTo(center.dx + r * 0.46, center.dy - r * 0.32);
        final metric = path.computeMetrics().first;
        // The check is cut out of the disc in the surface colour.
        canvas.drawPath(
          metric.extractPath(0, metric.length * t),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.9
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = surface,
        );
      case HermesTodoStatus.cancelled:
        canvas.drawCircle(
          center,
          r,
          stroke..color = Color.lerp(surface, muted, 0.5)!,
        );
        canvas.drawLine(
          center + Offset(-r * 0.45 * t, 0),
          center + Offset(r * 0.45 * t, 0),
          stroke..color = muted,
        );
    }
  }

  @override
  bool shouldRepaint(_TodoGlyphPainter old) =>
      old.t != t ||
      old.status != status ||
      old.ink != ink ||
      old.accent != accent ||
      old.surface != surface;
}
