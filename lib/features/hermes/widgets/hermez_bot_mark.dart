import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/hermes_bot.dart';
import 'hermez_chat_palette.dart';

/// Visual identity only. Derived from the profile name, not from capabilities.
enum HermezBotIdentity { neutral, kai, local, autopilot, fast, strong }

HermezBotIdentity hermezIdentityForBot(HermesBot bot) =>
    hermezIdentityForName(bot.name);

HermezBotIdentity hermezIdentityForName(String? name) {
  final key = (name ?? '').toLowerCase();
  if (key.contains('kai')) return HermezBotIdentity.kai;
  if (key.contains('local')) return HermezBotIdentity.local;
  if (key.contains('autopilot')) return HermezBotIdentity.autopilot;
  if (key.contains('fast')) return HermezBotIdentity.fast;
  if (key.contains('strong')) return HermezBotIdentity.strong;
  return HermezBotIdentity.neutral;
}

class HermezBotMark extends StatelessWidget {
  const HermezBotMark({
    super.key,
    required this.identity,
    this.size = 44,
    this.label,
  });

  final HermezBotIdentity identity;
  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    return Semantics(
      label: label == null ? 'Bot' : 'Bot $label',
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _BotMarkPainter(identity: identity, palette: palette),
        ),
      ),
    );
  }
}

class _BotMarkPainter extends CustomPainter {
  const _BotMarkPainter({required this.identity, required this.palette});

  final HermezBotIdentity identity;
  final HermezChatPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final body = Paint()..color = palette.surface;
    final ink = Paint()..color = const Color(0xFF17181C);
    final accent = Paint()..color = palette.accent;
    final line = Paint()
      ..color = palette.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, size.width * 0.035)
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.42;

    if (identity == HermezBotIdentity.fast) {
      final streak = Paint()
        ..color = palette.accent.withValues(alpha: 0.55)
        ..strokeWidth = size.width * 0.045
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 3; i++) {
        final y = size.height * (0.32 + i * 0.16);
        canvas.drawLine(
          Offset(size.width * 0.02, y),
          Offset(size.width * 0.28, y),
          streak,
        );
      }
    }

    canvas.drawCircle(center, radius, body);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = palette.ink.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawCircle(center, radius * 0.62, ink);

    final eye = Paint()..color = palette.accent;
    for (final dx in [-0.16, 0.16]) {
      canvas.drawCircle(
        center.translate(size.width * dx, -size.height * 0.01),
        size.width * 0.055,
        eye,
      );
    }

    switch (identity) {
      case HermezBotIdentity.neutral:
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius * 1.08),
          -math.pi * 0.95,
          math.pi * 0.45,
          false,
          line,
        );
      case HermezBotIdentity.kai:
        final crest = Path()
          ..moveTo(center.dx, center.dy - radius * 1.28)
          ..lineTo(center.dx + radius * 0.28, center.dy - radius * 0.72)
          ..lineTo(center.dx, center.dy - radius * 0.9)
          ..lineTo(center.dx - radius * 0.28, center.dy - radius * 0.72)
          ..close();
        canvas.drawPath(crest, accent);
      case HermezBotIdentity.local:
        final vent = Paint()
          ..color = palette.ink.withValues(alpha: 0.45)
          ..strokeWidth = size.width * 0.035
          ..strokeCap = StrokeCap.round;
        for (var i = 0; i < 3; i++) {
          final y = center.dy - radius * 0.28 + i * size.height * 0.09;
          canvas.drawLine(
            Offset(center.dx - radius * 0.95, y),
            Offset(center.dx - radius * 0.7, y),
            vent,
          );
        }
      case HermezBotIdentity.autopilot:
        final bolt = Path()
          ..moveTo(center.dx + radius * 0.15, center.dy - radius * 1.2)
          ..lineTo(center.dx - radius * 0.05, center.dy - radius * 0.72)
          ..lineTo(center.dx + radius * 0.22, center.dy - radius * 0.72)
          ..lineTo(center.dx - radius * 0.12, center.dy - radius * 0.2)
          ..lineTo(center.dx + radius * 0.08, center.dy - radius * 0.55)
          ..lineTo(center.dx - radius * 0.16, center.dy - radius * 0.55)
          ..close();
        canvas.drawPath(bolt, accent);
      case HermezBotIdentity.fast:
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius * 1.05),
          -0.4,
          1.1,
          false,
          line,
        );
      case HermezBotIdentity.strong:
        final armor = Paint()
          ..color = palette.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.4, size.width * 0.04);
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius * 0.86),
          -2.4,
          1.2,
          false,
          armor,
        );
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius * 0.86),
          0.5,
          1.1,
          false,
          armor,
        );
    }
  }

  @override
  bool shouldRepaint(_BotMarkPainter oldDelegate) =>
      identity != oldDelegate.identity || palette != oldDelegate.palette;
}
