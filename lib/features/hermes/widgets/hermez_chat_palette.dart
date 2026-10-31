import 'package:flutter/material.dart';

import '../../../shared/theme/tweakcn_themes.dart';

/// Debug-only Android polish for Hermes chat; not a second app theme or route.
bool shouldUseHermezChatVisuals({
  required bool debugBuild,
  required bool android,
  required bool hermes,
}) => debugBuild && android && hermes;

enum HermezSignal { ink, red }

/// Hermes colours (docs/app-design-2026-10-30/DIRECTION.md, "Colour roles").
///
/// One accent, one role: [live] amber means a bot is working right now. The
/// primary action colour, [accent], is ink, so buttons never compete with it.
@immutable
class HermezChatPalette {
  const HermezChatPalette({
    required this.canvas,
    required this.surface,
    required this.raised,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.accent,
    required this.onAccent,
    required this.live,
    required this.liveText,
    required this.failed,
    required this.userBubble,
    required this.onUserBubble,
    required this.border,
  });

  /// The page ground.
  final Color canvas;

  /// Quiet fills: counts, chips, the soft pill.
  final Color surface;

  /// Sheets, rows and cards that sit on [canvas].
  final Color raised;
  final Color ink;
  final Color muted;

  /// The third ink, for times and meta.
  final Color faint;

  /// Primary actions: ink pills.
  final Color accent;
  final Color onAccent;

  /// A bot working right now: the tally dot, the live frame, the step bar.
  final Color live;

  /// [live] as text on [raised] or [canvas].
  final Color liveText;

  /// A failed run, and nothing else.
  final Color failed;
  final Color userBubble;
  final Color onUserBubble;
  final Color border;

  /// The signal of the active Hermez theme ("Hermez" or "Hermez Red"). Set
  /// when the app theme is built; every caller reads the palette through
  /// `Theme.of(context)`, so a theme change rebuilds them all.
  static HermezSignal signal = HermezSignal.ink;

  static void useThemeId(String id) =>
      signal = id == 'hermez_red' ? HermezSignal.red : HermezSignal.ink;

  static const Color liveAmber = Color(0xFFFFB020);

  static HermezChatPalette forBrightness(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final red = signal == HermezSignal.red;
    final ink = dark ? const Color(0xFFF2F3F5) : const Color(0xFF0E1116);
    final raised = dark ? const Color(0xFF16181C) : const Color(0xFFFFFFFF);
    // White text on the red keeps 4.8:1.
    final accent = red ? const Color(0xFFE3192B) : ink;
    final onAccent = red ? const Color(0xFFFFFFFF) : raised;
    return dark
        ? HermezChatPalette(
            canvas: const Color(0xFF0B0C0E),
            surface: const Color(0xFF22252B),
            raised: raised,
            ink: ink,
            muted: const Color(0xFFA3A8B2),
            faint: const Color(0xFF8F95A0),
            accent: accent,
            onAccent: onAccent,
            live: liveAmber,
            liveText: liveAmber,
            failed: const Color(0xFFFF7A6E),
            userBubble: const Color(0xFF22252B),
            onUserBubble: ink,
            border: const Color(0xFF272A30),
          )
        : HermezChatPalette(
            canvas: TweakcnThemes.lightCanvas,
            surface: TweakcnThemes.lightSurface,
            raised: raised,
            ink: ink,
            muted: const Color(0xFF5A606B),
            faint: const Color(0xFF686E78),
            accent: accent,
            onAccent: onAccent,
            live: liveAmber,
            liveText: const Color(0xFF8A5A00),
            failed: const Color(0xFFC2362B),
            userBubble: TweakcnThemes.lightSurface,
            onUserBubble: ink,
            border: const Color(0xFFE6E7EA),
          );
  }
}
