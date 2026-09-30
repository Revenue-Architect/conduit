import 'package:flutter/material.dart';

/// Debug-only Android polish for Hermes chat; not a second app theme or route.
bool shouldUseHermezChatVisuals({
  required bool debugBuild,
  required bool android,
  required bool hermes,
}) => debugBuild && android && hermes;

enum HermezSignal { orange, red }

@immutable
class HermezChatPalette {
  const HermezChatPalette({
    required this.canvas,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.userBubble,
    required this.onUserBubble,
    required this.border,
  });

  final Color canvas;
  final Color surface;
  final Color ink;
  final Color muted;
  final Color accent;
  final Color onAccent;
  final Color userBubble;
  final Color onUserBubble;
  final Color border;

  /// The signal colour of the active Hermez theme ("Hermez" or "Hermez
  /// Red"). Set when the app theme is built; every caller reads the palette
  /// through `Theme.of(context)`, so a theme change rebuilds them all.
  static HermezSignal signal = HermezSignal.orange;

  static void useThemeId(String id) =>
      signal = id == 'hermez_red' ? HermezSignal.red : HermezSignal.orange;

  static HermezChatPalette forBrightness(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final red = signal == HermezSignal.red;
    // Graphite on orange reads well; on red it would be ~3.7:1, so white.
    final accent = red
        ? const Color(0xFFE3192B)
        : dark
        ? const Color(0xFFFF6A36)
        : const Color(0xFFFF5A26);
    final onAccent = red ? const Color(0xFFFFFFFF) : const Color(0xFF17181C);
    return dark
        ? HermezChatPalette(
            canvas: const Color(0xFF111215),
            surface: const Color(0xFF24252A),
            ink: const Color(0xFFF6F5F2),
            muted: const Color(0xFFB6B7B4),
            accent: accent,
            onAccent: onAccent,
            userBubble: const Color(0xFFEAE8E3),
            onUserBubble: const Color(0xFF17181C),
            border: const Color(0xFF434449),
          )
        : HermezChatPalette(
            canvas: const Color(0xFFF7F7F7),
            surface: const Color(0xFFFFFFFF),
            ink: const Color(0xFF17181C),
            muted: const Color(0xFF666765),
            accent: accent,
            onAccent: onAccent,
            userBubble: const Color(0xFF202126),
            onUserBubble: const Color(0xFFFFFFFF),
            border: const Color(0xFFDADADA),
          );
  }
}
