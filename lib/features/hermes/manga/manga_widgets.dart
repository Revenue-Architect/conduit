import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/theme/theme_extensions.dart';
import 'manga_theme.dart';

/// Anything you can press on the page. It answers the finger at once: 0.97
/// in 120 ms on a strong ease-out, back in 160 ms. A selection haptic only
/// where the press chooses something.
class MangaPress extends StatefulWidget {
  const MangaPress({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.semanticLabel,
    this.haptic = false,
    this.scale = .97,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? semanticLabel;
  final bool haptic;
  final double scale;

  @override
  State<MangaPress> createState() => _MangaPressState();
}

class _MangaPressState extends State<MangaPress> {
  bool _down = false;

  void _set(bool down) {
    if (_down == down) return;
    setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTapCancel: () => _set(false),
        onLongPress: widget.onLongPress,
        onTap: enabled
            ? () {
                if (widget.haptic) HapticFeedback.selectionClick();
                widget.onTap!();
              }
            : null,
        child: AnimatedScale(
          scale: _down && !context.reduceMotion ? widget.scale : 1,
          duration: _down ? MangaMotion.press : MangaMotion.release,
          curve: MangaMotion.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

/// A manga panel: square corners, an ink border, whatever is inside cropped
/// by its edge.
class MangaPanel extends StatelessWidget {
  const MangaPanel({
    super.key,
    required this.child,
    this.color,
    this.working = false,
    this.rayCentre = const Alignment(.52, .24),
  });

  final Widget child;
  final Color? color;

  /// Speed lines behind the content: this bot is working now.
  final bool working;
  final Alignment rayCentre;

  @override
  Widget build(BuildContext context) {
    final ink = MangaInk.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? ink.ground,
        border: Border.all(color: ink.ink, width: ink.border),
      ),
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (working)
              Positioned.fill(
                child: SpeedLines(
                  centre: rayCentre,
                  ground: color ?? ink.ground,
                  tone: ink.tone,
                ),
              ),
            child,
          ],
        ),
      ),
    );
  }
}

/// Radiating speed lines: the page's sign for "working now". Static on
/// purpose; a working bot is shown by the lines being there, not by them
/// moving, so nothing on the page competes with the live text.
class SpeedLines extends StatelessWidget {
  const SpeedLines({
    super.key,
    required this.centre,
    required this.ground,
    required this.tone,
    this.rays = 52,
    this.clear = .2,
  });

  final Alignment centre;
  final Color ground;
  final Color tone;
  final int rays;

  /// The calm disc around the centre, as a share of the longer side.
  final double clear;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _SpeedLinesPainter(centre, ground, tone, rays, clear),
    ),
  );
}

class _SpeedLinesPainter extends CustomPainter {
  _SpeedLinesPainter(
    this.centre,
    this.ground,
    this.tone,
    this.rays,
    this.clear,
  );

  final Alignment centre;
  final Color ground;
  final Color tone;
  final int rays;
  final double clear;

  @override
  void paint(Canvas canvas, Size size) {
    final c = centre.alongSize(size);
    final reach = size.longestSide * 1.5;
    final paint = Paint()..color = tone;
    final step = math.pi * 2 / rays;
    for (var i = 0; i < rays; i++) {
      // Uneven widths, like ruled tone: every third ray a little wider.
      final a = i * step;
      final w = step * (i % 3 == 0 ? .5 : .34);
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + math.cos(a) * reach, c.dy + math.sin(a) * reach)
        ..lineTo(c.dx + math.cos(a + w) * reach, c.dy + math.sin(a + w) * reach)
        ..close();
      canvas.drawPath(path, paint);
    }
    canvas.drawCircle(
      c,
      size.longestSide * clear,
      Paint()
        ..shader =
            RadialGradient(
              colors: [ground, ground, ground.withValues(alpha: 0)],
              stops: const [0, .7, 1],
            ).createShader(
              Rect.fromCircle(center: c, radius: size.longestSide * clear),
            ),
    );
  }

  @override
  bool shouldRepaint(_SpeedLinesPainter old) =>
      old.centre != centre ||
      old.ground != ground ||
      old.tone != tone ||
      old.rays != rays ||
      old.clear != clear;
}

/// A speech bubble: the bot's own latest words. An ellipse with an ink
/// stroke and a tail pointing at whoever speaks.
class MangaBubble extends StatelessWidget {
  const MangaBubble({
    super.key,
    required this.child,
    this.tail = MangaTail.right,
    this.fill,
    this.stroke,
    this.strokeWidth,
    this.padding = const EdgeInsets.fromLTRB(18, 13, 18, 14),
  });

  final Widget child;
  final MangaTail tail;
  final Color? fill;
  final Color? stroke;
  final double? strokeWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final ink = MangaInk.of(context);
    return CustomPaint(
      painter: _BubblePainter(
        fill: fill ?? ink.ground,
        stroke: stroke ?? ink.ink,
        width: strokeWidth ?? ink.border,
        tail: tail,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

enum MangaTail { right, left, none }

class _BubblePainter extends CustomPainter {
  _BubblePainter({
    required this.fill,
    required this.stroke,
    required this.width,
    required this.tail,
  });

  final Color fill;
  final Color stroke;
  final double width;
  final MangaTail tail;

  @override
  void paint(Canvas canvas, Size size) {
    final oval = Path()..addOval(Offset.zero & size);
    var shape = oval;
    if (tail != MangaTail.none) {
      final right = tail == MangaTail.right;
      final x = right ? size.width * .9 : size.width * .1;
      final y = size.height * .66;
      final tip = Offset(right ? size.width + 16 : -16, size.height * .86);
      final spike = Path()
        ..moveTo(x, y - 8)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(x - (right ? 10 : -10), y + 6)
        ..close();
      shape = Path.combine(PathOperation.union, oval, spike);
    }
    canvas
      ..drawPath(shape, Paint()..color = fill)
      ..drawPath(
        shape,
        Paint()
          ..color = stroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeJoin = StrokeJoin.round,
      );
  }

  @override
  bool shouldRepaint(_BubblePainter old) =>
      old.fill != fill ||
      old.stroke != stroke ||
      old.width != width ||
      old.tail != tail;
}

/// The orange stamp: "ON IT", "ON IT · 4 MIN". Set slightly askew, like a
/// stamp is.
class MangaStamp extends StatelessWidget {
  const MangaStamp(this.text, {super.key, this.tilt = 0});

  final String text;
  final double tilt;

  @override
  Widget build(BuildContext context) {
    final ink = MangaInk.of(context);
    return Transform.rotate(
      angle: tilt * math.pi / 180,
      child: DecoratedBox(
        decoration: BoxDecoration(color: ink.accent),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Text(text.toUpperCase(), style: MangaType.stamp(ink.onAccent)),
        ),
      ),
    );
  }
}

/// "4 min", "1 h", "20:08" when it was earlier today, "Oct 21" before.
String mangaWhen(DateTime at, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final local = at.toLocal();
  final ago = current.difference(local);
  if (ago.inMinutes < 1) return 'just now';
  if (ago.inMinutes < 60) return '${ago.inMinutes} min';
  final sameDay =
      local.year == current.year &&
      local.month == current.month &&
      local.day == current.day;
  if (sameDay) {
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[local.month - 1]} ${local.day}';
}

/// "just now", else "last 4 min" / "last 20:08" / "last Oct 20".
String mangaLastSeen(String when) => when == 'just now' ? when : 'last $when';
