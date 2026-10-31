import 'package:conduit/features/hermes/widgets/hermez_chat_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  // The redesign's rule: every text colour reads at 4.5:1 or better on every
  // ground it sits on, in light and dark.
  for (final brightness in Brightness.values) {
    test('Hermez text colours are readable in ${brightness.name}', () {
      final p = HermezChatPalette.forBrightness(brightness);
      final grounds = {
        'canvas': p.canvas,
        'surface': p.surface,
        'raised': p.raised,
      };
      final inks = {
        'ink': p.ink,
        'muted': p.muted,
        'faint': p.faint,
        'liveText': p.liveText,
        'failed': p.failed,
      };
      for (final g in grounds.entries) {
        for (final i in inks.entries) {
          expect(
            _contrast(i.value, g.value),
            greaterThanOrEqualTo(4.5),
            reason: '${i.key} on ${g.key}',
          );
        }
      }
      expect(_contrast(p.onAccent, p.accent), greaterThanOrEqualTo(4.5));
    });
  }
}
