import 'package:flutter/material.dart';

import 'hermez_chat_palette.dart';

/// Quiet, deterministic construction marks for Hermez surfaces. This paints
/// behind content, never handles input, and uses the existing palette.
enum HermezBackgroundVariant { lightGeometry, mechanical, editorial }

class HermezTechnicalBackground extends StatelessWidget {
  const HermezTechnicalBackground({
    super.key,
    required this.child,
    this.variant = HermezBackgroundVariant.lightGeometry,
  });

  final Widget child;
  final HermezBackgroundVariant variant;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _TechnicalPainter(palette: palette, variant: variant),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _TechnicalPainter extends CustomPainter {
  const _TechnicalPainter({required this.palette, required this.variant});

  final HermezChatPalette palette;
  final HermezBackgroundVariant variant;

  @override
  void paint(Canvas canvas, Size size) {
    final hairline = Paint()
      ..color = palette.border.withValues(alpha: 0.28)
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;
    final accent = Paint()
      ..color = palette.accent.withValues(alpha: 0.65)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final right = size.width;
    final top = 0.0;
    switch (variant) {
      case HermezBackgroundVariant.lightGeometry:
        canvas.drawLine(Offset(right * .68, top), Offset(right, 42), hairline);
        canvas.drawLine(Offset(right * .82, top), Offset(right, 24), hairline);
        canvas.drawLine(Offset(right - 30, 9), Offset(right - 21, 9), accent);
      case HermezBackgroundVariant.mechanical:
        canvas.drawArc(
          Rect.fromCircle(center: Offset(right - 5, 4), radius: 44),
          1.4,
          1.5,
          false,
          hairline,
        );
        canvas.drawLine(Offset(right - 27, 8), Offset(right - 18, 8), accent);
      case HermezBackgroundVariant.editorial:
        canvas.drawLine(Offset(right * .72, top), Offset(right, 55), hairline);
        canvas.drawLine(Offset(right * .86, top), Offset(right, 27), hairline);
        canvas.drawLine(Offset(right - 24, 8), Offset(right - 16, 8), accent);
    }
  }

  @override
  bool shouldRepaint(covariant _TechnicalPainter oldDelegate) =>
      oldDelegate.palette != palette || oldDelegate.variant != variant;
}
