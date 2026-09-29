import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../feedback/hermez_feedback.dart';
import '../motion/hermez_motion.dart';
import 'hermez_chat_palette.dart';
import 'hermez_touch_light.dart';

enum HermezSurfaceKind { hero, utility, list, technical }

enum HermezMotif { none, slash, arc, crop, etched }

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
///
/// A tappable surface is a physical object: it compresses under the finger
/// and springs back (see [HermezMotionSurface]). With [morphId] its body can
/// travel to another screen and become that screen's surface. [onOpen]
/// passes where the surface sits so a destination can grow out of it.
class HermezSurface extends StatelessWidget {
  const HermezSurface({
    super.key,
    required this.child,
    this.kind = HermezSurfaceKind.utility,
    this.motif = HermezMotif.none,
    this.onTap,
    this.onOpen,
    this.padding = const EdgeInsets.all(16),
    this.indexLabel,
    this.morphId,
    this.motifMorphId,
    this.border,
    this.weight = HermezMotionWeight.medium,
    this.semanticLabel,
    this.feedbackCue,
    this.touchLight = false,
  });

  final Widget child;
  final HermezSurfaceKind kind;

  /// Sound + haptic on a confirmed tap; see [HermezMotionSurface.feedbackCue].
  final HermezFeedbackCue? feedbackCue;

  /// Light that follows the finger ([HermezTouchLight]). Opt-in, for a few
  /// focal surfaces only.
  final bool touchLight;
  final HermezMotif motif;
  final VoidCallback? onTap;
  final ValueChanged<HermezMorphOrigin?>? onOpen;
  final EdgeInsets padding;
  final String? indexLabel;
  final String? morphId;

  /// Lets this surface's construction marks travel to the matching surface
  /// on the next screen instead of appearing there from nowhere.
  final String? motifMorphId;
  final BoxBorder? border;
  final HermezMotionWeight weight;
  final String? semanticLabel;

  static double radiusFor(HermezSurfaceKind kind) => switch (kind) {
    HermezSurfaceKind.hero => 28.0,
    HermezSurfaceKind.utility => 18.0,
    HermezSurfaceKind.list => 0.0,
    HermezSurfaceKind.technical => 22.0,
  };

  static Color colorFor(HermezSurfaceKind kind, HermezChatPalette palette) =>
      switch (kind) {
        HermezSurfaceKind.technical => const Color(0xFF17181C),
        HermezSurfaceKind.list => Colors.transparent,
        _ => palette.surface,
      };

  @override
  Widget build(BuildContext context) {
    final palette = HermezChatPalette.forBrightness(
      Theme.of(context).brightness,
    );
    final technical = kind == HermezSurfaceKind.technical;
    final radius = radiusFor(kind);
    final color = colorFor(kind, palette);
    final borderRadius = BorderRadius.circular(radius);
    final surface = Stack(
      children: [
        Positioned.fill(
          child: HermezMorphSurface(
            id: morphId,
            decoration: BoxDecoration(
              color: color,
              borderRadius: borderRadius,
              border: border,
            ),
          ),
        ),
        ClipRRect(
          borderRadius: borderRadius,
          clipBehavior: kind == HermezSurfaceKind.list
              ? Clip.none
              : Clip.antiAlias,
          child: Material(
            type: MaterialType.transparency,
            child: Stack(
              children: [
                if (motif != HermezMotif.none && kind != HermezSurfaceKind.list)
                  Positioned.fill(
                    child: HermezMorph(
                      id: motifMorphId,
                      flight: HermezMorphFlight.stretch,
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _MotifPainter(
                            motif: motif,
                            accent: palette.accent,
                            ink: technical
                                ? const Color(0xFFF6F5F2)
                                : palette.ink,
                            indexLabel: indexLabel,
                          ),
                        ),
                      ),
                    ),
                  ),
                Padding(padding: padding, child: child),
              ],
            ),
          ),
        ),
      ],
    );
    if (onTap == null && onOpen == null) return surface;
    // Inside the pressable surface, so the light compresses with it.
    final lit = touchLight && kind != HermezSurfaceKind.list
        ? HermezTouchLight(
            borderRadius: radius,
            dark: technical,
            accent: palette.accent,
            child: surface,
          )
        : surface;
    return HermezMotionSurface(
      onTap: onTap,
      onOpen: onOpen,
      feedbackCue: feedbackCue,
      weight: weight,
      semanticLabel: semanticLabel,
      originRadius: radius,
      originColor: color,
      originBorderColor: border is Border
          ? (border! as Border).top.color
          : null,
      child: lit,
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
    final line = Paint()
      ..color = ink.withValues(alpha: .09)
      ..strokeWidth = .65
      ..style = PaintingStyle.stroke;
    if (motif != HermezMotif.none) {
      canvas.drawLine(Offset(size.width - 92, 0), Offset(size.width, 92), line);
      canvas.drawLine(Offset(size.width - 68, 0), Offset(size.width, 68), line);
    }
    switch (motif) {
      case HermezMotif.none:
        return;
      case HermezMotif.etched:
        final edge = Path()
          ..moveTo(size.width - 48, size.height)
          ..lineTo(size.width, size.height - 48)
          ..lineTo(size.width, size.height)
          ..close();
        canvas.drawPath(edge, Paint()..color = ink.withValues(alpha: .08));
        for (var i = 0; i < 4; i++) {
          canvas.drawLine(
            Offset(size.width - 26 + i * 5, size.height - 4),
            Offset(size.width - 4, size.height - 26 + i * 5),
            line,
          );
        }
        canvas.drawLine(
          Offset(size.width - 18, size.height - 3),
          Offset(size.width - 3, size.height - 18),
          accentPaint,
        );
      case HermezMotif.slash:
        canvas.drawLine(
          Offset(size.width - 28, 10),
          Offset(size.width - 8, 34),
          accentPaint,
        );
      case HermezMotif.arc:
        canvas.drawArc(
          Rect.fromCircle(center: Offset(size.width - 8, 8), radius: 36),
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
        canvas.drawPath(crop, Paint()..color = ink.withValues(alpha: 0.05));
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
      ink != oldDelegate.ink ||
      indexLabel != oldDelegate.indexLabel;
}
