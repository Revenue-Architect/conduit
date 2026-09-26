import 'package:flutter/material.dart';

import 'hermez_chat_palette.dart';

@immutable
class HermezStatusColors extends ThemeExtension<HermezStatusColors> {
  const HermezStatusColors({
    required this.success,
    required this.warning,
    required this.danger,
  });

  final Color success;
  final Color warning;
  final Color danger;

  @override
  HermezStatusColors copyWith({
    Color? success,
    Color? warning,
    Color? danger,
  }) => HermezStatusColors(
    success: success ?? this.success,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
  );

  @override
  HermezStatusColors lerp(ThemeExtension<HermezStatusColors>? other, double t) {
    if (other is! HermezStatusColors) return this;
    return HermezStatusColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

/// Renderer-owned identity. Agent JSON cannot set colors or load visual assets.
ThemeData hermezVisualTheme(ThemeData base) {
  final dark = base.brightness == Brightness.dark;
  final palette = HermezChatPalette.forBrightness(base.brightness);
  final status = dark
      ? const HermezStatusColors(
          success: Color(0xFF74D3A1),
          warning: Color(0xFFFFC477),
          danger: Color(0xFFFF8F8F),
        )
      : const HermezStatusColors(
          success: Color(0xFF18704B),
          warning: Color(0xFF925600),
          danger: Color(0xFFB43432),
        );
  final scheme = base.colorScheme.copyWith(
    primary: palette.accent,
    onPrimary: palette.onAccent,
    primaryContainer: palette.accent,
    onPrimaryContainer: palette.onAccent,
    secondary: palette.ink,
    onSecondary: palette.surface,
    secondaryContainer: palette.accent.withValues(alpha: dark ? 0.24 : 0.16),
    onSecondaryContainer: palette.ink,
    surface: palette.surface,
    surfaceContainer: palette.surface,
    surfaceContainerLow: palette.canvas,
    surfaceContainerHigh: palette.surface,
    onSurface: palette.ink,
    onSurfaceVariant: palette.muted,
    outline: palette.border,
    outlineVariant: palette.border,
    error: status.danger,
    tertiary: status.warning,
  );
  final text = base.textTheme.apply(
    bodyColor: palette.ink,
    displayColor: palette.ink,
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.canvas,
    appBarTheme: AppBarTheme(
      backgroundColor: palette.canvas,
      foregroundColor: palette.ink,
      elevation: 0,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: palette.accent,
      foregroundColor: palette.onAccent,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: palette.surface,
      selectedColor: palette.accent.withValues(alpha: dark ? 0.24 : 0.16),
      labelStyle: TextStyle(color: palette.ink, fontWeight: FontWeight.w600),
      side: BorderSide(color: palette.border),
      showCheckmark: false,
    ),
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
      ),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    ),
    extensions: [
      ...base.extensions.values.where((e) => e is! HermezStatusColors),
      status,
    ],
    cardTheme: CardThemeData(
      color: palette.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: palette.border),
      ),
    ),
    dividerTheme: DividerThemeData(color: palette.border, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.accent, width: 2),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: palette.accent,
        foregroundColor: palette.onAccent,
        minimumSize: const Size(48, 48),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.ink,
        minimumSize: const Size(48, 48),
        side: BorderSide(color: palette.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: palette.ink,
        minimumSize: const Size(48, 48),
      ),
    ),
  );
}
