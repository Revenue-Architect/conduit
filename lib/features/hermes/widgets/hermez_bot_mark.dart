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
    final unit = size.width;
    final center = Offset(unit * 0.5, unit * 0.53);
    final shellRect = Rect.fromLTWH(
      unit * 0.11,
      unit * 0.15,
      unit * 0.78,
      unit * 0.74,
    );
    final shell = RRect.fromRectAndRadius(
      shellRect,
      Radius.circular(unit * 0.31),
    );
    final shadow = RRect.fromRectAndRadius(
      shellRect.shift(Offset(0, unit * 0.035)),
      Radius.circular(unit * 0.31),
    );
    canvas.drawRRect(shadow, Paint()..color = const Color(0xFFAFB3B8));
    canvas.drawRRect(
      shell,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFE8EAEC), Color(0xFFC9CDD0)],
        ).createShader(shellRect),
    );
    canvas.drawRRect(
      shell,
      Paint()
        ..color = const Color(0xFFB4B8BC)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, unit * 0.017),
    );
    final faceRect = Rect.fromLTWH(
      unit * 0.24,
      unit * 0.32,
      unit * 0.52,
      unit * 0.35,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(faceRect, Radius.circular(unit * 0.115)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF090B0E), Color(0xFF25282D)],
        ).createShader(faceRect),
    );
    final eye = Paint()..color = palette.accent;
    for (final dx in [-0.105, 0.105]) {
      canvas.drawCircle(
        center.translate(unit * dx, -unit * 0.03),
        unit * 0.041,
        eye,
      );
    }
    final seam = Paint()
      ..color = const Color(0xFF9DA2A7)
      ..strokeWidth = math.max(0.75, unit * 0.016)
      ..strokeCap = StrokeCap.round;
    final signal = Paint()
      ..color = palette.accent
      ..strokeWidth = math.max(1.25, unit * 0.035)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(unit * 0.38, unit * 0.77),
      Offset(unit * 0.62, unit * 0.77),
      seam,
    );
    switch (identity) {
      case HermezBotIdentity.neutral:
        canvas.drawLine(
          Offset(unit * 0.39, unit * 0.21),
          Offset(unit * 0.61, unit * 0.21),
          signal,
        );
      case HermezBotIdentity.kai:
        canvas.drawLine(
          Offset(unit * 0.5, unit * 0.08),
          Offset(unit * 0.5, unit * 0.19),
          signal,
        );
        canvas.drawCircle(Offset(unit * 0.5, unit * 0.065), unit * 0.045, eye);
      case HermezBotIdentity.local:
        for (var i = 0; i < 3; i++) {
          final y = unit * (0.36 + i * 0.09);
          canvas.drawLine(Offset(unit * 0.14, y), Offset(unit * 0.20, y), seam);
        }
      case HermezBotIdentity.autopilot:
        final bolt = Path()
          ..moveTo(unit * 0.52, unit * 0.08)
          ..lineTo(unit * 0.44, unit * 0.20)
          ..lineTo(unit * 0.53, unit * 0.20)
          ..lineTo(unit * 0.48, unit * 0.29);
        canvas.drawPath(bolt, signal..style = PaintingStyle.stroke);
      case HermezBotIdentity.fast:
        for (var i = 0; i < 3; i++) {
          final y = unit * (0.37 + i * 0.11);
          canvas.drawLine(
            Offset(unit * 0.03, y),
            Offset(unit * 0.17, y),
            signal,
          );
        }
      case HermezBotIdentity.strong:
        canvas.drawArc(
          Rect.fromLTWH(unit * 0.07, unit * 0.20, unit * 0.86, unit * 0.66),
          math.pi * 0.12,
          math.pi * 0.75,
          false,
          signal..style = PaintingStyle.stroke,
        );
    }
  }

  @override
  bool shouldRepaint(_BotMarkPainter oldDelegate) =>
      identity != oldDelegate.identity || palette != oldDelegate.palette;
}
