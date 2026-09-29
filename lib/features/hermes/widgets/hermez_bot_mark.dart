import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

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
    final brightness = Theme.of(context).brightness;
    return Semantics(
      label: label == null ? 'Bot' : 'Bot $label',
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _CachedBotMarkPainter(
            identity: identity,
            brightness: brightness,
            devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
          ),
        ),
      ),
    );
  }
}

/// Draws a bot mark from an image rendered once per identity, theme, and
/// pixel size.
///
/// The mark is static art built from blurred glows and gradients. Drawn live,
/// every blurred path is rendered offscreen and blurred again on every frame
/// the mark is on screen, so a page of marks moving (a scroll, the side
/// navigation sliding Home away) spent most of its frame on them and dropped
/// frames. The cached image is drawn like any picture.
class _CachedBotMarkPainter extends CustomPainter {
  const _CachedBotMarkPainter({
    required this.identity,
    required this.brightness,
    required this.devicePixelRatio,
  });

  final HermezBotIdentity identity;
  final Brightness brightness;
  final double devicePixelRatio;

  /// Glows reach a little past the square; render with this margin so the
  /// image holds everything the live painter drew.
  static const double _margin = 0.25;
  static const int _capacity = 32;
  static final LinkedHashMap<(HermezBotIdentity, Brightness, int), ui.Image>
  _cache = LinkedHashMap();

  static ui.Image _imageFor(
    HermezBotIdentity identity,
    Brightness brightness,
    double logicalSize,
    double devicePixelRatio,
  ) {
    final pixels = math.max(1, (logicalSize * devicePixelRatio).round());
    final key = (identity, brightness, pixels);
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached; // most recently used last
      return cached;
    }
    final scale = pixels / logicalSize;
    final pad = (pixels * _margin).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..translate(pad.toDouble(), pad.toDouble())
      ..scale(scale);
    _BotMarkPainter(
      identity: identity,
      palette: HermezChatPalette.forBrightness(brightness),
    ).paint(canvas, Size.square(logicalSize));
    final picture = recorder.endRecording();
    final image = picture.toImageSync(pixels + pad * 2, pixels + pad * 2);
    picture.dispose();
    _cache[key] = image;
    if (_cache.length > _capacity) {
      final oldest = _cache.keys.first;
      _cache.remove(oldest)!.dispose();
    }
    return image;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final image = _imageFor(identity, brightness, size.width, devicePixelRatio);
    // The same integer geometry the image was rendered with.
    final pixels = math.max(1, (size.width * devicePixelRatio).round());
    final pad = (pixels * _margin).ceil();
    final unit = size.width / pixels;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(
        -pad * unit,
        -pad * unit,
        image.width * unit,
        image.height * unit,
      ),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_CachedBotMarkPainter oldDelegate) =>
      identity != oldDelegate.identity ||
      brightness != oldDelegate.brightness ||
      devicePixelRatio != oldDelegate.devicePixelRatio;
}

/// Draws the Hermez bot family from the reference renders: a white spherical
/// shell with a side disc, a large dark face turned slightly to the right,
/// glowing orange eyes, and a few profile-specific parts. Everything is in
/// unit space so the mark stays crisp from 40 px chips to 88 px headers.
class _BotMarkPainter extends CustomPainter {
  const _BotMarkPainter({required this.identity, required this.palette});

  final HermezBotIdentity identity;
  final HermezChatPalette palette;

  static const _shellHi = Color(0xFFFFFFFF);
  static const _shellMid = Color(0xFFEDEFF1);
  static const _shellLow = Color(0xFFCDD1D5);
  static const _shellEdge = Color(0xFFA3A8AE);
  static const _seam = Color(0xFF8E949A);
  static const _faceTop = Color(0xFF2B2E34);
  static const _faceBottom = Color(0xFF07080A);
  static const _glow = Color(0xFFFF8A1F);
  static const _eyeCore = Color(0xFFFFB45C);

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width;
    Offset p(double x, double y) => Offset(u * x, u * y);
    final blur = math.max(0.6, u * 0.022);

    // Ground shadow.
    canvas.drawOval(
      Rect.fromCenter(center: p(0.5, 0.925), width: u * 0.6, height: u * 0.07),
      Paint()
        ..color = const Color(0x2E000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur * 1.4),
    );

