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

  // The owner's rule: the evening is the A2 dusk sky until 11 pm, not night.
  test('the evening shows the dusk sky until 11 pm', () {
    final day = DateTime(2026, 10, 30);
    final sunset = day.add(const Duration(hours: 18, minutes: 9));
    for (final t in [
      const Duration(hours: 19),
      const Duration(hours: 20, minutes: 44),
      const Duration(hours: 22, minutes: 50),
    ]) {
      expect(
        hermezSkyPhaseAt(day.add(t), sunset: sunset, dark: false),
        HermezSkyPhase.dusk,
      );
    }
    expect(
      hermezSkyPhaseAt(
        day.add(const Duration(hours: 23, minutes: 30)),
        sunset: sunset,
        dark: false,
      ),
      HermezSkyPhase.night,
    );
  });
}
