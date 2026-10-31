import 'package:conduit/features/hermes/sky/hermez_sky.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The rule: dark mode always shows the evening or night sky, never day.
  test('dark mode never shows a daytime sky', () {
    final day = DateTime(2026, 10, 30);
    final sunrise = day.add(const Duration(hours: 7, minutes: 51));
    final sunset = day.add(const Duration(hours: 18, minutes: 9));
    for (var minutes = 0; minutes < 24 * 60; minutes += 15) {
      final phase = hermezSkyPhaseAt(
        day.add(Duration(minutes: minutes)),
        sunrise: sunrise,
        sunset: sunset,
        dark: true,
      );
      expect(
        phase,
        anyOf(HermezSkyPhase.dusk, HermezSkyPhase.night),
        reason: 'at ${minutes ~/ 60}:${minutes % 60}',
      );
    }
  });
}
