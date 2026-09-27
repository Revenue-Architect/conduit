import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'hermez_chat_palette.dart';

enum HermezSurfaceKind { hero, utility, list, technical }

enum HermezMotif { none, slash, arc, crop }

class HermezType {
  const HermezType._();

  static TextStyle display(HermezChatPalette palette) => TextStyle(
    color: palette.ink,
    fontSize: 32,
    height: 1.02,
    fontWeight: FontWeight.w900,
    letterSpacing: -1.2,
  );

  static TextStyle section(HermezChatPalette palette) => TextStyle(
    color: palette.ink,
    fontSize: 16,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.3,
  );

  static TextStyle body(HermezChatPalette palette) => TextStyle(
    color: palette.ink,
    fontSize: 14,
    height: 1.35,
    fontWeight: FontWeight.w500,
  );

  static TextStyle meta(HermezChatPalette palette) => TextStyle(
    color: palette.muted,
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w500,
  );

  static TextStyle technical(Color color) => TextStyle(
    color: color,
    fontSize: 10,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.6,
  );

  static TextStyle numeric(Color color) => TextStyle(
    color: color,
    fontSize: 28,
    height: 1,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.8,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

/// A section label plus an optional action. Wraps instead of painting an overflow.
class HermezSectionBar extends StatelessWidget {
  const HermezSectionBar({
    super.key,
    required this.label,
    this.actionLabel,
    this.onAction,
  });

  final String label;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        Text(label, style: HermezType.technical(palette.muted)),
        if (onAction != null)
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 40),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: onAction,
            child: Text(actionLabel ?? 'See all'),
          ),
      ],
    );
  }
}

/// One of four Hermez surfaces. Geometry is drawn in Flutter and ignores input.
class HermezSurface extends StatelessWidget {
  const HermezSurface({
    super.key,
    required this.child,
    this.kind = HermezSurfaceKind.utility,
    this.motif = HermezMotif.none,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.indexLabel,
  });

  final Widget child;
  final HermezSurfaceKind kind;
  final HermezMotif motif;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final String? indexLabel;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final technical = kind == HermezSurfaceKind.technical;
    final radius = switch (kind) {
      HermezSurfaceKind.hero => 28.0,
      HermezSurfaceKind.utility => 18.0,
      HermezSurfaceKind.list => 0.0,
      HermezSurfaceKind.technical => 22.0,
    };
    final color = technical ? const Color(0xFF17181C) : palette.surface;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );
    final content = Padding(padding: padding, child: child);
    return Material(
      color: kind == HermezSurfaceKind.list ? Colors.transparent : color,
      clipBehavior: Clip.antiAlias,
      shape: shape,
      child: Stack(
        children: [
          if (motif != HermezMotif.none && kind != HermezSurfaceKind.list)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _MotifPainter(
                    motif: motif,
                    accent: palette.accent,
                    ink: technical ? const Color(0xFFF6F5F2) : palette.ink,
                    indexLabel: indexLabel,
                  ),
                ),
              ),
            ),
          if (onTap == null)
            content
          else
            InkWell(
              onTap: onTap,
              child: content,
            ),
        ],
      ),
    );
  }
}

class _MotifPainter extends CustomPainter {
  const _MotifPainter({
    required this.motif,
    required this.accent,
    required this.ink,
    this.indexLabel,
  });

  final HermezMotif motif;
  final Color accent;
  final Color ink;
  final String? indexLabel;

  @override
  void paint(Canvas canvas, Size size) {
    final accentPaint = Paint()
      ..color = accent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    switch (motif) {
      case HermezMotif.none:
        return;
      case HermezMotif.slash:
        canvas.drawLine(
          Offset(size.width - 28, 10),
          Offset(size.width - 8, 34),
          accentPaint,
        );
      case HermezMotif.arc:
        canvas.drawArc(
          Rect.fromCircle(
            center: Offset(size.width - 8, 8),
            radius: 36,
          ),
          math.pi * 0.35,
          math.pi * 0.7,
          false,
          accentPaint..color = accent.withValues(alpha: 0.8),
        );
      case HermezMotif.crop:
        final crop = Path()
          ..moveTo(size.width, 0)
          ..lineTo(size.width, size.height * 0.42)
          ..lineTo(size.width * 0.72, 0)
          ..close();
        canvas.drawPath(
          crop,
          Paint()..color = ink.withValues(alpha: 0.05),
        );
        canvas.drawLine(
          Offset(size.width - 36, 14),
          Offset(size.width - 12, 42),
          accentPaint,
        );
    }
    final label = indexLabel;
    if (label == null) return;
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: ink.withValues(alpha: 0.35),
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(12, size.height - 18));
  }

  @override
  bool shouldRepaint(_MotifPainter oldDelegate) =>
      motif != oldDelegate.motif ||
      accent != oldDelegate.accent ||
      indexLabel != oldDelegate.indexLabel;
}
