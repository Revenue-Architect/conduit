import 'package:conduit/features/hermes/widgets/hermez_chat_palette.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  tearDown(() => HermezChatPalette.useThemeId('conduit'));

  test('Hermez Red is listed and only swaps the signal colour', () {
    expect(TweakcnThemes.all, contains(TweakcnThemes.hermezRed));
    expect(TweakcnThemes.byId('hermez_red'), TweakcnThemes.hermezRed);
    expect(TweakcnThemes.isHermez(TweakcnThemes.hermezRed), isTrue);
    expect(TweakcnThemes.isHermez(TweakcnThemes.conduit), isTrue);
    expect(TweakcnThemes.isHermez(TweakcnThemes.catppuccin), isFalse);

    for (final brightness in Brightness.values) {
      final red = TweakcnThemes.hermezRed.variantFor(brightness);
      final orange = TweakcnThemes.conduit.variantFor(brightness);
      for (final signal in [
        red.primary,
        red.ring,
        red.sidebarPrimary,
        red.sidebarRing,
      ]) {
        expect(signal, const Color(0xFFE3192B));
      }
      expect(red.background, orange.background);
      expect(red.foreground, orange.foreground);
      expect(red.card, orange.card);
      expect(red.border, orange.border);
      expect(red.success, orange.success);
      expect(red.destructive, orange.destructive);
      expect(_contrast(red.primaryForeground, red.primary), greaterThan(4.5));
    }
  });

  test('the Hermez palette follows the active theme, orange by default', () {
    for (final brightness in Brightness.values) {
      HermezChatPalette.useThemeId('conduit');
      final orange = HermezChatPalette.forBrightness(brightness);
      expect(orange.accent, isNot(const Color(0xFFE3192B)));

      HermezChatPalette.useThemeId('hermez_red');
      final red = HermezChatPalette.forBrightness(brightness);
      expect(red.accent, const Color(0xFFE3192B));
      expect(red.onAccent, const Color(0xFFFFFFFF));
      expect(_contrast(red.onAccent, red.accent), greaterThan(4.5));
      // Nothing else about the design changes.
      expect(red.canvas, orange.canvas);
      expect(red.ink, orange.ink);
      expect(red.surface, orange.surface);
      expect(red.border, orange.border);
    }
    HermezChatPalette.useThemeId('catppuccin');
    expect(HermezChatPalette.signal, HermezSignal.orange);
  });
}
