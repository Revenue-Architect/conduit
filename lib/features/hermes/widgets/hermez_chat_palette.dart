import 'package:flutter/material.dart';

/// Debug-only Android polish for Hermes chat; not a second app theme or route.
bool shouldUseHermezChatVisuals({
  required bool debugBuild,
  required bool android,
  required bool hermes,
}) => debugBuild && android && hermes;

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

  static HermezChatPalette forBrightness(Brightness brightness) =>
      brightness == Brightness.dark
      ? const HermezChatPalette(
          canvas: Color(0xFF111215),
          surface: Color(0xFF24252A),
          ink: Color(0xFFF6F5F2),
          muted: Color(0xFFB6B7B4),
          accent: Color(0xFFFF6A36),
          onAccent: Color(0xFF17181C),
          userBubble: Color(0xFFEAE8E3),
          onUserBubble: Color(0xFF17181C),
          border: Color(0xFF434449),
        )
      : const HermezChatPalette(
          canvas: Color(0xFFF6F5F2),
          surface: Color(0xFFFFFFFF),
          ink: Color(0xFF17181C),
          muted: Color(0xFF666765),
          accent: Color(0xFFFF5A26),
          onAccent: Color(0xFF17181C),
          userBubble: Color(0xFF202126),
          onUserBubble: Color(0xFFFFFFFF),
          border: Color(0xFFDAD9D5),
        );
}