    final center = p(0.5, 0.53);
    final radius = u * 0.385;

    if (identity == HermezBotIdentity.fast) _paintStreaks(canvas, u, p);

    // Shell.
    final shellRect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.42, -0.5),
          radius: 1.05,
          colors: [_shellHi, _shellMid, _shellLow, _shellEdge],
          stops: [0, 0.42, 0.82, 1],
        ).createShader(shellRect),
    );

    if (identity == HermezBotIdentity.fast) _paintFins(canvas, u, p);

    canvas.save();
    canvas.clipPath(Path()..addOval(shellRect));
    _paintShellDetail(canvas, u, p, blur);
    canvas.restore();

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = _shellEdge.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.6, u * 0.009),
    );

    // Face: a dark visor turned slightly right, inside a seam.
    final face = Rect.fromCenter(
      center: p(0.575, 0.545),
      width: u * 0.5,
      height: u * 0.45,
    );
    canvas.drawOval(
      face.inflate(u * 0.022),
      Paint()..color = _shellEdge.withValues(alpha: 0.75),
    );
    canvas.drawOval(
      face,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.35, -0.45),
          radius: 0.95,
          colors: [_faceTop, _faceBottom],
        ).createShader(face),
    );
    // Glass highlight.
    canvas.drawArc(
      face.deflate(u * 0.035),
      math.pi * 1.08,
      math.pi * 0.42,
      false,
      Paint()
        ..color = const Color(0x2EFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(0.6, u * 0.018),
    );

    if (identity == HermezBotIdentity.neutral) {
      final notch = Path()
        ..moveTo(u * 0.535, u * 0.305)
        ..lineTo(u * 0.625, u * 0.29)
        ..lineTo(u * 0.575, u * 0.38)
        ..close();
      canvas.drawPath(notch, Paint()..color = _shellMid);
    }

    // Eyes.
    for (final x in [0.5, 0.655]) {
      final eye = p(x, 0.545);
      canvas.drawCircle(
        eye,
        u * 0.07,
        Paint()
          ..color = _glow.withValues(alpha: 0.42)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur * 1.3),
      );
      canvas.drawCircle(
        eye,
        u * 0.047,
        Paint()
          ..shader = RadialGradient(colors: [_eyeCore, palette.accent])
              .createShader(Rect.fromCircle(center: eye, radius: u * 0.047)),
      );
    }

    if (identity == HermezBotIdentity.kai) _paintCrest(canvas, u, p, blur);
    if (identity == HermezBotIdentity.autopilot) {
      _paintAntenna(canvas, u, p, blur);
    }
  }

  void _glowLine(
    Canvas canvas,
    Path path,
    double u,
    double blur, {
    double width = 0.013,
  }) {
    canvas.drawPath(
      path,
      Paint()
        ..color = _glow.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1, u * width * 2.4)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = palette.accent
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(0.7, u * width),
    );
  }

  Paint _seamPaint(double u) => Paint()
    ..color = _seam.withValues(alpha: 0.7)
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(0.5, u * 0.009);

  /// Side disc, seams, and per-profile panel work, clipped to the shell.
  void _paintShellDetail(
    Canvas canvas,
    double u,
    Offset Function(double, double) p,
    double blur,
  ) {
    // Side disc.
    final disc = Rect.fromCenter(
      center: p(0.215, 0.54),
      width: u * 0.2,
      height: u * 0.31,
    );
    canvas.drawOval(
      disc,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_shellHi, _shellLow],
        ).createShader(disc),
    );
    canvas.drawOval(disc, _seamPaint(u));

    switch (identity) {
      case HermezBotIdentity.neutral:
        _glowLine(
          canvas,
          Path()
            ..moveTo(u * 0.47, u * 0.17)
            ..quadraticBezierTo(u * 0.5, u * 0.26, u * 0.49, u * 0.3),
          u,
          blur,
        );
        _glowLine(
          canvas,
          Path()
            ..moveTo(u * 0.33, u * 0.33)
            ..quadraticBezierTo(u * 0.26, u * 0.6, u * 0.4, u * 0.82),
          u,
          blur,
        );
      case HermezBotIdentity.kai:
        _glowLine(
          canvas,
          Path()
            ..moveTo(u * 0.31, u * 0.36)
            ..quadraticBezierTo(u * 0.25, u * 0.62, u * 0.4, u * 0.84),
          u,
          blur,
        );
        canvas.drawArc(
          Rect.fromCenter(
            center: p(0.215, 0.54),
            width: u * 0.26,
            height: u * 0.37,
          ),
          math.pi * 0.55,
          math.pi * 0.9,
          false,
          _seamPaint(u),
        );
      case HermezBotIdentity.strong:
        final plate = _seamPaint(u)
          ..color = const Color(0xFF3B3E43)
          ..strokeWidth = math.max(0.8, u * 0.018);
        canvas.drawArc(
          Rect.fromCircle(center: p(0.5, 0.53), radius: u * 0.3),
          math.pi * 1.05,
          math.pi * 0.9,
          false,
          plate,
        );
        canvas.drawLine(p(0.5, 0.14), p(0.5, 0.23), plate);
        canvas.drawLine(p(0.3, 0.8), p(0.38, 0.68), plate);
        canvas.drawLine(p(0.72, 0.84), p(0.66, 0.72), plate);
        // Lit slot along the crown and the disc ring.
        _glowLine(
          canvas,
          Path()
            ..moveTo(u * 0.5, u * 0.16)
            ..lineTo(u * 0.5, u * 0.26),
          u,
          blur,
          width: 0.028,
        );
        _glowLine(
          canvas,
          Path()..addOval(
            Rect.fromCenter(
              center: p(0.215, 0.54),
              width: u * 0.25,
              height: u * 0.37,
            ),
          ),
          u,
          blur,
          width: 0.016,
        );
      case HermezBotIdentity.fast:
        _glowLine(
          canvas,
          Path()
            ..moveTo(u * 0.3, u * 0.24)
            ..quadraticBezierTo(u * 0.4, u * 0.3, u * 0.37, u * 0.46),
          u,
          blur,
        );
        _glowLine(
          canvas,
          Path()
            ..moveTo(u * 0.34, u * 0.7)
            ..quadraticBezierTo(u * 0.44, u * 0.84, u * 0.56, u * 0.87),
          u,
          blur,
        );
      case HermezBotIdentity.local:
        final vent = Paint()..color = const Color(0xFF2A2D32);
        for (final rect in [
          Rect.fromCenter(
            center: p(0.38, 0.17),
            width: u * 0.14,
            height: u * 0.07,
          ),
          Rect.fromCenter(
            center: p(0.64, 0.155),
            width: u * 0.12,
            height: u * 0.06,
          ),
          Rect.fromCenter(
            center: p(0.46, 0.885),
            width: u * 0.16,
            height: u * 0.06,
          ),
        ]) {
          final rrect = RRect.fromRectAndRadius(
            rect,
            Radius.circular(u * 0.02),
          );
          canvas.drawRRect(rrect, vent);
          for (var i = 1; i < 4; i++) {
            final y = rect.top + rect.height * i / 4;
            canvas.drawLine(
              Offset(rect.left + u * 0.012, y),
              Offset(rect.right - u * 0.012, y),
              Paint()
                ..color = _glow.withValues(alpha: 0.85)
                ..strokeWidth = math.max(0.4, u * 0.006),
            );
          }
        }
        // Lens port on the disc.
        canvas.drawCircle(p(0.2, 0.53), u * 0.058, Paint()..color = _shellEdge);
        canvas.drawCircle(
          p(0.2, 0.53),
          u * 0.036,
          Paint()..color = const Color(0xFF3A3E44),
        );
        _glowLine(
          canvas,
          Path()
            ..moveTo(u * 0.31, u * 0.4)
            ..lineTo(u * 0.31, u * 0.47),
          u,
          blur,
          width: 0.016,
        );
      case HermezBotIdentity.autopilot:
        _glowLine(
          canvas,
          Path()
            ..moveTo(u * 0.33, u * 0.33)
            ..quadraticBezierTo(u * 0.27, u * 0.6, u * 0.4, u * 0.82),
          u,
          blur,
        );
    }
  }

  void _paintCrest(
    Canvas canvas,
    double u,
    Offset Function(double, double) p,
    double blur,
  ) {
    final crest = Path()
      ..moveTo(u * 0.3, u * 0.25)
      ..lineTo(u * 0.25, u * 0.1)
      ..quadraticBezierTo(u * 0.36, u * 0.15, u * 0.43, u * 0.19)
      ..lineTo(u * 0.53, u * 0.01)
      ..lineTo(u * 0.61, u * 0.19)
      ..quadraticBezierTo(u * 0.69, u * 0.14, u * 0.78, u * 0.1)
      ..lineTo(u * 0.72, u * 0.27)
      ..quadraticBezierTo(u * 0.6, u * 0.24, u * 0.56, u * 0.36)
      ..quadraticBezierTo(u * 0.5, u * 0.24, u * 0.3, u * 0.25)
      ..close();
    canvas.drawPath(
      crest,
      Paint()
        ..color = const Color(0x33000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur * 0.8),
    );
    canvas.drawPath(
      crest,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_shellHi, _shellLow],
        ).createShader(Rect.fromLTWH(u * 0.25, 0, u * 0.53, u * 0.36)),
    );
    _glowLine(
      canvas,
      Path()
        ..moveTo(u * 0.25, u * 0.1)
        ..quadraticBezierTo(u * 0.36, u * 0.15, u * 0.43, u * 0.19)
        ..lineTo(u * 0.53, u * 0.01)
        ..lineTo(u * 0.61, u * 0.19)
        ..quadraticBezierTo(u * 0.69, u * 0.14, u * 0.78, u * 0.1),
      u,
      blur,
      width: 0.011,
    );
    final gem = Path()
      ..moveTo(u * 0.53, u * 0.12)
      ..lineTo(u * 0.565, u * 0.18)
      ..lineTo(u * 0.53, u * 0.24)
      ..lineTo(u * 0.495, u * 0.18)
      ..close();
    canvas.drawPath(
      gem,
      Paint()
        ..color = _glow.withValues(alpha: 0.6)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
    );
    canvas.drawPath(gem, Paint()..color = palette.accent);
  }

  void _paintFins(Canvas canvas, double u, Offset Function(double, double) p) {
    final fin = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerRight,
        end: Alignment.centerLeft,
        colors: [_shellHi, _shellLow],
      ).createShader(Rect.fromLTWH(0, u * 0.1, u * 0.5, u * 0.7));
    final edge = Paint()
      ..color = _shellEdge
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.5, u * 0.008);
    for (final points in const [
      [0.36, 0.2, 0.2, 0.16, 0.3, 0.31],
      [0.22, 0.36, 0.08, 0.37, 0.2, 0.5],
      [0.2, 0.62, 0.07, 0.68, 0.25, 0.74],
    ]) {
      final path = Path()
        ..moveTo(u * points[0], u * points[1])
        ..quadraticBezierTo(
          u * (points[2] + 0.06),
          u * points[3],
          u * points[2],
          u * points[3],
        )
        ..lineTo(u * points[4], u * points[5])
        ..close();
      canvas.drawPath(path, fin);
      canvas.drawPath(path, edge);
    }
  }

  void _paintStreaks(
    Canvas canvas,
    double u,
    Offset Function(double, double) p,
  ) {
    for (final (y, length) in const [
      (0.34, 0.26),
      (0.46, 0.34),
      (0.58, 0.3),
      (0.7, 0.22),
    ]) {
      final start = p(0.2, y);
      final end = p(0.2 - length, y);
      canvas.drawLine(
        start,
        end,
        Paint()
          ..shader = LinearGradient(
            colors: [_glow.withValues(alpha: 0.75), _glow.withValues(alpha: 0)],
          ).createShader(Rect.fromPoints(start, end.translate(0, 1)))
          ..strokeWidth = math.max(0.8, u * 0.022)
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _paintAntenna(
    Canvas canvas,
    double u,
    Offset Function(double, double) p,
    double blur,
  ) {
    canvas.drawLine(
      p(0.56, 0.16),
      p(0.62, 0.05),
      Paint()
        ..color = _shellEdge
        ..strokeWidth = math.max(0.8, u * 0.018)
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      p(0.625, 0.045),
      u * 0.045,
      Paint()
        ..color = _glow.withValues(alpha: 0.5)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
    );
    canvas.drawCircle(
      p(0.625, 0.045),
      u * 0.03,
      Paint()..color = palette.accent,
    );
  }

  @override
  bool shouldRepaint(_BotMarkPainter oldDelegate) =>
      identity != oldDelegate.identity || palette != oldDelegate.palette;
}
