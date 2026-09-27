import 'package:conduit/features/hermes/widgets/hermez_chat_palette.dart';
import 'package:conduit/features/hermes/widgets/hermez_visual_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    test('A2UI uses Hermez tokens and distinct health color: $brightness', () {
      final base = ThemeData(brightness: brightness);
      final themed = hermezVisualTheme(base);
      final palette = HermezChatPalette.forBrightness(brightness);
      if (brightness == Brightness.light) {
        expect(palette.canvas, const Color(0xFFF7F7F7));
      }
      expect(themed.colorScheme.primary, palette.accent);
      expect(themed.colorScheme.surface, palette.surface);
      expect(themed.colorScheme.onSurface, palette.ink);
      expect(themed.colorScheme.primaryContainer, palette.accent);
      expect(themed.floatingActionButtonTheme.backgroundColor, palette.accent);
      expect(
        themed.chipTheme.selectedColor,
        isNot(base.chipTheme.selectedColor),
      );
      expect(themed.cardTheme.elevation, 0);
      expect(
        themed.extension<HermezStatusColors>()!.success,
        isNot(palette.accent),
      );
      expect(
        themed.extension<HermezStatusColors>()!.danger,
        isNot(palette.accent),
      );
    });
  }
}
