import 'package:flutter/material.dart';

import '../feedback/hermez_feedback.dart';
import '../motion/hermez_motion.dart';
import 'hermez_chat_palette.dart';
import 'hermez_touch_light.dart';

enum HermezSurfaceKind { hero, utility, list, technical }

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
    this.onTap,
    this.onOpen,
    this.padding = const EdgeInsets.all(16),
    this.morphId,
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
  final VoidCallback? onTap;
  final ValueChanged<HermezMorphOrigin?>? onOpen;
  final EdgeInsets padding;
  final String? morphId;

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
